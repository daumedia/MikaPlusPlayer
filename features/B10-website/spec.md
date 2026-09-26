# B10 · Website — Spezifikation

Status: `rekonstruiert` · Stand: 2026-09-15 · Rekonstruktion aus dem Code (sdd-erfassen)

> **Rekonstruiert, nicht geplant.** Beschrieben ist, was `web/` @ `c01f1cf` tut — nicht, was es tun sollte.
> Grundlage: Lesen aller Dateien unter `web/` (ohne `node_modules`, `.next`), Abgleich jeder Aussage über die
> App mit `Sources/`, `project.yml`, `Info.plist`, dem Tag `v1.1` und dem Release-DMG `dist/MikaPlusPlayer-v1.1.dmg`.
> **Ausgeführt am 2026-09-15:** `npm run build` und `next start -p 3917` (GitHub erreichbar, ohne `GITHUB_TOKEN`,
> ohne `NEXT_PUBLIC_SITE_URL`), alle Routen per `curl`; Fallback-Pfade in einer Kopie im Scratchpad nachgestellt
> (`GITHUB_TOKEN=invalid`, GitHub per totem Proxy unerreichbar, Server auf Port 3918); Markdown-Rendering mit
> einem Nachbau der Konfiguration aus `components/release-notes.tsx` gegen `react-markdown` 10.1.0 geprüft;
> `npm audit --omit=dev`; lesende Abfrage der Vercel-URLs aus den GitHub-Deployments. Kein Deployment.

## Zweck

Die Website stellt die macOS-App vor, leitet über einen stabilen Link zum DMG des aktuellen GitHub-Releases,
zeigt Changelog, Einrichtungshilfe und FAQ und trägt die **einzige Datenschutzerklärung** zu App und Website.
Sie ist nur Englisch, läuft auf Next.js 16 (App Router) und ist für Vercel gebaut.

## Abhängigkeiten

| Braucht | Status | Warum |
|---|---|---|
| B09 Auto-Update | bestand | Download-Link und Changelog lesen die GitHub-Releases, die `scripts/release.sh` vorbereitet; Seite beschreibt Sparkle und EdDSA |
| B01–B08 | bestand | Seite macht Aussagen über deren Verhalten (Import, Senderliste, Favoriten, Wiedergabe, Bild-in-Bild, Multiview) — Abgleich unten |
| GitHub REST API | extern | `releases/latest` und `releases?per_page=20` von `daumedia/MikaPlusPlayer` |
| Google Fonts | extern, nur beim Build | `next/font/google` lädt Archivo, IBM Plex Sans und IBM Plex Mono beim Build herunter |

## User Stories

- **US-01** · Als Mac-Nutzer mit eigenem IPTV-Abo möchte ich sehen, was die App kann und was sie braucht, damit ich entscheide, ob ich sie lade.
- **US-02** · Als Besucher möchte ich mit einem Klick die aktuelle Version laden, ohne eine Versionsnummer zu suchen.
- **US-03** · Als Nutzer möchte ich wissen, wie ich die App trotz Gatekeeper-Warnung zum ersten Mal starte.
- **US-04** · Als Nutzer möchte ich nachlesen, wie ich eine Playlist hinzufüge, welche Tasten es gibt und was bei typischen Fehlern hilft.
- **US-05** · Als Nutzer möchte ich sehen, was sich je Version geändert hat.
- **US-06** · Als datenschutzbewusster Nutzer möchte ich wissen, was App und Website speichern und wohin sie verbinden.
- **US-07** · Als Portfolio-Betrachter möchte ich den Quellcode finden.

## Nicht im Scope

- Das Verhalten der App selbst → B01–B09. Die Website beschreibt es nur; Abweichungen stehen unter *Fehlbestand*.
- `appcast.xml`, Sparkle-Feed, Release-Skripte → B09.
- Formulare, Konten, Newsletter, Kontaktformular, Analytics — im Code nicht vorhanden. Support läuft über GitHub Issues.
- Lokalisierung — die Website ist nur Englisch.
- Vercel-Projekteinstellungen (Domain, Deployment Protection, Log-Aufbewahrung, Node-Version) — nicht im Repository; der beobachtete Live-Zustand steht als Befund unter *Fehlbestand*.

## Akzeptanzkriterien

Jedes Kriterium ist ohne Codekenntnis prüfbar. **Prüfumgebung, wenn nicht anders angegeben:**
`cd web && npm run build && npx next start -p <port>`, ohne `GITHUB_TOKEN` und ohne `NEXT_PUBLIC_SITE_URL`,
GitHub erreichbar. „Aktuelles Release" = Antwort von `GET /repos/daumedia/MikaPlusPlayer/releases/latest`
(am 2026-09-15: `v1.1`, einziges Release, DMG-Asset 36 455 860 Bytes, Content-Type `application/x-apple-diskimage`).

### Build und Auslieferung

- **AK-01** · Angenommen die Abhängigkeiten sind installiert und GitHub sowie Google Fonts sind erreichbar, wenn
  `npm run build` läuft, dann endet der Build erfolgreich, und die Routenübersicht führt `/` und `/changelog` als
  statisch mit *Revalidate* `1h` und *Expire* `1y`, `/privacy`, `/support`, `/robots.txt`, `/sitemap.xml`,
  `/opengraph-image`, `/icon.png`, `/apple-icon.png` und `/_not-found` als statisch ohne Revalidierung und
  `/download` als dynamisch (`ƒ`).
- **AK-02** · Angenommen der Produktionsserver läuft, wenn eine beliebige Route abgerufen wird (geprüft: `/`,
  `/download`, `/opengraph-image`), dann enthält die Antwort `X-Content-Type-Options: nosniff`,
  `Referrer-Policy: strict-origin-when-cross-origin`, `X-Frame-Options: DENY` und
  `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload`, aber keinen `X-Powered-By`-Header.
- **AK-03** · Angenommen der Produktionsserver läuft, wenn `/` oder `/changelog` abgerufen werden, dann lautet
  `Cache-Control` `s-maxage=3600, stale-while-revalidate=31532400`; bei `/privacy` und `/support` lautet er
  `s-maxage=31536000`.
- **AK-04** · Angenommen der Produktionsserver läuft, wenn eine unbekannte Route wie `/does-not-exist` oder `/.env`
  abgerufen wird, dann antwortet er mit Status 404 und einer HTML-Seite mit Kopf- und Fußzeile; `/download/` mit
  Schrägstrich antwortet mit 308 auf `/download`.

### Kopf- und Fußzeile (alle Seiten)

- **AK-05** · Angenommen eine beliebige Seite ist geöffnet, wenn man die Kopfzeile betrachtet, dann bleibt sie beim
  Scrollen oben stehen und zeigt App-Symbol und Wortmarke „Mika+Player" (Link auf `/`) sowie die Links „Support",
  „Changelog", „Privacy" und „GitHub"; „GitHub" öffnet in einem neuen Tab. Unter 640 px Breite fehlt „Privacy" in der
  Kopfzeile, unter 380 px wird die Wortmarke durch einen nur für Screenreader sichtbaren Text ersetzt.
- **AK-06** · Angenommen eine beliebige Seite ist geöffnet, wenn man die Fußzeile betrachtet, dann steht dort
  „An open-source IPTV player. It plays the playlist you bring and is not affiliated with any provider." mit den Links
  „Support", „Changelog", „Privacy", „Report an issue" (GitHub Issues, neuer Tab) und „Source" (GitHub, neuer Tab) —
  ohne Namen, Anschrift oder Kontakt eines Anbieters.
- **AK-07** · Angenommen eine Seite ist mit der Tastatur geöffnet, wenn der erste Tabulatorschritt erfolgt, dann
  erscheint oben links „Skip to content", und Enter springt zum Hauptinhalt. Das Dokument trägt `lang="en"`.
- **AK-08** · Angenommen das Betriebssystem steht auf hell bzw. dunkel, wenn eine Seite geladen wird, dann folgt die
  Farbgebung diesem Modus (Hintergrund `#f6f4f3` bzw. `#120f10`); einen Umschalter auf der Seite gibt es nicht.

### Startseite `/`

- **AK-09** · Angenommen das aktuelle Release hat ein DMG-Asset, wenn `/` geladen wird, dann zeigt der Kopfbereich
  „Mika+Player · IPTV for macOS", die Überschrift „Four streams. One window.", eine Schaltfläche
  „Download for macOS", deren Link direkt auf die Download-URL des DMG bei `github.com` zeigt, darunter
  „Version 1.1 · 34.8 MB · macOS 14 Sonoma or later" und daneben den Hinweis „First launch" mit der Anweisung
  „right-click Mika+Player and choose Open".
- **AK-10** · Angenommen `/` ist geladen, wenn im oberen Multiview-Nachbau auf eine der kleinen Kacheln geklickt wird,
  dann wird dieser Kanal groß dargestellt und trägt das Abzeichen „Sound", die bisher große Kachel wird klein. Im
  zweiten Nachbau (Abschnitt „Multiview · macOS") gibt es zusätzlich die Umschalter „focus" und „grid"; „grid" zeigt
  vier gleich große Kacheln, ein Klick setzt dort Rahmen und „Sound"-Abzeichen auf die angeklickte Kachel. Es wird
  kein Video und keine externe Ressource geladen.
- **AK-11** · Angenommen `/` ist geladen, wenn man nach unten scrollt, dann folgen in dieser Reihenfolge: die drei
  Spalten „You bring", „The app adds", „It never does"; „Getting started" mit den Schritten CH 01 „Add a playlist",
  CH 02 „Find your channels", CH 03 „Watch"; ein Senderlisten-Nachbau mit „Seventeen thousand channels, still
  usable"; „What it does" mit acht Funktionen in den Gruppen Library (3), Playback (3) und System (2); der Abschnitt
  „Up to four streams, in a window of their own"; „What it needs" mit den Karten „macOS 14 Sonoma or later"
  (inkl. „Universal build for Apple silicon and Intel"), „A playlist of your own" und „iPhone and iPad", einer zweiten
  Download-Schaltfläche und Links auf GitHub und `/support`.
- **AK-12** · Angenommen `content/screenshots.ts` ist leer (Ist-Stand), wenn `/` geladen wird, dann erscheint kein
  Abschnitt „The app itself".
- **AK-13** · Angenommen `/` ist geladen, wenn man den HTML-Kopf liest, dann lauten Titel
  „Mika+Player — IPTV player for macOS", `robots` „index, follow", `og:image` verweist auf `/opengraph-image`
  (1200 × 630), `twitter:card` ist `summary_large_image`, und `canonical` sowie `og:url` zeigen auf die Site-URL
  aus AK-28.

### Download `/download`

- **AK-14** · Angenommen das aktuelle Release hat ein DMG-Asset, wenn `GET /download` aufgerufen wird, dann antwortet
  der Server mit 302 und `Location` auf dessen Download-URL (am 2026-09-15
  `https://github.com/daumedia/MikaPlusPlayer/releases/download/v1.1/MikaPlusPlayer-v1.1.dmg`). Query-Parameter wie
  `?url=https://evil.example` ändern das Ziel nicht; `HEAD` liefert ebenfalls 302, `POST` liefert 405.
- **AK-15** · Angenommen GitHub hat die Release-Abfrage zuletzt mit Status 200 beantwortet, wenn `/download` innerhalb
  der folgenden Stunde mehrfach aufgerufen wird, dann stellt der Server dafür keine neue Anfrage an die GitHub-API
  (Nachweis: `x-ratelimit-remaining` für die eigene IP vor und nach sechs Aufrufen unverändert).
- **AK-16** · Angenommen das neueste Release hat noch kein DMG-Asset, wenn `/` geladen oder `/download` aufgerufen
  wird, dann zeigen Schaltfläche und Weiterleitung auf das DMG von `v1.1`, während die Beschriftung Versionsnummer
  des neuen Releases und Größe des v1.1-DMG zeigt (siehe OF-01).
- **AK-17** · Angenommen ein Release hat mehrere Assets, wenn das DMG bestimmt wird, dann gilt das erste Asset mit
  Content-Type `application/x-apple-diskimage`, ersatzweise das erste, dessen Name auf `.dmg` endet (ohne
  Beachtung der Groß-/Kleinschreibung).

### Changelog `/changelog`

- **AK-18** · Angenommen GitHub antwortet, wenn `/changelog` geladen wird, dann stehen unter „Every version so far"
  und dem Satz „Pulled from GitHub releases. The Mac app also checks this list for itself through Sparkle." bis zu
  20 Releases in der Reihenfolge der API — Entwürfe ausgenommen, **Vorabversionen eingeschlossen** (OF-02). Jeder
  Eintrag zeigt Titel (Release-Name, ersatzweise Tag), Datum auf Englisch in UTC („June 23, 2026"), die Notizen,
  sofern vorhanden einen Link „Download <Dateiname> (<Größe> MB)" und einen Link „Release on GitHub" (neuer Tab).
  Am Ende verweist „releases page" auf die GitHub-Releases.
- **AK-19** · Angenommen für den Tag eines Releases gibt es einen englischen Ersatztext in
  `content/changelog-overrides.ts` (Ist-Stand: nur `v1.1`), wenn `/changelog` geladen wird, dann erscheint dieser
  Text statt des deutschen GitHub-Textes (beginnt mit „Multiview (macOS) — watch up to four streams at once");
  ohne Ersatztext erscheint der GitHub-Text als Markdown mit GFM (Tabellen, automatische Links); ein leerer Text
  erzeugt keinen Notizblock.
- **AK-20** · Angenommen ein GitHub-Release-Text enthält Markdown und HTML, wenn er auf `/changelog` gerendert wird,
  dann erscheint rohes HTML (`<script>`, `<img onerror>`, `<iframe>`, `<a href="javascript:…">`) als sichtbarer,
  maskierter Text und wird nicht ausgeführt; Markdown-Links mit `javascript:`, `vbscript:` oder `data:` erhalten ein
  leeres `href`; `http(s)`-Links und GFM-Autolinks werden als Links mit `target="_blank"` und
  `rel="noopener noreferrer"` gerendert; Bilder (auch per Referenz) und Trennlinien entfallen; Überschriften der
  Ebenen 1 und 2 werden als `h3` ausgegeben.
- **AK-21** · Angenommen `/changelog` ist geladen, wenn man die vom Browser geladenen JavaScript-Dateien durchsucht,
  dann enthalten sie weder `react-markdown` noch `remark`/`micromark` — die Notizen sind fertig gerendertes HTML.

### Support `/support`

- **AK-22** · Angenommen `/support` ist geladen, wenn man die Seite liest, dann folgen „First launch on macOS" mit
  vier nummerierten Schritten (DMG öffnen und nach Applications ziehen · Applications öffnen · Rechtsklick auf
  Mika+Player → Open · im Dialog bestätigen), „Adding a playlist" mit denselben drei Schritten wie auf `/` und dem
  Beispiel-Link `https://iptv-org.github.io/iptv/index.m3u` (neuer Tab), „Keyboard controls" mit genau sechs Zeilen
  (Space · ↑ ↓ + − · M · F · P · Esc) und „Questions" mit neun Fragen.
- **AK-23** · Angenommen `/support` ist geladen, wenn auf eine Frage unter „Questions" geklickt wird, dann klappt die
  Antwort auf und das Plus-Symbol dreht sich; anfangs sind alle Antworten zugeklappt. Das funktioniert auch ohne
  JavaScript (`<details>`).

### Datenschutz `/privacy`

- **AK-24** · Angenommen `/privacy` ist geladen, wenn man die Seite liest, dann stehen dort die Abschnitte
  „What the app stores", „What the app connects to" (Punkte „Your provider.", „Channel logo servers.", „GitHub."),
  „Xtream logins travel over plain HTTP", „This website", „Content", darunter „Last updated 30 July 2026" und der
  Verweis, Fragen in „a GitHub issue" zu stellen. Die Aussagen, die der Code nicht erfüllt, sind unter
  *Fehlbestand* wörtlich zitiert (FB-03, FB-04, FB-05, FB-17).
- **AK-25** · Angenommen `/privacy` ist geladen, wenn man den Abschnitt „Xtream logins travel over plain HTTP" liest,
  dann steht dort, dass die App ein eingegebenes `https://` auf `http://` umschreibt und Benutzername und Passwort
  unverschlüsselt überträgt — das entspricht dem Verhalten der App.
- **AK-26** · Angenommen `/privacy` ist geladen, wenn man „This website" liest, dann steht dort „No cookies, no
  analytics, no tracking scripts, no fonts loaded from third parties", Hosting bei Vercel mit „standard server logs"
  und dass GitHub Downloads je Release zählt — die ersten vier Punkte erfüllt der Code (AK-35, AK-36); zur Live-Umgebung siehe FB-15.

### Metadaten-Routen

- **AK-27** · Angenommen der Produktionsserver läuft, wenn `/robots.txt` abgerufen wird, dann lautet der Inhalt
  `User-Agent: *`, `Allow: /`, `Disallow: /download` und `Sitemap: <Site-URL>/sitemap.xml`.
- **AK-28** · Angenommen weder `NEXT_PUBLIC_SITE_URL` noch `VERCEL_PROJECT_PRODUCTION_URL` ist beim Build gesetzt,
  wenn `canonical`, `og:url`, `sitemap.xml` oder `robots.txt` gelesen werden, dann zeigen sie auf
  `http://localhost:3000` — unabhängig vom tatsächlichen Port. Ist `NEXT_PUBLIC_SITE_URL` gesetzt, gilt dieser Wert,
  sonst `https://<VERCEL_PROJECT_PRODUCTION_URL>`; ein abschließender Schrägstrich wird entfernt.
- **AK-29** · Angenommen der Produktionsserver läuft, wenn `/sitemap.xml` abgerufen wird, dann enthält sie genau vier
  Adressen — `/` (Priorität 1, monthly), `/support` (0.8, monthly), `/changelog` (0.6, weekly), `/privacy` (0.3,
  yearly) — jeweils mit `lastmod` = Zeitpunkt des Builds; `/download` fehlt.
- **AK-30** · Angenommen der Produktionsserver läuft, wenn `/opengraph-image` abgerufen wird, dann ist die Antwort ein
  PNG mit 1200 × 630 Pixeln (dunkler Hintergrund, App-Symbol, „MIKA+PLAYER", „IPTV player for macOS",
  „Four streams. One window.", vier Farbbalken); `/icon.png` und `/apple-icon.png` liefern PNG-Dateien.

### GitHub-Anbindung und Fallback

- **AK-31** · Angenommen `GITHUB_TOKEN` ist nicht gesetzt, wenn die Seite Release-Daten abruft, dann fragt der Server
  die GitHub-API ohne Authentifizierung ab (Limit 60 Anfragen je Stunde je IP); ist ein Token gesetzt, sendet er ihn
  als `Authorization: Bearer …` nur in dieser serverseitigen Anfrage.
- **AK-32** · Angenommen `GITHUB_TOKEN=invalid`, wenn `npm run build` läuft, dann protokolliert der Build
  `[releases] /repos/daumedia/MikaPlusPlayer/releases?per_page=20 -> 401; rate limit remaining: null` und dieselbe
  Zeile für `/releases/latest`, endet trotzdem erfolgreich, und `/` sowie `/changelog` zeigen das eingebaute
  Ersatz-Release: Titel „v1.1 – Multiview", Datum „June 23, 2026", englischer v1.1-Text, DMG `v1.1` mit 34.8 MB.
- **AK-33** · Angenommen GitHub ist beim Build nicht erreichbar, wenn `npm run build` läuft, dann protokolliert der
  Build `[releases] request failed: … [TypeError: fetch failed]` für beide Abfragen, endet erfolgreich und liefert
  dieselben Ersatzinhalte wie in AK-32.
- **AK-34** ⚠ · Angenommen GitHub ist zur Laufzeit nicht erreichbar oder antwortet nicht mit Status 200, wenn
  `/download` aufgerufen wird, dann leitet der Server mit 302 auf das DMG von `v1.1` weiter **und stellt bei jedem
  einzelnen Aufruf erneut eine Anfrage an GitHub**, die er als Warnung protokolliert (Nachweis: vier Aufrufe, vier
  Protokollzeilen) — ohne eigenes Limit.
  *(So verhält sich der Code heute: Next.js legt nur Antworten mit Status 200 im Daten-Cache ab, eine eigene Drosselung
  gibt es nicht. Als Kriterium aufgenommen, damit die QA es reproduziert; als Fehler eingestuft → FB-21.)*

### Datenschutz und Missbrauchsschutz

Katalog `~/.claude/sdd/sicherheit.md`, **Stufe B, voller Katalog**. Zuordnung:

| Katalog | Trifft zu? | Kriterien / Befunde |
|---|---|---|
| 1 · Personenbezogene Daten | ja: IP-Adresse, User-Agent und Referer der Besucher in den Server-Logs von Vercel und beim Klick auf den Download bei GitHub. Keine Formulare, keine Freitexte, keine besonderen Kategorien. Speicherdauer der Vercel-Logs im Repository nicht festgelegt | AK-35, AK-36, AK-37, AK-39, FB-17 |
| 2 · Weitergabe an externe Dienste | ja: Vercel (Hosting, Logs), GitHub (Download durch den Browser des Besuchers; serverseitige API-Abfrage **ohne** Besucherdaten), Google Fonts nur beim Build **ohne** Besucherdaten. Kein AV-Vertrag dokumentiert, `docs/datenschutz.md` fehlt | AK-35, AK-36, AK-37, FB-17 |
| 3 · Zugriff | trifft nicht zu, weil die Website keine nutzerbezogenen Datensätze, keine Anmeldung und keine Rollen hat — alle Inhalte sind öffentlich. Geprüft wird stattdessen, dass keine Parameter ausgewertet werden (kein offener Redirect, kein offener Bild-Proxy) | AK-14, AK-40, AK-41 |
| 4 · Missbrauch und Kosten | ja: `/download` ruft je Aufruf eine Server-Funktion auf; Fehlerfall ohne Cache; kein eigenes Limit. Keine Uploads, keine kostenpflichtigen APIs | AK-15, AK-34, AK-41, FB-20, FB-21, FB-22 |
| 5 · Löschen und Auskunft | trifft auf gespeicherte Kontodaten nicht zu, weil die Website nichts speichert; für Vercel-Logs gibt es keinen dokumentierten Auskunfts- oder Löschweg, Anfragen nur über öffentliche GitHub Issues | FB-17, FB-18 |
| 6 · Geheimnisse | ja: optional `GITHUB_TOKEN` | AK-31, AK-38 |

- **AK-35** · Angenommen der Produktionsserver läuft, wenn `/`, `/changelog`, `/privacy`, `/support`, `/download`,
  `/robots.txt`, `/sitemap.xml`, `/opengraph-image` und eine unbekannte Route abgerufen werden, dann enthält keine
  Antwort einen `Set-Cookie`-Header.
- **AK-36** · Angenommen `/`, `/changelog`, `/privacy` oder `/support` ist im Browser geöffnet, wenn die Seite geladen
  ist, dann stammen alle geladenen Skripte, Stylesheets, Schriften und Bilder vom eigenen Ursprung (Schriften unter
  `/_next/static/media/…woff2`, Symbol über `/_next/image`); es gibt keine Anfrage an `fonts.googleapis.com`,
  `fonts.gstatic.com`, an Analytics-, Tracking- oder Vercel-Insights-Dienste. Externe Hosts (github.com,
  iptv-org.github.io) werden nur über angeklickte Links erreicht.
- **AK-37** · Angenommen ein Besucher klickt „Download for macOS", wenn der Browser der Verbindung folgt, dann lädt er
  das DMG direkt von `github.com`; die Website selbst reicht keine Besucherdaten weiter, der `Referer` enthält wegen
  der Referrer-Policy nur den Ursprung der Website.
- **AK-38** · Angenommen die Seite wurde gebaut, wenn man die an den Browser ausgelieferten Dateien unter
  `.next/static` nach `GITHUB_TOKEN`, `api.github.com` und `x-ratelimit` durchsucht, dann gibt es keinen Treffer; der
  Token-Name kommt nur in serverseitigen Dateien vor, ist keine `NEXT_PUBLIC_`-Variable, `.env*` ist per `.gitignore`
  ausgeschlossen, und die Git-Historie von `web/` enthält kein Token.
- **AK-39** · Angenommen eine GitHub-Abfrage schlägt fehl, wenn der Server eine Warnung protokolliert, dann enthält
  sie nur API-Pfad, HTTP-Status und `x-ratelimit-remaining` bzw. das Fehlerobjekt — keine Besucherdaten und kein
  Token.
- **AK-40** · Angenommen der Produktionsserver läuft, wenn `/_next/image?url=https://evil.example/x.png&w=64&q=75`
  abgerufen wird, dann antwortet er mit 400; `/_next/image?url=%2Ficon-512.png&w=64&q=75` liefert ein PNG.
- **AK-41** · Angenommen ein Besucher ruft eine beliebige Seite auf, wenn er mit ihr interagiert, dann gibt es kein
  Eingabefeld, kein Formular, keinen Upload und keine Anmeldung; keine Route verarbeitet Besuchereingaben
  serverseitig.

## Abgleich der Website-Aussagen mit dem App-Code

Jede Aussage der Website über die App, mit Beleg. „stimmt" ist durch Code oder Artefakt belegt; alles andere
verweist auf *Fehlbestand*.

| # | Aussage der Website (Fundstelle) | Beleg im App-Code / Artefakt | Ergebnis |
|---|---|---|---|
| 1 | Drei Wege: Xtream, M3U-Link, Datei; Name optional (`content/features.ts:48`, `content/setup-steps.ts:12`) | `ImportPlaylistView.swift:11-18,50` — Tabs „Xtream", „URL", „Datei", Standard Xtream, „Name (optional)" | stimmt; Beschriftungen deutsch → FB-14 |
| 2 | „registers as a handler for .m3u files, so double-clicking one opens it here" (`content/features.ts:48`) | `Info.plist:68-82` registriert den Dokumenttyp; in `Sources/` kein `onOpenURL`, `handlesExternalEvents` oder App-Delegate | **FB-01** |
| 3 | Senderliste über `player_api.php`, MPEG-TS als Standard (`content/features.ts:23`, `content/faq.ts:25`) | `XtreamClient.swift:35,42,65`; `ImportPlaylistView.swift:31` | stimmt |
| 4 | „switch the format to .m3u8 when you log in" (`content/faq.ts:25`) | `XtreamCodes.swift:15` Beschriftung „HLS (.m3u8)" | stimmt |
| 5 | `.ts`, `.mpegts`, `.mts`, `.m2ts` gehen automatisch an VLC, AVKit für HLS und den Rest (`content/faq.ts:30`, `content/features.ts:28`) | `PlaybackEngine.swift:15-17,99-108`; VLCKitSPM an beiden Targets (`project.yml:58-60,75-77`) | stimmt; zusätzlich `.m3u` → AVKit |
| 6 | Suche und Gruppenfilter „run in the database, not in memory", Liste reagiert sofort (`content/features.ts:13`, `app/page.tsx:108-110`, `content/faq.ts:35`) | Filter per `@Query` in der DB (`ChannelListView.swift:88-97`), aber Gruppenliste im Speicher (`ChannelListView.swift:70-80`), kein Index (DM-05) | teilweise → **FB-06** |
| 7 | Favoriten über alle Playlists; beim Refresh „matches favourites by their tvg-id" (`content/features.ts:18`) | `FavoritesView.swift:8-12`; Schlüssel `tvg-id`, sonst kleingeschriebener Name (`Channel.swift:48-51`), nicht eindeutig (DM-06) | teilweise → **FB-07** |
| 8 | Bild-in-Bild; auf iPhone/iPad Autostart; Taste P (`content/features.ts:30-34,38`, `app/support/page.tsx:18`) | Nicht in `v1.1` (`git show v1.1:Sources/Views/PlayerView.swift` hat keinen Fall `"p"`); auf `main` nur AVKit-Engine (`PlaybackEngine.swift:86`, `PlayerView.swift:114`), Standardformat TS → VLC ohne PiP; iOS nicht verteilt | **FB-02** |
| 9 | Tasten Space, ↑/↓, +/−, M, F, Esc; 5-%-Schritte (`app/support/page.tsx:13-20`) | `PlayerView.swift:30,293-321` | stimmt; zusätzlich `=`; Esc nur im Vollbild |
| 10 | „On-screen feedback confirms each one" (`content/features.ts:38`) | HUD nur für Play/Pause, Stumm, Lautstärke (`PlayerView.swift:323-346`); F, P, Esc ohne HUD | teilweise → **FB-08** |
| 11 | Multiview: bis 4 Streams, Fokus/Raster, Ton nur beim Fokus, Klick verschiebt Ton und großes Bild, ⊞ in Senderliste und Favoriten, nur macOS (`app/page.tsx:150-158`, `content/changelog-overrides.ts:7-12`) | `MultiviewSession.swift:34,53-64,94-98`, `MultiviewScreen.swift:39-93`, `MultiviewTile.swift:26,29`, `ChannelRowView.swift:27-29,73-85`, `FavoritesView.swift:25` | stimmt |
| 12 | „Updates that install themselves", „can install them on its own", EdDSA, Prüfung aus dem App-Menü (`content/features.ts:42-43`, `content/faq.ts:50`) | `Info.plist:27-32` (`SUEnableAutomaticChecks`, `SUPublicEDKey`, kein `SUAutomaticallyUpdate`); Menü „Nach Updates suchen …" (`MikaPlusPlayerApp.swift:35-40`) | Prüfung und EdDSA stimmen; Selbstinstallation teilweise → **FB-09** |
| 13 | „The Mac app also checks this list for itself through Sparkle" (`app/changelog/page.tsx:21`) | Sparkle liest `appcast.xml` (`Info.plist:28`), nicht die GitHub-Releases; `v1.1` liest den alten `Mukaarts`-Pfad | **FB-10** |
| 14 | „macOS 14 Sonoma or later" (`lib/site.ts:10`) | `project.yml:7,66`; `appcast.xml` `minimumSystemVersion 14.0`; DMG `LSMinimumSystemVersion 14.0` | stimmt |
| 15 | „Universal build for Apple silicon and Intel", DMG statt App Store (`app/page.tsx:173-175`) | `lipo -info` am Binary aus `dist/MikaPlusPlayer-v1.1.dmg` (36 455 860 Bytes = Release-Asset): `x86_64 arm64`; `scripts/make-dmg.sh` | stimmt |
| 16 | „signed ad-hoc rather than notarised" (`app/support/page.tsx:36`, `content/faq.ts:10`, `components/gatekeeper-note.tsx:10`) | `project.yml:70-71`; `codesign -dv` am DMG-Inhalt: `Signature=adhoc`; `spctl --assess`: `rejected` | stimmt |
| 17 | Erststart per „Right-click → Open", danach normal (`app/support/page.tsx:40-44`, `components/gatekeeper-note.tsx:10-13`, `content/faq.ts:10`, `content/changelog-overrides.ts:16`) | Plattformverhalten, kein App-Code | **FB-11** |
| 18 | „drag Mika+Player to Applications", „Right-click Mika+Player" (`app/support/page.tsx:41-43`) | Bundle heißt `MikaPlusPlayer.app`; `v1.1` hat `CFBundleName` `MikaPlusPlayer` | **FB-12** |
| 19 | iOS: „builds for iOS 17", keine verteilte Version (`app/page.tsx:188-189`, `content/faq.ts:45`) | `project.yml:6,48-60`; kein iOS-Release | stimmt laut Konfiguration; iOS-Build weist die QA nach |
| 20 | „all on your Mac, all local", „It never does … send your data anywhere", FAQ „Where does my data go? Nowhere.", „nothing goes to us" (`app/page.tsx:64-72`, `content/faq.ts:40`, `app/privacy/page.tsx:19`) | Zugangsdaten gehen im Klartext per HTTP an den Anbieter (`XtreamCodes.swift:69-74`), Logos von beliebigen Hosts (`ChannelRowView.swift:36`) | **FB-03** |
| 21 | „They stay in the app's own storage", „deleting the app removes all of it" (`app/privacy/page.tsx:37-39`) | macOS ohne Sandbox (`MikaPlusPlayer.entitlements:7-8`) + unbenannte `ModelConfiguration` (`MikaPlusPlayerApp.swift:8-9`) → `~/Library/Application Support/default.store` | **FB-04** |
| 22 | „Every stream, channel list and logo request goes to the host you entered" (`app/privacy/page.tsx:47-49`) | M3U-Playlists verweisen auf beliebige Stream- und Logo-Hosts (`M3UParser.swift:48-56`) | **FB-05** |
| 23 | GitHub: Feed von `raw.githubusercontent.com`, Download von `github.com` (`app/privacy/page.tsx:57-59`) | `Info.plist:28`; `appcast.xml` Enclosure auf `github.com` | stimmt |
| 24 | Formate M3U/M3U8 per URL oder Datei; liest `tvg-id`, `tvg-logo`, `group-title`; Kommas in Anführungszeichen (`content/faq.ts:20`) | `M3UParser.swift:79-119`, zusätzlich `#EXTGRP` (`:38-42`) | stimmt |
| 25 | „Importing a list that size takes a few seconds; browsing it afterwards does not" (`content/faq.ts:35`) | nicht aus Code ablesbar | unbelegt — Messung durch die QA |
| 26 | „no account and no analytics", „two playback engines", „no engine to pick" (`app/page.tsx:64,72,82`) | kein Analytics-SDK in `Sources/`; Engine-Wahl automatisch | stimmt |
| 27 | „An open-source IPTV player" (`components/site-footer.tsx:14`) | keine `LICENSE`; GitHub-API `license: null` | **FB-13** |
| 28 | Website komplett Englisch, Nachbauten mit englischen Beschriftungen („All", „Search channels", „focus/grid", „Sound") | App-Oberfläche nur Deutsch („Alle", „Sender suchen", „Fokus/Raster") | **FB-14** |

## Edge Cases

- **EC-01** · GitHub-Rate-Limit ohne Token auf Vercel erschöpft (geteilte Ausgangs-IPs) → jede Abfrage liefert 403,
  Seiten und `/download` fallen auf `v1.1` zurück; da Fehler nicht gecacht werden, versucht jeder `/download`-Aufruf
  es erneut (aus dem Code und AK-34 abgeleitet; die Vercel-Umgebung wurde nicht beobachtet).
- **EC-02** · GitHub fällt genau bei der stündlichen Neuberechnung von `/` oder `/changelog` aus → die Seite wird ohne
  Fehler mit dem Ersatz-Release neu erzeugt und bis zur nächsten Neuberechnung ausgeliefert; der Changelog schrumpft
  dann auf `v1.1` (aus dem Code abgeleitet, nicht ausgeführt).
- **EC-03** · Neues Release, DMG-Upload läuft noch → AK-16: alter Link, neue Versionsnummer.
- **EC-04** · Vorabversion auf GitHub → erscheint im Changelog mit Download-Link, nicht auf `/` und nicht über
  `/download` (`releases/latest` schließt Vorabversionen aus).
- **EC-05** · Mehr als 20 Releases → nur die neuesten 20 im Changelog; ältere über „releases page".
- **EC-06** · Release ohne englischen Ersatztext → deutscher GitHub-Text auf der englischen Seite; HTML darin (etwa
  `<details>`) erscheint als Quelltext (AK-20).
- **EC-07** · Release-Text mit `#`/`##`-Überschrift oder Link → Ausgabe enthält das ungültige Attribut
  `node="[object Object]"` (FB-23).
- **EC-08** · Google Fonts beim Build nicht erreichbar → Build bricht mit `next/font: error` ab (ausgeführt:
  Proxy auch für Google gesperrt). GitHub-Ausfall bricht den Build dagegen nicht ab (AK-33).
- **EC-09** · Build außerhalb von Vercel ohne `NEXT_PUBLIC_SITE_URL` → Canonical, OG-Adressen, Sitemap und robots
  zeigen auf `http://localhost:3000` (AK-28).
- **EC-10** · Vorschau-Deployments auf Vercel: `NEXT_PUBLIC_SITE_URL` ist laut `web/README.md:69` nur für Production
  gesetzt → Canonical zeigt über `VERCEL_PROJECT_PRODUCTION_URL` auf die Produktionsadresse.
- **EC-11** · JavaScript im Browser deaktiviert → alle Texte, Links und FAQ sind im ausgelieferten HTML enthalten;
  die Multiview-Nachbauten bleiben im Ausgangszustand stehen.
- **EC-12** · Node-Version außerhalb von `engines` (`>=20.9.0 <25`): lokal mit Node 26.8.2 gebaut, ohne Warnung und
  ohne Fehler.
- **EC-13** · Dateigröße: Umrechnung durch 1024², Einheit „MB" (36 455 860 Bytes → „34.8 MB").
- **EC-14** · Release-Zeitpunkt nahe Mitternacht → Datum wird in UTC formatiert und kann vom lokalen Datum abweichen.
- **EC-15** · Die Schaltfläche „Download for macOS" fällt nie auf die GitHub-Release-Seite zurück, weil
  `getLatestRelease` immer ein DMG liefert (Ersatz-DMG) — der Zweig in `components/download-button.tsx:6` wird
  nicht erreicht.

## Offene Fragen

- **OF-01** · Soll die Download-Schaltfläche beim Ersatz-DMG (neues Release ohne Asset) die Version und Größe des
  tatsächlich verlinkten DMG zeigen statt der neuen Versionsnummer? — Nutzer, vor dem nächsten Release.
- **OF-02** · Sollen Vorabversionen im Changelog erscheinen? Der Code filtert nur Entwürfe. — Nutzer, vor der ersten
  Vorabversion.
- **OF-03** · Der Cache-Tag `github-releases` wird nirgends per `revalidateTag` ausgelöst. War eine Aktualisierung per
  Webhook beim Release geplant, oder reicht die Stunde? — Nutzer, bei Überarbeitung von B09.
- **OF-04** · Unter welcher öffentlichen Adresse soll die Website erreichbar sein? Die Homepage im GitHub-Repository
  (`https://mikaplus-player.vercel.app`) liefert `DEPLOYMENT_NOT_FOUND`, `mikaplusplayer.com` aus `web/README.md:69`
  antwortet nicht (FB-15). — Nutzer, vor jeder weiteren Prüfung der Live-Seite.

*Eingetragen bei `sdd-build` B10 Teil 1 (2026-09-16), ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung
durch den Nutzer:*

- **OF-05** · Reicht die Content-Security-Policy mit `script-src 'self' 'unsafe-inline'` (BUG-09)? Sie blockiert fremde
  Skripte, `eval`, Plugins, Framing sowie fremde Bilder und Verbindungen, aber keine eingeschleusten Inline-Skripte. Eine
  Nonce-CSP würde jede Seite dynamisch rendern: keine statischen Seiten, kein ISR, eine Server-Funktion je Seitenaufruf.
  Das widerspricht AK-01/AK-03 und den Kostenzielen aus FB-21. — Nutzer, vor einer Änderung am Rendering.
- **OF-06** · Soll `/download` zusätzlich ein Plattform-Limit je Client bekommen (Vercel Firewall) und soll auf Vercel ein
  `GITHUB_TOKEN` gesetzt werden? Das Fehlerfenster von 5 Minuten (BUG-04) gilt nur je Server-Prozess bzw.
  Funktionsinstanz. Beides braucht Vercel-Zugang. — Nutzer, zusammen mit OF-04.
- **OF-07** · Die Kriterien AK-09, AK-16, AK-22, AK-32, AK-33 und AK-34 beschreiben den Stand vor der Reparatur. Sie
  nennen den Rechtsklick-Weg, das v1.1-Ersatz-DMG und eine Anfrage je Aufruf. Nach BUG-04, BUG-06 und BUG-08 gilt:
  Erststart über Systemeinstellungen mit SHA-256-Prüfung, bei Störung oder fehlendem DMG ein Link auf die
  Release-Seite, im Fehlerfall höchstens eine Anfrage je 5-Minuten-Fenster. OF-01 ist damit gegenstandslos. Die
  Kriterien neu zu fassen ist Spec-Pflege und nicht Aufgabe von `sdd-build`. — `sdd-qa` B10 Durchlauf 2.

## Fehlbestand

Nicht vorhanden oder nicht zutreffend, aus Code, Build oder Artefakt belegt. Kein Kriterium — `sdd-qa` prüft nichts
davon als bestanden, sondern nimmt es als Suchliste.

### Aussagen der Website, die der Code nicht erfüllt

- **FB-01 · Doppelklick-Import von `.m3u` fehlt.** `content/features.ts:48`: „double-clicking one opens it here".
  `Info.plist:68-82` registriert den Dokumenttyp (sogar für `public.text`), in `Sources/` gibt es aber keinen
  `onOpenURL`-, `handlesExternalEvents`- oder Delegate-Handler (AS-01). Folge: Doppelklick startet die App ohne Import;
  die App bietet sich zudem als Öffner für beliebige Textdateien an.
- **FB-02 · Bild-in-Bild beworben, aber in keinem Release und für das Standardformat nicht verfügbar.**
  `content/features.ts:30-34` („Picture in Picture … On iPhone and iPad it starts on its own"), Taste „P" in
  `content/features.ts:38` und `app/support/page.tsx:18`. Das einzige Release `v1.1` (2026-06-23) enthält weder PiP
  noch die Taste P (PiP kam mit `54550b2` am 2026-07-15, ohne Release). Auf `main` bietet nur die AVKit-Engine PiP
  (`PlaybackEngine.swift:86`, `PlayerView.swift:114`); Xtream-Standardformat MPEG-TS läuft über VLC ohne PiP
  (`ImportPlaylistView.swift:31`). Eine iOS-Version wird nicht verteilt. Folge: Heruntergeladene App hat die
  beworbene Funktion nicht; die Taste P tut nichts.
- **FB-03 · „Sendet deine Daten nirgendwohin" ist falsch.** `app/page.tsx:70-72` („send your data anywhere"),
  `app/page.tsx:64-65` („all on your Mac, all local"), `content/faq.ts:40` („Where does my data go? Nowhere."),
  `app/privacy/page.tsx:19`. Die App sendet Xtream-Benutzername und -Passwort im Klartext per HTTP an den Anbieter
  (`XtreamCodes.swift:69-74`, `XtreamClient.swift:65-70`), die IP-Adresse an beliebige Logo-Hosts
  (`ChannelRowView.swift:36`) und an GitHub (Sparkle). Die Datenschutzseite widerspricht sich selbst (Abschnitt
  „Xtream logins travel over plain HTTP"). Folge: irreführende Datenschutzaussage auf Start- und FAQ-Seite.
- **FB-04 · Speicherort und Löschaussage stimmen auf macOS nicht.** `app/privacy/page.tsx:37-39`: „They stay in the
  app's own storage" und „deleting the app removes all of it". Die macOS-App läuft ohne Sandbox
  (`MikaPlusPlayer.entitlements:7-8`) mit unbenannter `ModelConfiguration` (`MikaPlusPlayerApp.swift:8-9`); SwiftData
  legt dann `default.store` direkt in `~/Library/Application Support/` ab, nicht nach App getrennt (DM-03). Auf dem
  Entwicklungs-Mac liegt dort am 2026-09-15 eine solche Datei (nur Dateiname geprüft, Inhalt nicht gelesen, Herkunft
  nicht zugeordnet). Das Löschen von `MikaPlusPlayer.app` entfernt diese Datei nicht. Auf iOS trifft die Aussage zu.
  Folge: Zugangsdaten bleiben nach dem Löschen der App auf dem Mac liegen, entgegen der Zusage.
- **FB-05 · „Alles geht an den eingegebenen Host" ist falsch.** `app/privacy/page.tsx:47-49`: „Every stream, channel
  list and logo request goes to the host you entered". Bei M3U-Playlists stehen Stream- und Logo-Adressen beliebiger
  Hosts in der Datei (`M3UParser.swift:48-56`); bei Xtream kommen Logos aus `stream_icon` beliebiger Hosts. Der
  nächste Punkt der Seite („Channel logo servers") widerspricht dem. Folge: Nutzer unterschätzt, wer seine IP sieht.
- **FB-06 · Suche und Gruppenfilter nicht vollständig „in der Datenbank".** `content/features.ts:13`,
  `app/page.tsx:108-110`, `content/faq.ts:35`. Die Senderfilterung läuft per `@Query` (`ChannelListView.swift:88-97`),
  die Gruppenliste wird aber aus allen Sendern der Playlist im Speicher berechnet (`ChannelListView.swift:70-80`,
  DM-07), und es gibt keinen Index auf `playlistID`/`name` (DM-05). Folge: Leistungsaussage bei 17 000 Sendern
  unbelegt; von der QA zu messen.
- **FB-07 · Favoriten werden nicht nur über `tvg-id` wiedererkannt.** `content/features.ts:18`. Ohne `tvg-id` gilt
  der kleingeschriebene Name (`Channel.swift:48-51`); gleiche Schlüssel machen nach einem Refresh mehrere Sender zu
  Favoriten (`PlaylistImporter.swift:136,169`, DM-06). Folge: Umbenennung beim Anbieter verliert Favoriten, Dubletten
  werden ungewollt Favoriten.
- **FB-08 · Nicht jede Taste zeigt eine Rückmeldung.** `content/features.ts:38`: „On-screen feedback confirms each
  one". Ein HUD gibt es nur für Play/Pause, Stumm und Lautstärke (`PlayerView.swift:323-346`); F, P und Esc blenden
  höchstens die Steuerung ein. Folge: geringe Abweichung, Aussage überzeichnet.
- **FB-09 · „Updates that install themselves" überzeichnet.** `content/features.ts:42-43`, `content/faq.ts:50`.
  `Info.plist:27-32` aktiviert nur die automatische Prüfung; `SUAutomaticallyUpdate` ist nicht gesetzt, eine
  Installation ohne Zutun setzt nach Sparkle-Standard die Zustimmung des Nutzers im Update-Dialog voraus. Am
  laufenden Build unter B09 nachzuweisen. Folge: Nutzer erwartet stille Updates.
- **FB-10 · Changelog behauptet, Sparkle lese diese Liste.** `app/changelog/page.tsx:21`. Sparkle liest
  `appcast.xml` (`Info.plist:28`); die installierte `v1.1` liest noch
  `https://raw.githubusercontent.com/Mukaarts/MikaPlusPlayer/main/appcast.xml` (Info.plist im DMG). Ein GitHub-Release
  ohne appcast-Eintrag erreicht keinen Nutzer. Folge: falsches Bild vom Update-Weg.
- **FB-11 · Gatekeeper-Anleitung vermutlich veraltet; kein Integritätsnachweis für den Erstdownload.**
  `app/support/page.tsx:35-44`, `components/gatekeeper-note.tsx:9-13`, `content/faq.ts:10`,
  `content/changelog-overrides.ts:16`: „Right-click … choose Open, then confirm". Seit macOS 15 lässt Apple das
  Umgehen per Control-Klick nicht mehr zu, die Freigabe erfolgt unter Systemeinstellungen → Datenschutz & Sicherheit;
  die App unterstützt laut Seite macOS 14 und neuer. `spctl --assess` weist die App aus dem DMG ab (`rejected`).
  Die Seite nennt keine Prüfsumme; Sparkle-EdDSA schützt nur Updates, nicht den Erstdownload. Das Stack-Profil
  `swiftui-macos` verlangt für eine Veröffentlichung Developer ID und Notarisierung. Folge: Anleitung führt auf
  aktuellem macOS ins Leere; Nutzer werden angeleitet, eine Schutzfunktion für eine unprüfbare Datei zu umgehen.
  Auf aktuellem macOS durch die QA nachzustellen.
- **FB-12 · App-Name in der Anleitung passt nicht zur Datei.** `app/support/page.tsx:41-43`: „drag Mika+Player …",
  „Right-click Mika+Player". Das Bundle heißt `MikaPlusPlayer.app`, in `v1.1` ist `CFBundleName` `MikaPlusPlayer`.
  Folge: Nutzer sucht in „Programme" nach einem Namen, der dort nicht steht.
- **FB-13 · „Open-source" ohne Lizenz.** `components/site-footer.tsx:14`, dazu „The full source is on GitHub"
  (`app/page.tsx:197-205`). Keine `LICENSE` im Repository, GitHub-API meldet `license: null`. Folge: rechtlich „alle
  Rechte vorbehalten"; die Aussage „open-source" trifft nicht zu.
- **FB-14 · Sprachbruch nicht offengelegt.** Website und Nachbauten sind Englisch (`app/layout.tsx:76`,
  `components/channel-list-demo.tsx:9,63`, `components/multiview-demo.tsx:83,110`), Einrichtungsschritte nennen
  „File" (`content/setup-steps.ts:12`); die App-Oberfläche ist nur Deutsch („Datei", „Alle", „Sender suchen",
  „Fokus"/„Raster", „Nach Updates suchen …"). Nirgends steht, dass die App Deutsch ist. Folge: englischsprachige
  Nutzer finden die beschriebenen Bedienelemente nicht wieder.

### Betrieb, Datenschutzerklärung, Anbieterkennzeichnung

- **FB-15 · Die Website ist öffentlich nicht erreichbar.** Stand 2026-09-15, lesend geprüft: Die Homepage des
  Repositories `https://mikaplus-player.vercel.app` liefert `404 DEPLOYMENT_NOT_FOUND`; die Adresse des letzten
  Production-Deployments (`https://mikaplus-player-bgidneikr-daumedia.vercel.app`, GitHub-Deployment vom 2026-09-10)
  und `https://mikaplus-player-daumedia.vercel.app` leiten auf `vercel.com/sso-api` um (Vercel Deployment Protection),
  setzen dabei das Cookie `_vercel_sso_nonce` und senden `x-robots-tag: noindex`. Die App verlinkt die Website bzw.
  Datenschutzseite nirgends. Folge: Die einzige Datenschutzerklärung zu App und Website ist für Nutzer nicht
  abrufbar; die Aussage „No cookies" gilt für die erreichbare Vercel-Oberfläche nicht.
- **FB-16 · Keine Anbieterkennzeichnung.** Keine Seite nennt Namen, Anschrift oder Kontakt des Anbieters; „daumedia"
  erscheint nur in GitHub-URLs (AK-06). Das Bundle-ID-Präfix `lu.daumedia` deutet auf einen Anbieter in Luxemburg.
  Befund, keine Rechtsberatung: Für Diensteanbieter in der EU bestehen Informationspflichten (Art. 5
  E-Commerce-Richtlinie 2000/31/EG, in Luxemburg umgesetzt) — ob sie hier greifen, ist nicht Teil dieser Erfassung.
  Folge: Besucher und Behörden können den Verantwortlichen nicht ermitteln.
- **FB-17 · Datenschutzseite unvollständig und in einem Punkt irreführend.** `app/privacy/page.tsx`. Es fehlen:
  Name und Kontakt des Verantwortlichen, Zwecke und Rechtsgrundlagen, Empfänger (Vercel, GitHub) mit Sitz und
  Drittlandübermittlung, Speicherdauer der Vercel-Server-Logs, Betroffenenrechte und Beschwerdestelle. Die Aussage
  „Neither of those tells us who you are" (`:82`) übergeht, dass IP-Adressen in Logs personenbezogen sind. Das Datum
  „Last updated 30 July 2026" ist ein fester Wert (`:11`). `docs/datenschutz.md` existiert nicht, ein
  Auftragsverarbeitungsvertrag mit Vercel ist nirgends dokumentiert. Befund, keine Rechtsberatung. Folge: Stufe B
  verlangt Datenschutzhinweise, Löschkonzept und AV-Verträge — keins davon ist belegt.
- **FB-18 · Kein Weg für Auskunft oder Löschung.** Einziger Kontakt sind öffentliche GitHub Issues
  (`app/privacy/page.tsx:95-103`, `app/support/page.tsx:124-133`). Folge: Wer Auskunft über seine Log-Daten will, muss
  ein GitHub-Konto anlegen und die Anfrage öffentlich stellen.

### Technik und Missbrauchsschutz

- **FB-19 · Ersatz-Release fest auf `v1.1` verdrahtet, ohne Pflegeweg.** `lib/releases.ts:46-60`
  (Tag, Titel, Datum, Größe, URL) und `content/changelog-overrides.ts:6-17`. `scripts/release.sh` aktualisiert beides
  nicht. Folge: Nach dem nächsten Release zeigt jede GitHub-Störung wieder `v1.1` an und verlinkt ein veraltetes DMG;
  deutschsprachige Release-Texte erscheinen ungefiltert auf der englischen Seite.
- **FB-20 · Keine Content-Security-Policy und keine Permissions-Policy.** `next.config.ts:5-19` setzt nur `nosniff`,
  Referrer-Policy, X-Frame-Options und HSTS. Die Seite rendert fremde Inhalte (GitHub-Release-Texte); die Entschärfung
  hängt allein am Standardverhalten von `react-markdown` (AK-20). Folge: keine zweite Verteidigungslinie, falls
  künftig `rehype-raw` o. ä. hinzukommt oder ein Paket eine Lücke hat.
- **FB-21 · Kein Rate Limit auf `/download`; Fehler werden nicht gecacht.** `app/download/route.ts:5-9`,
  `lib/releases.ts:73-90`. Jeder Aufruf startet eine Server-Funktion; solange GitHub nicht mit 200 antwortet, löst
  jeder Aufruf eine neue API-Anfrage aus (AK-34). Ohne `GITHUB_TOKEN` teilen sich Vercel-Funktionen das Limit von
  60 Anfragen je Stunde je Ausgangs-IP. Folge: Funktionsaufrufe auf Kosten des Betreibers beliebig vervielfachbar;
  ein erschöpftes Limit hält die Seite dauerhaft im Ersatzzustand.
- **FB-22 · Abhängigkeiten mit bekannten Sicherheitslücken.** `web/package.json:15` pinnt `next` 16.2.12;
  `npm audit --omit=dev` am 2026-09-15: 1 kritisch, 3 hoch — `next` (GHSA-2xp9-vwfh-vxw4 „Unauthenticated Remote Code
  Execution in Image Optimization API when AVIF files are used", GHSA-p293-qw3h-jr36 nur Windows-Hosting; behoben ab
  16.3.3), mitgebracht `postcss` (u. a. GHSA-6g55-p6wh-862q), `sharp`/libvips (GHSA-f88m-g3jw-g9cj,
  GHSA-rgj7-g3m4-5g8c), `nanoid` (GHSA-2v37-7h3g-55p8). Die Seite nutzt die Bildoptimierung (`/_next/image`,
  `components/site-header.tsx:14-21`). Ausnutzbarkeit auf Vercel (dort eigene Bildoptimierung) nicht geprüft.
  Folge: je nach Hosting-Pfad Codeausführung auf dem Server möglich.
- **FB-23 · Ungültiges Attribut `node="[object Object]"` in Release-Notizen.** `components/release-notes.tsx:13-18`
  reicht alle Props von `react-markdown` einschließlich `node` an `h3` und `a` weiter. Nachweis mit dem Nachbau:
  `<h3 node="[object Object]">`, `<a href="…" … node="[object Object]">`. Heute unsichtbar, weil `v1.1` per
  Ersatztext ohne Überschriften und Links gerendert wird. Folge: ungültiges HTML sobald ein GitHub-Text ohne
  Ersatztext Überschriften oder Links enthält.

## Decision Log

Alle Einträge: **ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer.**

| # | Frage | Entscheidung | Begründung |
|---|---|---|---|
| 1 | Aussagen der Website, die der Code nicht erfüllt, als Kriterium oder als Befund? | Befund (FB-01 bis FB-14); die Kriterien der Datenschutzseite nennen nur Aufbau und belegte Aussagen | Zielmodus-Regel „Website verspricht etwas, das der Code nicht tut → Fehlbestand"; ein Kriterium „Seite sagt X" würde grün melden, wo X falsch ist |
| 2 | `/download` ohne Limit, Fehlerfall ungecacht | ⚠-Kriterium AK-34 **und** FB-21 | Missbrauch und Kosten nach `sicherheit.md` Abschnitt 4 |
| 3 | Neues Release ohne DMG → alter Link | reguläres Kriterium AK-16; Beschriftung als OF-01 | der alte Link ist im Code-Kommentar als gewollt beschrieben (`lib/releases.ts:125`), die widersprüchliche Beschriftung nicht |
| 4 | Vorabversionen im Changelog | reguläres Kriterium AK-18 mit Hinweis; OF-02 | Absicht nicht ableitbar, keine Sicherheitsrelevanz |
| 5 | Gatekeeper-Anleitung | Inhalt als reguläres Kriterium (AK-09, AK-22), Aktualität und fehlender Integritätsnachweis als FB-11 | Anleitung ist auf der Seite ausdrücklich gewollt; Notarisierung verlangt das Stack-Profil |
| 6 | Live-Zustand auf Vercel aufnehmen, obwohl nicht im Code? | ja, als FB-15 und OF-04 | die einzige Datenschutzerklärung muss erreichbar sein; nur lesend geprüft, kein Deployment |
| 7 | Fehlende Anbieterkennzeichnung | FB-16 als Befund, ausdrücklich ohne rechtliche Bewertung | Auftrag verlangt Befund, keine Rechtsberatung |
| 8 | `npm audit`-Treffer | FB-22, Schweregrad bewertet die QA | Abhängigkeitslücken sind Teil des Missbrauchsschutzes; Ausnutzbarkeit auf Vercel offen |
| 9 | `node`-Attribut in Release-Notizen | nur FB-23 und EC-07, kein ⚠-Kriterium | offensichtlich unbeabsichtigt, keine Sicherheitsrelevanz |
| 10 | Markdown-Entschärfung ohne Codeänderung prüfen | Nachbau der Konfiguration im Scratchpad gegen die installierte Bibliothek | „Keine Zeile Code ändern"; gleiche Version, gleiche Komponenten-Überschreibungen |
| 11 | Fallback-Pfade ausführen, ohne `web/.next` mehrfach zu überschreiben | Build-Kopie im Scratchpad, GitHub per totem Proxy gesperrt, Google Fonts ausgenommen | der erste Versuch mit komplett gesperrtem Netz scheiterte an `next/font` (EC-08) |
| 12 | Aussage „Universal build" | anhand des lokal vorhandenen `dist/MikaPlusPlayer-v1.1.dmg` geprüft (Bytegröße identisch mit dem Release-Asset) | Release-Asset nicht erneut heruntergeladen |
