// B10 · Website — Browser-Tests über das Chrome DevTools Protocol (QA-Durchlauf 1, 2026-09-15;
// ergänzt bei der Reparatur Teil 1, 2026-09-16: FB-20/BUG-09 — Seiten rendern unter CSP ohne Verstöße)
//
// Voraussetzung: Produktionsserver wie in tests/site.http.test.mjs, dazu ein Chromium-Headless-Binary.
// Keine zusätzliche Abhängigkeit: Der Test startet das Binary selbst und spricht CDP über das in Node
// eingebaute WebSocket. Gesucht wird in CHROME_BIN, sonst im Playwright-/Puppeteer-Cache; fehlt beides,
// werden die Tests übersprungen. Ohne Ton: --mute-audio, es werden keine Medien geladen.
//
//   cd web
//   BASE_URL=http://127.0.0.1:3918 node --test tests/browser.cdp.test.mjs
//   # optional Screenshots ablegen:
//   QA_SCREENSHOT_DIR=../features/B10-website/qa BASE_URL=http://127.0.0.1:3918 node --test tests/browser.cdp.test.mjs

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, readdirSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

const BASE = (process.env.BASE_URL ?? "http://127.0.0.1:3918").replace(/\/$/, "");
const SHOTS = process.env.QA_SCREENSHOT_DIR;

function findChrome() {
  if (process.env.CHROME_BIN && existsSync(process.env.CHROME_BIN)) return process.env.CHROME_BIN;
  const roots = [join(homedir(), "Library/Caches/ms-playwright"), join(homedir(), ".cache/ms-playwright")];
  for (const root of roots) {
    if (!existsSync(root)) continue;
    for (const d of readdirSync(root).filter((n) => n.startsWith("chromium_headless_shell-")).sort().reverse()) {
      for (const sub of ["chrome-headless-shell-mac-arm64", "chrome-headless-shell-mac-x64", "chrome-headless-shell-linux64"]) {
        const bin = join(root, d, sub, "chrome-headless-shell");
        if (existsSync(bin)) return bin;
      }
    }
  }
  return null;
}

const CHROME = findChrome();
const skip = CHROME ? false : "kein Chromium-Headless-Binary gefunden (CHROME_BIN setzen)";

let proc, profile, ws, nextId = 0;
const pending = new Map();
const listeners = new Set();

function send(method, params = {}) {
  const id = ++nextId;
  ws.send(JSON.stringify({ id, method, params }));
  return new Promise((resolve, reject) => pending.set(id, { resolve, reject, method }));
}

function waitFor(method, predicate = () => true, timeout = 15000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { listeners.delete(fn); reject(new Error(`Timeout: ${method}`)); }, timeout);
    const fn = (msg) => {
      if (msg.method === method && predicate(msg.params)) { clearTimeout(timer); listeners.delete(fn); resolve(msg.params); }
    };
    listeners.add(fn);
  });
}

async function evaluate(expression) {
  const r = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description ?? r.exceptionDetails.text);
  return r.result.value;
}

async function navigate(path) {
  const loaded = waitFor("Page.loadEventFired");
  await send("Page.navigate", { url: BASE + path });
  await loaded;
  await new Promise((r) => setTimeout(r, 400));
}

async function viewport(width, height = 900) {
  await send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: false });
}

async function shot(name) {
  if (!SHOTS) return;
  const { data } = await send("Page.captureScreenshot", { format: "png" });
  mkdirSync(SHOTS, { recursive: true });
  writeFileSync(join(SHOTS, name), Buffer.from(data, "base64"));
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

before(async () => {
  if (!CHROME) return;
  profile = mkdtempSync(join(tmpdir(), "b10-cdp-"));
  proc = spawn(CHROME, ["--headless", "--mute-audio", "--no-first-run", "--disable-gpu", "--autoplay-policy=user-gesture-required", `--user-data-dir=${profile}`, "--remote-debugging-port=0", "about:blank"], { stdio: ["ignore", "ignore", "pipe"] });
  const wsUrl = await new Promise((resolve, reject) => {
    let buf = "";
    proc.stderr.on("data", (d) => {
      buf += d;
      const m = buf.match(/DevTools listening on (ws:\/\/\S+)/);
      if (m) resolve(m[1]);
    });
    setTimeout(() => reject(new Error("Chrome startet nicht")), 15000);
  });
  const port = new URL(wsUrl).port;
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = targets.find((t) => t.type === "page");
  ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      const p = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.error) p.reject(new Error(`${p.method}: ${msg.error.message}`));
      else p.resolve(msg.result);
    } else if (msg.method) {
      for (const fn of [...listeners]) fn(msg);
    }
  };
  await send("Page.enable");
  await send("Runtime.enable");
  await send("Network.enable");
  await send("Emulation.setFocusEmulationEnabled", { enabled: true });
  await viewport(1280);
});

after(async () => {
  try { ws?.close(); } catch {}
  if (proc) {
    const exited = new Promise((r) => proc.once("exit", r));
    proc.kill("SIGKILL");
    await exited;
  }
  if (profile) rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
});

test("AK-36: Seiten laden nur Ressourcen vom eigenen Ursprung (Netzwerkprotokoll des Browsers)", { skip }, async (t) => {
  for (const path of ["/", "/changelog", "/privacy", "/support"]) {
    const urls = [];
    const fn = (msg) => { if (msg.method === "Network.requestWillBeSent") urls.push(msg.params.request.url); };
    listeners.add(fn);
    await navigate(path);
    await evaluate("window.scrollTo(0, document.body.scrollHeight)");
    await sleep(600);
    listeners.delete(fn);
    const foreign = urls.filter((u) => !u.startsWith(BASE) && !u.startsWith("data:"));
    t.diagnostic(`${path}: ${urls.length} Anfragen, fremd: ${foreign.length}; Schriften: ${urls.filter((u) => u.endsWith(".woff2")).length}; Bilder: ${urls.filter((u) => u.includes("/_next/image")).length}`);
    assert.deepEqual(foreign, [], path);
    assert.ok(urls.some((u) => /\/_next\/static\/media\/[^/]+\.woff2$/.test(u)), `${path}: Schriften vom eigenen Ursprung`);
    assert.ok(urls.some((u) => u.includes("/_next/image?url=%2Ficon-512.png")), `${path}: Symbol über /_next/image`);
  }
});

test("AK-05: Kopfzeile bleibt beim Scrollen oben; Privacy unter 640 px ausgeblendet; Wortmarke unter 380 px nur für Screenreader", { skip }, async () => {
  await viewport(1280);
  await navigate("/");
  await evaluate("window.scrollTo(0, 2500)");
  await sleep(200);
  assert.equal(await evaluate("Math.round(document.querySelector('header').getBoundingClientRect().top)"), 0);
  assert.ok(await evaluate("window.scrollY") > 2000);
  const vis = (sel) => evaluate(`(() => { const e = document.querySelector(${JSON.stringify(sel)}); return getComputedStyle(e).display !== 'none'; })()`);
  assert.equal(await vis("header nav a[href='/privacy']"), true, "1280: Privacy sichtbar");
  await viewport(639);
  await navigate("/");
  assert.equal(await vis("header nav a[href='/privacy']"), false, "639: Privacy ausgeblendet");
  assert.equal(await vis("header a[href='/'] > span:not(.sr-only)"), true, "639: Wortmarke sichtbar");
  await viewport(379);
  await navigate("/");
  assert.equal(await vis("header a[href='/'] > span:not(.sr-only)"), false, "379: Wortmarke ausgeblendet");
  const sr = await evaluate("(() => { const e = document.querySelector('header a[href=\"/\"] > span.sr-only'); const s = getComputedStyle(e); return { text: e.textContent, w: e.getBoundingClientRect().width, pos: s.position, display: s.display }; })()");
  assert.deepEqual({ text: sr.text, pos: sr.pos }, { text: "Mika+Player", pos: "absolute" });
  assert.ok(sr.w <= 1, "sr-only: 1px breit");
  const overflow = await evaluate("document.documentElement.scrollWidth - window.innerWidth");
  assert.ok(overflow <= 0, `379 px: kein horizontales Scrollen (${overflow}px)`);
  await shot("AK-05-kopfzeile-379px.png");
  await viewport(380);
  await navigate("/");
  assert.equal(await vis("header a[href='/'] > span:not(.sr-only)"), true, "380: Wortmarke sichtbar");
  await viewport(1280);
});

test("AK-07: erster Tab zeigt „Skip to content“ oben links, Enter springt zu #main", { skip }, async () => {
  await viewport(1280);
  await navigate("/support");
  await send("Input.dispatchKeyEvent", { type: "keyDown", key: "Tab", code: "Tab", windowsVirtualKeyCode: 9 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Tab", code: "Tab", windowsVirtualKeyCode: 9 });
  await sleep(100);
  const focus = await evaluate("(() => { const e = document.activeElement; const r = e.getBoundingClientRect(); return { text: e.textContent, x: Math.round(r.left), y: Math.round(r.top), w: Math.round(r.width) }; })()");
  assert.equal(focus.text, "Skip to content");
  assert.ok(focus.w > 20 && focus.x <= 20 && focus.y <= 20, JSON.stringify(focus));
  await shot("AK-07-skip-link.png");
  await send("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
  await sleep(150);
  assert.equal(await evaluate("location.hash"), "#main");
  assert.equal(await evaluate("document.documentElement.lang"), "en");
});

test("AK-08: Farbgebung folgt prefers-color-scheme, kein Umschalter", { skip }, async () => {
  const bg = () => evaluate("getComputedStyle(document.body).backgroundColor");
  await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "light" }] });
  await navigate("/privacy");
  assert.equal(await bg(), "rgb(246, 244, 243)");
  await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "dark" }] });
  await sleep(150);
  assert.equal(await bg(), "rgb(18, 15, 16)");
  await shot("AK-08-dunkel.png");
  const toggles = await evaluate("[...document.querySelectorAll('button, [role=switch]')].filter(b => /theme|dark|light|mode/i.test(b.textContent + (b.getAttribute('aria-label') ?? ''))).length");
  assert.equal(toggles, 0);
  await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "light" }] });
});

test("AK-10: Multiview-Nachbau reagiert auf Klicks (Fokus und Raster), lädt nichts", { skip }, async () => {
  await viewport(1280);
  await navigate("/");
  const urls = [];
  const fn = (msg) => { if (msg.method === "Network.requestWillBeSent") urls.push(msg.params.request.url); };
  listeners.add(fn);
  const demo = (i) => `document.querySelectorAll('[aria-label^="Multiview demonstration"]')[${i}]`;
  const bigLabel = (i) => evaluate(`${demo(i)}.querySelector('.absolute.inset-x-0 p.font-display').textContent`);
  const hasBigSound = (i) => evaluate(`${demo(i)}.querySelector('.absolute.inset-x-0').textContent.includes('Sound')`);
  const tiles = (i) => evaluate(`[...${demo(i)}.querySelectorAll('button')].map(b => b.textContent.trim())`);

  assert.equal(await bigLabel(0), "News");
  assert.deepEqual(await tiles(0), ["02", "03", "04"]);
  await evaluate(`${demo(0)}.querySelectorAll('button')[1].click()`); // Kanal 03
  await sleep(100);
  assert.equal(await bigLabel(0), "Documentary");
  assert.equal(await hasBigSound(0), true);
  assert.deepEqual(await tiles(0), ["01", "02", "04"], "bisher große Kachel wird klein");

  const toggles = await evaluate(`[...document.querySelectorAll('[role=group][aria-labelledby=layout-label] button')].map(b => b.textContent)`);
  assert.deepEqual(toggles, ["focus", "grid"]);
  assert.equal(await evaluate("document.querySelectorAll('[role=group][aria-labelledby=layout-label]').length"), 1, "Umschalter nur im zweiten Nachbau");
  await evaluate(`[...document.querySelectorAll('[role=group][aria-labelledby=layout-label] button')][1].click()`);
  await sleep(100);
  const grid = await evaluate(`[...${demo(1)}.querySelectorAll('button')].map(b => ({ t: b.textContent.trim(), pressed: b.getAttribute('aria-pressed'), ring: b.className.includes('ring-accent'), w: Math.round(b.getBoundingClientRect().width), h: Math.round(b.getBoundingClientRect().height) }))`);
  assert.equal(grid.length, 4);
  assert.equal(new Set(grid.map((g) => `${g.w}x${g.h}`)).size, 1, `gleich große Kacheln: ${JSON.stringify(grid)}`);
  assert.equal(grid[0].pressed, "true");
  await evaluate(`${demo(1)}.querySelectorAll('button')[2].click()`);
  await sleep(100);
  const after = await evaluate(`[...${demo(1)}.querySelectorAll('button')].map(b => ({ t: b.textContent.trim(), pressed: b.getAttribute('aria-pressed'), ring: b.className.includes('ring-accent') }))`);
  assert.deepEqual(after.map((a) => a.pressed), ["false", "false", "true", "false"]);
  assert.ok(after[2].ring && after[2].t.includes("Sound"));
  assert.ok(!after[0].t.includes("Sound"));
  await evaluate(`${demo(1)}.scrollIntoView({block: 'center'})`);
  await sleep(150);
  await shot("AK-10-multiview-raster.png");
  listeners.delete(fn);
  assert.equal(await evaluate("document.querySelectorAll('video, audio, iframe').length"), 0);
  assert.deepEqual(urls.filter((u) => !u.startsWith(BASE) && !u.startsWith("data:")), []);
});

test("AK-23: Fragen anfangs zu, Klick öffnet und dreht das Plus", { skip }, async () => {
  await viewport(1280);
  await navigate("/support");
  assert.equal(await evaluate("[...document.querySelectorAll('details')].filter(d => d.open).length"), 0);
  assert.equal(await evaluate("document.querySelectorAll('details').length"), 9);
  // Tailwind v4: rotate-45 setzt die CSS-Eigenschaft `rotate`, nicht `transform`.
  const rot = () => evaluate("getComputedStyle(document.querySelector('details summary span')).rotate");
  const before = await rot();
  await evaluate("document.querySelector('details summary').scrollIntoView({block:'center'})");
  const box = await evaluate("(() => { const r = document.querySelector('details summary').getBoundingClientRect(); return { x: r.left + 20, y: r.top + r.height / 2 }; })()");
  for (const type of ["mousePressed", "mouseReleased"]) {
    await send("Input.dispatchMouseEvent", { type, x: box.x, y: box.y, button: "left", clickCount: 1 });
  }
  await sleep(450);
  assert.equal(await evaluate("document.querySelector('details').open"), true);
  const afterRot = await rot();
  assert.ok(before === "none" || before === "0deg", `vorher ${before}`);
  assert.equal(afterRot, "45deg");
  await shot("AK-23-faq-offen.png");
});

test("AK-23/EC-11: ohne JavaScript — Texte vorhanden, Frage klappt nativ auf, Multiview im Ausgangszustand", { skip }, async () => {
  await send("Emulation.setScriptExecutionDisabled", { value: true });
  try {
    await navigate("/support");
    const { root } = await send("DOM.getDocument", { depth: -1 });
    const { nodeId } = await send("DOM.querySelector", { nodeId: root.nodeId, selector: "details summary" });
    await send("DOM.scrollIntoViewIfNeeded", { nodeId });
    await sleep(100);
    const { model } = await send("DOM.getBoxModel", { nodeId });
    const [x1, y1, , , , y3] = model.content;
    const detailsId = (await send("DOM.querySelector", { nodeId: root.nodeId, selector: "details" })).nodeId;
    const attrsBefore = (await send("DOM.getAttributes", { nodeId: detailsId })).attributes;
    assert.ok(!attrsBefore.includes("open"));
    for (const type of ["mousePressed", "mouseReleased"]) {
      await send("Input.dispatchMouseEvent", { type, x: x1 + 10, y: (y1 + y3) / 2, button: "left", clickCount: 1 });
    }
    await sleep(300);
    const attrsAfter = (await send("DOM.getAttributes", { nodeId: detailsId })).attributes;
    assert.ok(attrsAfter.includes("open"), `details ohne JS nicht geöffnet: ${attrsAfter}`);
    const { outerHTML } = await send("DOM.getOuterHTML", { nodeId: root.nodeId });
    assert.ok(outerHTML.includes("macOS says the app cannot be opened. What now?"));
    assert.ok(outerHTML.includes("Nowhere. Playlists, credentials and favourites live in a local database"));

    await navigate("/");
    const doc = await send("DOM.getDocument", { depth: -1 });
    const home = (await send("DOM.getOuterHTML", { nodeId: doc.root.nodeId })).outerHTML;
    assert.ok(home.includes("Four streams. One window."));
    assert.match(home, /aria-pressed="true"[^>]*>focus<\/button>/);
  } finally {
    await send("Emulation.setScriptExecutionDisabled", { value: false });
  }
});

test("AK-37: Klick auf „Download for macOS“ geht direkt zu github.com, Referer nur Ursprung (Anfrage abgefangen, kein Download)", { skip }, async () => {
  await viewport(1280);
  await navigate("/");
  await send("Fetch.enable", { patterns: [{ urlPattern: "*github.com*", requestStage: "Request" }] });
  try {
    const paused = waitFor("Fetch.requestPaused");
    await evaluate("[...document.querySelectorAll('a')].find(a => a.textContent.includes('Download for macOS')).click()");
    const req = await paused;
    await send("Fetch.failRequest", { requestId: req.requestId, errorReason: "Aborted" });
    assert.equal(req.request.url, "https://github.com/daumedia/MikaPlusPlayer/releases/download/v1.1/MikaPlusPlayer-v1.1.dmg");
    assert.equal(req.request.headers.Referer, `${BASE}/`);
    assert.ok(!Object.keys(req.request.headers).some((k) => k.toLowerCase() === "cookie"));
  } finally {
    await send("Fetch.disable");
  }
});

test("FB-20 (BUG-09): CSP und Permissions-Policy aktiv — Seiten rendern ohne Verstöße, ohne Konsolenfehler, JavaScript läuft", { skip }, async (t) => {
  await viewport(1280);
  await send("Log.enable");
  const { identifier } = await send("Page.addScriptToEvaluateOnNewDocument", {
    source: "window.__qaCsp = []; addEventListener('securitypolicyviolation', (e) => window.__qaCsp.push({ directive: e.effectiveDirective, blocked: e.blockedURI, source: e.sourceFile, line: e.lineNumber, sample: e.sample }), true);",
  });
  const problems = [];
  const documents = [];
  const fn = (msg) => {
    const p = msg.params;
    if (msg.method === "Log.entryAdded" && ["error", "warning"].includes(p.entry.level)) problems.push(`log ${p.entry.level}/${p.entry.source}: ${p.entry.text} ${p.entry.url ?? ""}`);
    if (msg.method === "Runtime.exceptionThrown") problems.push(`exception: ${p.exceptionDetails.exception?.description ?? p.exceptionDetails.text}`);
    if (msg.method === "Runtime.consoleAPICalled" && ["error", "warning", "assert"].includes(p.type)) problems.push(`console.${p.type}: ${p.args.map((a) => a.value ?? a.description).join(" ")}`);
    if (msg.method === "Network.loadingFailed" && p.blockedReason) problems.push(`blocked (${p.blockedReason}): ${p.type}`);
    if (msg.method === "Network.responseReceived" && p.type === "Document") documents.push(p.response);
  };
  listeners.add(fn);
  try {
    for (const path of ["/", "/changelog", "/privacy", "/support"]) {
      await navigate(path);
      await evaluate("window.scrollTo(0, document.body.scrollHeight)");
      await sleep(500);

      const response = documents.findLast((r) => r.url === BASE + path);
      assert.ok(response, `${path}: Dokument-Antwort nicht gesehen`);
      const header = (name) => Object.entries(response.headers).find(([k]) => k.toLowerCase() === name)?.[1];
      assert.match(header("content-security-policy") ?? "", /script-src 'self' 'unsafe-inline'(;|$)/, `${path}: CSP nicht aktiv`);
      assert.match(header("permissions-policy") ?? "", /camera=\(\)/, `${path}: Permissions-Policy nicht aktiv`);

      const violations = await evaluate("window.__qaCsp");
      t.diagnostic(`${path}: CSP-Verstöße ${violations.length}`);
      assert.deepEqual(violations, [], `${path}: CSP-Verstöße`);
    }

    // Hydration unter der CSP: Der Multiview-Nachbau reagiert nur, wenn die Next-Skripte (auch die Inline-Skripte) laufen.
    await navigate("/");
    const demo = `document.querySelectorAll('[aria-label^="Multiview demonstration"]')[0]`;
    const big = () => evaluate(`${demo}.querySelector('.absolute.inset-x-0 p.font-display').textContent`);
    assert.equal(await big(), "News");
    await evaluate(`${demo}.querySelectorAll('button')[0].click()`);
    await sleep(150);
    assert.equal(await big(), "Sports", "Klick ohne Wirkung — JavaScript unter der CSP blockiert?");
    assert.deepEqual(await evaluate("window.__qaCsp"), []);

    t.diagnostic(`Konsole/Log/Netz: ${problems.length} Fehler oder Warnungen`);
    assert.deepEqual(problems, [], "Konsole, Log oder Netzwerk melden Fehler/Warnungen");
  } finally {
    listeners.delete(fn);
    await send("Page.removeScriptToEvaluateOnNewDocument", { identifier });
    await send("Log.disable");
  }
});
