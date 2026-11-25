// Relays messages between the NarzX Search page (127.0.0.1:7878) and the extension.
// Only talks to the exact local origin; nothing leaves the machine from here.
(() => {
  const origin = location.origin;
  window.addEventListener("message", (e) => {
    if (e.source !== window || e.origin !== origin) return;
    const m = e.data;
    if (!m || m.narzx !== "app" || !m.payload) return;
    browser.runtime.sendMessage(m.payload)
      .then((reply) => { if (reply) window.postMessage({ narzx: "ext", payload: reply }, origin); })
      .catch(() => {});
  });
  browser.runtime.onMessage.addListener((m) => {
    if (m && m.toApp) window.postMessage({ narzx: "ext", payload: m.toApp }, origin);
  });
})();
