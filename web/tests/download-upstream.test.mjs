// B10 · Website — Upstream-Verhalten von /download und Changelog-Rendering am echten Build (QA-Durchlauf 1, 2026-09-15;
// angepasst bei der Reparatur Teil 1, 2026-09-16: BUG-04, BUG-08, BUG-10 behoben, BUG-06 Prüfsumme;
// Reparatur Teil 2, 2026-09-30: AK-34 prüft die Download-Beschriftung statt jedes „Version 1.1“ im Text,
// weil die Seitentexte seit BUG-02/BUG-07 bewusst das Release v1.1 benennen)
//
// Ausführen (keine zusätzliche Abhängigkeit, dauert ca. 30–60 s, braucht installierte node_modules):
//   cd web && node --test --test-timeout=300000 tests/download-upstream.test.mjs
//
// Ablauf: Der Test kopiert web/ (ohne .next und tests) in ein Temp-Verzeichnis, klont node_modules
// (macOS: `cp -c`, sonst normale Kopie), ersetzt in der KOPIE nur die Konstante `API` in lib/releases.ts
// durch `process.env.QA_GITHUB_API ?? "https://api.github.com"` und zeigt damit auf einen lokalen
// Mock der GitHub-API (127.0.0.1, zufälliger Port). Außerdem wird in der KOPIE das Fehlerfenster von
// /download (`DOWNLOAD_RETRY_AFTER_MS`, im Produktcode 5 Minuten) auf RETRY_MS verkürzt, damit der
// Test Ablauf des Fensters und die Erholung nach einem Fehler in Sekunden beobachten kann. Der Mock zählt jede Anfrage und schreibt die
// Header mit. Danach `next build` und `next start -H 127.0.0.1` in der Kopie. Der Produktcode in web/
// bleibt unverändert; es gibt keinen Zugriff auf das echte GitHub.
//
// Mock-Verhalten: /releases/latest antwortet zunächst 403 mit x-ratelimit-remaining: 0 (erschöpftes
// Limit, EC-01), später 200. /releases?per_page=20 antwortet 200 mit einem Entwurf, einer
// Vorabversion mit feindseligem Markdown/HTML und v1.1.
//
// Tests, die einen gefundenen Fehler belegen, tragen { todo: "BUG-NN …" }.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { spawn, execFileSync } from "node:child_process";
import { cpSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const WEB = fileURLToPath(new URL("../", import.meta.url));
const TOKEN = "qa-fake-token-4711";
const VISITOR = {
  ua: "qa-visitor-agent/1.0 marker-ua-93817",
  cookie: "session=marker-cookie-55120",
  xff: "203.0.113.77",
  referer: "https://referer.example/marker-ref-4410",
  query: "email=qa-visitor%40example.com",
};
const MALICIOUS = [
  "# Heading One",
  "## Heading Two",
  '<script>alert("qa-xss-1")</script>',
  "<img src=x onerror=\"alert('qa-xss-2')\">",
  '<iframe src="https://evil.example/"></iframe>',
  "<a href=\"javascript:alert('qa-xss-3')\">raw link</a>",
  "",
  "[md-js](javascript:alert('qa-xss-4')) [md-vb](vbscript:msgbox('qa-xss-5')) [md-data](data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==)",
  "",
  "[md-http](https://example.com/qa-link) Autolink: https://example.org/qa-auto",
  "",
  "![qa-image](https://evil.example/qa.png) ![qa-ref][ref]",
  "",
  "---",
  "",
  "| a | b |",
  "|---|---|",
  "| 1 | 2 |",
  "",
  "[ref]: https://evil.example/ref.png",
].join("\n");

const DMG = (tag, name = `MikaPlusPlayer-${tag}.dmg`, digest = undefined) => ({
  name,
  size: 1_048_576 * 12,
  content_type: "application/x-apple-diskimage",
  browser_download_url: `https://github.com/daumedia/MikaPlusPlayer/releases/download/${tag}/${name}`,
  download_count: 1,
  ...(digest === undefined ? {} : { digest }),
});
const BETA_SHA = "ab".repeat(32);
const RETRY_MS = 4000;
const LATEST_RELEASE_PAGE = "https://github.com/daumedia/MikaPlusPlayer/releases/latest";
const REL = (tag, extra) => ({
  tag_name: tag,
  name: tag,
  body: "",
  draft: false,
  prerelease: false,
  published_at: "2026-09-01T10:00:00Z",
  html_url: `https://github.com/daumedia/MikaPlusPlayer/releases/tag/${tag}`,
  assets: [],
  ...extra,
});

const state = { latestOk: false, requests: [] };
let mock, mockPort, dir, server, serverLog = "", buildLog = "";
const PORT = 3000 + Math.floor(Math.random() * 900) + 7000;
const BASE = `http://127.0.0.1:${PORT}`;

function latestHits() {
  return state.requests.filter((r) => r.url === "/repos/daumedia/MikaPlusPlayer/releases/latest").length;
}

function run(cmd, args, env, onData) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { cwd: join(dir, "web"), env, stdio: ["ignore", "pipe", "pipe"] });
    child.stdout.on("data", (d) => onData(String(d)));
    child.stderr.on("data", (d) => onData(String(d)));
    child.on("error", reject);
    child.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`${cmd} ${args.join(" ")} → ${code}`))));
  });
}

before(async () => {
  mock = http.createServer((req, res) => {
    state.requests.push({ method: req.method, url: req.url, headers: { ...req.headers }, at: Date.now() });
    if (req.url === "/repos/daumedia/MikaPlusPlayer/releases/latest") {
      if (!state.latestOk) {
        res.writeHead(403, { "content-type": "application/json", "x-ratelimit-remaining": "0" });
        return res.end('{"message":"API rate limit exceeded"}');
      }
      res.writeHead(200, { "content-type": "application/json" });
      return res.end(JSON.stringify(REL("v9.9", { assets: [DMG("v9.9")] })));
    }
    if (req.url === "/repos/daumedia/MikaPlusPlayer/releases?per_page=20") {
      res.writeHead(200, { "content-type": "application/json" });
      return res.end(JSON.stringify([
        REL("v9.10-draft", { draft: true, body: "DRAFT-MARKER" }),
        REL("v9.9-beta", { prerelease: true, body: MALICIOUS, assets: [DMG("v9.9-beta", undefined, `sha256:${BETA_SHA}`)] }),
        REL("v9.8", { body: "   \n" }),
        REL("v1.1", { body: "Deutscher Text, der ersetzt wird" , assets: [DMG("v1.1", undefined, "sha512:<b>kein-sha256</b>")] }),
      ]));
    }
    res.writeHead(404);
    res.end();
  });
  await new Promise((r) => mock.listen(0, "127.0.0.1", r));
  mockPort = mock.address().port;

  dir = mkdtempSync(join(tmpdir(), "b10-qa-"));
  cpSync(WEB, join(dir, "web"), {
    recursive: true,
    filter: (src) => !/[\\/](node_modules|\.next|tests)([\\/]|$)/.test(src.slice(WEB.length - 1)),
  });
  try {
    execFileSync("cp", ["-cR", join(WEB, "node_modules"), join(dir, "web", "node_modules")]);
  } catch {
    cpSync(join(WEB, "node_modules"), join(dir, "web", "node_modules"), { recursive: true });
  }
  const releasesPath = join(dir, "web", "lib", "releases.ts");
  const src = readFileSync(releasesPath, "utf8");
  const patchedApi = src.replace('const API = "https://api.github.com";', 'const API = process.env.QA_GITHUB_API ?? "https://api.github.com";');
  assert.notEqual(patchedApi, src, "API-Konstante in der Kopie nicht gefunden");
  const patched = patchedApi.replace("export const DOWNLOAD_RETRY_AFTER_MS = 5 * 60 * 1000;", `export const DOWNLOAD_RETRY_AFTER_MS = ${RETRY_MS};`);
  assert.notEqual(patched, patchedApi, "DOWNLOAD_RETRY_AFTER_MS in der Kopie nicht gefunden");
  writeFileSync(releasesPath, patched);

  const env = { ...process.env, QA_GITHUB_API: `http://127.0.0.1:${mockPort}`, GITHUB_TOKEN: TOKEN, NEXT_TELEMETRY_DISABLED: "1" };
  delete env.NEXT_PUBLIC_SITE_URL;
  delete env.VERCEL_PROJECT_PRODUCTION_URL;
  const nextBin = join(dir, "web", "node_modules", "next", "dist", "bin", "next");
  await run(process.execPath, [nextBin, "build"], env, (d) => (buildLog += d));

  server = spawn(process.execPath, [nextBin, "start", "-H", "127.0.0.1", "-p", String(PORT)], {
    cwd: join(dir, "web"), env, stdio: ["ignore", "pipe", "pipe"],
  });
  server.stdout.on("data", (d) => (serverLog += d));
  server.stderr.on("data", (d) => (serverLog += d));
  for (let i = 0; i < 100; i++) {
    try { if ((await fetch(`${BASE}/privacy`)).ok) break; } catch {}
    await new Promise((r) => setTimeout(r, 200));
  }
});

after(async () => {
  server?.kill("SIGTERM");
  await new Promise((r) => mock.close(r));
  if (dir && !process.env.QA_KEEP_COPY) rmSync(dir, { recursive: true, force: true });
});

const get = (path, init = {}) => fetch(BASE + path, { redirect: "manual", ...init });

function articles(page) {
  return [...page.matchAll(/<article [\s\S]*?<\/article>/g)].map((m) => m[0]);
}

test("AK-18/EC-04: Changelog am echten Build — Entwurf fehlt, Vorabversion erscheint mit DMG-Link, Reihenfolge der API", async () => {
  const page = await (await get("/changelog")).text();
  const arts = articles(page);
  assert.equal(arts.length, 3);
  assert.match(arts[0], /v9\.9-beta/);
  assert.match(arts[0], /Download (<!-- -->)?MikaPlusPlayer-v9\.9-beta\.dmg/);
  assert.match(arts[1], /v9\.8/);
  assert.ok(!arts[1].includes('class="prose'), "AK-19: leerer Text erzeugt keinen Notizblock");
  assert.ok(!arts[1].includes("Download "), "ohne Asset kein Download-Link");
  assert.match(arts[2], /v1\.1/);
  assert.ok(!page.includes("DRAFT-MARKER") && !page.includes("v9.10-draft"));
  assert.match(arts[2], /Multiview \(macOS\)/, "Ersatztext für v1.1 statt GitHub-Text");
  assert.ok(!arts[2].includes("Deutscher Text"));
  assert.match(arts[0], new RegExp(`SHA-256 (<!-- -->)?${BETA_SHA}<`), "BUG-06: Prüfsumme aus dem Asset-digest");
  assert.ok(!/SHA-256 (<!-- -->)?[0-9a-f]{64}/.test(arts[2]) && !arts[2].includes("kein-sha256"), "BUG-06: ungültiger digest erscheint nicht");
});

test("AK-20: feindseliges Markdown/HTML wird maskiert bzw. entschärft", async () => {
  const [a] = articles(await (await get("/changelog")).text());
  assert.ok(a.includes('&lt;script&gt;alert(&quot;qa-xss-1&quot;)&lt;/script&gt;') || a.includes("&lt;script&gt;"), "script als Text");
  assert.ok(!/<script\b/i.test(a), "kein script-Element");
  assert.ok(!/<img\b/i.test(a), "kein img-Element (auch nicht per Referenz)");
  assert.ok(!/<iframe\b/i.test(a), "kein iframe-Element");
  assert.ok(!/<[a-z]+[^>]*\sonerror=/i.test(a), "kein onerror-Attribut in einem Tag");
  assert.ok(!/href="(javascript|vbscript|data):/i.test(a), "kein gefährliches href");
  for (const label of ["md-js", "md-vb", "md-data"]) {
    assert.match(a, new RegExp(`<a href=""[^>]*>${label}</a>`), `${label}: leeres href`);
  }
  assert.match(a, /<a href="https:\/\/example\.com\/qa-link" target="_blank" rel="noopener noreferrer"[^>]*>md-http<\/a>/);
  assert.match(a, /<a href="https:\/\/example\.org\/qa-auto" target="_blank" rel="noopener noreferrer"[^>]*>https:\/\/example\.org\/qa-auto<\/a>/);
  assert.ok(!/<hr\b/i.test(a), "keine Trennlinie");
  assert.ok(!/<h1\b|<h2\b[^>]*>Heading/i.test(a), "keine h1/h2 aus dem Release-Text");
  assert.match(a, /<h3[^>]*>Heading One<\/h3>/);
  assert.match(a, /<h3[^>]*>Heading Two<\/h3>/);
  assert.match(a, /<table>/, "GFM-Tabelle");
});

test("EC-07 (BUG-10 behoben): kein ungültiges node-Attribut an h3/a", async () => {
  const [a] = articles(await (await get("/changelog")).text());
  assert.ok(!a.includes('node="[object Object]"'), `Treffer: ${(a.match(/node="\[object Object\]"/g) ?? []).length}`);
});

// Erster /download-Aufruf dieses Laufs: Das Fehlerfenster ist noch leer, also geht genau eine Anfrage an den Mock.
test("AK-31/AK-37/Angriff PII: Upstream-Anfrage trägt feste Header und Bearer-Token, aber keine Besucherdaten", async () => {
  const before = state.requests.length;
  await get(`/download?${VISITOR.query}`, {
    headers: { "user-agent": VISITOR.ua, cookie: VISITOR.cookie, "x-forwarded-for": VISITOR.xff, referer: VISITOR.referer },
  });
  const upstream = state.requests.slice(before);
  assert.equal(upstream.length, 1, "erster Aufruf: genau eine Anfrage");
  const h = upstream[0].headers;
  assert.equal(h.authorization, `Bearer ${TOKEN}`);
  assert.equal(h["user-agent"], "mikaplusplayer-website");
  assert.equal(h.accept, "application/vnd.github+json");
  assert.equal(h["x-github-api-version"], "2022-11-28");
  const dump = JSON.stringify(upstream);
  for (const marker of ["marker-ua-93817", "marker-cookie-55120", "203.0.113.77", "marker-ref-4410", "qa-visitor", "example.com"]) {
    assert.ok(!dump.includes(marker), `Besucherdatum ${marker} an GitHub weitergereicht`);
  }
  assert.deepEqual(Object.keys(h).sort().filter((k) => !["host", "connection", "accept-encoding", "accept-language", "sec-fetch-mode", "authorization", "user-agent", "accept", "x-github-api-version"].includes(k)), []);
});

test("AK-34 (BUG-08 behoben): GitHub antwortet nicht mit 200 → /download leitet auf die Seite des neuesten Releases, nicht auf ein festes v1.1-DMG", async () => {
  for (let i = 0; i < 4; i++) {
    const res = await get("/download");
    assert.equal(res.status, 302);
    assert.equal(res.headers.get("location"), LATEST_RELEASE_PAGE);
  }
  const home = await (await get("/")).text();
  const buttons = [...home.matchAll(/<a href="([^"]+)"[^>]*>(?:(?!<\/a>)[\s\S])*Download for macOS<\/a>/g)].map((m) => m[1]);
  assert.deepEqual(buttons, [LATEST_RELEASE_PAGE, LATEST_RELEASE_PAGE], "Startseite (beim Build ohne Release-Daten) verlinkt die Release-Seite");
  assert.match(home, /Latest release on GitHub/);
  // Die Seitentexte beschreiben seit Teil 2 bewusst das Release v1.1 („Version 1.1 still pauses …“). Fest verdrahtet
  // wäre ein v1.1-DMG-Link oder die Download-Beschriftung „Version 1.1 · <Größe> · macOS …“ ohne Release-Daten.
  assert.ok(!home.includes("v1.1/MikaPlusPlayer-v1.1.dmg"), "kein fest verdrahteter v1.1-DMG-Link");
  const homeText = home.replace(/<!-- -->/g, "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ");
  assert.ok(!/Version 1\.1 · /.test(homeText), "keine fest verdrahtete v1.1-Beschriftung unter der Schaltfläche");
  assert.ok((homeText.match(/Latest release on GitHub · macOS 14 Sonoma or later/g) ?? []).length >= 2, "beide Beschriftungen ohne Version");
});

test("AK-34/FB-21 (BUG-04 behoben): im Fehlerfall höchstens eine Upstream-Anfrage je Zeitfenster; gleichzeitige Aufrufe teilen sich eine", async (t) => {
  const beforeSeq = latestHits();
  const logBefore = (serverLog.match(/\[releases\] \/repos\/daumedia\/MikaPlusPlayer\/releases\/latest -> 403/g) ?? []).length;
  for (let i = 0; i < 4; i++) await get("/download");
  const seq = latestHits() - beforeSeq;
  const beforePar = latestHits();
  const res = await Promise.all(Array.from({ length: 60 }, () => get("/download")));
  const par = latestHits() - beforePar;
  await new Promise((r) => setTimeout(r, 300));
  const logLines = (serverLog.match(/\[releases\] \/repos\/daumedia\/MikaPlusPlayer\/releases\/latest -> 403/g) ?? []).length - logBefore;
  t.diagnostic(`im Fenster: 4 sequentielle Aufrufe → ${seq} Upstream-Anfragen; 60 parallele Aufrufe → ${par} Upstream-Anfragen; Status: ${[...new Set(res.map((r) => r.status))].join(",")}; neue Warnzeilen: ${logLines}`);
  assert.ok(res.every((r) => r.status === 302 && r.headers.get("location") === LATEST_RELEASE_PAGE));
  assert.ok(seq + par <= 1, `erwartet ≤ 1 Upstream-Anfrage für 64 Aufrufe, tatsächlich ${seq + par}`);

  // Fenster ablaufen lassen: Ein Schwall gleichzeitiger Aufrufe erzeugt genau eine neue Anfrage.
  await new Promise((r) => setTimeout(r, RETRY_MS + 500));
  const beforeBurst = latestHits();
  const burst = await Promise.all(Array.from({ length: 60 }, () => get("/download")));
  const afterWindow = latestHits() - beforeBurst;
  t.diagnostic(`nach Ablauf des Fensters: 60 parallele Aufrufe → ${afterWindow} Upstream-Anfrage(n)`);
  assert.ok(burst.every((r) => r.status === 302));
  assert.equal(afterWindow, 1);
});

test("AK-15: nach einer 200-Antwort lösen weitere Aufrufe keine Upstream-Anfrage aus (Erholung nach Ablauf des Fehlerfensters)", async (t) => {
  state.latestOk = true;
  await new Promise((r) => setTimeout(r, RETRY_MS + 500));
  const first = await get("/download");
  assert.equal(first.headers.get("location"), "https://github.com/daumedia/MikaPlusPlayer/releases/download/v9.9/MikaPlusPlayer-v9.9.dmg");
  const afterFirst = latestHits();
  for (let i = 0; i < 6; i++) {
    const res = await get("/download");
    assert.equal(res.status, 302);
    assert.equal(res.headers.get("location"), first.headers.get("location"));
  }
  t.diagnostic(`6 Aufrufe nach 200 → ${latestHits() - afterFirst} Upstream-Anfragen`);
  assert.equal(latestHits() - afterFirst, 0);
});

test("AK-39/Angriff PII in Logs: Build- und Serverprotokoll ohne Token und ohne Besucherdaten", async () => {
  const logs = buildLog + serverLog;
  assert.match(logs, /\[releases\] \/repos\/daumedia\/MikaPlusPlayer\/releases\/latest -> 403; rate limit remaining: 0/);
  for (const marker of [TOKEN, "marker-ua-93817", "marker-cookie-55120", "203.0.113.77", "marker-ref-4410", "qa-visitor"]) {
    assert.ok(!logs.includes(marker), `Protokoll enthält ${marker}`);
  }
});

test("AK-38: Token nicht im Browser-Bundle des Builds mit gesetztem GITHUB_TOKEN", () => {
  let out = "";
  try {
    out = execFileSync("grep", ["-rl", TOKEN, join(dir, "web", ".next", "static")], { encoding: "utf8" }).trim();
  } catch (error) {
    assert.equal(error.status, 1, "grep: 1 = kein Treffer");
  }
  assert.equal(out, "");
});
