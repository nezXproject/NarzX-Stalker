#!/usr/bin/env python3
"""NarzX Search - local privacy self-audit scanner.

Stdlib only. Binds to 127.0.0.1. No telemetry, no cookies, no disk writes,
no request logging. For checking YOUR OWN exposure or authorized research.
"""
import argparse
import hashlib
import json
import re
import sys
import threading
import time
import webbrowser
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib import error, parse, request

VERSION = "1.0.0"
ROOT = Path(__file__).resolve().parent
UA = "NarzXSearch/1.0 (local privacy self-audit; no telemetry)"
PORT = 7878
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


# ----------------------------------------------------------------- input
def clean(v, limit=120):
    return re.sub(r'["\r\n\t]+', " ", v or "").strip()[:limit]


def classify(v):
    if EMAIL_RE.match(v):
        return "email"
    digits = re.sub(r"\D", "", v)
    if re.fullmatch(r"\+?[\d\s().-]{7,20}", v) and 7 <= len(digits) <= 15:
        return "phone"
    return "name"


def phone_variants(v):
    digits = re.sub(r"\D", "", v)
    out = [v, digits]
    if len(digits) == 10:
        out += [f"{digits[:3]}-{digits[3:6]}-{digits[6:]}",
                f"({digits[:3]}) {digits[3:6]}-{digits[6:]}",
                f"{digits[:5]} {digits[5:]}"]
    elif len(digits) > 10:
        out.append("+" + digits)
    seen, res = set(), []
    for x in out:
        if x and x not in seen:
            seen.add(x)
            res.append(x)
    return res


# ------------------------------------------------------------ search plan
def build_plan(value, context):
    value = clean(value)
    kind = classify(value)
    ctx = [clean(c, 60) for c in re.split(r"[,;]", context or "") if clean(c, 60)][:3]
    ctxq = " ".join(f'"{c}"' for c in ctx)
    if kind == "phone":
        vs = phone_variants(value)[:4]
        term = "(" + " OR ".join(f'"{x}"' for x in vs) + ")"
    else:
        term = f'"{value}"'

    plan = []

    def add(cat, label, s):
        plan.append({"id": f"q{len(plan)}", "category": cat, "label": label,
                     "q": f"{term} {s} {ctxq}".replace("  ", " ").strip()})

    for expr, lab in [("filetype:pdf", "PDF documents"),
                      ("(filetype:doc OR filetype:docx)", "Word documents"),
                      ("(filetype:xls OR filetype:xlsx OR filetype:csv)", "Spreadsheets"),
                      ("(filetype:ppt OR filetype:pptx)", "Presentations"),
                      ("(filetype:txt OR filetype:log)", "Text files & logs")]:
        add("Documents", lab, expr)
    add("Documents", "Resume / CV", '(resume OR CV OR "curriculum vitae")')
    add("Shared files", "Google Docs / Drive", "(site:docs.google.com OR site:drive.google.com)")
    add("Shared files", "Public boards & notes", "(site:trello.com OR site:notion.site OR site:airtable.com)")
    add("Calendars", "Google Calendar", "site:calendar.google.com")
    add("Calendars", "iCal feeds & booking pages", "(filetype:ics OR inurl:ical OR site:calendly.com)")
    add("Profiles", "Professional networks", "(site:linkedin.com OR site:xing.com)")
    add("Profiles", "Social networks", "(site:facebook.com OR site:instagram.com OR site:x.com OR site:tiktok.com)")
    add("Profiles", "Code & forums", "(site:github.com OR site:reddit.com OR site:stackoverflow.com)")
    if kind != "phone":
        add("Contact details", "Phone numbers near this identity", '(intext:"phone" OR intext:"mobile" OR intext:"whatsapp")')
    if kind != "email":
        add("Contact details", "Email addresses near this identity", '(intext:"email" OR intext:"e-mail")')
    add("Pastes & dumps", "Paste sites", "(site:pastebin.com OR site:paste.ee OR site:rentry.co)")
    add("Pastes & dumps", "Gists & repositories", "(site:gist.github.com OR site:gitlab.com)")
    add("Data brokers", "People-search sites (opt-out candidates)",
        "(site:spokeo.com OR site:whitepages.com OR site:truepeoplesearch.com OR site:radaris.com OR site:mylife.com)")
    return {"kind": kind, "value": value, "queries": plan}


# ------------------------------------------------------- background sources
def http_get(url, headers=None, timeout=12):
    req = request.Request(url, headers={"User-Agent": UA, "Accept": "application/json", **(headers or {})})
    try:
        with request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(2_000_000)
    except error.HTTPError as e:
        return e.code, b""


def q(s):
    return parse.quote(s, safe="")


def item(title, url="", snippet=""):
    return {"title": title, "url": url, "snippet": snippet}


def src_gravatar(kind, v, ctx):
    if kind != "email":
        return None
    h = hashlib.sha256(v.lower().encode()).hexdigest()
    st, body = http_get(f"https://api.gravatar.com/v3/profiles/{h}")
    if st == 404:
        return []
    if st != 200:
        raise RuntimeError(f"HTTP {st}")
    j = json.loads(body)
    bits = [j.get(k) for k in ("job_title", "company", "location") if j.get(k)]
    return [item(j.get("display_name") or "Gravatar profile", j.get("profile_url", ""), " / ".join(bits))]


def src_openpgp(kind, v, ctx):
    if kind != "email":
        return None
    st, _ = http_get(f"https://keys.openpgp.org/vks/v1/by-email/{q(v)}")
    if st == 404:
        return []
    if st != 200:
        raise RuntimeError(f"HTTP {st}")
    return [item("Public PGP key published for this email", f"https://keys.openpgp.org/search?q={q(v)}")]


def src_calendar(kind, v, ctx):
    if kind != "email":
        return None
    url = f"https://calendar.google.com/calendar/ical/{q(v)}/public/basic.ics"
    st, body = http_get(url, {"Accept": "text/calendar"})
    if st in (403, 404):
        return []
    if st != 200:
        raise RuntimeError(f"HTTP {st}")
    n = body.count(b"BEGIN:VEVENT")
    return [item(f"Public Google Calendar feed is readable ({n} events)", url,
                 "Anyone can read this calendar. Set it to private in Google Calendar settings.")]


def src_github(kind, v, ctx):
    if kind == "phone":
        return None
    qs = f"{v} in:email" if kind == "email" else f'"{v}" in:fullname'
    st, body = http_get(f"https://api.github.com/search/users?per_page=5&q={q(qs)}",
                        {"Accept": "application/vnd.github+json"})
    if st == 403:
        raise RuntimeError("rate limited")
    if st != 200:
        raise RuntimeError(f"HTTP {st}")
    return [item(u["login"], u["html_url"]) for u in json.loads(body).get("items", [])]


def src_orcid(kind, v, ctx):
    if kind == "phone":
        return None
    qs = f'email:"{v}"' if kind == "email" else f'"{v}"'
    st, body = http_get(f"https://pub.orcid.org/v3.0/expanded-search/?rows=5&q={q(qs)}")
    if st != 200:
        raise RuntimeError(f"HTTP {st}")
    out = []
    for r in (json.loads(body).get("expanded-result") or []):
        nm = f'{r.get("given-names", "")} {r.get("family-names", "")}'.strip()
        orgs = ", ".join(r.get("institution-name") or [])
        out.append(item(nm or r["orcid-id"], f'https://orcid.org/{r["orcid-id"]}', orgs))
    return out


def src_openalex(kind, v, ctx):
    if kind != "name":
        return None
    st, body = http_get(f"https://api.openalex.org/authors?per-page=5&search={q(v)}")
    if st != 200:
        raise RuntimeError(f"HTTP {st}")
    out = []
    for a in json.loads(body).get("results", []):
        inst = ((a.get("last_known_institutions") or [{}])[0] or {}).get("display_name", "")
        out.append(item(a.get("display_name", ""), a.get("id", ""), f'{inst} - {a.get("works_count", 0)} works'))
    return out


def src_arxiv(kind, v, ctx):
    if kind != "name":
        return None
    st, body = http_get(f'https://export.arxiv.org/api/query?max_results=5&search_query=au:{q(chr(34) + v + chr(34))}',
                        {"Accept": "application/atom+xml"})
    if st != 200:
        raise RuntimeError(f"HTTP {st}")
    ns = {"a": "http://www.w3.org/2005/Atom"}
    out = []
    for e in ET.fromstring(body).findall("a:entry", ns):
        out.append(item(" ".join((e.findtext("a:title", "", ns) or "").split()),
                        e.findtext("a:id", "", ns) or ""))
    return out


def src_wikipedia(kind, v, ctx):
    if kind != "name":
        return None
    st, body = http_get(f"https://en.wikipedia.org/w/api.php?action=query&list=search&srlimit=3&format=json&srsearch={q(chr(34) + v + chr(34))}")
    if st != 200:
        raise RuntimeError(f"HTTP {st}")
    return [item(r["title"], "https://en.wikipedia.org/wiki/" + q(r["title"].replace(" ", "_")),
                 re.sub(r"<[^>]+>", "", r.get("snippet", "")))
            for r in json.loads(body)["query"]["search"]]


def src_hn(kind, v, ctx):
    st, body = http_get(f'https://hn.algolia.com/api/v1/search?hitsPerPage=5&query={q(chr(34) + v + chr(34))}')
    if st != 200:
        raise RuntimeError(f"HTTP {st}")
    return [item(h.get("title") or (h.get("comment_text") or "")[:80],
                 f'https://news.ycombinator.com/item?id={h["objectID"]}')
            for h in json.loads(body).get("hits", [])]


SOURCES = [
    ("Gravatar profile", "Profiles", src_gravatar),
    ("OpenPGP keyserver", "Contact details", src_openpgp),
    ("Public Google Calendar (.ics)", "Calendars", src_calendar),
    ("GitHub users", "Profiles", src_github),
    ("ORCID", "Profiles", src_orcid),
    ("OpenAlex authors", "Profiles", src_openalex),
    ("arXiv", "Documents", src_arxiv),
    ("Wikipedia", "Profiles", src_wikipedia),
    ("Hacker News", "Profiles", src_hn),
]


def run_background(value, context):
    value = clean(value)
    kind = classify(value)

    def one(s):
        name, cat, fn = s
        try:
            res = fn(kind, value, context)
        except Exception as e:  # network or parse error: report, never crash
            return {"source": name, "category": cat, "status": "error", "detail": str(e)[:120], "items": []}
        if res is None:
            return {"source": name, "category": cat, "status": "skipped", "items": []}
        return {"source": name, "category": cat, "status": "found" if res else "none", "items": res}

    with ThreadPoolExecutor(max_workers=4) as ex:
        results = list(ex.map(one, SOURCES))
    return {"kind": kind, "results": results}


# ------------------------------------------------------------------ server
class Handler(BaseHTTPRequestHandler):
    server_version = "NarzXSearch"

    def log_message(self, *a):  # privacy: never log requests
        pass

    def _allowed_host(self):
        host = (self.headers.get("Host") or "").lower()
        return host in {f"127.0.0.1:{PORT}", f"localhost:{PORT}"}  # blocks DNS rebinding

    def _send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy",
                         "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; "
                         "connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if not self._allowed_host():
            return self._send(403, {"error": "bad host"})
        if self.path.split("?")[0] in ("/", "/index.html"):
            return self._send(200, (ROOT / "web" / "index.html").read_bytes(), "text/html")
        if self.path == "/api/health":
            return self._send(200, {"ok": True, "version": VERSION})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        origin = self.headers.get("Origin", "")
        if not self._allowed_host() or origin not in (f"http://127.0.0.1:{PORT}", f"http://localhost:{PORT}"):
            return self._send(403, {"error": "forbidden origin"})
        try:
            n = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(min(n, 10_000)) or b"{}")
            value, context = str(body.get("value", "")), str(body.get("context", ""))
            if len(clean(value)) < 3:
                return self._send(400, {"error": "Enter at least 3 characters."})
            if body.get("consent") is not True:
                return self._send(400, {"error": "Confirm this is your own data or an authorized assessment."})
        except (ValueError, TypeError):
            return self._send(400, {"error": "bad request"})
        if self.path == "/api/plan":
            return self._send(200, build_plan(value, context))
        if self.path == "/api/background":
            return self._send(200, run_background(value, context))
        self._send(404, {"error": "not found"})


def main():
    global PORT
    ap = argparse.ArgumentParser(description="NarzX Search - local privacy self-audit scanner")
    ap.add_argument("--port", type=int, default=PORT)
    ap.add_argument("--no-browser", action="store_true", help="do not open the app automatically")
    args = ap.parse_args()
    PORT = args.port
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    url = f"http://127.0.0.1:{PORT}"
    print(f"NarzX Search {VERSION} running at {url}  (Ctrl+C to stop)")
    print("Local only. No telemetry. For your own data or authorized research.")
    if not args.no_browser:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
        srv.server_close()
        sys.exit(0)


if __name__ == "__main__":
    main()
