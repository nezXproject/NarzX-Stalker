// NarzX Search Companion: opens Google searches for a local self-audit, collects results,
// closes its tab/window and deletes the searched URLs from history. No network calls of its own.
const VERSION = browser.runtime.getManifest().version;
const APP_ORIGINS = ["http://127.0.0.1:7878/", "http://localhost:7878/"];
let job = null;                 // one scan at a time
const waiters = new Map();      // tabId -> resolve

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const jitter = () => 1500 + Math.random() * 2000;   // polite pacing, fewer CAPTCHAs

function toApp(msg) {
  if (!job) return;
  browser.tabs.sendMessage(job.appTabId, { toApp: { scanId: job.id, ...msg } }).catch(() => {});
}

browser.runtime.onMessage.addListener((msg, sender) => {
  if (!msg || !msg.type) return;
  const fromApp = sender.tab && sender.url && APP_ORIGINS.some((o) => sender.url.startsWith(o));

  if (fromApp) {
    if (msg.type === "PING") {
      return browser.extension.isAllowedIncognitoAccess().then((ok) => ({ type: "PONG", version: VERSION, privateAllowed: ok }));
    }
    if (msg.type === "START") {
      if (job) return Promise.resolve({ type: "ERROR", scanId: msg.scanId, text: "A scan is already running." });
      runScan(msg, sender.tab.id);
      return;
    }
    if (msg.type === "CANCEL" && job && job.id === msg.scanId) { job.cancel = true; resolveAll({ type: "ABORT" }); }
    return;
  }

  // From results.js on a Google tab we opened
  if (sender.tab && job && sender.tab.id === job.tabId) {
    job.visited.add(sender.url);
    if (msg.type === "CAPTCHA") {
      toApp({ type: "STATUS", warn: true, text: "Google wants a human check. Complete it in the scan tab/window; the scan resumes automatically." });
      browser.tabs.update(job.tabId, { active: true }).catch(() => {});
      if (job.winId) browser.windows.update(job.winId, { focused: true }).catch(() => {});
    }
    if (msg.type === "RESULTS") { const w = waiters.get(sender.tab.id); if (w) w(msg); }
  }
});

function resolveAll(m) { for (const w of waiters.values()) w(m); }

function waitForResults(tabId, ms) {
  return new Promise((resolve) => {
    const t = setTimeout(() => { waiters.delete(tabId); resolve({ type: "TIMEOUT" }); }, ms);
    waiters.set(tabId, (m) => { clearTimeout(t); waiters.delete(tabId); resolve(m); });
  });
}

browser.tabs.onRemoved.addListener((tabId) => {
  if (job && tabId === job.tabId) { job.cancel = true; job.tabGone = true; const w = waiters.get(tabId); if (w) w({ type: "ABORT" }); }
});

async function runScan(req, appTabId) {
  job = { id: req.scanId, appTabId, cancel: false, tabGone: false, visited: new Set(), tabId: null, winId: null };
  const pages = Math.max(1, Math.min(10, req.pages | 0 || 2));
  try {
    const priv = req.mode === "private";
    if (priv && !(await browser.extension.isAllowedIncognitoAccess())) {
      toApp({ type: "ERROR", text: "Private windows are not allowed for this extension (about:addons → Run in Private Windows → Allow)." });
      return;
    }
    if (priv) {
      const win = await browser.windows.create({ incognito: true, url: "about:blank", focused: false });
      job.winId = win.id; job.tabId = win.tabs[0].id;
    } else {
      const tab = await browser.tabs.create({ url: "about:blank", active: false });
      job.tabId = tab.id;
    }

    outer:
    for (let qi = 0; qi < req.queries.length; qi++) {
      const query = req.queries[qi];
      for (let p = 0; p < pages; p++) {
        if (job.cancel) break outer;
        toApp({ type: "STATUS", text: `Query ${qi + 1}/${req.queries.length}, page ${p + 1}/${pages}…` });
        const url = "https://www.google.com/search?hl=en&pws=0&nfpr=1&q=" + encodeURIComponent(query.q) + "&start=" + p * 10;
        job.visited.add(url);
        const pending = waitForResults(job.tabId, 300000);   // up to 5 min to solve a human check
        try { await browser.tabs.update(job.tabId, { url }); } catch (_) { job.cancel = true; break outer; }
        const res = await pending;
        if (res.type === "ABORT" || job.cancel) break outer;
        if (res.type === "TIMEOUT") { toApp({ type: "STATUS", warn: true, text: `Query ${qi + 1} timed out (consent or human check not completed). Skipping.` }); break; }
        toApp({ type: "RESULTS", queryId: query.id, page: p, results: res.results });
        if (!res.hasNext || !res.results.length) break;
        await sleep(jitter());
      }
      await sleep(jitter());
    }
  } catch (e) {
    toApp({ type: "ERROR", text: "Scan failed: " + e.message });
  } finally {
    const cleaned = await cleanup();
    toApp({ type: "DONE", cleaned });
    job = null; waiters.clear();
  }
}

async function cleanup() {
  const j = job;
  try { if (j.winId) await browser.windows.remove(j.winId); else if (j.tabId && !j.tabGone) await browser.tabs.remove(j.tabId); } catch (_) {}
  let n = 0;
  for (const u of j.visited) { try { await browser.history.deleteUrl({ url: u }); n++; } catch (_) {} }
  return n;
}
