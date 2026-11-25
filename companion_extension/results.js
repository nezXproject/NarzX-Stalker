// Runs on Google result pages opened by the scan. Extracts titles/links only.
(() => {
  const send = (m) => browser.runtime.sendMessage(m).catch(() => {});

  if (location.pathname.startsWith("/sorry") || document.querySelector("form#captcha-form, iframe[src*='recaptcha']")) {
    send({ type: "CAPTCHA" });
    return; // after you verify, Google navigates and this script runs again on the results page
  }

  const SKIP = /(^|\.)google\.[a-z.]+$/i;
  const extract = () => {
    const out = [], seen = new Set();
    document.querySelectorAll("#search a, #rso a").forEach((a) => {
      const h3 = a.querySelector("h3");
      if (!h3 || !a.href) return;
      let u; try { u = new URL(a.href); } catch (_) { return; }
      if (!/^https?:$/.test(u.protocol) || SKIP.test(u.hostname) || seen.has(u.href)) return;
      seen.add(u.href);
      const title = h3.innerText.trim();
      let box = a, snippet = "";
      for (let i = 0; i < 5 && box.parentElement; i++) {
        box = box.parentElement;
        const t = (box.innerText || "").replace(title, "").replace(/\s+/g, " ").trim();
        if (t.length > 40) { snippet = t.slice(0, 280); break; }
      }
      out.push({ title, url: u.href, snippet });
    });
    return out;
  };

  let tries = 0;
  const tick = () => {
    const results = extract();
    if (results.length || tries++ >= 6) {
      send({ type: "RESULTS", results, hasNext: !!document.querySelector("a#pnnext") });
    } else setTimeout(tick, 500);
  };
  tick();
})();
