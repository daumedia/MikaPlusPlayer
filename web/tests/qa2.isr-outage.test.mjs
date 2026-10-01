// B10 · Website — GitHub-Ausfall genau bei der ISR-Neuberechnung (EC-02; QA-Durchlauf 2, 2026-09-30)
//
// Ausführen (keine zusätzliche Abhängigkeit, dauert ca. 40–60 s, braucht installierte node_modules, kein Internet):
//   cd web && node --test --test-timeout=300000 tests/qa2.isr-outage.test.mjs
//
// Ablauf: Der Test kopiert web/ (ohne .next, node_modules und tests) in ein Temp-Verzeichnis, klont node_modules
// (macOS: `cp -c`), ersetzt in der KOPIE die Konstante `API` durch einen lokalen Mock der GitHub-API und verkürzt
// `REVALIDATE` von 3600 s auf REVALIDATE_S Sekunden, damit eine Neuberechnung in Sekunden statt in einer Stunde
// fällig wird. Der Produktcode in web/ bleibt unverändert.
//
// Zeitlinie: Build und Start mit gesundem Mock (200) → Mock liefert 503 → nach Ablauf der Frist ein Abruf, der die
// Neuberechnung auslöst → Stand ablesen → Mock wieder 200 → nach Ablauf erneut auslösen → Stand ablesen.
// Im Produktcode entspricht jede Frist einer Stunde.
//
// Tests, die einen Befund aus QA-Durchlauf 2 belegen, tragen { todo: "BUG-NN …" }.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { spawn, execFileSync } from "node:child_process";
import { cpSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const WEB = fileURLToPath(new URL("../", import.meta.url));
const REVALIDATE_S = 4;
const PORT = 3000 + Math.floor(Math.random() * 900) + 7000;
const BASE = `http://127.0.0.1:${PORT}`;
const SHA = "cd".repeat(32);
const DMG_URL = "https://github.com/daumedia/MikaPlusPlayer/releases/download/v9.9/MikaPlusPlayer-v9.9.dmg";
const LATEST_RELEASE_PAGE = "https://github.com/daumedia/MikaPlusPlayer/releases/latest";
const RELEASE = {
  tag_name: "v9.9", name: "v9.9", body: "QA mock notes", draft: false, prerelease: false,
  published_at: "2026-09-01T10:00:00Z", html_url: "https://github.com/daumedia/MikaPlusPlayer/releases/tag/v9.9",
  assets: [{ name: "MikaPlusPlayer-v9.9.dmg", size: 12_582_912, content_type: "application/x-apple-diskimage",
    browser_download_url: DMG_URL, download_count: 1, digest: `sha256:${SHA}` }],
};

const state = { ok: true, requests: [] };
const snapshots = {};
let mock, dir, server, serverLog = "";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function run(cmd, args, env) {
  return new Promise((resolve, reject) => {
    let out = "";
    const child = spawn(cmd, args, { cwd: join(dir, "web"), env, stdio: ["ignore", "pipe", "pipe"] });
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (out += d));
    child.on("exit", (code) => (code === 0 ? resolve(out) : reject(new Error(`${cmd} ${args.join(" ")} → ${code}\n${out}`))));
  });
}

async function snapshot() {
  const home = await (await fetch(`${BASE}/`)).text();
  const changelog = await (await fetch(`${BASE}/changelog`)).text();
  const buttons = [...home.matchAll(/<a href="([^"]+)"[^>]*>(?:(?!<\/a>)[\s\S])*Download for macOS<\/a>/g)].map((m) => m[1]);
  return {
    buttons,
    homeSha: home.includes(SHA),
    articles: (changelog.match(/<article /g) ?? []).length,
    changelogSha: changelog.includes(SHA),
    changelogNotice: changelog.includes("could not be loaded from GitHub just now"),
  };
}

/** Frist ablaufen lassen, Neuberechnung durch einen Abruf auslösen, ihr Zeit geben, dann ablesen. */
async function regenerateAndRead() {
  await sleep(REVALIDATE_S * 1000 + 1500);
  await fetch(`${BASE}/`);
  await fetch(`${BASE}/changelog`);
  await sleep(3000);
  return snapshot();
}

before(async () => {
  mock = http.createServer((req, res) => {
    state.requests.push({ url: req.url, ok: state.ok });
    if (!state.ok) {
      res.writeHead(503, { "content-type": "application/json" });
      return res.end('{"message":"Service Unavailable"}');
    }
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify(req.url.endsWith("/releases/latest") ? RELEASE : [RELEASE]));
  });
  await new Promise((r) => mock.listen(0, "127.0.0.1", r));

  dir = mkdtempSync(join(tmpdir(), "b10-qa2-isr-"));
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
  const patched = src
    .replace('const API = "https://api.github.com";', `const API = "http://127.0.0.1:${mock.address().port}";`)
    .replace("const REVALIDATE = 3600;", `const REVALIDATE = ${REVALIDATE_S};`);
  assert.equal((patched.match(/127\.0\.0\.1/g) ?? []).length, 1, "API-Konstante in der Kopie nicht gefunden");
  assert.ok(patched.includes(`const REVALIDATE = ${REVALIDATE_S};`), "REVALIDATE in der Kopie nicht gefunden");
  writeFileSync(releasesPath, patched);

  const env = { ...process.env, NEXT_TELEMETRY_DISABLED: "1" };
  delete env.GITHUB_TOKEN;
  delete env.NEXT_PUBLIC_SITE_URL;
  delete env.VERCEL_PROJECT_PRODUCTION_URL;
  const nextBin = join(dir, "web", "node_modules", "next", "dist", "bin", "next");
  await run(process.execPath, [nextBin, "build"], env);
  server = spawn(process.execPath, [nextBin, "start", "-H", "127.0.0.1", "-p", String(PORT)], {
    cwd: join(dir, "web"), env, stdio: ["ignore", "pipe", "pipe"],
  });
  server.stdout.on("data", (d) => (serverLog += d));
  server.stderr.on("data", (d) => (serverLog += d));
  for (let i = 0; i < 100; i++) {
    try { if ((await fetch(`${BASE}/privacy`)).ok) break; } catch {}
    await sleep(200);
  }

  snapshots.afterBuild = await snapshot();
  state.ok = false;
  snapshots.duringOutage = await regenerateAndRead();
  state.ok = true;
  snapshots.afterRecovery = await regenerateAndRead();
});

after(async () => {
  server?.kill("SIGTERM");
  await new Promise((r) => mock.close(r));
  if (dir && !process.env.QA_KEEP_COPY) rmSync(dir, { recursive: true, force: true });
});

test("EC-02 (belegt): ein GitHub-Fehler bei der Neuberechnung ersetzt / und /changelog durch den Ersatzzustand, bis eine spätere Neuberechnung gelingt", (t) => {
  t.diagnostic(`nach dem Build: ${JSON.stringify(snapshots.afterBuild)}`);
  t.diagnostic(`nach Neuberechnung im Ausfall: ${JSON.stringify(snapshots.duringOutage)}`);
  t.diagnostic(`nach Erholung: ${JSON.stringify(snapshots.afterRecovery)}`);
  t.diagnostic(`Mock-Anfragen: ${state.requests.map((r) => `${r.url.split("/").pop()}=${r.ok ? 200 : 503}`).join(", ")}`);
  assert.deepEqual(snapshots.afterBuild.buttons, [DMG_URL, DMG_URL], "nach dem Build: direkter DMG-Link");
  assert.ok(snapshots.afterBuild.homeSha && snapshots.afterBuild.changelogSha && snapshots.afterBuild.articles === 1);
  assert.ok(state.requests.some((r) => !r.ok), "die Neuberechnung hat GitHub im Ausfall wirklich gefragt");
  assert.deepEqual(snapshots.duringOutage.buttons, [LATEST_RELEASE_PAGE, LATEST_RELEASE_PAGE], "im Ausfall: Link auf die Release-Seite");
  assert.equal(snapshots.duringOutage.homeSha, false, "im Ausfall: keine Prüfsumme auf /");
  assert.equal(snapshots.duringOutage.articles, 0, "im Ausfall: Changelog ohne Einträge");
  assert.ok(snapshots.duringOutage.changelogNotice, "im Ausfall: Hinweis im Changelog");
  assert.deepEqual(snapshots.afterRecovery.buttons, [DMG_URL, DMG_URL], "nach der Erholung wieder der DMG-Link");
  assert.ok(!/\bat \w+ \(/.test(serverLog), "kein Stacktrace eines abgebrochenen Renderings");
});

test("BUG-16 (Soll): ein einzelner Fehler bei der Neuberechnung lässt DMG-Link, Prüfsumme und Changelog des letzten guten Stands stehen", { todo: "BUG-16 Ausfall bei der Neuberechnung entfernt Prüfsumme bis zur nächsten Neuberechnung" }, () => {
  assert.deepEqual(snapshots.duringOutage.buttons, [DMG_URL, DMG_URL], "DMG-Link bleibt");
  assert.ok(snapshots.duringOutage.homeSha, "Prüfsumme auf / bleibt (Support-Schritt 02 verweist darauf)");
  assert.ok(snapshots.duringOutage.changelogSha && snapshots.duringOutage.articles === 1, "Changelog bleibt");
});
