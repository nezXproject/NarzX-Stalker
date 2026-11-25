# NarzX Search

A free, open source, **zero-telemetry** privacy self-audit tool. It helps you find what is publicly exposed under **your own** name, email, or phone number (leaked documents, public calendars, profiles, contact details, paste sites, data-broker listings) so you can remove it before someone else finds it.

Runs entirely on your machine: a small local web app (`127.0.0.1:7878`) plus an optional companion extension for Firefox-based browsers. Works on **Linux** and **Windows** (and macOS). Only needs Python 3.8+, no packages to install.

> **Authorized use only.** Use NarzX Search for your own security, or for research you have explicit written permission to do. Do not use it to harass, stalk, or surveil anyone. The app asks you to confirm this before every scan.

## Quick start

**Linux / macOS**
```bash
python3 narzx_search.py
```
**Windows (PowerShell or cmd)**
```bat
py narzx_search.py
```
The app opens at <http://127.0.0.1:7878>. Use `--no-browser` to skip auto-open, or `--port 9000` to change the port (the extension is set up for 7878, so edit `manifest.json` if you change it).

## Install the companion extension (needed for Fast and Private modes)

Supported: Firefox, LibreWolf, Zen, Floorp, Waterfox, Mullvad Browser.

1. Open `about:debugging#/runtime/this-firefox`
2. **Load Temporary Add-on...** and pick `companion_extension/manifest.json` (it is removed when the browser closes, which is the most privacy-friendly option).
3. For Private mode: `about:addons` -> **NarzX Search Companion** -> **Run in Private Windows** -> **Allow** (Firefox resets this each time you reload a temporary add-on).
4. Open the app **in that same browser** and check the "extension" badge turns green.

Tip: keep only that browser open while scanning, so tabs do not open somewhere else.

## Modes

| Mode | What it does |
|---|---|
| **Fast** | Opens Google searches in your normal browser session (fewer CAPTCHAs), reads up to N result pages per query, closes its tab, and deletes every searched URL from history. |
| **Private window** | Same, inside a private window so queries are not tied to your Google account or local history. Use a VPN to hide lookups from your ISP/DNS. If Google asks "verify you are human", do it in that window and the scan resumes. |
| **Background** | The local server queries public APIs (Gravatar, GitHub, ORCID, OpenAlex, arXiv, Wikipedia, Hacker News, OpenPGP keyserver, public Google Calendar `.ics`) with no tabs and no extension. Name-only matches may be other people; verify before acting. |

Search categories: documents, shared files, calendars, profiles, contact details, pastes and dumps, data brokers. Add context (city, company, school) to narrow common names.

## Privacy design

- Binds to `127.0.0.1` only; rejects requests with a wrong Host or Origin (blocks DNS-rebinding and drive-by web pages).
- No telemetry, analytics, cookies, accounts, or request logging. Nothing is written to disk; results live in the page until you close it. **Export JSON** is optional and saves only where you choose.
- The extension makes no network calls of its own and only talks to the local page and Google result pages it opened.
- Page content from the web is rendered as text, never as HTML.
- Google sees your queries in browser modes; background mode contacts only the listed public sources. Use a VPN if that matters to you.

## After you scan

Delete or restrict the source, then use Google's "Results about you" / "Remove outdated content", make calendars private, opt out of data brokers, tighten profile visibility, and rotate anything sensitive that leaked. Re-scan after a few weeks.

## License

MIT. See `LICENSE`.
