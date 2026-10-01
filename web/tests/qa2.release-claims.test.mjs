// B10 · Website — Abgleich der Website-Aussagen mit dem ausgelieferten Release (QA-Durchlauf 2, 2026-09-30)
//
// Die Seiten beschreiben ausdrücklich eine App-Version (`DESCRIBED_VERSION` in app/privacy/page.tsx, heute "1.1").
// Diese Tests lesen den Quelltext genau dieses Tags per `git show v<Version>:<Pfad>` und halten jede geprüfte
// Aussage der laufenden Seite dagegen. Ändert sich die Seite oder wird ein neues Release beschrieben, ohne dass
// Text und Code zusammenpassen, schlägt der passende Test an (Muster „Außendarstellung läuft dem Code voraus“,
// spec.md OF-10). Das Verhalten selbst ist in den QA-Berichten B01–B09 und in der Sonde aus QA-Durchlauf 2
// ausgeführt belegt; hier wird nur die Übereinstimmung von Text und ausgeliefertem Code dauerhaft gesichert.
//
// Voraussetzung: Git-Repository mit dem Tag v<Version>, Produktionsserver wie in tests/site.http.test.mjs:
//   cd web
//   env -u GITHUB_TOKEN -u NEXT_PUBLIC_SITE_URL -u VERCEL_PROJECT_PRODUCTION_URL npm run build
//   env -u GITHUB_TOKEN npx next start -H 127.0.0.1 -p 3941 &
//   BASE_URL=http://127.0.0.1:3941 node --test tests/qa2.release-claims.test.mjs
//   kill %1
//
// Keine zusätzliche Abhängigkeit (node:test, node:child_process, globales fetch).
// Tests, die einen Befund aus QA-Durchlauf 2 belegen, tragen { todo: "BUG-NN …" }: Sie prüfen das Soll,
// schlagen heute fehl und halten die Suite trotzdem grün. Die Reparatur entfernt die Markierung.

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const BASE = (process.env.BASE_URL ?? "http://127.0.0.1:3918").replace(/\/$/, "");
const WEB = fileURLToPath(new URL("../", import.meta.url));
const REPO = join(WEB, "..");

const DESCRIBED_VERSION = /const DESCRIBED_VERSION = "([^"]+)";/.exec(
  readFileSync(join(WEB, "app/privacy/page.tsx"), "utf8"),
)?.[1];
const TAG = `v${DESCRIBED_VERSION}`;

function show(path) {
  return execFileSync("git", ["-C", REPO, "show", `${TAG}:${path}`], { encoding: "utf8" });
}

function tagFiles(prefix) {
  return execFileSync("git", ["-C", REPO, "ls-tree", "-r", "--name-only", TAG, "--", prefix], { encoding: "utf8" })
    .split("\n")
    .filter(Boolean);
}

function visibleText(markup) {
  return markup
    .slice(markup.indexOf("<body"))
    .replace(/<script[\s\S]*?<\/script>/g, " ")
    .replace(/<style[\s\S]*?<\/style>/g, " ")
    .replace(/<!-- -->/g, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#x27;|&#39;|&rsquo;/g, "'")
    .replace(/\s+/g, " ")
    .trim();
}

async function page(path) {
  const res = await fetch(BASE + path, { redirect: "manual" });
  assert.equal(res.status, 200, `${path} sollte 200 liefern`);
  return res.text();
}

/** Text zwischen zwei Überschriften bzw. Markierungen der Datenschutzseite. */
function between(text, from, to) {
  const start = text.indexOf(from);
  assert.ok(start >= 0, `„${from}“ fehlt`);
  const end = to ? text.indexOf(to, start + from.length) : text.length;
  assert.ok(end > start, `„${to}“ fehlt nach „${from}“`);
  return text.slice(start, end);
}

let home, support, privacy, changelog, supportHtml, sources;

before(async () => {
  assert.ok(DESCRIBED_VERSION, "DESCRIBED_VERSION in app/privacy/page.tsx nicht gefunden");
  execFileSync("git", ["-C", REPO, "rev-parse", "--verify", `${TAG}^{commit}`], { stdio: "ignore" });
  home = visibleText(await page("/"));
  supportHtml = await page("/support");
  support = visibleText(supportHtml);
  privacy = visibleText(await page("/privacy"));
  changelog = visibleText(await page("/changelog"));
  sources = Object.fromEntries(tagFiles("Sources").filter((f) => f.endsWith(".swift")).map((f) => [f, show(f)]));
});

const allSwift = () => Object.values(sources).join("\n");

// ---------------------------------------------------------------- Datenschutzseite gegen v<Version>

test("Datenschutz · Speicherort (BUG-02): ohne Sandbox und mit unbenannter ModelConfiguration liegt die Datenbank unter ~/Library/Application Support/default.store", () => {
  const entitlements = show("Sources/Resources/MikaPlusPlayer.entitlements");
  assert.match(entitlements, /com\.apple\.security\.app-sandbox<\/key>\s*<false\/>/, `${TAG}: Sandbox aus`);
  const app = sources["Sources/App/MikaPlusPlayerApp.swift"];
  assert.match(app, /ModelConfiguration\(schema: schema, isStoredInMemoryOnly: false\)/, `${TAG}: unbenannte ModelConfiguration`);
  assert.ok(!/ModelConfiguration\([^)]*url:/.test(app) && !/ModelConfiguration\("/.test(app), `${TAG}: kein eigener Name, kein eigener Pfad`);
  assert.ok(privacy.includes("~/Library/Application Support/default.store"), "Seite nennt den Pfad");
  assert.ok(privacy.includes("default.store-shm") && privacy.includes("default.store-wal"), "Seite nennt die SQLite-Begleitdateien");
});

test("Datenschutz · Klartext (BUG-02): kein Schlüsselbund, kein Backup-Ausschluss, Zugangsdaten in Playlist- und Sender-Adresse", () => {
  const swift = allSwift();
  assert.ok(!/SecItem|kSecClass|Keychain/.test(swift), `${TAG}: kein Schlüsselbund-Code`);
  assert.ok(!/isExcludedFromBackup/.test(swift), `${TAG}: kein Backup-Ausschluss`);
  assert.match(sources["Sources/Services/XtreamCodes.swift"], /URLQueryItem\(name: "password"/, `${TAG}: Passwort in der player_api-Adresse`);
  assert.match(sources["Sources/Services/PlaylistImporter.swift"], /sourceURL: credentials\.playerAPIURL\(\)/, `${TAG}: diese Adresse wird gespeichert`);
  assert.match(sources["Sources/Services/XtreamClient.swift"], /\/live\/\\\(user\)\/\\\(pass\)\//, `${TAG}: Zugangsdaten in jeder Stream-Adresse`);
  const stores = between(privacy, "What the app stores", "Removing everything");
  for (const s of ["not encrypted", "does not use the macOS Keychain", "plain text", "address of every one of its channels", "Time Machine"]) {
    assert.ok(stores.includes(s), `Seite: „${s}“`);
  }
});

test("Datenschutz · Xtream über HTTP (AK-25): https:// wird umgeschrieben, Zugangsdaten begleiten jede Anfrage und jeden Stream", () => {
  assert.match(sources["Sources/Services/XtreamCodes.swift"], /h = "http:\/\/" \+ h\.dropFirst\("https:\/\/"\.count\)/, `${TAG}: https → http`);
  const section = between(privacy, "Xtream logins travel over plain HTTP", "This website");
  assert.ok(section.includes("rewrites an https:// host to plain HTTP"));
  assert.ok(section.includes("every stream you play"));
});

test("Datenschutz · Logo-Hosts (B04 BUG-06, B05 BUG-03): Logos laden automatisch in Liste und Favoriten, ohne Schalter", () => {
  assert.match(sources["Sources/Views/ChannelRowView.swift"], /AsyncImage\(url: channel\.logoURL\)/, `${TAG}: Logo per AsyncImage`);
  assert.match(sources["Sources/Views/FavoritesView.swift"], /ChannelRowView\(channel: channel\)/, `${TAG}: Favoriten-Tab zeigt dieselbe Karte`);
  assert.ok(!/@AppStorage|UserDefaults/.test(allSwift()), `${TAG}: keine Einstellung in der App`);
  const logos = between(privacy, "Channel logo servers.", "GitHub.");
  for (const s of ["automatically", "over plain HTTP", "following redirects", "Favourites tab", "no setting to turn logos off"]) {
    assert.ok(logos.includes(s), `Seite: „${s}“`);
  }
  assert.match(show("Sources/Resources/Info.plist"), /NSAllowsArbitraryLoads<\/key>\s*<true\/>/, `${TAG}: HTTP erlaubt`);
});

test("Datenschutz · Update-Prüfung (BF-12): automatisch ohne Rückfrage, Feed auf raw.githubusercontent.com, kein Systemprofil", () => {
  const plist = show("Sources/Resources/Info.plist");
  assert.match(plist, /SUEnableAutomaticChecks<\/key>\s*<true\/>/, `${TAG}: automatische Prüfung ohne Einwilligungsdialog`);
  assert.ok(!plist.includes("SUSendProfileInfo"), `${TAG}: kein Systemprofil`);
  assert.ok(!plist.includes("SUScheduledCheckInterval"), `${TAG}: Standardintervall (ein Tag)`);
  assert.equal(new URL(/<key>SUFeedURL<\/key>\s*<string>([^<]+)<\/string>/.exec(plist)[1]).host, "raw.githubusercontent.com");
  const github = between(privacy, "GitHub. Sparkle", "Xtream logins travel over plain HTTP");
  for (const s of ["automatically, about once a day", "without asking first", "raw.githubusercontent.com", "sends no system profile", "github.com"]) {
    assert.ok(github.includes(s), `Seite: „${s}“`);
  }
  const appcast = show("appcast.xml");
  assert.ok(/<enclosure url="https:\/\/github\.com\//.test(appcast), `${TAG}: Update-Download von github.com`);
});

test("Datenschutz · keine Kanäle, keine Telemetrie (FAQ, Kurzfassung): v1.1 enthält weder Sender noch Analyse-SDK", () => {
  const swift = allSwift();
  assert.ok(!/iptv-org|Analytics|Telemetry|Crashlytics|Sentry|Firebase/i.test(swift), `${TAG}: keine mitgelieferten Sender, kein SDK`);
  assert.ok(privacy.includes("no account, no telemetry and no analytics"));
  assert.ok(support.includes("the app ships with none of that"));
});

// ---------------------------------------------------------------- Start, Funktionen, Support, FAQ gegen v<Version>

test("Funktionen/FAQ · Engine-Wahl (BUG-07): genau .ts, .mpegts, .mts und .m2ts gehen an VLC; MPEG-TS ist Standard beim Xtream-Login", () => {
  const engine = sources["Sources/Services/PlaybackEngine.swift"];
  assert.match(engine, /case "ts", "mpegts", "mts", "m2ts": self = \.transportStream/, `${TAG}: Endungen für VLC`);
  assert.ok(support.includes("anything ending in .ts, .mpegts, .mts or .m2ts goes to the VLC engine automatically"));
  assert.match(sources["Sources/Views/ImportPlaylistView.swift"], /xtreamOutput: XtreamOutput = \.mpegts/, `${TAG}: MPEG-TS vorausgewählt`);
  assert.ok(home.includes("MPEG-TS is the default output format"));
});

test("Support · Tastatur (BF-103, BF-107): Tastentabelle und Rückmeldung entsprechen v1.1; keine Taste P", () => {
  const player = sources["Sources/Views/PlayerView.swift"];
  for (const key of [".space", ".upArrow", ".downArrow", ".escape", '"m"', '"f"', '"+", "="', '"-"']) {
    assert.ok(player.includes(`case ${key}`), `${TAG}: Taste ${key}`);
  }
  assert.ok(!/case "p"/.test(player), `${TAG}: keine Taste P`);
  assert.match(player, /volumeStep = 0\.05/, `${TAG}: 5-%-Schritte`);
  const hudKinds = new Set([...player.matchAll(/showHUD\(\.(\w+)/g)].map((m) => m[1]));
  assert.deepEqual([...hudKinds].sort(), ["mute", "playPause", "volume"], `${TAG}: Rückmeldung nur für Play/Pause, Stumm, Lautstärke`);
  const dts = [...supportHtml.matchAll(/<dt class="font-mono text-sm">([^<]+)<\/dt>/g)].map((m) => m[1]);
  assert.deepEqual(dts, ["Space", "↑ ↓ + −", "M", "F", "Esc"]);
  assert.ok(support.includes("Space, the volume keys and M confirm with a short on-screen indicator; F and Esc only switch full screen."));
});

test("Support · App-Name (BUG-07, FB-12): Finder und Warnung zeigen MikaPlusPlayer", () => {
  assert.match(show("project.yml"), /PRODUCT_NAME: MikaPlusPlayer\b/, `${TAG}: Produktname`);
  assert.ok(!show("Sources/Resources/Info.plist").includes("CFBundleDisplayName"), `${TAG}: kein abweichender Anzeigename`);
  assert.ok(support.includes("In the Finder and in the warning the app is called MikaPlusPlayer."));
  assert.ok(privacy.includes("move MikaPlusPlayer from Applications to the Trash"));
});

test("Funktionen · nicht im Release (BUG-07, FB-01/FB-02): kein Doppelklick-Import, kein Bild-in-Bild", () => {
  const swift = allSwift();
  assert.ok(!/onOpenURL|handlesExternalEvents|NSApplicationDelegateAdaptor/.test(swift), `${TAG}: kein Öffnen-Handler`);
  assert.ok(!/PictureInPicture|pictureInPicture/.test(swift), `${TAG}: kein Bild-in-Bild`);
  assert.ok(home.includes("Double-clicking a playlist in Finder does not import it in version 1.1."));
  for (const [name, text] of [["/", home], ["/support", support], ["/privacy", privacy], ["/changelog", changelog]]) {
    assert.ok(!/Picture in Picture|\bPiP\b/.test(text), `${name}: kein Bild-in-Bild`);
  }
});

test("Funktionen · Sprache und Menü (BUG-07, FB-14, BF-16): Oberfläche Deutsch, Menüeintrag „Nach Updates suchen …“", () => {
  const all = execFileSync("git", ["-C", REPO, "ls-tree", "-r", "--name-only", TAG], { encoding: "utf8" });
  assert.ok(!/\.lproj\/|\.xcstrings|Localizable\.strings/.test(all), `${TAG}: keine Übersetzungen`);
  assert.match(sources["Sources/Views/ImportPlaylistView.swift"], /case file = "Datei"/, `${TAG}: Reiter „Datei“`);
  assert.match(sources["Sources/App/MikaPlusPlayerApp.swift"], /Button\("Nach Updates suchen …"\)/, `${TAG}: Menüeintrag`);
  assert.ok(home.includes("The app's interface is in German."));
  assert.ok(home.includes("Datei (file)"));
  assert.ok(support.includes("choose “Nach Updates suchen …”") || support.includes('choose "Nach Updates suchen …"'));
});

test("Funktionen · Favoriten (BUG-07, B05 H-5): Wiedererkennung über tvg-id, sonst den Namen", () => {
  const channel = sources["Sources/Models/Channel.swift"];
  assert.match(channel, /if let tvgID, !tvgID\.isEmpty \{ return "id:\\\(tvgID\)" \}/, `${TAG}: tvg-id zuerst`);
  assert.match(channel, /return "name:\\\(name\.lowercased\(\)\)"/, `${TAG}: sonst der Name`);
  assert.ok(home.includes("the same tvg-id — or, if it has none, the same name"));
});

// ---------------------------------------------------------------- Befunde aus QA-Durchlauf 2 (Soll, heute rot)

test("BUG-13 (Soll): Datenschutzseite nennt, dass Anfragen die macOS-Version und bei Streams Sprache und Player verraten", { todo: "BUG-13 Kopfzeilen der App-Anfragen unvollständig beschrieben" }, () => {
  // Sonde QA-Durchlauf 2 (Bundle wie v1.1: CFBundleName MikaPlusPlayer, Build 2, ohne .lproj), lokaler Mock:
  //   URLSession  → User-Agent „MikaPlusPlayer/2 CFNetwork/3896.100.1.1.1 Darwin/27.0.0“, Accept-Language „de-DE,de;q=0.9“
  //   AVURLAsset  → User-Agent „AppleCoreMedia/1.0.0.26A428 (Macintosh; U; Intel Mac OS X 27_0; de_de)“
  //   VLC (B06 AK-32) → „VLC/3.0.21 LibVLC/3.0.21“ mit Accept-Language
  const connects = between(privacy, "What the app connects to", "Your provider.");
  // „the version of macOS’s network components“ (CFNetwork) ist nicht die Systemversion (Darwin/27.0.0).
  assert.ok(/Darwin|macOS version|system version|operating system|version of macOS(?!['’]s)/i.test(connects), "Kopfzeile nennt die Systemversion (Darwin/…)");
  const streams = between(privacy, "Stream servers.", "Channel logo servers.");
  assert.ok(/User-Agent|language|player/i.test(streams), "Stream-Anfragen: Systemversion, Sprache bzw. Player-Version");
});

test("BUG-14 (Soll): „Removing everything“ nennt jeden Ort, den v1.1 anlegt, und „What the app stores“ alle gespeicherten Angaben", { todo: "BUG-14 Löschweg und Speicherliste unvollständig" }, () => {
  // v1.1 bindet VLCKit ein; libVLC legt ~/Library/Preferences/<Bundle-ID>/vlcrc an (B06 Release-Lauf REL-10,
  // auf dem Entwicklungs-Mac vorhanden: ~/Library/Preferences/lu.daumedia.MikaPlusPlayer/vlcrc, nur Name gelesen).
  assert.match(show("project.yml"), /vlckit/i, `${TAG}: VLCKit eingebunden`);
  const removing = between(privacy, "Removing everything", "What the app connects to");
  assert.ok(/Preferences\/lu\.daumedia\.MikaPlusPlayer(\/|\s|$)|vlcrc/.test(removing), "Ordner ~/Library/Preferences/lu.daumedia.MikaPlusPlayer/ (vlcrc) fehlt im Löschweg");
  // Playlist.createdAt/lastRefreshed und Channel.tvgID stehen in der Datenbank.
  assert.match(sources["Sources/Models/Playlist.swift"], /var createdAt: Date/);
  assert.match(sources["Sources/Models/Playlist.swift"], /var lastRefreshed: Date\?/);
  const stores = between(privacy, "What the app stores", "Removing everything");
  assert.ok(/when you (added|imported|last refreshed)|refresh(ed)? (date|time)|tvg-id/i.test(stores), "Zeitpunkte von Import/Aktualisierung und tvg-id fehlen in der Aufzählung");
});

test("BUG-15 (Soll): FAQ verspricht keine Versionshinweise, solange der Update-Feed keine enthält", { todo: "BUG-15 FAQ „shows the release notes“" }, () => {
  // Sparkle zeigt im Update-Fenster nur, was der Feed mitbringt (B09 AK-06: „ohne Versionshinweise, weil der Feed keine enthält“).
  const appcast = readFileSync(join(REPO, "appcast.xml"), "utf8");
  const feedHasNotes = /<description>|sparkle:releaseNotesLink|sparkle:fullReleaseNotesLink/.test(appcast);
  if (!feedHasNotes) {
    assert.ok(!support.includes("shows the release notes"), "FAQ „How do updates arrive?“ verspricht Versionshinweise, der Feed enthält keine");
  }
});

test("BUG-12 (Soll): next mindestens 16.3.6 (GHSA-vcvr-r3jv-pc5j, RCE in next/og ImageResponse)", { todo: "BUG-12 next 16.3.3 mit kritischer Advisory" }, () => {
  const installed = JSON.parse(readFileSync(join(WEB, "node_modules/next/package.json"), "utf8")).version;
  const [maj, min, pat] = installed.split(".").map((n) => parseInt(n, 10));
  assert.ok(maj > 16 || (maj === 16 && (min > 3 || (min === 3 && pat >= 6))), `installiert: next ${installed}`);
});
