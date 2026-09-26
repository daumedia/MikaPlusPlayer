# B10 · Website — Testbericht

Stand: 2026-09-15 · Durchlauf 1 · Geprüft gegen `spec.md` vom 2026-09-15 (Status `rekonstruiert`) · Code `web/` @ `c01f1cf`

## Fazit

**Production-ready: nein** — höchster Schweregrad: **hoch**

Die Website selbst tut lokal fast alles, was die Spec beschreibt. Alle 41 Kriterien wurden ausgeführt, 40 davon
bestanden: Routen, Header, Caching, Download-Weiterleitung, Fallbacks, Entschärfung fremder Release-Texte, keine
Cookies, keine Fremdressourcen, kein Token im Bundle. Ein Browser-Durchlauf (headless, ohne Ton) deckte Kopfzeile,
Tastatur, Hell/Dunkel, Multiview-Nachbau und FAQ ab. Durchgefallen ist AK-34: 64 Aufrufe von `/download` bei
GitHub-Störung erzeugen 64 Anfragen an GitHub.

Drei Befunde sind **hoch** und blockieren. **Erstens** ist die Seite öffentlich nicht erreichbar. Die Homepage liefert
`DEPLOYMENT_NOT_FOUND`, das letzte Production-Deployment leitet auf den Vercel-Login um und setzt dabei ein Cookie,
die Domain existiert nicht. Die einzige Datenschutzerklärung zu App und Website ist damit für niemanden abrufbar
(BUG-01). **Zweitens** widerspricht die Datenschutzerklärung dem App-Verhalten. Das ist am Code nachgestellt: Die
Zugangsdaten liegen außerhalb der App, und das Löschen der App entfernt sie nicht. Anfragen gehen an beliebige
Stream- und Logo-Hosts, nicht nur „an den eingegebenen Host" (BUG-02). **Drittens** fehlen Verantwortlicher,
Rechtsgrundlagen, Speicherdauer, Betroffenenrechte und ein nicht öffentlicher Kontaktweg (BUG-03).

Dazu kommen fünf mittlere Befunde:

- **BUG-04:** `/download` ohne Cache und ohne Limit im Fehlerfall.
- **BUG-05:** `next` 16.2.12 mit kritischer Advisory. Die Angriffsfläche ist lokal belegt klein: nur lokale
  Bildquellen, keine AVIF-Quelle erreichbar.
- **BUG-06:** Gatekeeper-Anleitung ohne Integritätsnachweis. Der Rechtsklick-Weg selbst ist nicht prüfbar.
- **BUG-07:** Werbeaussagen, die das ausgelieferte Release nicht erfüllt.
- **BUG-08:** Ersatz-Release fest auf v1.1 verdrahtet — ein Build mit `get-task-allow`, siehe B09 BUG-01/02.

Drei Befunde sind niedrig (BUG-09 bis BUG-11). BUG-11 kommt aus dem Code-Review und ist verifiziert.

**Nächster Schritt:** `/sdd-build B10` mit BUG-01 bis BUG-11, danach `/sdd-qa B10` (Durchlauf 2). **Die Erfassung wartet.**
Für BUG-01 bis BUG-03 braucht die Reparatur Angaben des Nutzers: öffentliche Adresse (OF-04), Vercel-Einstellung
*Deployment Protection* sowie Name und Kontakt des Verantwortlichen. Diese Befunde sind keine Rechtsberatung.

| | Anzahl |
|---|---|
| Akzeptanzkriterien geprüft | 41 von 41 |
| davon bestanden | 40 |
| davon durchgefallen | 1 (AK-34 → BUG-04) |
| **nicht prüfbar** | 0 |
| Edge Cases belegt | 11 von 15 (9 ✅, 2 ❌, 4 nicht prüfbar) |
| Tests neu geschrieben | 61 in 5 Dateien unter `web/tests/` |
| Tests grün | 61 von 61 (53 bestanden, 8 als `todo` markierte Befund-Tests; 0 fehlgeschlagen) |

Zusätzlich *nicht prüfbar* und außerhalb der AK:

- der Gatekeeper-Weg „Rechtsklick → Öffnen" (FB-11, siehe BUG-06)
- die Leistungsaussage „17.000 Sender" (FB-06, → **B04**)
- EC-02, EC-04 (GitHub-Teil), EC-05, EC-10
- die Vercel-Log-Aufbewahrung

## Prüfumgebung

- macOS 27.0 (26A428), Node 26.8.2, npm 11.19.1, `next` 16.2.12, ohne `GITHUB_TOKEN`, ohne `NEXT_PUBLIC_SITE_URL`.
- Build `web/`: `npm run build` am 2026-09-15 23:27. Routenübersicht wie AK-01, Log im Scratchpad unter `b10qa/build-main.log`.
- Server: `npx next start -p 3918`, nach der Prüfung beendet.
- Nachstellungen in einer Scratchpad-Kopie von `web/` (inzwischen gelöscht). In der Kopie war nur
  `const API = process.env.QA_GITHUB_API ?? "https://api.github.com"` geändert:
  - `GITHUB_TOKEN=invalid` gegen das echte GitHub (AK-32)
  - Host `api.github.invalid` (AK-33, AK-34)
  - toter Proxy für Google Fonts (EC-08)
  - lokaler GitHub-Mock im Test `download-upstream.test.mjs`
- `npx tsc --noEmit` → Exit 0 · `npm run lint` → 0 Fehler, 0 Warnungen, einschließlich der neuen Tests.
- Browser: `chrome-headless-shell` aus dem Playwright-Cache über CDP, `--mute-audio`, keine Medien.
- Kein Deployment, keine Vercel-CLI, nichts auf GitHub angelegt. Live-Adressen und GitHub-API nur per GET.
- Nichts unter `Sources/`, `Tests/`, `project.yml` geändert, kein `xcodebuild`/`xcodegen`.
- App-Seite der Datenschutzaussagen, jeweils lesend und ohne Änderung:
  - `dist/MikaPlusPlayer-v1.1.dmg` schreibgeschützt eingehängt (`codesign`, `PlistBuddy`, `strings`, `lipo`)
  - Kopien von `XtreamCodes.swift` und `M3UParser.swift` im Scratchpad mit `swiftc` zu einer Sonde übersetzt,
    mit erfundenen Zugangsdaten `qa-user`/`qa-pass-123`
  - Dateinamen unter `~/Library` aufgelistet, **Inhalte nicht gelesen**

## Akzeptanzkriterien im Einzelnen

Testdateien: `U` = `web/tests/releases.unit.test.mjs`, `H` = `site.http.test.mjs`, `B` = `browser.cdp.test.mjs`,
`M` = `download-upstream.test.mjs` (Mock-Build), `L` = `live.readonly.test.mjs`.

| AK | Ergebnis | Nachweis |
|---|---|---|
| AK-01 | ✅ bestanden | Build-Log: `/` und `/changelog` mit Revalidate `1h` / Expire `1y`, `ƒ /download`, übrige `○`. `H::AK-01` prüft `prerender-manifest.json` (`initialRevalidateSeconds` 3600 / `initialExpireSeconds` 31536000, sonst `false`; `/download` nicht vorgerendert) |
| AK-02 | ✅ bestanden | `H::AK-02` auf `/`, `/download`, `/opengraph-image`, `/does-not-exist`: vier Header exakt, kein `X-Powered-By` |
| AK-03 | ✅ bestanden | `H::AK-03`: `s-maxage=3600, stale-while-revalidate=31532400` bzw. `s-maxage=31536000` |
| AK-04 | ✅ bestanden | `H::AK-04`: `/does-not-exist`, `/.env`, `/next.config.ts`, `/package.json`, `/.next/BUILD_ID` → 404 mit Kopf- und Fußzeile; `/download/` → 308 auf `/download` |
| AK-05 | ✅ bestanden | `B::AK-05`: bei 1280 px nach `scrollTo(0,2500)` steht `header.top` auf 0. Privacy bei 639 px `display:none`. Wortmarke bei 379 px ausgeblendet, `sr-only`-Text „Mika+Player" (1 px, absolut), sichtbar ab 380 px. `H::AK-05…`: Links und GitHub-Link `target=_blank`. Screenshot `qa/AK-05-kopfzeile-379px.png` |
| AK-06 | ✅ bestanden | `H::AK-05/AK-06/AK-07`: Fußzeilentext wörtlich, „Report an issue" und „Source" mit `target=_blank`. Kein Name, keine Anschrift, kein Kontakt — genau das ist BUG-03 |
| AK-07 | ✅ bestanden | `B::AK-07`: erster Tab → `activeElement` „Skip to content" bei x/y ≤ 20 px, Enter → `location.hash` `#main`; `lang="en"`. Screenshot `qa/AK-07-skip-link.png` |
| AK-08 | ✅ bestanden | `B::AK-08`: `prefers-color-scheme` hell → `rgb(246, 244, 243)`, dunkel → `rgb(18, 15, 16)`; kein Umschalter. Screenshot `qa/AK-08-dunkel.png` |
| AK-09 | ✅ bestanden | `H::AK-09`: Kopfzeile des Hero, Überschrift, „Version 1.1 · 34.8 MB · macOS 14 Sonoma or later", „First launch"-Hinweis; beide Schaltflächen verlinken `https://github.com/daumedia/MikaPlusPlayer/releases/download/v1.1/MikaPlusPlayer-v1.1.dmg` (Anleitung selbst: BUG-06) |
| AK-10 | ✅ bestanden | `B::AK-10`: Klick auf Kachel 03 → groß „Documentary" mit „Sound", Kacheln danach 01/02/04. Umschalter nur im zweiten Nachbau. „grid" → 4 gleich große Kacheln, Klick auf 3 → `aria-pressed`, Rahmen und „Sound" wandern. 0 `video`/`audio`/`iframe`, 0 Fremdanfragen. Screenshot `qa/AK-10-multiview-raster.png` |
| AK-11 | ✅ bestanden | `H::AK-11/AK-12`: Reihenfolge aller Abschnitte, 8 Funktionen, zweite Schaltfläche, Links auf GitHub und `/support` |
| AK-12 | ✅ bestanden | `H::AK-11/AK-12`: „The app itself" fehlt |
| AK-13 | ✅ bestanden | `H::AK-13`: Titel, `robots` „index, follow", `og:image` `…/opengraph-image?…` 1200 × 630, `summary_large_image`, `canonical`/`og:url` `http://localhost:3000` (Unterseiten: BUG-11) |
| AK-14 | ✅ bestanden | `H::AK-14`: 302 auf DMG, auch mit `?url=https://evil.example` und `?redirect=//evil.example`; `HEAD` 302, `POST`/`PUT`/`DELETE`/`PATCH` 405 |
| AK-15 | ✅ bestanden | `M::AK-15`: nach 200 lösen 6 Aufrufe 0 Upstream-Anfragen aus. Zusätzlich gegen das echte GitHub: `rate_limit.core.remaining` vor und nach 6 Aufrufen 60 → 60, nach 60 parallelen Aufrufen ebenfalls 60 → 60 |
| AK-16 | ✅ bestanden | `U::AK-16/EC-03`: Release `v3.0` ohne DMG → `version` „3.0", `dmg` = v1.1-DMG, `isFallback` false |
| AK-17 | ✅ bestanden | `U::AK-14/AK-17`: Content-Type schlägt früheren `.DMG`-Namen. `U::AK-17`: ohne Content-Type gilt das erste `.DMG`/`.dmg` |
| AK-18 | ✅ bestanden | `U::AK-18/EC-04`: Entwurf gefiltert, Vorabversion bleibt, API-Reihenfolge, leerer/`null`-Name → Tag, `per_page=20`. `M::AK-18/EC-04` am echten Build. `H::AK-18/AK-19` live gegen GitHub: v1.1, „June 23, 2026", Links mit neuem Tab |
| AK-19 | ✅ bestanden | `U::AK-19`: v1.1-Ersatztext ersetzt den GitHub-Text, andere Texte getrimmt. `M::AK-18`: Release mit leerem Text ohne `prose`-Block, v1.1 zeigt „Multiview (macOS)" statt des deutschen Textes. GFM-Tabelle in `M::AK-20` |
| AK-20 | ✅ bestanden | `M::AK-20` am echten Build: `<script>`, `<img onerror>`, `<iframe>`, `<a href="javascript:">` erscheinen als `&lt;…&gt;`-Text. `[md-js]`/`[md-vb]`/`[md-data]` → `href=""`. `https`-Link und Autolink mit `target="_blank" rel="noopener noreferrer"`. Kein `<img>` (auch Referenzbild), kein `<hr>`, `#`/`##` → `h3` |
| AK-21 | ✅ bestanden | `H::AK-21`: alle auf `/changelog` eingebundenen JS-Chunks ohne `react-markdown`, `remark`, `micromark`, `mdast` |
| AK-22 | ✅ bestanden | `H::AK-22/AK-23`: vier Erststart-Schritte wörtlich, drei Einrichtungsschritte, Beispiel-Link mit neuem Tab, Tasten genau `Space`, `↑ ↓ + −`, `M`, `F`, `P`, `Esc`, neun Fragen (inhaltliche Richtigkeit: BUG-06, BUG-07) |
| AK-23 | ✅ bestanden | `B::AK-23`: 9 × `details`, alle zu; Mausklick öffnet, CSS `rotate` `0deg` → `45deg`. `B::AK-23/EC-11` ohne JavaScript: Klick setzt `open`. Screenshot `qa/AK-23-faq-offen.png` |
| AK-24 | ✅ bestanden | `H::AK-24/AK-25/AK-26`: Abschnitte, drei Punkte, „Last updated 30 July 2026", „a GitHub issue" in dieser Reihenfolge. Die falschen Aussagen sind BUG-02 und BUG-03 |
| AK-25 | ✅ bestanden | Seitentext per `H::AK-24/AK-25/AK-26`. App-Seite ausgeführt (Swift-Sonde): eingegeben `https://panel.qa.example:8443` → `baseURL` `http://panel.qa.example:8443`, `playerAPI` `http://…/player_api.php?username=qa-user&password=qa-pass-123` |
| AK-26 | ✅ bestanden | Wortlaut per `H`; die vier Punkte lokal erfüllt (AK-35, AK-36). **Live gilt „No cookies" nicht** → BUG-01 |
| AK-27 | ✅ bestanden | `H::AK-27/AK-28`: Inhalt byte-genau `User-Agent: *`, `Allow: /`, `Disallow: /download`, `Sitemap: http://localhost:3000/sitemap.xml` |
| AK-28 | ✅ bestanden | Standardfall per `H::AK-13`, `H::AK-27`, `H::AK-29` (Server auf Port 3918, URLs zeigen auf `localhost:3000`). `U::AK-28/EC-09`: `NEXT_PUBLIC_SITE_URL` hat Vorrang, sonst `https://<VERCEL_PROJECT_PRODUCTION_URL>`, abschließender Schrägstrich entfernt |
| AK-29 | ✅ bestanden | `H::AK-28/AK-29`: genau vier `<url>` mit Priorität und Frequenz wie spezifiziert, gemeinsamer `lastmod` `2026-09-15T21:27:24.692Z` (Build-Zeitpunkt), kein `/download` |
| AK-30 | ✅ bestanden | `H::AK-30`: PNG-IHDR 1200 × 630, `/icon.png` und `/apple-icon.png` `image/png`. Bild gesichtet: `qa/AK-30-opengraph-image.png` |
| AK-31 | ✅ bestanden | `U::AK-31` (ohne Token kein `Authorization`, feste Header, `next.revalidate` 3600). `M::AK-31/AK-37`: Mock erhielt `authorization: Bearer qa-fake-token-4711` nur in der Server-Anfrage |
| AK-32 | ✅ bestanden | Build der Kopie mit `GITHUB_TOKEN=invalid` gegen das echte GitHub: beide Zeilen `[releases] … -> 401; rate limit remaining: null`, Exit 0. `/` zeigt „Version 1.1 · 34.8 MB", `/changelog` „v1.1 – Multiview", „June 23, 2026", englischer Text. `U::AK-32/AK-39` |
| AK-33 | ✅ bestanden | Build der Kopie mit Host `api.github.invalid`: zweimal `[releases] request failed: … [TypeError: fetch failed] { [cause]: Error: getaddrinfo ENOTFOUND … }`, Exit 0, dieselben Ersatzinhalte. `U::AK-33` |
| AK-34 ⚠ | ❌ durchgefallen | Ist reproduziert, als Fehler eingestuft → **BUG-04**. `api.github.invalid`: 4 Aufrufe → 4 × 302 auf v1.1 und 4 Warnzeilen. `M::AK-34/FB-21` (Mock 403, `x-ratelimit-remaining: 0`): 4 sequentielle Aufrufe → 4 Upstream-Anfragen, 60 parallele → 60, alle 302, kein 429 |
| AK-35 | ✅ bestanden | `H::AK-35`: kein `Set-Cookie` auf 11 Routen und `/_next/image` (lokal; live: BUG-01) |
| AK-36 | ✅ bestanden | `B::AK-36` (Netzwerkprotokoll des Browsers): je Seite 31 Anfragen, 0 fremd, 4 × `/_next/static/media/*.woff2`, Symbol über `/_next/image`. `H::AK-36`: kein Google-Fonts-, Analytics- oder Insights-Verweis |
| AK-37 | ✅ bestanden | `B::AK-37`: Klick auf „Download for macOS", Anfrage per CDP vor dem Senden abgefangen (kein Download). Ziel ist direkt `https://github.com/…/MikaPlusPlayer-v1.1.dmg`, `Referer: http://127.0.0.1:3918/` (nur Ursprung), kein Cookie |
| AK-38 | ✅ bestanden | `H::AK-38`: `.next/static` ohne `GITHUB_TOKEN`, `api.github.com`, `x-ratelimit`; `*.js.map` → 404; `.gitignore` enthält `.env*`. `M::AK-38`: Build mit gesetztem Token → 0 Treffer in `.next/static`. Git-Verlauf (19 Commits): nur `GITHUB_TOKEN=invalid` in `web/README.md`, kein `ghp_`/`github_pat_`. Einzige `NEXT_PUBLIC_`-Variable ist die Site-URL |
| AK-39 | ✅ bestanden | `U::AK-32/AK-39`, `U::AK-39` (Warnung = Pfad, Status, Restkontingent, kein Token). `M::AK-39`: Build- und Serverprotokoll ohne Token und ohne Besucher-Marker |
| AK-40 | ✅ bestanden | `H::AK-40`: fremde, protokollrelative, `127.0.0.1`-, rekursive und Traversal-URL sowie `w=65`/`q=50` → 400; `url=%2Ficon-512.png&w=64&q=75` → 200 `image/png`; `images-manifest.json`: `remotePatterns []`, `formats ["image/webp"]` |
| AK-41 | ✅ bestanden | `H::AK-41`: kein `form`/`input`/`textarea`/`select`/`type=file`, keine Server Action auf 5 Seiten |

## Edge Cases

| EC | Ergebnis | Nachweis |
|---|---|---|
| EC-01 | ❌ durchgefallen | Mechanismus mit Mock nachgestellt (`403`, `x-ratelimit-remaining: 0`): jeder `/download` fragt erneut (`M::AK-34/FB-21`), Seite fällt auf v1.1 zurück → BUG-04. Die Vercel-Umgebung selbst wurde nicht beobachtet |
| EC-02 | ⚠️ nicht prüfbar | Neuberechnung erst nach 3600 s; ohne einstündige Wartezeit oder Codeänderung am Revalidate-Wert nicht auslösbar |
| EC-03 | ✅ bestanden | `U::AK-16/EC-03` |
| EC-04 | ⚠️ nicht prüfbar | Website-Teil ausgeführt: Vorabversion erscheint im Changelog mit DMG-Link (`M::AK-18/EC-04`). Dass `/` und `/download` sie auslassen, folgt aus GitHubs `releases/latest`; ohne echte Vorabversion nicht beobachtbar |
| EC-05 | ⚠️ nicht prüfbar | Die Seite begrenzt nicht selbst, sie fragt `per_page=20` ab (`U::AK-18/EC-04`); die Kappung liegt bei GitHub, und es gibt nur ein Release |
| EC-06 | ✅ bestanden | `M::AK-20`: HTML eines Release-Textes ohne Ersatztext erscheint als maskierter Quelltext; `U::AK-19`: ohne Ersatztext gilt der GitHub-Text |
| EC-07 | ❌ durchgefallen | `M::EC-07`: 7 × `node="[object Object]"` an `h3` und `a` im echten Build → BUG-10 |
| EC-08 | ✅ bestanden | Build der Kopie mit totem Proxy: `next/font: error: Failed to fetch \`Archivo\` from Google Fonts.` (dreimal), `Turbopack build failed with 3 errors`, Exit 1 (`b10qa/build-ec08-fonts-blocked.log`) |
| EC-09 | ✅ bestanden | `H::AK-27/AK-28`, `U::AK-28/EC-09` |
| EC-10 | ⚠️ nicht prüfbar | Vercel-Vorschau-Umgebung nicht zugänglich (Deployment Protection). Vorrang der Variablen per `U::AK-28/EC-09` belegt |
| EC-11 | ✅ bestanden | `B::AK-23/EC-11`: JavaScript per CDP abgeschaltet; FAQ-Texte im DOM, `details` öffnet nativ, Multiview-Nachbau steht auf `focus` |
| EC-12 | ✅ bestanden | Build mit Node 26.8.2 (außerhalb `engines` `>=20.9.0 <25`) ohne Warnung, Exit 0 (`build-main.log`) |
| EC-13 | ✅ bestanden | `U::EC-13`: 36 455 860 → „34.8 MB" |
| EC-14 | ✅ bestanden | `U::EC-14`: `2026-06-23T23:30:00-02:00` → „June 24, 2026" |
| EC-15 | ✅ bestanden | `U::AK-16`, `U::AK-32`, `U::AK-33`: jeder Pfad von `getLatestRelease` liefert ein `dmg` (neu, Ersatz-DMG bei fehlendem Asset, Ersatz-Release bei Fehler) — der `htmlUrl`-Zweig wird nie erreicht |

## Datenschutzseite Satz für Satz

Aussagen von `/privacy` (`web/app/privacy/page.tsx`) und die Datenschutzaussagen von Start- und FAQ-Seite, gegen die
App gehalten.

| # | Aussage | Beleg | Ergebnis |
|---|---|---|---|
| 1 | „nothing goes to us, because there is no us to send it to" (`:19`) | App: `strings` im v1.1-Binary ohne Analytics-/Crash-SDK, Frameworks nur `Sparkle`, `VLCKit`. Website: Vercel speichert Server-Logs für den Betreiber (Seite selbst, `:81`) | **irreführend** für die Website → BUG-02 |
| 2 | „No account, no server, no telemetry, no analytics — in the app or on this site" (`:19-20`) | Analytics: 0 Fremdanfragen (`B::AK-36`), keine SDK-Strings. „no server … on this site": `/download` ist eine Server-Funktion (`ƒ`, AK-01) | **teilweise falsch** → BUG-02 |
| 3 | Daten „are written to a local database on your Mac" (`:36-37`) | `~/Library/Application Support/default.store` vorhanden (nur Dateiname und Größe gelesen); B01 AK-24/AK-28 ausgeführt | stimmt |
| 4 | „They stay in the app's own storage" (`:37`) | v1.1-DMG: `com.apple.security.app-sandbox => false`; Datenbank unter dem generischen Namen `default.store` im gemeinsamen `Application Support` (B01 AK-28) | **falsch** → BUG-02 (FB-04) |
| 5 | „no copy anywhere else" (`:38`) | `~/Library/Caches/lu.daumedia.MikaPlusPlayer/Cache.db` vorhanden; B01 AK-25 (ausgeführt): Anfrage-URLs mit Benutzername und Passwort samt Antworten im HTTP-Cache | **falsch** → BUG-02 |
| 6 | „Deleting a playlist removes its channels" (`:39`) | Kaskade gehört zu B03 und wurde hier nicht ausgeführt; Cache-Einträge bleiben laut B01 AK-25 | ⚠️ nicht prüfbar (→ B03) |
| 7 | „deleting the app removes all of it" (`:39`) | App liegt unter `/Applications/MikaPlusPlayer.app`. Außerhalb davon vorhanden: `default.store` (+ `-wal`, `-shm`), `Caches/lu.daumedia.MikaPlusPlayer/Cache.db`, `HTTPStorages/lu.daumedia.MikaPlusPlayer`, `Preferences/lu.daumedia.MikaPlusPlayer.plist`, `Containers/lu.daumedia.MikaPlusPlayer` | **falsch** → BUG-02 (FB-04) |
| 8 | „Every stream, channel list and logo request goes to the host you entered" (`:47-48`) | Swift-Sonde: M3U von `playlist.qa.example` mit Streams auf `streams.third-host.example`, `cdn.fourth-host.example` und Logos auf `logos.other-host.example`, `203.0.113.9` → 4 fremde Hosts | **falsch** → BUG-02 (FB-05) |
| 9 | „Channel logo servers … loads those images from whichever host the playlist points at" (`:52-54`) | Sonde: `logoURL` beliebiger Hosts; `AsyncImage(url: channel.logoURL)` (`ChannelRowView.swift:36`). Das tatsächliche Laden gehört zu B04 | stimmt laut Sonde; widerspricht Satz 8 |
| 10 | „fetches an update feed from raw.githubusercontent.com and downloads new versions from github.com" (`:57-59`) | v1.1-DMG: `SUFeedURL = https://raw.githubusercontent.com/Mukaarts/MikaPlusPlayer/main/appcast.xml`; `appcast.xml`-Enclosure `https://github.com/daumedia/…/MikaPlusPlayer-v1.1.dmg` | stimmt (Namensraum-Risiko: B09 BUG-01) |
| 11 | „That request tells GitHub your IP address" (`:59`) | Sparkle sendet zusätzlich App- und Sparkle-Version im User-Agent (B09 BUG-12) | unvollständig → B09 |
| 12 | Xtream über HTTP, `https://` wird umgeschrieben, Zugangsdaten unverschlüsselt (`:66-73`) | Swift-Sonde (AK-25) | stimmt |
| 13 | „No cookies" (`:80`) | lokal 0 `Set-Cookie` (AK-35); live `Set-Cookie: _vercel_sso_nonce=…` auf beiden erreichbaren Deployments | lokal stimmt, **live falsch** → BUG-01 |
| 14 | „no analytics, no tracking scripts, no fonts loaded from third parties" (`:80`) | `B::AK-36` | stimmt |
| 15 | „hosted on Vercel, which keeps standard server logs" (`:81`) | Vercel-Projekt nicht einsehbar, Speicherdauer nirgends genannt | ⚠️ nicht prüfbar; fehlende Speicherdauer → BUG-03 |
| 16 | „GitHub, which counts downloads per release" (`:82`) | GitHub-API liefert `download_count` je Asset; Link zeigt direkt auf `github.com` (AK-37) | stimmt |
| 17 | „Neither of those tells us who you are" (`:82`) | IP-Adressen in Server-Logs sind personenbezogen; kein Verantwortlicher, keine Rechtsgrundlage genannt | **irreführend** → BUG-03 (FB-17) |
| 18 | „Last updated 30 July 2026" (`:11`) | `git log -- web/app/privacy/page.tsx`: einziger Commit `0fc392a` vom 2026-07-30 | stimmt mit dem Verlauf überein, ist aber eine feste Konstante |
| 19 | „Questions … belong in a GitHub issue" (`:95-103`) | einziger Kontaktweg öffentlich (`H::FB-16/FB-17/FB-18`) | → BUG-03 (FB-18) |
| 20 | Start: „all on your Mac, all local", „It never does … send your data anywhere" (`app/page.tsx:64-72`) | Sätze 5, 8 und 12 | **falsch** → BUG-02 (FB-03) |
| 21 | FAQ: „Where does my data go? Nowhere. … talks to the provider you entered and, for updates, to GitHub" (`content/faq.ts:40`) | Satz 8: Logo- und Stream-Hosts fehlen | **falsch** → BUG-02 (FB-03) |

## Sicherheitsprüfung

Aktiv angegriffen, nicht nur gelesen. Grundlage: `~/.claude/sdd/sicherheit.md`, Stufe B.

| Prüfung | Ergebnis | Beleg |
|---|---|---|
| Zugriff auf fremde ID (IDOR) | bestanden (trifft auf Datensätze nicht zu) | Keine nutzerbezogenen Datensätze vorhanden. Stattdessen Parameter manipuliert: `/download?url=https://evil.example` und `?redirect=//evil.example` → 302 auf das DMG; `/_next/image?url=https://evil.example/x.png` → 400; `/_next/image?url=%2F..%2F..%2Fetc%2Fpasswd` → 400 „isn't a valid image" (kein Dateiinhalt) |
| Zugriffsregeln serverseitig | bestanden | `/.env`, `/next.config.ts`, `/package.json`, `/.next/BUILD_ID`, `/_next/static/..%2F..%2Fpackage.json` → 404/400; `*.js.map` → 404; `POST`/`PUT`/`DELETE`/`PATCH /download` → 405 |
| Rate Limit greift | **BUG-04** | Kein Limit: 60 parallele `/download` → 60 × 302, kein 429. Mit gültigem Cache 0 GitHub-Anfragen (`remaining` 60 → 60). Im Fehlerfall 64 Aufrufe → 64 Upstream-Anfragen und 64 Warnzeilen (`M::AK-34/FB-21`) |
| PII in Logs | bestanden (lokal) | Serverprotokoll `next start` (11 Zeilen): keine IP, kein User-Agent, kein Cookie; nur Pfade abgewiesener Bildanfragen (`⨯ internal image response is empty for /download`). Mock-Build: Token `qa-fake-token-4711` und Besucher-Marker weder im Build- noch im Serverprotokoll (`M::AK-39`). Vercel-Logs nicht einsehbar |
| PII an externe Dienste | bestanden | **Tatsächlicher Payload am GitHub-Mock**, Aufruf von `/download?email=qa-visitor%40example.com` mit User-Agent-, Cookie-, `X-Forwarded-For`- und Referer-Markern. Beim Mock kam nur an: `host`, `accept: application/vnd.github+json`, `user-agent: mikaplusplayer-website`, `x-github-api-version: 2022-11-28`, `authorization: Bearer <Test-Token>`, `accept-language`, `sec-fetch-mode`, `accept-encoding`; Pfad ohne Query, 0 Marker (`M::AK-31/AK-37`). Browser: 0 Fremdanfragen beim Laden; Download-Klick sendet an GitHub nur `Referer` = Ursprung, kein Cookie |
| Geheimnisse im Repository | bestanden | `git log -p --all`: kein `ghp_…`/`github_pat_…`, `GITHUB_TOKEN` nur als `=invalid`-Beispiel in `web/README.md`; `.next/static` ohne Token/API-Host, auch bei Build mit gesetztem Token; `.env*` ignoriert |
| Eingaben | bestanden | Keine Eingabefelder (AK-41). Fuzzing: leer, 1 Zeichen, 10.000 Zeichen, Emoji, `'; drop table --`, `<script>alert(1)</script>`, `../../etc/passwd`, `#?/%&`, Umlaute × 5 Routen (Pfad, Query, Fragment) → kein 5xx, keine Reflexion, kein Dateiinhalt |
| Löschen | trifft nicht zu / **BUG-03** | Website speichert keine Besucherdaten (`.next/cache/images` enthält nur Bildvarianten). Für Vercel-Server-Logs gibt es keinen Auskunfts- oder Löschweg außer öffentlichen GitHub Issues |
| Abhängigkeiten | **BUG-05** | `npm audit --omit=dev`: 1 kritisch, 3 hoch (Details unter BUG-05) |
| Sicherheits-Header | bestanden / **BUG-09** | Vier Header gesetzt (AK-02); `Content-Security-Policy` und `Permissions-Policy` fehlen |
| Fremde Inhalte (XSS über Release-Text) | bestanden | `M::AK-20` mit feindseligem Release-Text am echten Build |
| Live-Umgebung | **BUG-01** | siehe BUG-01 |

## Fehler

### BUG-01 · Website öffentlich nicht erreichbar; einzige Datenschutzerklärung nicht abrufbar — hoch

**Betrifft:** US-01 bis US-07, AK-26 und AK-35 (live) · **Fehlbestand:** FB-15 · Offene Frage OF-04

**Reproduktion** (2026-09-15 21:28 UTC, nur GET, Test `L::FB-15`):
1. `curl -sI https://mikaplus-player.vercel.app/privacy` → `404`, `x-vercel-error: DEPLOYMENT_NOT_FOUND`. Das ist die
   Homepage laut GitHub-API.
2. `https://mikaplus-player-bgidneikr-daumedia.vercel.app/privacy` → `302` auf `https://vercel.com/sso-api?…`,
   dazu `set-cookie: _vercel_sso_nonce=…; Max-Age=3600; Secure; HttpOnly` und `x-robots-tag: noindex`. Die Adresse
   ist das letzte Production-Deployment `6380009546` vom 2026-09-10 auf `c01f1cf`.
3. `curl -L` endet auf `https://vercel.com/login?…` mit „Login – Vercel", ohne „What leaves your Mac".
   `https://mikaplus-player-daumedia.vercel.app/privacy` verhält sich gleich.
4. `dig mikaplusplayer.com` → `NXDOMAIN`. Das ist die Domain aus `web/README.md:69`.

**Erwartet:** `/privacy` ist unter einer öffentlichen Adresse ohne Anmeldung und ohne Cookie erreichbar, und diese
Adresse steht als Homepage im Repository.

**Tatsächlich:** Keine Adresse liefert die Seite aus. Die einzige Datenschutzerklärung zu App und Website ist für
Nutzer nicht abrufbar. Der erreichbare Vercel-Rand setzt ein Cookie, entgegen „No cookies".

**Ort:** Vercel-Projekteinstellungen (Deployment Protection, Domains), nicht im Repository. Dazu die GitHub-Homepage
des Repositorys.

**Vorschlag:** Öffentliche Production-Domain festlegen (OF-04), Deployment Protection für Production abschalten,
Repository-Homepage korrigieren. Die App oder das README sollten auf `/privacy` verweisen.

**Nicht behoben (Teil 1):** Die Ursache liegt in den Vercel-Projekteinstellungen (Deployment Protection, Domain) und in der Repository-Homepage auf GitHub. Beides braucht Zugänge, die dieser Auftrag ausschließt, und die öffentliche Adresse ist eine Nutzerentscheidung (OF-04). Nachstellung am 2026-09-16 (`L::FB-15`, weiter `todo`): `mikaplus-player.vercel.app/privacy` → 404 `DEPLOYMENT_NOT_FOUND`; das letzte Production-Deployment → 302 auf `vercel.com/sso-api` mit `_vercel_sso_nonce`; `mikaplusplayer.com` → `ENOTFOUND`.

### BUG-02 · Datenschutzaussagen widersprechen dem App-Verhalten — hoch

**Betrifft:** AK-24 (Inhalt) · **Fehlbestand:** FB-03, FB-04, FB-05 · Test `H::FB-03/FB-04/FB-05` (`todo`)

**Reproduktion:**
1. `/privacy` öffnen: „They stay in the app's own storage", „no copy anywhere else", „deleting the app removes all
   of it", „Every stream, channel list and logo request goes to the host you entered", „nothing goes to us",
   „no server … on this site". Startseite: „send your data anywhere", „all local". FAQ: „Where does my data go?
   Nowhere."
2. Speicherort: `codesign -d --entitlements - MikaPlusPlayer.app` aus `dist/MikaPlusPlayer-v1.1.dmg` →
   `app-sandbox => false`. Die Datenbank liegt unter `~/Library/Application Support/default.store` (B01 AK-28).
3. Zweite Kopie: `~/Library/Caches/lu.daumedia.MikaPlusPlayer/Cache.db` hält Anfrage-URLs mit Benutzername und
   Passwort (B01 AK-25, dort ausgeführt).
4. App löschen: Die Dateien unter `~/Library/{Application Support,Caches,HTTPStorages,Preferences,Containers}`
   liegen außerhalb von `/Applications/MikaPlusPlayer.app` und bleiben stehen.
5. Hosts: Swift-Sonde mit einer M3U von `playlist.qa.example` → Streams und Logos auf 4 anderen Hosts.

**Erwartet:** Die Datenschutzerklärung beschreibt Speicherort, Kopien, Löschweg und alle Empfänger zutreffend.

**Tatsächlich:** Nach dem Löschen der App liegen Xtream-Passwörter im Klartext weiter auf dem Mac, entgegen der
Zusage. Empfänger außer dem eingegebenen Host werden auf Start- und FAQ-Seite verneint. Die Seite widerspricht sich
selbst (Satz 8 gegen Satz 9, „Nowhere" gegen den HTTP-Abschnitt).

**Ort:**
- `web/app/privacy/page.tsx:19-20,37-39,47-49,82`
- `web/app/page.tsx:64-72`
- `web/content/faq.ts:40`

**Vorschlag:** Texte an das tatsächliche Verhalten anpassen, also Pfad, Cache, Löschanleitung für macOS und alle
Empfängerarten nennen. Unabhängig davon die Ursachen in B01 beheben (Keychain, Cache, eigener Store-Name).

**Nicht behoben (Teil 1):** Die Reparatur ist für Teil 2 vorgesehen, nach den App-Reparaturen (B01: Keychain, Cache, Store-Name). Die Texte sollen das reparierte App-Verhalten beschreiben, nicht den Zwischenstand. Test `H::FB-03/FB-04/FB-05` bleibt `todo`.

### BUG-03 · Pflichtangaben fehlen: Verantwortlicher, Rechtsgrundlagen, Speicherdauer, Rechte, Kontaktweg — hoch

**Betrifft:** AK-06, AK-24; Katalog 1, 2, 5 · **Fehlbestand:** FB-16, FB-17, FB-18 · Test `H::FB-16/FB-17/FB-18` (`todo`)

**Reproduktion:** Auf `/`, `/privacy`, `/support` und `/changelog` nach Name, Anschrift, E-Mail, „Imprint/Legal
notice/Controller", Rechtsgrundlagen, Speicherdauer, Betroffenenrechten und Aufsichtsbehörde suchen → 0 Treffer.
Einziger Kontakt sind öffentliche GitHub Issues. `docs/datenschutz.md` existiert nicht, und nirgends ist ein
Auftragsverarbeitungsvertrag mit Vercel dokumentiert.

**Erwartet:** Stufe B verlangt Datenschutzhinweise mit Verantwortlichem und Kontakt, Zwecken und Rechtsgrundlagen,
Empfängern (Vercel, GitHub) samt Drittlandbezug, Speicherdauer der Logs, Betroffenenrechten und einem nicht
öffentlichen Weg für Auskunft und Löschung.

**Tatsächlich:** Nichts davon ist vorhanden. „Neither of those tells us who you are" übergeht, dass IP-Adressen in
Logs personenbezogen sind. *Befund, keine Rechtsberatung.*

**Ort:** `web/app/privacy/page.tsx`, `web/components/site-footer.tsx`, `docs/datenschutz.md` (fehlt)

**Vorschlag:** Verantwortlichen samt Kontakt-E-Mail aufnehmen und die Datenschutzseite um die fehlenden Pflichtteile
ergänzen. Die Anbieterkennzeichnung ist durch den Nutzer rechtlich bewerten zu lassen.

**Nicht behoben (Teil 1):** Die Reparatur ist für Teil 2 vorgesehen. Sie braucht Angaben des Nutzers (Verantwortlicher, Anschrift, Kontakt-E-Mail) und seine rechtliche Bewertung. Test `H::FB-16/FB-17/FB-18` bleibt `todo`.

### BUG-04 · `/download` ohne Cache im Fehlerfall und ohne Limit — mittel

**Betrifft:** AK-34 ⚠, EC-01 · **Fehlbestand:** FB-21 · Test `M::AK-34/FB-21` (`todo`)

**Reproduktion:**
1. `cd web && node --test --test-timeout=300000 tests/download-upstream.test.mjs`. Der Mock beantwortet
   `releases/latest` mit 403 und `x-ratelimit-remaining: 0`.
2. 4 sequentielle Aufrufe → 4 Upstream-Anfragen; 60 parallele → 60 Upstream-Anfragen. Alle 302, 64 Warnzeilen.
3. Gegenprobe: Nach einer 200-Antwort lösen 6 Aufrufe 0 Anfragen aus (AK-15).

**Erwartet:** Im Fehlerfall höchstens eine Upstream-Anfrage je Zeitfenster und ein Limit je Client.

**Tatsächlich:** Jeder Aufruf startet eine Server-Funktion und eine GitHub-Anfrage. Auf Vercel ohne `GITHUB_TOKEN`
hält ein erschöpftes Limit von 60 Anfragen je Stunde die Seite im Ersatzzustand, und jeder Klick verbraucht erneut
Kontingent und Funktionszeit.

**Ort:** `web/app/download/route.ts:5-9`, `web/lib/releases.ts:73-90` (Next.js cacht nur Status 200)

**Vorschlag:** Fehlerantworten kurz zwischenspeichern oder `/download` statisch aus dem ISR-Ergebnis bedienen. Dazu
ein Plattform-Limit und ein gesetztes `GITHUB_TOKEN`.

**Behoben 2026-09-16 (Teil 1):** `/download` fragt GitHub nicht mehr bei jedem Klick. Neu ist `getLatestReleaseForDownload()` in `web/lib/releases.ts:138`, benutzt von `web/app/download/route.ts`:
- Gleichzeitige Aufrufe teilen sich eine laufende Anfrage.
- Nach einem Fehler gilt die Antwort für `DOWNLOAD_RETRY_AFTER_MS` = 5 Minuten als unbekannt (`:8`). In dieser Zeit geht `/download` ohne Upstream-Anfrage auf die Release-Seite (BUG-08).
- Der Erfolgsfall bleibt unverändert im Daten-Cache von Next.js (AK-15).
- Die Seiten `/` und `/changelog` nutzen das Fenster bewusst nicht, damit ihre ISR-Neuberechnung die Anfrage selbst ausführt und stündlich bleibt.

Nachweis: `M::AK-34/FB-21` ohne `todo`. Die Kopie hat ein verkürztes Fenster von 4 s. Im Fenster erzeugen 4 sequentielle und 60 parallele Aufrufe **0** Upstream-Anfragen und 0 Warnzeilen, vorher waren es 64. Nach Ablauf erzeugen 60 parallele Aufrufe genau **1** Anfrage. `M::AK-15`: Nach der Erholung auf 200 lösen 6 Aufrufe 0 Anfragen aus. Dazu die Unit-Tests `U::BUG-04` (2). Gegenprobe mit unerreichbarem GitHub: 6 Aufrufe ergeben 1 Warnzeile.
**Offen:** Ein Limit je Client ist in der Anwendung nicht verlässlich lösbar, weil es ohne gemeinsamen Speicher (neue Abhängigkeit) nicht geht. Es gehört als Plattform-Limit (Vercel Firewall) zusammen mit einem gesetzten `GITHUB_TOKEN` in die Vercel-Einstellungen, also OF-06. Auf Vercel gilt das Fenster je Funktionsinstanz.

### BUG-05 · `next` 16.2.12 mit bekannten kritischen/hohen Advisories — mittel

**Betrifft:** Katalog 4 · **Fehlbestand:** FB-22 · Test `H::FB-22` (`todo`)

**Reproduktion:** `cd web && npm audit --omit=dev` → 1 kritisch, 3 hoch:

- `next` GHSA-2xp9-vwfh-vxw4: RCE in der Bildoptimierung beim Optimieren von AVIF-Dateien (libheif über sharp),
  behoben ab 16.3.3
- `next` GHSA-p293-qw3h-jr36: nur Windows-Hosting
- `sharp` 0.34.5: GHSA-f88m-g3jw-g9cj, GHSA-rgj7-g3m4-5g8c
- `postcss` ≤ 8.5.22: GHSA-6g55-p6wh-862q u. a.
- `nanoid`: GHSA-2v37-7h3g-55p8

Vorgeschlagene Behebung laut npm: `next@16.3.5`.

**Angriffsfläche** lokal am laufenden Server belegt, **kein Exploit ausgeführt:**

- `/_next/image` ist öffentlich ansprechbar.
- `images-manifest.json`: `remotePatterns []`, `domains []`, `formats ["image/webp"]`, `dangerouslyAllowSVG false`.
- Fremde, `127.0.0.1`- und protokollrelative URLs → 400.
- `w`/`q` sind auf die Listen beschränkt.
- `localPatterns` erlaubt jeden lokalen Pfad. `url=/opengraph-image` wird optimiert (200 PNG).
- `url=/download` → 400 „internal response is invalid", die Weiterleitung zu GitHub wird also nicht verfolgt.
- `url=/changelog` → 400.
- Keine Route liefert von außen steuerbare Bytes, und in `public/` liegt keine AVIF-Datei.

Eine AVIF-Quelle unter Kontrolle eines Angreifers ist heute also nicht erreichbar.

**Erwartet:** Keine Produktionsabhängigkeit mit bekannter kritischer Lücke, für die ein Patch existiert.

**Tatsächlich:** Die Lücke ist heute nicht erreichbar. Ein einziger `remotePatterns`-Eintrag, künftige
Nutzer-Screenshots oder Self-Hosting mit fremden Bildern machen sie ausnutzbar. Auf Vercel übernimmt die Plattform die
Optimierung, dort nicht geprüft.

**Ort:** `web/package.json:15`, `web/package-lock.json`

**Vorschlag:** Auf `next` ≥ 16.3.3 aktualisieren (npm schlägt 16.3.5 vor), danach `npm audit` erneut ausführen.

**Behoben 2026-09-16 (Teil 1):**
- Pakete: `next` 16.2.12 → **16.3.3**, die kleinste Version mit Fix für GHSA-2xp9-vwfh-vxw4 und GHSA-p293-qw3h-jr36. Dazu `eslint-config-next` 16.2.12 → 16.3.3, beides exakt gepinnt (`web/package.json`).
- Mitgezogen: `postcss` 8.5.23, `sharp` 0.35.4.
- `nanoid` 3.3.16 → 3.3.19 per `npm update nanoid`. Das ist nur eine Lockfile-Aktualisierung innerhalb der vorhandenen Semver-Range, kein neues Paket.
- `npm audit --omit=dev` → **found 0 vulnerabilities**.
- Mit Dev-Abhängigkeiten bleibt 1 hoch: `js-yaml` 4.0.0–4.3.1 (GHSA-2883-xcg3-v3hh), nur über ESLint, nicht im Auftrag.
- Test `H::FB-22` ohne `todo`, grün.

### BUG-06 · Gatekeeper-Anleitung ohne Integritätsnachweis; Rechtsklick-Weg auf aktuellem macOS fraglich — mittel

**Betrifft:** AK-09, AK-22 (Inhalt) · **Fehlbestand:** FB-11

**Reproduktion:**
1. Eigene Attrappe `QADummy.app` im Scratchpad: C-Binary, `codesign -s -`, Quarantäne-Attribut
   `0081;…;Safari;<uuid>`. Die App des Nutzers wurde nicht verwendet.
2. `codesign -dv` → `Signature=adhoc`.
3. `spctl --assess --type execute -vv` → `rejected`, mit und ohne Quarantäne.
4. `syspolicy_check distribution` → „Adhoc Signed App" und „Notary Ticket Missing — Severity: Fatal".
5. `/`, `/support` und `/changelog` nach `sha256|checksum|shasum` sowie „System Settings / Open Anyway" durchsucht
   → 0 Treffer.

**Nicht prüfbar:** Ob „Rechtsklick → Öffnen → Bestätigen" auf macOS 27 die Sperre aufhebt, ist ohne
Klick-Automatisierung im Finder nicht beobachtbar. Aus Rücksicht auf die Tonvorgabe wurde die Attrappe nicht mit
`open` gestartet. Apple dokumentiert unter „Updates to runtime protection in macOS Sequoia" (6. August 2024,
`https://developer.apple.com/news/?id=saqachfa`): „In macOS Sequoia, users will no longer be able to Control-click to
override Gatekeeper when opening software that isn't signed correctly or notarized." Die Freigabe erfolgt dort unter
Systemeinstellungen → Datenschutz & Sicherheit. Die Seite unterstützt laut eigener Angabe macOS 14 und neuer.

**Erwartet:** Eine Anleitung, die auf den unterstützten macOS-Versionen funktioniert, und ein prüfbarer
Integritätsnachweis für den Erstdownload. Das Stack-Profil verlangt Developer ID und Notarisierung.

**Tatsächlich:** Die Anleitung beschreibt nur den laut Apple ab macOS 15 entfallenen Weg. Nutzer werden angeleitet,
eine Schutzfunktion für eine Datei ohne Prüfsumme zu umgehen. EdDSA schützt nur Updates.

**Ort:**
- `web/app/support/page.tsx:35-44`
- `web/components/gatekeeper-note.tsx:9-13`
- `web/content/faq.ts:10`
- `web/content/changelog-overrides.ts:16`

**Vorschlag:** Notarisieren (B09 BUG-03). Bis dahin den Weg über Systemeinstellungen beschreiben und eine
SHA-256-Prüfsumme je Release veröffentlichen.

**Behoben 2026-09-16 (Teil 1):** Die Anleitung beschreibt jetzt den Weg über die Systemeinstellungen. Belegt ist er durch zwei Apple-Quellen: „Updates to runtime protection in macOS Sequoia" (6. August 2024) und den Mac User Guide „Open a Mac app from an unknown developer" (Open Anyway, etwa eine Stunde nach dem blockierten Versuch verfügbar, Bestätigung mit dem Anmeldepasswort; in der macOS-14-Fassung zusätzlich Control-Klick → Öffnen).
- Die Prüfsumme kommt ohne neue Abhängigkeit aus dem Asset-`digest` der GitHub-API (`sha256FromDigest`, `web/lib/releases.ts:80`, nur gültige `sha256:`-Werte). Sie erscheint unter beiden Download-Schaltflächen und je Release im Changelog.
- Abgeglichen: API-`digest` für v1.1 = `shasum -a 256 dist/MikaPlusPlayer-v1.1.dmg` = `8da0620e…845a272c`.
- Geänderte Stellen: `web/components/gatekeeper-note.tsx`, `web/app/support/page.tsx` (fünf Schritte mit Prüfschritt `shasum -a 256`, Sprungziel `#first-launch`), `web/content/faq.ts`, `web/content/changelog-overrides.ts`, `web/components/download-button.tsx`, `web/app/changelog/page.tsx`.
- Tests `H::AK-09`, `H::AK-18/AK-19`, `H::AK-22/AK-23`, `U::BUG-06`, `M::AK-18/EC-04` (digest aus dem Mock, ungültiger digest wird ignoriert).

**Weiter offen:** Die Notarisierung (B09 BUG-03) braucht eine Developer ID. Der Klickweg selbst ist wegen der Tonvorgabe und ohne Finder-Automatisierung weiter nicht ausgeführt. Der App-Name in den Schritten („Mika+Player" statt `MikaPlusPlayer.app`, FB-12) gehört zu BUG-07, also Teil 2.

### BUG-07 · Werbeaussagen, die das ausgelieferte Release nicht erfüllt — mittel

**Betrifft:** AK-11, AK-22 (Inhalt) · **Fehlbestand:** FB-01, FB-02, FB-09, FB-10, FB-12, FB-13, FB-14

**Reproduktion** (je Punkt ausgeführt, soweit ohne App-Bedienung möglich):

- **FB-02 Bild-in-Bild und Taste P:** `git grep -c PictureInPicture v1.1 -- Sources` → 0 Treffer. `main` → 42 Treffer
  in 3 Dateien. `git tag --contains 54550b2` → kein Tag. Beworben in `content/features.ts:30-38` und
  `app/support/page.tsx:18`.
- **FB-01 Doppelklick-Import:** `grep -rnE 'onOpenURL|handlesExternalEvents|NSApplicationDelegateAdaptor' Sources`
  → 0 Treffer. `Info.plist` registriert `public.m3u-playlist` **und** `public.text` (nur gelesen; Bedienung → B02).
- **FB-10 Changelog als Update-Quelle:** v1.1-DMG `SUFeedURL = …/Mukaarts/MikaPlusPlayer/main/appcast.xml`, also
  `appcast.xml` und nicht die Release-Liste (`app/changelog/page.tsx:21`).
- **FB-09 Selbstinstallation:** v1.1-DMG `Info.plist` nur mit `SUEnableAutomaticChecks = true`, ohne
  `SUAutomaticallyUpdate` („Updates that install themselves", `content/features.ts:42`). Ablauf → B09 BUG-16.
- **FB-12 App-Name:** Bundle `MikaPlusPlayer.app`, `CFBundleName = MikaPlusPlayer`. Die Anleitung sagt „drag
  Mika+Player", „Right-click Mika+Player".
- **FB-13 Lizenz:** keine `LICENSE*` im Repository, GitHub-API `license: None`. Die Fußzeile sagt „An open-source
  IPTV player".
- **FB-14 Sprache:** `strings` im v1.1-Binary → „Alle", „Datei", „Fokus", „Raster", „Nach Updates suchen", kein
  `.lproj`. Die Website nennt „File", „All", „focus/grid", ohne Hinweis auf eine deutsche Oberfläche.

**Nicht hier geprüft, gehört zur jeweiligen QA:** FB-06 (Suche in der DB bei 17.000 Sendern → B04), FB-07
(Favoriten-Schlüssel → B05), FB-08 (HUD je Taste → B06).

**Erwartet:** Die Website bewirbt nur, was die herunterladbare Version kann.

**Tatsächlich:** Mehrere beworbene Eigenschaften fehlen im einzigen Release oder treffen nicht zu.

**Ort:**
- `web/content/features.ts:13-48`
- `web/app/support/page.tsx:18,41-43`
- `web/app/changelog/page.tsx:21`
- `web/components/site-footer.tsx:14`

**Vorschlag:** Aussagen auf den Release-Stand zurücknehmen oder als „coming in the next release" kennzeichnen,
Lizenz festlegen und den Sprachhinweis ergänzen.

**Nicht behoben (Teil 1):** Die Reparatur ist für Teil 2 vorgesehen. Die Aussagen hängen am App-Stand nach den Reparaturen und am nächsten Release (B02, B07, B09); Lizenz und Sprachhinweis sind Nutzerentscheidungen.

### BUG-08 · Ersatz-Release fest auf v1.1 verdrahtet, ohne Pflegeweg — mittel

**Betrifft:** AK-16, AK-32, AK-33, AK-34 · **Fehlbestand:** FB-19

**Reproduktion:**
1. `U::AK-32/AK-39` und der Build mit `api.github.invalid`: Jede GitHub-Störung sowie jedes neue Release ohne
   DMG-Asset verlinkt `…/v1.1/MikaPlusPlayer-v1.1.dmg`.
2. `grep -nE 'FALLBACK|releases\.ts|changelog-overrides|web/' scripts/*.sh` → 0 Treffer, der Release-Ablauf
   aktualisiert den Wert also nicht.
3. `codesign -d --entitlements -` am v1.1-DMG → `com.apple.security.get-task-allow => true`.

**Erwartet:** Der Ersatz folgt dem letzten Release, oder die Seite zeigt bei einer Störung die Release-Seite an.

**Tatsächlich:** Auch nach einem reparierten Release schickt die Website bei jeder GitHub-Störung Besucher auf v1.1.
Laut B09-QA hängt dieser Build an einem freien GitHub-Namensraum (B09 BUG-01) und trägt eine Debug-Berechtigung (B09
BUG-02, beide kritisch). `isFallback` wird nirgends ausgewertet.

**Ort:** `web/lib/releases.ts:46-60,126`, `web/content/changelog-overrides.ts:6-17`, `scripts/release.sh`

**Vorschlag:** Ersatzwerte beim Release mitschreiben oder bei `isFallback` auf `RELEASES_URL` verlinken.

**Behoben 2026-09-16 (Teil 1):** `FALLBACK_RELEASE` und `isFallback` sind entfernt, es gibt keine fest verdrahteten Versionsdaten mehr.
- `getLatestRelease()` und `getReleases()` liefern `null`, wenn GitHub nicht antwortet (`web/lib/releases.ts:119,150`).
- Ohne Release-Daten verlinken `/download` und beide Schaltflächen `https://github.com/daumedia/MikaPlusPlayer/releases/latest` (`LATEST_RELEASE_URL`, `web/lib/site.ts`; per GET geprüft: 302 auf das neueste Release). Die Beschriftung lautet „Latest release on GitHub".
- Ein neues Release ohne DMG verlinkt seine eigene Release-Seite statt des v1.1-DMG. Damit ist auch OF-01 gegenstandslos.
- `/changelog` zeigt bei einer Störung einen Hinweis mit Link auf die Release-Seite statt eines v1.1-Eintrags.

Nachweis:
- `M::AK-34`: Mock 403 → `/download` und `/` zeigen auf `/releases/latest`, kein „Version 1.1".
- Unit-Tests `U::AK-16/EC-03`, `U::AK-18`, `U::AK-32/AK-39`, `U::AK-33`.
- Gegenprobe mit `api.github.invalid` (Build-Kopie): Build Exit 0, beide Schaltflächen auf `/releases/latest`, Changelog-Hinweis, 0 Artikel.

**Nicht im Web-Code:** `scripts/release.sh` (B09) muss für den Ersatz nichts mehr pflegen. Der englische Ersatztext `content/changelog-overrides.ts` bleibt Handarbeit je Release (FB-19, zweiter Satz, → B09). Solange v1.1 das neueste Release ist, verlinkt die Seite regulär dieses Release (B09 BUG-01/02).

### BUG-09 · Keine Content-Security-Policy, keine Permissions-Policy — niedrig

**Betrifft:** AK-02 (Nebenaspekt) · **Fehlbestand:** FB-20 · Test `H::FB-20` (`todo`)

**Reproduktion:** `curl -sI http://127.0.0.1:3918/changelog` → weder `Content-Security-Policy` noch `Permissions-Policy`.

**Erwartet:** Eine zweite Verteidigungslinie für eine Seite, die fremde Release-Texte rendert.

**Tatsächlich:** Die Entschärfung hängt allein an `react-markdown`. Sie funktioniert heute (AK-20), bleibt aber ohne
Rückfallschutz.

**Ort:** `web/next.config.ts:5-19`

**Vorschlag:** CSP mit `script-src 'self'` (plus Nonce für Next-Inline-Skripte) und eine restriktive Permissions-Policy setzen.

**Behoben 2026-09-16 (Teil 1):** `web/next.config.ts:16-57` setzt für alle Routen zwei neue Header:
- `Content-Security-Policy`: `default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self'; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'`; `'unsafe-eval'` nur in `next dev`
- `Permissions-Policy`: `accelerometer, camera, geolocation, gyroscope, magnetometer, microphone, payment, usb, browsing-topics` jeweils `=()`

Nachweis:
- `H::FB-20` ohne `todo`: Direktiven auf 7 Routen geprüft.
- Neuer Browser-Test `B::FB-20 (BUG-09)`: auf `/`, `/changelog`, `/privacy`, `/support` **0** `securitypolicyviolation`-Ereignisse und **0** Fehler oder Warnungen in Konsole, Log und Netzwerk. Ein Klick im Multiview-Nachbau wirkt, die Hydration läuft also unter der CSP.
- **Negativkontrolle** (Build-Kopie mit zusätzlichem `script-src-elem 'self'`): derselbe Test schlägt mit 17 Verstößen fehl.
- `next dev` mit der CSP: 0 Verstöße, 0 Warnungen.

**Einschränkung:** Eine Nonce statt `'unsafe-inline'` würde jede Seite dynamisch machen (laut Next.js-Leitfaden keine statischen Seiten, kein ISR). Das widerspräche AK-01/AK-03, deshalb ist die Frage offen als OF-05. Die CSP blockiert fremde Skripte, `eval`, Plugins, Framing, `<base>`-Übernahme sowie fremde Bilder und Verbindungen, aber keine eingeschleusten Inline-Skripte.

### BUG-10 · Ungültiges Attribut `node="[object Object]"` in Release-Notizen — niedrig

**Betrifft:** EC-07 · **Fehlbestand:** FB-23 · Test `M::EC-07` (`todo`)

**Reproduktion:** Mock-Build mit einem Release-Text, der `# Heading` und Links enthält → im HTML 7 ×
`node="[object Object]"`, z. B. `<h3 node="[object Object]">Heading One</h3>` und
`<a href="https://example.com/qa-link" target="_blank" rel="noopener noreferrer" node="[object Object]">`.

**Erwartet:** Gültiges HTML ohne interne Props.

**Tatsächlich:** Die Props von `react-markdown` einschließlich `node` landen im DOM. Heute unsichtbar, weil v1.1
einen Ersatztext ohne Überschriften und Links hat.

**Ort:** `web/components/release-notes.tsx:14-18`

**Vorschlag:** `node` aus den Props entfernen (`({ node, ...props }) => …`).

**Behoben 2026-09-16 (Teil 1):** `withoutNode()` in `web/components/release-notes.tsx:5` entfernt die `node`-Prop, bevor `h1`/`h2` → `h3` und `a` gerendert werden. Nachweis: `M::EC-07` ohne `todo`, 0 Treffer statt 7; `M::AK-20` unverändert grün.

### BUG-11 · Open-Graph-Daten der Unterseiten zeigen auf die Startseite — niedrig

**Betrifft:** kein AK (Hinweis aus dem Code-Review, AK-13 prüft nur `/`) · Test `H::Hinweis (Code-Review)` (`todo`)

**Reproduktion:** `curl -s http://127.0.0.1:3918/changelog | grep -oE '<meta property="og:(url|title)"[^>]*>'` →
`og:url` `http://localhost:3000` und `og:title` „Mika+Player — IPTV player for macOS". `<title>` und `canonical`
stimmen dagegen (`Changelog — Mika+Player`, `…/changelog`). Bei `/privacy` und `/support` ist es genauso.

**Erwartet:** Geteilte Links auf Unterseiten zeigen Titel und URL der Unterseite.

**Tatsächlich:** Das Root-Layout vererbt sein `openGraph`-Objekt unverändert.

**Ort:** `web/app/layout.tsx:52-59`; `web/app/changelog/page.tsx:7-11`, `web/app/privacy/page.tsx:4-9`, `web/app/support/page.tsx:6-11`

**Vorschlag:** Je Unterseite `openGraph: { url, title, description }` setzen.

**Behoben 2026-09-16 (Teil 1):** Neues `pageMetadata()` in `web/lib/metadata.ts`. `/changelog`, `/privacy` und `/support` exportieren damit `generateMetadata` mit eigenem `og:url`, `og:title`, `og:description` und `canonical`. Das Vorschaubild übernehmen sie vom Layout: Ein seitenweises `openGraph` hätte das dateibasierte `og:image` sonst entfernt, das wurde beim Bau beobachtet und abgefangen. Die gemeinsamen OG-Grundwerte (`type`, `siteName`, `locale`) liegen in `OPEN_GRAPH_DEFAULTS`, das auch `web/app/layout.tsx` nutzt. Die Seiten bleiben statisch (AK-01). Nachweis: `H::Hinweis (Code-Review, BUG-11 behoben)` ohne `todo`, erweitert um `og:title`, `og:description`, `og:image` und `og:site_name` je Unterseite.

## Code-Review

Der `code-reviewer`-Agent hat `web/app`, `web/components`, `web/content`, `web/lib`, `next.config.ts` und
`package.json` geprüft, mit `design.md` und der Liste FB-01 bis FB-23 als bekanntem Stand. Er meldete einen neuen
Fund (og-Metadaten der Unterseiten). Dieser ist per `curl` auf allen drei Unterseiten verifiziert und steht als
BUG-11 im Bericht. Weitere Funde mit Konfidenz ≥ 80 meldete er nicht.

Eigene Nebenbeobachtungen, nicht als Fehler geführt:

- `next start` bindet ohne `-H` an alle Schnittstellen („Network: 192.168.178.43"). Das betrifft nur lokale
  Prüfläufe; der Mock-Test nutzt `-H 127.0.0.1`.
- Die Layout-Umschalter zeigen „Focus"/„Grid" per CSS `capitalize`, im Text stehen „focus"/„grid".

## Neue Tests

Alle unter `web/tests/`, ohne neue Abhängigkeit (`node:test`, globales `fetch`/`WebSocket`, `node:http`). Die
Ausführung steht jeweils als Kommentar oben in der Datei.

| Datei | Fälle | Deckt ab | Ausführen |
|---|---|---|---|
| `releases.unit.test.mjs` | 14 | AK-14, 16, 17, 18, 19, 28, 31, 32, 33, 39; EC-03, 04, 09, 13, 14, 15 | `node --test tests/releases.unit.test.mjs` (Node ≥ 23.6; Alias `@/` per `module.registerHooks`; Warnung `MODULE_TYPELESS_PACKAGE_JSON` ist harmlos) |
| `site.http.test.mjs` | 29 (davon 5 `todo`) | AK-01–07, 09–14, 18, 19, 21–30, 35–38, 40, 41; Angriff Eingaben; BUG-02, 03, 05, 09, 11 | Build ohne Token/Site-URL, `npx next start -p 3918`, dann `BASE_URL=http://127.0.0.1:3918 node --test tests/site.http.test.mjs` |
| `browser.cdp.test.mjs` | 8 | AK-05, 07, 08, 10, 23, 36, 37; EC-11 | wie oben, zusätzlich Chromium-Headless (`CHROME_BIN` oder Playwright-Cache, sonst übersprungen), `--mute-audio`; Screenshots mit `QA_SCREENSHOT_DIR=../features/B10-website/qa` |
| `download-upstream.test.mjs` | 9 (davon 2 `todo`) | AK-15, 18, 20, 31, 34, 37, 38, 39; EC-01, 04, 06, 07; Angriff PII/Rate Limit; BUG-04, 10 | `node --test --test-timeout=300000 tests/download-upstream.test.mjs` — baut eine Temp-Kopie gegen einen lokalen GitHub-Mock, ca. 11 s, räumt auf |
| `live.readonly.test.mjs` | 1 (`todo`) | FB-15 / BUG-01 | `node --test tests/live.readonly.test.mjs` (Internet, nur GET) |

Gesamtlauf mit laufendem Server auf 3918: `BASE_URL=http://127.0.0.1:3918 node --test --test-timeout=600000 tests/`

```
ℹ tests 61
ℹ pass 53
ℹ fail 0
ℹ todo 8
```

Die `todo`-Tests prüfen das Soll und schlagen heute erwartungsgemäß fehl (Äquivalent zu `XCTExpectFailure`). Sie
halten die Suite grün. Die Reparatur entfernt die Markierung.

Screenshots unter `features/B10-website/qa/`:

- `AK-05-kopfzeile-379px.png`
- `AK-07-skip-link.png`
- `AK-08-dunkel.png`
- `AK-10-multiview-raster.png`
- `AK-23-faq-offen.png`
- `AK-30-opengraph-image.png`

## Nächster Schritt

`/sdd-build B10` mit dem Auftrag, BUG-01 bis BUG-11 zu beheben. Priorität haben BUG-01 bis BUG-03 (hoch), danach
BUG-04, BUG-05 und BUG-08. Anschließend `/sdd-qa B10` (Durchlauf 2). **Die Erfassung pausiert**, bis die hohen
Befunde behoben und erneut geprüft sind.

Hinweise für die Reparatur:

- BUG-01 ist eine Vercel-Einstellung und keine Codeänderung.
- BUG-02 hängt teilweise an B01 (Keychain, Cache, Store-Name).
- BUG-06 und BUG-08 hängen an B09 (Notarisierung, neues Release).
- BUG-07 hängt an B02, B07 und B09.
- Für BUG-01 und BUG-03 sind Angaben des Nutzers nötig (OF-04, Verantwortlicher).

## Für befunde.md

| Befund | Grad | Fundstelle | BUG-Nr. |
|---|---|---|---|
| Website öffentlich nicht erreichbar (`DEPLOYMENT_NOT_FOUND`, Vercel-Login mit Cookie, Domain NXDOMAIN); einzige Datenschutzerklärung nicht abrufbar | hoch | Vercel-Projekt (Deployment Protection, Domains); Repository-Homepage | BUG-01 |
| Datenschutzerklärung widerspricht dem App-Verhalten (Speicherort, Kopien, Löschen der App, Empfänger, „Nowhere") | hoch | `web/app/privacy/page.tsx:19-20,37-39,47-49`; `web/app/page.tsx:64-72`; `web/content/faq.ts:40` | BUG-02 |
| Pflichtangaben fehlen: Verantwortlicher, Rechtsgrundlagen, Speicherdauer, Betroffenenrechte, nicht öffentlicher Kontaktweg; kein `docs/datenschutz.md`, kein AV-Vertrag dokumentiert | hoch | `web/app/privacy/page.tsx`; `web/components/site-footer.tsx` | BUG-03 |
| `/download` ohne Cache im Fehlerfall und ohne Limit (64 Aufrufe → 64 GitHub-Anfragen) | mittel | `web/app/download/route.ts:5-9`; `web/lib/releases.ts:73-90` | BUG-04 |
| `next` 16.2.12 mit kritischer Advisory GHSA-2xp9-vwfh-vxw4 u. a.; Angriffsfläche heute nur lokale Quellen | mittel | `web/package.json:15` | BUG-05 |
| Gatekeeper-Anleitung beschreibt laut Apple ab macOS 15 entfallenen Weg; keine Prüfsumme für den Erstdownload | mittel | `web/app/support/page.tsx:35-44`; `web/components/gatekeeper-note.tsx:9-13`; `web/content/faq.ts:10` | BUG-06 |
| Werbeaussagen, die das Release v1.1 nicht erfüllt (PiP/Taste P, Doppelklick-Import, Sparkle liest Changelog, Selbstinstallation, App-Name, „open-source" ohne Lizenz, Sprache) | mittel | `web/content/features.ts:13-48`; `web/app/support/page.tsx:18,41-43`; `web/app/changelog/page.tsx:21`; `web/components/site-footer.tsx:14` | BUG-07 |
| Ersatz-Release fest auf v1.1 (mit `get-task-allow`, altem Feed) verdrahtet, vom Release-Skript nicht gepflegt | mittel | `web/lib/releases.ts:46-60,126`; `scripts/release.sh` | BUG-08 |
| Keine Content-Security-Policy und keine Permissions-Policy | niedrig | `web/next.config.ts:5-19` | BUG-09 |
| `node="[object Object]"` an `h3`/`a` in gerenderten Release-Notizen | niedrig | `web/components/release-notes.tsx:14-18` | BUG-10 |
| Open-Graph-`url`/`title`/`description` der Unterseiten zeigen auf die Startseite | niedrig | `web/app/layout.tsx:52-59` | BUG-11 |

**Muster über Features hinweg:**

- Die Datenschutzaussagen der Website widersprechen den Ist-Befunden aus B01 (Klartext, Cache, Speicherort) und B09
  (Update-Weg, BUG-12/BUG-16).
- Der Download-Weg der Website liefert das in B09 als kritisch bewertete Release v1.1 aus. Behebung dort (neues
  Release) und hier (BUG-08) gehören zusammen.
