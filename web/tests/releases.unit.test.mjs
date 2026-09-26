// B10 · Website — Unit-Tests für lib/releases.ts und lib/format.ts (QA-Durchlauf 1, 2026-09-15;
// angepasst bei der Reparatur Teil 1, 2026-09-16: BUG-04, BUG-06 Prüfsumme, BUG-08 kein fest verdrahtetes Ersatz-Release)
//
// Ausführen (ohne zusätzliche Abhängigkeit, Node >= 23.6 wegen TypeScript-Type-Stripping):
//   cd web && node --test tests/releases.unit.test.mjs
// Unter Node 22 zusätzlich: --experimental-strip-types
//
// Die Datei lädt die echten Module aus lib/ und ersetzt nur globalThis.fetch durch einen Stub.
// Der Pfad-Alias "@/…" aus tsconfig.json wird über module.registerHooks aufgelöst.
// Kein Netzwerk, kein Server nötig.

import { registerHooks } from "node:module";
import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const WEB_ROOT = new URL("../", import.meta.url);

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith("@/")) {
      let target = new URL(specifier.slice(2), WEB_ROOT).href;
      if (!/\.[cm]?[jt]sx?$/.test(target)) target += ".ts";
      return nextResolve(target, context);
    }
    return nextResolve(specifier, context);
  },
});

const { getLatestRelease, getLatestReleaseForDownload, getReleases, DOWNLOAD_RETRY_AFTER_MS } = await import("../lib/releases.ts");
const { formatBytes, formatDate } = await import("../lib/format.ts");

const LATEST = "/repos/daumedia/MikaPlusPlayer/releases/latest";
const LIST = "/repos/daumedia/MikaPlusPlayer/releases?per_page=20";

const realFetch = globalThis.fetch;
const realWarn = console.warn;
const realToken = process.env.GITHUB_TOKEN;
let calls;
let warnings;

function asset(name, contentType, size = 1000, digest = undefined) {
  return {
    name,
    size,
    content_type: contentType,
    browser_download_url: `https://github.com/daumedia/MikaPlusPlayer/releases/download/x/${name}`,
    download_count: 7,
    ...(digest === undefined ? {} : { digest }),
  };
}

const HASH = "8da0620e570badddd25d7d94ccfc7e4aae953b79c8046ddf099b7c9d845a272c";

function release(tag, extra = {}) {
  return {
    tag_name: tag,
    name: `${tag} name`,
    body: "Body",
    draft: false,
    prerelease: false,
    published_at: "2026-09-01T10:00:00Z",
    html_url: `https://github.com/daumedia/MikaPlusPlayer/releases/tag/${tag}`,
    assets: [],
    ...extra,
  };
}

/** routes: { [path]: {status, json} | (() => never) } */
function stubFetch(routes) {
  globalThis.fetch = async (input, init = {}) => {
    const url = String(input);
    calls.push({ url, init });
    const path = url.replace("https://api.github.com", "");
    const route = routes[path];
    if (typeof route === "function") return route();
    if (!route) return new Response("not found", { status: 404 });
    return new Response(JSON.stringify(route.json ?? {}), {
      status: route.status ?? 200,
      headers: route.headers ?? {},
    });
  };
}

beforeEach(() => {
  calls = [];
  warnings = [];
  console.warn = (...args) => warnings.push(args);
  delete process.env.GITHUB_TOKEN;
});

afterEach(() => {
  globalThis.fetch = realFetch;
  console.warn = realWarn;
  if (realToken === undefined) delete process.env.GITHUB_TOKEN;
  else process.env.GITHUB_TOKEN = realToken;
});

test("AK-14/AK-17: DMG nach Content-Type, auch wenn vorher ein .DMG-Name steht", async () => {
  stubFetch({
    [LATEST]: {
      json: release("v2.0", {
        assets: [
          asset("notes.zip", "application/zip"),
          asset("Other.DMG", "application/octet-stream", 5),
          asset("real.dmg", "application/x-apple-diskimage", 36_455_860, `sha256:${HASH}`),
        ],
      }),
    },
  });
  const r = await getLatestRelease();
  assert.equal(r.dmg.name, "real.dmg");
  assert.equal(r.dmg.sizeBytes, 36_455_860);
  assert.equal(r.version, "2.0");
  assert.equal(r.dmg.sha256, HASH, "BUG-06: Prüfsumme aus dem Asset-digest");
});

test("BUG-06: Prüfsumme nur aus einem gültigen sha256-digest, sonst null", async () => {
  const cases = [
    [`sha256:${HASH.toUpperCase()}`, HASH],
    [undefined, null],
    [null, null],
    ["", null],
    [`sha512:${HASH}${HASH}`, null],
    [`sha256:${HASH.slice(1)}`, null],
    [`sha256:${HASH}<script>`, null],
  ];
  for (const [digest, expected] of cases) {
    stubFetch({ [LATEST]: { json: release("v2.0", { assets: [asset("a.dmg", "application/x-apple-diskimage", 1, digest)] }) } });
    const r = await getLatestRelease();
    assert.equal(r.dmg.sha256, expected, String(digest));
  }
});

test("AK-17: ohne Disk-Image-Content-Type gilt das erste Asset mit Endung .dmg (Groß-/Kleinschreibung egal)", async () => {
  stubFetch({
    [LATEST]: {
      json: release("v2.1", {
        assets: [
          asset("a.zip", "application/zip"),
          asset("MikaPlusPlayer.DMG", "application/octet-stream"),
          asset("second.dmg", "application/octet-stream"),
        ],
      }),
    },
  });
  const r = await getLatestRelease();
  assert.equal(r.dmg.name, "MikaPlusPlayer.DMG");
});

test("AK-16/EC-03 (BUG-08): neues Release ohne DMG → kein fremder v1.1-Link, sondern die Seite dieses Releases", async () => {
  stubFetch({ [LATEST]: { json: release("v3.0", { assets: [asset("a.zip", "application/zip")] }) } });
  const r = await getLatestRelease();
  assert.equal(r.version, "3.0");
  assert.equal(r.tag, "v3.0");
  assert.equal(r.dmg, null);
  assert.equal(r.htmlUrl, "https://github.com/daumedia/MikaPlusPlayer/releases/tag/v3.0");
  assert.ok(!JSON.stringify(r).includes("v1.1"), "kein fest verdrahtetes v1.1");
});

test("AK-18/EC-04: Changelog filtert Entwürfe, behält Vorabversionen und die API-Reihenfolge", async () => {
  stubFetch({
    [LIST]: {
      json: [
        release("v4.0-beta", { prerelease: true }),
        release("v3.9", { draft: true }),
        release("v3.8", { name: "   " }),
        release("v3.7", { name: null }),
      ],
    },
  });
  const list = await getReleases();
  assert.deepEqual(
    list.map((r) => r.tag),
    ["v4.0-beta", "v3.8", "v3.7"],
  );
  assert.equal(list[1].title, "v3.8", "leerer Name → Tag");
  assert.equal(list[2].title, "v3.7", "null-Name → Tag");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, `https://api.github.com${LIST}`);
});

test("AK-19: Ersatztext für v1.1 ersetzt den GitHub-Text; sonst getrimmter GitHub-Text; leer → leer", async () => {
  stubFetch({
    [LIST]: {
      json: [
        release("v1.1", { body: "Deutscher Text" }),
        release("v1.2", { body: "  **Neu**  \n" }),
        release("v1.3", { body: null }),
      ],
    },
  });
  const [v11, v12, v13] = await getReleases();
  assert.ok(v11.notes.startsWith("**Multiview (macOS)** — watch up to four streams at once"));
  assert.equal(v12.notes, "**Neu**");
  assert.equal(v13.notes, "");
});

test("AK-18 (BUG-08): leere Release-Liste → leere Liste, kein Ersatz-Release", async () => {
  stubFetch({ [LIST]: { json: [] } });
  assert.deepEqual(await getReleases(), []);
});

test("AK-31: ohne GITHUB_TOKEN kein Authorization-Header, feste Header gesetzt", async () => {
  stubFetch({ [LATEST]: { json: release("v2.0") } });
  await getLatestRelease();
  const headers = calls[0].init.headers;
  assert.equal(headers.Authorization, undefined);
  assert.equal(headers.Accept, "application/vnd.github+json");
  assert.equal(headers["X-GitHub-Api-Version"], "2022-11-28");
  assert.equal(headers["User-Agent"], "mikaplusplayer-website");
  assert.deepEqual(calls[0].init.next, { revalidate: 3600, tags: ["github-releases"] });
});

test("AK-31: mit GITHUB_TOKEN wird er als Bearer gesendet", async () => {
  process.env.GITHUB_TOKEN = "qa-fake-token-0000";
  stubFetch({ [LATEST]: { json: release("v2.0") } });
  await getLatestRelease();
  assert.equal(calls[0].init.headers.Authorization, "Bearer qa-fake-token-0000");
});

test("AK-32/AK-39 (BUG-08): 401 → keine Release-Daten (null) statt v1.1, Warnzeile exakt, ohne Token", async () => {
  process.env.GITHUB_TOKEN = "qa-fake-token-0000";
  stubFetch({
    [LATEST]: { status: 401, json: { message: "Bad credentials" } },
    [LIST]: { status: 401, json: { message: "Bad credentials" } },
  });
  const latest = await getLatestRelease();
  const list = await getReleases();
  assert.equal(latest, null);
  assert.equal(list, null);
  assert.deepEqual(
    warnings.map((w) => w.join(" ")),
    [
      `[releases] ${LATEST} -> 401; rate limit remaining: null`,
      `[releases] ${LIST} -> 401; rate limit remaining: null`,
    ],
  );
  const logged = JSON.stringify(warnings.map((w) => w.map(String)));
  assert.ok(!logged.includes("qa-fake-token-0000"), "Token darf nicht in der Warnung stehen");
});

test("AK-39: 403 mit Rate-Limit-Header → Warnung nennt nur Pfad, Status, Restkontingent", async () => {
  stubFetch({ [LATEST]: { status: 403, headers: { "x-ratelimit-remaining": "0" } } });
  await getLatestRelease();
  assert.deepEqual(warnings.map((w) => w.join(" ")), [`[releases] ${LATEST} -> 403; rate limit remaining: 0`]);
});

test("AK-33 (BUG-08): Netzwerkfehler → keine Release-Daten (null) und Warnung mit Fehlerobjekt", async () => {
  stubFetch({
    [LATEST]: () => {
      throw new TypeError("fetch failed");
    },
  });
  const r = await getLatestRelease();
  assert.equal(r, null);
  assert.equal(warnings.length, 1);
  assert.equal(warnings[0][0], `[releases] request failed: ${LATEST}`);
  assert.ok(warnings[0][1] instanceof TypeError);
});

// BUG-04: /download-Lookup. Der Zustand (Fehlerfenster) lebt im Modul; jeder Test nutzt deshalb einen
// eigenen, weit auseinanderliegenden Zeitpunkt `now`, damit sich die Fenster nicht überlappen.
const T = (n) => Date.now() + n * 10 * DOWNLOAD_RETRY_AFTER_MS;

test("BUG-04: nach einem Fehler fragt /download erst nach Ablauf des Fensters wieder bei GitHub an", async () => {
  stubFetch({ [LATEST]: { status: 403, headers: { "x-ratelimit-remaining": "0" } } });
  const t0 = T(1);
  assert.equal(await getLatestReleaseForDownload(t0), null);
  assert.equal(calls.length, 1);
  for (let i = 0; i < 10; i++) assert.equal(await getLatestReleaseForDownload(t0 + 1000 * i), null);
  await Promise.all(Array.from({ length: 50 }, () => getLatestReleaseForDownload(t0 + DOWNLOAD_RETRY_AFTER_MS - 1)));
  assert.equal(calls.length, 1, "innerhalb des Fensters keine weitere Anfrage");
  assert.equal(warnings.length, 1, "und keine weitere Warnzeile");
  assert.equal(await getLatestReleaseForDownload(t0 + DOWNLOAD_RETRY_AFTER_MS), null);
  assert.equal(calls.length, 2, "nach Ablauf genau eine neue Anfrage");
});

test("BUG-04: gleichzeitige /download-Aufrufe teilen sich eine Anfrage (Fehler- und Erfolgsfall)", async () => {
  let answer = null;
  globalThis.fetch = async (input) => {
    calls.push({ url: String(input) });
    await new Promise((r) => setTimeout(r, 30));
    return answer
      ? new Response(JSON.stringify(answer), { status: 200 })
      : new Response("{}", { status: 503 });
  };
  const t1 = T(2);
  const failed = await Promise.all(Array.from({ length: 60 }, () => getLatestReleaseForDownload(t1)));
  assert.ok(failed.every((r) => r === null));
  assert.equal(calls.length, 1, "60 gleichzeitige Aufrufe im Fehlerfall → 1 Anfrage");

  answer = release("v5.0", { assets: [asset("x.dmg", "application/x-apple-diskimage")] });
  const t2 = T(3);
  const ok = await Promise.all(Array.from({ length: 60 }, () => getLatestReleaseForDownload(t2)));
  assert.equal(calls.length, 2, "60 gleichzeitige Aufrufe nach Ablauf des Fensters → 1 Anfrage");
  assert.ok(ok.every((r) => r?.tag === "v5.0"));
  await getLatestReleaseForDownload(t2 + 1);
  assert.equal(calls.length, 3, "Erfolg öffnet kein Fehlerfenster; das Caching übernimmt der Daten-Cache von Next.js (AK-15)");
});

test("EC-13: Dateigröße ÷ 1024², eine Nachkommastelle, Einheit MB", () => {
  assert.equal(formatBytes(36_455_860), "34.8 MB");
  assert.equal(formatBytes(0), "0.0 MB");
});

test("EC-14: Datum in UTC, englisch", () => {
  assert.equal(formatDate("2026-06-23T12:42:50Z"), "June 23, 2026");
  // 23:30 in UTC-02:00 ist in UTC bereits der Folgetag
  assert.equal(formatDate("2026-06-23T23:30:00-02:00"), "June 24, 2026");
});

function siteUrl(env) {
  const clean = { ...process.env };
  delete clean.NEXT_PUBLIC_SITE_URL;
  delete clean.VERCEL_PROJECT_PRODUCTION_URL;
  return execFileSync(process.execPath, ["--no-warnings", "--input-type=module", "-e", "const m = await import('./lib/site.ts'); console.log(m.SITE_URL);"], {
    cwd: fileURLToPath(WEB_ROOT),
    env: { ...clean, ...env },
    encoding: "utf8",
  }).trim();
}

test("AK-28/EC-09: Site-URL — Standard localhost:3000, sonst NEXT_PUBLIC_SITE_URL, sonst https://VERCEL_PROJECT_PRODUCTION_URL; Schrägstrich am Ende entfernt", () => {
  assert.equal(siteUrl({}), "http://localhost:3000");
  assert.equal(siteUrl({ NEXT_PUBLIC_SITE_URL: "https://qa.example/" }), "https://qa.example");
  assert.equal(siteUrl({ VERCEL_PROJECT_PRODUCTION_URL: "qa-project.vercel.app" }), "https://qa-project.vercel.app");
  assert.equal(siteUrl({ NEXT_PUBLIC_SITE_URL: "https://qa.example", VERCEL_PROJECT_PRODUCTION_URL: "qa-project.vercel.app" }), "https://qa.example");
});
