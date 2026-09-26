// B10 · Website — HTTP-Tests gegen den lokal laufenden Produktionsserver (QA-Durchlauf 1, 2026-09-15;
// angepasst bei der Reparatur Teil 1, 2026-09-16: BUG-05, BUG-06, BUG-09, BUG-11 behoben, todo entfernt)
//
// Voraussetzung: Produktions-Build ohne GITHUB_TOKEN und ohne NEXT_PUBLIC_SITE_URL/VERCEL_PROJECT_PRODUCTION_URL,
// GitHub beim Build erreichbar, Server auf eigenem Port:
//   cd web
//   env -u GITHUB_TOKEN -u NEXT_PUBLIC_SITE_URL -u VERCEL_PROJECT_PRODUCTION_URL npm run build
//   env -u GITHUB_TOKEN npx next start -p 3918 &
//   BASE_URL=http://127.0.0.1:3918 node --test tests/site.http.test.mjs
//   kill %1
//
// Keine zusätzliche Abhängigkeit: node:test, globales fetch. Liest außerdem .next/ (Manifeste, statische Dateien).
// Tests, die einen gefundenen Fehler belegen, sind mit { todo: "BUG-NN …" } markiert: Sie laufen,
// ihr Fehlschlag lässt die Suite aber grün. Die Reparatur entfernt die Markierung.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const BASE = (process.env.BASE_URL ?? "http://127.0.0.1:3918").replace(/\/$/, "");
const WEB = fileURLToPath(new URL("../", import.meta.url));
const NEXT_DIR = join(WEB, ".next");
const SITE_URL_DEFAULT = "http://localhost:3000";

const ALL_ROUTES = ["/", "/changelog", "/privacy", "/support", "/download", "/robots.txt", "/sitemap.xml", "/opengraph-image", "/icon.png", "/apple-icon.png", "/does-not-exist"];

async function get(path, init = {}) {
  return fetch(BASE + path, { redirect: "manual", ...init });
}

async function html(path) {
  const res = await get(path);
  assert.equal(res.status, 200, `${path} sollte 200 liefern`);
  return res.text();
}

/** Sichtbarer Text ohne Skripte/Styles, Whitespace normalisiert, Entities grob aufgelöst. */
function visibleText(markup) {
  return markup
    .replace(/<script[\s\S]*?<\/script>/g, " ")
    .replace(/<style[\s\S]*?<\/style>/g, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#x27;|&#39;|&rsquo;/g, "'")
    .replace(/\s+/g, " ")
    .trim();
}

function body(markup) {
  return markup.slice(markup.indexOf("<body"));
}

function assertInOrder(text, phrases) {
  let pos = -1;
  for (const phrase of phrases) {
    const next = text.indexOf(phrase, pos + 1);
    assert.ok(next > pos, `„${phrase}" fehlt oder steht nicht nach dem vorigen Abschnitt`);
    pos = next;
  }
}

function pngSize(buf) {
  assert.equal(buf.subarray(1, 4).toString("latin1"), "PNG");
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
}

// ---------------------------------------------------------------- Build und Auslieferung

test("AK-01: Routenarten laut Build-Manifest (ISR 1h/1y, statisch, /download dynamisch)", async () => {
  const pre = JSON.parse(await readFile(join(NEXT_DIR, "prerender-manifest.json"), "utf8"));
  const routes = JSON.parse(await readFile(join(NEXT_DIR, "app-path-routes-manifest.json"), "utf8"));
  for (const r of ["/", "/changelog"]) {
    assert.equal(pre.routes[r].initialRevalidateSeconds, 3600, r);
    assert.equal(pre.routes[r].initialExpireSeconds, 31536000, r);
  }
  for (const r of ["/privacy", "/support", "/robots.txt", "/sitemap.xml", "/opengraph-image", "/icon.png", "/apple-icon.png", "/_not-found"]) {
    assert.ok(pre.routes[r], `${r} vorgerendert`);
    assert.equal(pre.routes[r].initialRevalidateSeconds, false, r);
  }
  assert.equal(pre.routes["/download"], undefined, "/download nicht vorgerendert");
  assert.equal(routes["/download/route"], "/download");
});

test("AK-02: Sicherheits-Header auf /, /download, /opengraph-image; kein X-Powered-By", async () => {
  for (const path of ["/", "/download", "/opengraph-image", "/does-not-exist"]) {
    const res = await get(path);
    assert.equal(res.headers.get("x-content-type-options"), "nosniff", path);
    assert.equal(res.headers.get("referrer-policy"), "strict-origin-when-cross-origin", path);
    assert.equal(res.headers.get("x-frame-options"), "DENY", path);
    assert.equal(res.headers.get("strict-transport-security"), "max-age=63072000; includeSubDomains; preload", path);
    assert.equal(res.headers.get("x-powered-by"), null, path);
  }
});

test("AK-03: Cache-Control für ISR- und statische Seiten", async () => {
  for (const path of ["/", "/changelog"]) {
    assert.equal((await get(path)).headers.get("cache-control"), "s-maxage=3600, stale-while-revalidate=31532400", path);
  }
  for (const path of ["/privacy", "/support"]) {
    assert.equal((await get(path)).headers.get("cache-control"), "s-maxage=31536000", path);
  }
});

test("AK-04: 404 mit Kopf- und Fußzeile; /download/ → 308 auf /download", async () => {
  for (const path of ["/does-not-exist", "/.env", "/next.config.ts", "/package.json", "/.next/BUILD_ID"]) {
    const res = await get(path);
    assert.equal(res.status, 404, path);
    const text = visibleText(await res.text());
    assert.match(text, /This page could not be found/, path);
    assert.match(text, /Support Changelog Privacy GitHub/, `${path}: Kopfzeile`);
    assert.match(text, /Report an issue Source/, `${path}: Fußzeile`);
  }
  const slash = await get("/download/");
  assert.equal(slash.status, 308);
  assert.equal(new URL(slash.headers.get("location"), BASE).pathname, "/download");
});

// ---------------------------------------------------------------- Kopf- und Fußzeile

test("AK-05/AK-06/AK-07: Kopfzeile, Fußzeile, Skip-Link und lang im ausgelieferten HTML", async () => {
  for (const path of ["/", "/changelog", "/privacy", "/support"]) {
    const page = await html(path);
    assert.match(page, /<html lang="en"/, path);
    const header = page.slice(page.indexOf("<header"), page.indexOf("</header>"));
    assert.match(header, /class="sticky top-0/, path);
    assert.match(header, /href="\/"/);
    assert.match(header, /src="\/_next\/image\?url=%2Ficon-512\.png/);
    for (const label of ["Support", "Changelog", "Privacy"]) assert.ok(header.includes(`>${label}</a>`), `${path}: ${label}`);
    assert.match(header, /<a href="https:\/\/github\.com\/daumedia\/MikaPlusPlayer"[^>]*target="_blank"[^>]*rel="noopener noreferrer"[^>]*>GitHub<\/a>/);
    assert.match(header, /class="[^"]*hidden sm:block" href="\/privacy"/);
    assert.match(header, /class="sr-only min-\[380px\]:hidden">Mika\+Player</);

    const footer = page.slice(page.indexOf("<footer"), page.indexOf("</footer>"));
    const ftext = visibleText(footer);
    assert.ok(ftext.includes("An open-source IPTV player. It plays the playlist you bring and is not affiliated with any provider."));
    assert.match(footer, /href="https:\/\/github\.com\/daumedia\/MikaPlusPlayer\/issues" target="_blank" rel="noopener noreferrer"[^>]*>Report an issue</);
    assert.match(footer, /href="https:\/\/github\.com\/daumedia\/MikaPlusPlayer" target="_blank" rel="noopener noreferrer"[^>]*>Source</);

    assert.match(page, /<a href="#main" class="sr-only focus:not-sr-only[^"]*">Skip to content<\/a>/);
    assert.match(page, /<main id="main">/);
  }
});

// ---------------------------------------------------------------- Startseite

test("AK-09 (BUG-06): Hero mit Download-Link direkt auf das DMG bei github.com, Version, Größe, SHA-256, Erststart-Hinweis über die Systemeinstellungen", async () => {
  const page = await html("/");
  const text = visibleText(body(page));
  assert.ok(text.includes("Mika + Player · IPTV for macOS") || text.includes("Mika+Player · IPTV for macOS"));
  assert.ok(text.includes("Four streams. One window."));
  assert.ok(text.includes("Version 1.1 · 34.8 MB · macOS 14 Sonoma or later"));
  assert.ok(text.includes("First launch"));
  assert.ok(text.includes("go to System Settings → Privacy & Security and click Open Anyway"), "BUG-06: Weg ab macOS 15");
  assert.ok(text.includes("On macOS 14 Sonoma, Control-click → Open works as well."));
  assert.ok(!/right-click Mika\+Player and choose Open/i.test(text), "BUG-06: nicht mehr nur der Rechtsklick-Weg");
  assert.match(page, /href="\/support#first-launch"[^>]*>All steps, including the checksum check</);
  const sums = [...text.matchAll(/SHA-256 ([0-9a-f]{64})\b/g)].map((m) => m[1]);
  assert.equal(sums.length, 2, "BUG-06: Prüfsumme unter beiden Download-Schaltflächen");
  assert.equal(new Set(sums).size, 1);
  const buttons = [...page.matchAll(/<a href="([^"]+)"[^>]*>(?:(?!<\/a>)[\s\S])*Download for macOS<\/a>/g)].map((m) => m[1]);
  assert.equal(buttons.length, 2, "zwei Download-Schaltflächen");
  for (const href of buttons) {
    assert.equal(href, "https://github.com/daumedia/MikaPlusPlayer/releases/download/v1.1/MikaPlusPlayer-v1.1.dmg");
  }
});

test("AK-11/AK-12: Abschnittsreihenfolge der Startseite; kein Abschnitt „The app itself“", async () => {
  const text = visibleText(body(await html("/")));
  assertInOrder(text, [
    "You bring", "The app adds", "It never does",
    "Getting started", "CH 01 Add a playlist", "CH 02 Find your channels", "CH 03 Watch",
    "Seventeen thousand channels, still usable",
    "What it does", "Library", "Playback", "System",
    "Up to four streams, in a window of their own",
    "What it needs", "macOS 14 Sonoma or later", "Universal build for Apple silicon and Intel",
    "A playlist of your own", "iPhone and iPad", "Download for macOS", "on GitHub", "support page",
  ]);
  const page = await html("/");
  const featureTitles = [...page.matchAll(/<h4 class="font-display text-base font-semibold">([^<]+)<\/h4>/g)];
  assert.equal(featureTitles.length, 8, "acht Funktionen");
  assert.ok(!text.includes("The app itself"));
  assert.match(page, /href="\/support"[^>]*>\s*support page/);
});

test("AK-10 (statischer Teil): Multiview-Nachbau ohne Video und ohne externe Ressource", async () => {
  const page = await html("/");
  assert.ok(!/<video|<iframe|<audio/.test(page));
  assert.match(page, /aria-label="Give sound and the large picture to channel 02, Sports"/);
  assert.match(page, /aria-pressed="true"[^>]*>focus<\/button>|>focus<\/button>/);
});

test("AK-13: Metadaten der Startseite", async () => {
  const page = await html("/");
  assert.match(page, /<title>Mika\+Player — IPTV player for macOS<\/title>/);
  assert.match(page, /<meta name="robots" content="index, follow"\/>/);
  assert.match(page, /<meta property="og:image" content="http:\/\/localhost:3000\/opengraph-image\?[^"]*"\/>/);
  assert.match(page, /<meta property="og:image:width" content="1200"\/>/);
  assert.match(page, /<meta property="og:image:height" content="630"\/>/);
  assert.match(page, /<meta name="twitter:card" content="summary_large_image"\/>/);
  assert.match(page, /<link rel="canonical" href="http:\/\/localhost:3000"\/>/);
  assert.match(page, /<meta property="og:url" content="http:\/\/localhost:3000"\/>/);
});

// ---------------------------------------------------------------- Download

test("AK-14: /download 302 auf das DMG; Query ändert nichts; HEAD 302; POST 405", async () => {
  const dmg = "https://github.com/daumedia/MikaPlusPlayer/releases/download/v1.1/MikaPlusPlayer-v1.1.dmg";
  for (const q of ["", "?url=https://evil.example", "?redirect=//evil.example&next=https%3A%2F%2Fevil.example"]) {
    const res = await get(`/download${q}`);
    assert.equal(res.status, 302, q);
    assert.equal(res.headers.get("location"), dmg, q);
  }
  const head = await get("/download", { method: "HEAD" });
  assert.equal(head.status, 302);
  assert.equal(head.headers.get("location"), dmg);
  const post = await get("/download", { method: "POST" });
  assert.equal(post.status, 405);
  for (const method of ["PUT", "DELETE", "PATCH"]) {
    assert.equal((await get("/download", { method })).status, 405, method);
  }
});

// ---------------------------------------------------------------- Changelog

test("AK-18/AK-19: Changelog mit v1.1, englischem Ersatztext, Datum, Links, SHA-256 (BUG-06)", async () => {
  const page = await html("/changelog");
  const text = visibleText(body(page));
  assertInOrder(text, [
    "Every version so far",
    "Pulled from GitHub releases. The Mac app also checks this list for itself through Sparkle.",
    "v1.1 – Multiview", "June 23, 2026",
    "Multiview (macOS) — watch up to four streams at once",
    "the support page on this site shows how to allow it and how to check the download's SHA-256 checksum",
    "Download MikaPlusPlayer-v1.1.dmg ( 34.8 MB )",
    "Release on GitHub", "SHA-256", "releases page",
  ]);
  assert.ok(!/right-click/i.test(text), "BUG-06: Ersatztext ohne Rechtsklick-Anleitung");
  const home = visibleText(body(await html("/")));
  assert.equal(text.match(/SHA-256 ([0-9a-f]{64})\b/)?.[1], home.match(/SHA-256 ([0-9a-f]{64})\b/)?.[1], "gleiche Prüfsumme wie auf /");
  assert.match(page, /<time dateTime="2026-06-23T12:42:50Z"/);
  assert.match(page, /href="https:\/\/github\.com\/daumedia\/MikaPlusPlayer\/releases\/tag\/v1\.1" target="_blank" rel="noopener noreferrer"/);
  assert.match(page, /href="https:\/\/github\.com\/daumedia\/MikaPlusPlayer\/releases" target="_blank" rel="noopener noreferrer"[^>]*>releases page</);
  assert.equal((page.match(/<article /g) ?? []).length, 1);
});

test("AK-21: vom Browser geladene JS-Dateien enthalten kein react-markdown/remark/micromark", async () => {
  const page = await html("/changelog");
  const scripts = [...new Set([...page.matchAll(/(?:src|href)="(\/_next\/static\/chunks\/[^"]+\.js)"/g)].map((m) => m[1]))];
  assert.ok(scripts.length > 0);
  for (const src of scripts) {
    const js = await (await get(src)).text();
    assert.ok(!/react-markdown|remark|micromark|mdast/i.test(js), src);
  }
});

// ---------------------------------------------------------------- Support

test("AK-22/AK-23 (BUG-06): Support-Seite — fünf Erststart-Schritte mit Prüfsumme und Systemeinstellungen, drei Einrichtungsschritte, sechs Tasten, neun zugeklappte Fragen", async () => {
  const page = await html("/support");
  const text = visibleText(body(page));
  assertInOrder(text, [
    "First launch on macOS",
    "Since macOS 15 Sequoia, Control-clicking the app and choosing Open no longer gets past that",
    "01 Open the DMG and drag Mika+Player to Applications.",
    "02 Check the download before you open it. In Terminal, type shasum -a 256 and a space, drag the DMG into the window and press Return.",
    "The result has to match the SHA-256 shown under the download button",
    "03 Open Mika+Player from the Applications folder once.",
    "04 Open System Settings → Privacy & Security , scroll to Security and click Open Anyway .",
    "The button is there for about an hour after the blocked attempt.",
    "05 Confirm with your login password.",
    "On macOS 14 Sonoma, Control-clicking Mika+Player in Applications and choosing Open works as well.",
    "Adding a playlist", "CH 01 Add a playlist", "CH 02 Find your channels", "CH 03 Watch",
    "https://iptv-org.github.io/iptv/index.m3u",
    "Keyboard controls", "Questions",
  ]);
  assert.match(page, /href="https:\/\/iptv-org\.github\.io\/iptv\/index\.m3u" target="_blank" rel="noopener noreferrer"/);
  const dts = [...page.matchAll(/<dt class="font-mono text-sm">([^<]+)<\/dt>/g)].map((m) => m[1]);
  assert.deepEqual(dts, ["Space", "↑ ↓ + −", "M", "F", "P", "Esc"]);
  const details = [...page.matchAll(/<details\b([^>]*)>/g)];
  assert.equal(details.length, 9);
  for (const d of details) assert.ok(!/\bopen\b/.test(d[1]), "anfangs zugeklappt");
  assert.match(page, /group-open:rotate-45/);
  assert.match(page, /<section id="first-launch"/, "Sprungziel für den Hinweis auf /");
  assert.ok(!/Right-click Mika\+Player and choose Open/.test(text), "BUG-06: alter Rechtsklick-Schritt entfernt");
  assert.ok(text.includes("Try to open the app once, then go to System Settings → Privacy & Security and click Open Anyway"), "BUG-06: FAQ-Antwort");
});

// ---------------------------------------------------------------- Datenschutz

test("AK-24/AK-25/AK-26: Aufbau und Wortlaut der Datenschutzseite", async () => {
  const text = visibleText(body(await html("/privacy")));
  assertInOrder(text, [
    "What the app stores",
    "What the app connects to", "Your provider.", "Channel logo servers.", "GitHub.",
    "Xtream logins travel over plain HTTP",
    "This website",
    "Content",
    "Last updated 30 July 2026",
    "a GitHub issue",
  ]);
  assert.ok(text.includes("rewrites an https:// host to plain HTTP"));
  assert.ok(text.includes("Your username and password are therefore sent unencrypted"));
  assert.ok(text.includes("No cookies, no analytics, no tracking scripts, no fonts loaded from third parties."));
  assert.ok(text.includes("hosted on Vercel, which keeps standard server logs"));
  assert.ok(text.includes("GitHub, which counts downloads per release"));
});

test("FB-03/FB-04/FB-05 (Befund): Datenschutzseite enthält Aussagen, die der App-Code nicht erfüllt", { todo: "BUG-02 Datenschutzaussagen widersprechen dem App-Verhalten" }, async () => {
  const privacy = visibleText(body(await html("/privacy")));
  const home = visibleText(body(await html("/")));
  assert.ok(!privacy.includes("nothing goes to us"), "FB-03: „nothing goes to us“ — App sendet an Anbieter, Logo-Hosts, GitHub");
  assert.ok(!home.includes("send your data anywhere"), "FB-03: „It never does … send your data anywhere“");
  assert.ok(!privacy.includes("They stay in the app’s own storage"), "FB-04: default.store liegt unter ~/Library/Application Support/");
  assert.ok(!privacy.includes("deleting the app removes all of it"), "FB-04: Löschen der App entfernt default.store und Cache.db nicht");
  assert.ok(!privacy.includes("Every stream, channel list and logo request goes to the host you entered"), "FB-05");
});

test("FB-16/FB-17/FB-18 (Befund): keine Anbieterkennzeichnung, kein Verantwortlicher, kein Auskunftsweg", { todo: "BUG-03 Pflichtangaben fehlen" }, async () => {
  const all = [];
  for (const p of ["/", "/privacy", "/support", "/changelog"]) all.push(visibleText(body(await html(p))));
  const joined = all.join(" ");
  assert.ok(/@[a-z0-9-]+\.[a-z]{2,}/i.test(joined), "keine E-Mail-Adresse eines Verantwortlichen");
  assert.ok(/Controller|Verantwortlich|Imprint|Impressum|Legal notice/i.test(joined), "kein Verantwortlicher/Impressum");
  assert.ok(/GDPR|DSGVO|right to access|erasure|supervisory authority|CNPD/i.test(joined), "keine Betroffenenrechte/Beschwerdestelle");
});

// ---------------------------------------------------------------- Metadaten-Routen

test("AK-27/AK-28: robots.txt mit localhost-Site-URL", async () => {
  const res = await get("/robots.txt");
  assert.equal(res.status, 200);
  assert.equal(await res.text(), `User-Agent: *\nAllow: /\nDisallow: /download\n\nSitemap: ${SITE_URL_DEFAULT}/sitemap.xml\n`);
});

test("AK-28/AK-29: sitemap.xml mit genau vier Adressen, Prioritäten, Frequenzen, lastmod = Build", async () => {
  const xml = await (await get("/sitemap.xml")).text();
  const urls = [...xml.matchAll(/<url>\s*<loc>([^<]+)<\/loc>\s*<lastmod>([^<]+)<\/lastmod>\s*<changefreq>([^<]+)<\/changefreq>\s*<priority>([^<]+)<\/priority>\s*<\/url>/g)]
    .map((m) => [m[1], m[3], m[4], m[2]]);
  assert.deepEqual(urls.map((u) => u.slice(0, 3)), [
    [`${SITE_URL_DEFAULT}/`, "monthly", "1"],
    [`${SITE_URL_DEFAULT}/support`, "monthly", "0.8"],
    [`${SITE_URL_DEFAULT}/changelog`, "weekly", "0.6"],
    [`${SITE_URL_DEFAULT}/privacy`, "yearly", "0.3"],
  ]);
  assert.equal(new Set(urls.map((u) => u[3])).size, 1, "ein gemeinsamer lastmod");
  assert.ok(!xml.includes("/download"));
  const built = JSON.parse(await readFile(join(NEXT_DIR, "prerender-manifest.json"), "utf8"));
  assert.ok(built.routes["/sitemap.xml"], "sitemap beim Build erzeugt");
});

test("AK-30: /opengraph-image ist PNG 1200×630; Icons sind PNG", async () => {
  const og = Buffer.from(await (await get("/opengraph-image")).arrayBuffer());
  assert.deepEqual(pngSize(og), { width: 1200, height: 630 });
  for (const p of ["/icon.png", "/apple-icon.png"]) {
    const res = await get(p);
    assert.equal(res.headers.get("content-type"), "image/png");
    pngSize(Buffer.from(await res.arrayBuffer()));
  }
});

// ---------------------------------------------------------------- Datenschutz und Missbrauchsschutz

test("AK-35: keine Antwort setzt ein Cookie", async () => {
  for (const path of [...ALL_ROUTES, "/_next/image?url=%2Ficon-512.png&w=64&q=75"]) {
    const res = await get(path);
    assert.equal(res.headers.get("set-cookie"), null, path);
  }
});

test("AK-36 (HTML-Teil): alle eingebundenen Skripte, Styles, Schriften, Bilder vom eigenen Ursprung", async () => {
  for (const path of ["/", "/changelog", "/privacy", "/support"]) {
    const page = await html(path);
    const refs = [
      ...page.matchAll(/<script[^>]+src="([^"]+)"/g),
      ...page.matchAll(/<link[^>]+href="([^"]+)"/g),
      ...page.matchAll(/<img[^>]+src="([^"]+)"/g),
      ...page.matchAll(/imageSrcSet="([^"]+)"/g),
    ].map((m) => m[1]);
    for (const ref of refs) {
      const isCanonical = ref.startsWith(SITE_URL_DEFAULT) && /rel="canonical"/.test(page);
      assert.ok(ref.startsWith("/") || isCanonical, `${path}: externe Ressource ${ref}`);
    }
    assert.ok(!/fonts\.googleapis\.com|fonts\.gstatic\.com|vercel-insights|va\.vercel-scripts|googletagmanager|plausible|umami/i.test(page), path);
  }
});

test("AK-37: Download-Link ist ein einfacher Link auf github.com; Referrer-Policy begrenzt auf den Ursprung", async () => {
  const page = await html("/");
  const tags = [...page.matchAll(/<a href="https:\/\/github\.com\/[^"]+\.dmg"([^>]*)>/g)];
  assert.equal(tags.length, 2);
  for (const t of tags) assert.ok(!/referrerPolicy|ping=/i.test(t[1]));
  assert.equal((await get("/")).headers.get("referrer-policy"), "strict-origin-when-cross-origin");
});

test("AK-38: kein Token, keine API-Adresse und kein Rate-Limit-Header im Browser-Bundle; keine Source-Maps ausgeliefert", async () => {
  const files = await readdir(join(NEXT_DIR, "static"), { recursive: true });
  let scanned = 0;
  for (const f of files) {
    if (!/\.(js|css|json|html|txt)$/.test(f)) continue;
    const content = await readFile(join(NEXT_DIR, "static", f), "utf8");
    scanned++;
    assert.ok(!/GITHUB_TOKEN|api\.github\.com|x-ratelimit/i.test(content), f);
  }
  assert.ok(scanned > 0);
  const page = await html("/changelog");
  const js = [...page.matchAll(/src="(\/_next\/static\/chunks\/[^"]+\.js)"/g)].map((m) => m[1]);
  for (const src of js) assert.equal((await get(`${src}.map`)).status, 404, `${src}.map`);
  const gi = await readFile(join(WEB, ".gitignore"), "utf8");
  assert.match(gi, /^\.env\*$/m);
});

test("AK-40: Bildoptimierung nur für lokale Quellen und erlaubte Parameter", async () => {
  const cases = [
    ["/_next/image?url=https://evil.example/x.png&w=64&q=75", 400],
    ["/_next/image?url=http://127.0.0.1:3918/icon-512.png&w=64&q=75", 400],
    ["/_next/image?url=%2F%2Fevil.example%2Fx.png&w=64&q=75", 400],
    ["/_next/image?url=%2Ficon-512.png&w=65&q=75", 400],
    ["/_next/image?url=%2Ficon-512.png&w=64&q=50", 400],
    ["/_next/image?url=%2F_next%2Fimage%3Furl%3D%252Ficon-512.png&w=64&q=75", 400],
    ["/_next/image?url=%2Fdownload&w=64&q=75", 400],
    ["/_next/image?url=%2F..%2F..%2Fetc%2Fpasswd&w=64&q=75", 400],
  ];
  for (const [path, status] of cases) assert.equal((await get(path)).status, status, path);
  const ok = await get("/_next/image?url=%2Ficon-512.png&w=64&q=75", { headers: { Accept: "*/*" } });
  assert.equal(ok.status, 200);
  assert.equal(ok.headers.get("content-type"), "image/png");
  const avif = await get("/_next/image?url=%2Ficon-512.png&w=64&q=75", { headers: { Accept: "image/avif,image/webp,*/*" } });
  assert.equal(avif.headers.get("content-type"), "image/webp", "AVIF-Ausgabe nicht aktiviert (images.formats = webp)");
  const manifest = JSON.parse(await readFile(join(NEXT_DIR, "images-manifest.json"), "utf8")).images;
  assert.deepEqual(manifest.remotePatterns, []);
  assert.deepEqual(manifest.domains, []);
  assert.deepEqual(manifest.formats, ["image/webp"]);
});

test("FB-22 (BUG-05 behoben): next mindestens in der gepatchten Version 16.3.3", async () => {
  const pkg = JSON.parse(await readFile(join(WEB, "node_modules/next/package.json"), "utf8"));
  const [maj, min, pat] = pkg.version.split(".").map(Number);
  assert.ok(maj > 16 || (maj === 16 && (min > 3 || (min === 3 && pat >= 3))), `next ${pkg.version} < 16.3.3`);
});

test("FB-20 (BUG-09 behoben): Content-Security-Policy und Permissions-Policy auf allen Routen", async () => {
  for (const path of ["/", "/changelog", "/privacy", "/support", "/download", "/opengraph-image", "/does-not-exist"]) {
    const res = await get(path);
    const csp = res.headers.get("content-security-policy");
    assert.ok(csp, `${path}: CSP fehlt`);
    const directives = Object.fromEntries(csp.split(";").map((d) => d.trim().split(/\s+/)).map(([k, ...v]) => [k, v]));
    assert.deepEqual(directives["default-src"], ["'self'"], path);
    assert.deepEqual(directives["script-src"], ["'self'", "'unsafe-inline'"], `${path}: keine fremden Skripte, kein eval`);
    assert.deepEqual(directives["img-src"], ["'self'"], path);
    assert.deepEqual(directives["connect-src"], ["'self'"], path);
    assert.deepEqual(directives["object-src"], ["'none'"], path);
    assert.deepEqual(directives["base-uri"], ["'self'"], path);
    assert.deepEqual(directives["frame-ancestors"], ["'none'"], path);
    assert.equal(res.headers.get("content-security-policy-report-only"), null, `${path}: CSP wird durchgesetzt, nicht nur gemeldet`);
    const pp = res.headers.get("permissions-policy");
    assert.ok(pp, `${path}: Permissions-Policy fehlt`);
    for (const feature of ["camera", "microphone", "geolocation", "payment", "usb", "browsing-topics"]) {
      assert.ok(pp.split(",").map((x) => x.trim()).includes(`${feature}=()`), `${path}: ${feature}=() fehlt`);
    }
  }
});

test("Hinweis (Code-Review, BUG-11 behoben): Open-Graph-Daten der Unterseiten gehören zur Unterseite", async () => {
  const titles = { "/changelog": "Changelog", "/privacy": "Privacy", "/support": "Support" };
  for (const [path, title] of Object.entries(titles)) {
    const page = await html(path);
    assert.match(page, new RegExp(`<meta property="og:url" content="${SITE_URL_DEFAULT}${path}"/>`), `${path}: og:url`);
    assert.doesNotMatch(page, /<meta property="og:title" content="Mika\+Player — IPTV player for macOS"\/>/, `${path}: og:title der Startseite`);
    assert.match(page, new RegExp(`<meta property="og:title" content="${title} — Mika\\+Player"/>`), `${path}: og:title`);
    const description = page.match(/<meta name="description" content="([^"]+)"\/>/)?.[1];
    assert.ok(description && page.includes(`<meta property="og:description" content="${description}"/>`), `${path}: og:description = description`);
    assert.match(page, /<meta property="og:image" content="http:\/\/localhost:3000\/opengraph-image\?[^"]*"\/>/, `${path}: Vorschaubild bleibt erhalten`);
    assert.match(page, /<meta property="og:site_name" content="Mika\+Player"\/>/, `${path}: og:site_name`);
  }
});

test("AK-41: kein Formular, kein Eingabefeld, kein Upload auf irgendeiner Seite", async () => {
  for (const path of ["/", "/changelog", "/privacy", "/support", "/does-not-exist"]) {
    const res = await get(path);
    const page = await res.text();
    assert.ok(!/<form\b|<input\b|<textarea\b|<select\b|type="file"/i.test(page), path);
    assert.ok(!/\$ACTION_ID|next-action/i.test(page), `${path}: keine Server Action`);
  }
});

// ---------------------------------------------------------------- Angriff: Eingaben

test("Angriff/Eingaben: Sonderzeichen, 10.000 Zeichen, Emoji, Pfad-Traversal — kein 5xx, keine Reflexion", async () => {
  const payloads = [
    "",
    "a",
    "x".repeat(10_000),
    "%F0%9F%98%80",
    "'%3B%20drop%20table%20--",
    "%3Cscript%3Ealert(1)%3C%2Fscript%3E",
    "..%2F..%2Fetc%2Fpasswd",
    "%23%3F%2F%25%26",
    "%C3%A4%C3%B6%C3%BC%C3%9F",
  ];
  for (const p of payloads) {
    for (const path of [`/${p}`, `/download?q=${p}`, `/changelog?q=${p}`, `/privacy?${p}`, `/support#${p}`]) {
      const res = await get(path);
      assert.ok(res.status < 500, `${path.slice(0, 60)} → ${res.status}`);
      const txt = await res.text();
      assert.ok(!txt.includes("<script>alert(1)</script>"), `${path.slice(0, 60)}: reflektiert`);
      assert.ok(!txt.includes("root:x:0:0"), `${path.slice(0, 60)}: Dateiinhalt`);
    }
  }
  const trav = await get("/_next/static/..%2F..%2Fpackage.json");
  assert.ok([400, 404].includes(trav.status), `static traversal → ${trav.status}`);
});
