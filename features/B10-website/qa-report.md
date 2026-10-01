# B10 · Website — Testbericht

Stand: 2026-09-30 · **Durchlauf 2** (nach Reparatur Teil 1 und Teil 2) · Geprüft gegen `spec.md` vom 2026-09-15 (Offene
Fragen ergänzt bis 2026-09-30) und `build-bericht.md` (Teil 1 vom 2026-09-16, Teil 2 vom 2026-09-30) · Code `web/` =
`47a90c3` + Reparatur Teil 2 im Arbeitsbaum (nicht committet) · Maßstab der App-Aussagen: Release **v1.1** (Tag `v1.1` =
`907c9f8`, `dist/MikaPlusPlayer-v1.1.dmg`)

Durchlauf 1 (2026-09-15) steht unverändert weiter unten, samt den Vermerken aus `sdd-build` Teil 1 und Teil 2.

> **Wie geprüft wurde.** macOS 27.0 (26A428), Node 26.10.0, npm 11.19.1, `next` 16.3.3. Build ohne `GITHUB_TOKEN`,
> `NEXT_PUBLIC_SITE_URL` und `VERCEL_PROJECT_PRODUCTION_URL`, Server `next start -H 127.0.0.1 -p 3941`, danach beendet.
> Ersatzpfade (AK-32, AK-33, EC-08, EC-02) und Negativkontrollen in Kopien unter
> `~/.claude/projects/…/wt/b10qa2-copy` bzw. `…/wt/b10qa2-neg`, der alte Stand (HEAD, vor Teil 2) in einem Worktree
> `…/wt/b10qa2-head`; alle drei danach entfernt. **App-Seite, nur lesend bzw. isoliert:** `git show v1.1:<pfad>`;
> `dist/MikaPlusPlayer-v1.1.dmg` schreibgeschützt eingehängt (`PlistBuddy`, `codesign`, `spctl`, `lipo`, `strings`) und
> wieder ausgehängt; eine **Sonde aus den v1.1-Quellen** (`XtreamCodes.swift`, `XtreamClient.swift`, `M3UParser.swift`,
> `StreamType` aus `PlaybackEngine.swift`, per `swiftc` übersetzt) gegen einen lokalen Mock mit `qa-user`/`qa-pass-123`;
> eine **Kopfzeilen-Sonde** als Bundle wie v1.1 (`CFBundleName` MikaPlusPlayer, Build 2, Entwicklungssprache `en`, ohne
> `.lproj`, eigene Bundle-ID `lu.daumedia.qa.b10ua`) mit `URLSession` und `AVURLAsset` (nur Laden der Playlist, kein
> Abspielen, kein Ton); ihre Ordner unter `~/Library/Caches` und `~/Library/HTTPStorages` sind gelöscht. Die App wurde
> **nicht** gestartet, kein `xcodebuild`. Unter `~/Library`, `$TMPDIR` und `DARWIN_USER_CACHE_DIR` nur **Namen** gelistet,
> keine Inhalte gelesen. Live-Adressen, GitHub-API und GitHub-Download nur per GET/HEAD. Kein Deployment, nichts auf
> Vercel oder GitHub. Nichts unter `Sources/`, `Tests/`, `project.yml` und außerhalb von `features/B10-website/` geändert.

## Fazit (Durchlauf 2)

**Production-ready: nein** — höchster offener Schweregrad **hoch** (BUG-01, BUG-03; beide unverändert, beide brauchen
Entscheidungen oder Zugänge des Nutzers).

Die Reparaturen wirken. Alle elf Befunde aus Durchlauf 1 sind mit ihrer ursprünglichen Reproduktion erneut ausgeführt:
acht sind behoben, BUG-04 teilweise, BUG-01 und BUG-03 nicht. Die Datenschutzseite enthält keine der widerlegten
Aussagen mehr (0 Treffer auf allen vier Seiten, HTML und RSC). Satz für Satz gegen v1.1 gehalten stimmen Speicherort,
Klartext, Cache, Cookies, Einstellungen, Xtream über HTTP, Logo-Hosts, Update-Prüfung und Löschen einer Playlist. Das
ist über die v1.1-Sonde, das DMG und die ausgeführten QA-Nachweise aus B01–B09 belegt. Die Werbeaussagen auf Start-,
Support- und Changelog-Seite entsprechen v1.1. Kein Bild-in-Bild, keine Taste P, kein „open-source“; die Leistungszahlen
sind die gemessenen. Die umgestellten Tests sind **nicht aufgeweicht**. Drei Negativkontrollen gegen `M::AK-34` schlagen an.
Neun Wortlaut- und Soll-Tests schlagen am alten Stand alle an. CSP im Browser: 0 Verstöße auf allen vier Seiten.
`/download` bei GitHub-Störung: 1 Anfrage je Fenster. Kein Token im Bundle, kein Cookie, keine Besucherdaten in
Protokollen oder an GitHub.

Offen bleiben:
- **BUG-01 (hoch):** Keine Adresse liefert die Seite öffentlich aus. Neu beobachtet: Das neueste Production-Deployment
  steht auf `47a90c3`, also **ohne** die Teil-2-Texte. Wird nur der Schutz abgeschaltet, gehen die alten, widerlegten
  Datenschutzaussagen online.
- **BUG-03 (hoch):** Verantwortlicher, Rechtsgrundlagen, Speicherdauer, Betroffenenrechte und ein nicht öffentlicher
  Kontaktweg fehlen weiter; 0 Treffer.
- **BUG-04 (Teil):** Ein Limit je Client fehlt weiter (60 parallele Aufrufe → 60 × 302, kein 429). Gehört laut OF-06 in
  die Vercel-Einstellungen.

Neu gefunden:
- **BUG-12 (mittel):** `npm audit --omit=dev` meldet wieder eine **kritische** Advisory für `next` 16.3.3
  (GHSA-vcvr-r3jv-pc5j, RCE in `next/og` `ImageResponse`, veröffentlicht am 2026-09-22, behoben ab 16.3.6). Die
  Angriffsfläche ist belegt nicht erreichbar, siehe unten.
- **BUG-13 bis BUG-17 (niedrig), Datenschutz- und FAQ-Texte, die v1.1 nicht vollständig oder nicht zutreffend
  beschreiben:**
  - BUG-13: Kopfzeilen verraten die macOS-Version; bei Streams auch Sprache und Player.
  - BUG-14: Löschweg ohne `~/Library/Preferences/lu.daumedia.MikaPlusPlayer/` (VLC).
  - BUG-15: Die FAQ verspricht Versionshinweise im Update-Fenster.
  - BUG-16: Ein einzelner GitHub-Fehler bei der stündlichen Neuberechnung entfernt Prüfsumme, DMG-Link und Changelog
    bis zur nächsten Neuberechnung (EC-02, jetzt ausgeführt).
  - BUG-17: Die erzwungene HTTP-Umschreibung wird den Panels zugeschrieben.

**Nächster Schritt:** zuerst `/sdd-klaeren B10`. Zu entscheiden sind OF-04 (öffentliche Adresse), OF-06 (Limit und Token
auf Vercel), OF-07/OF-08 (Spec-Wortlaut, siehe H-1), OF-09 (Lizenz), OF-10 (Kopplung an das Release), OF-11 und die
Angaben zum Verantwortlichen für BUG-03. Danach `/sdd-build B10` mit BUG-12 bis BUG-17, dazu BUG-01 und BUG-03, sobald
die Entscheidungen vorliegen. Dann `/sdd-qa B10` (Durchlauf 3). **Die Erfassung wartet**, solange BUG-01 und BUG-03
(hoch) offen sind. Befunde, keine Rechtsberatung.

| | Anzahl |
|---|---|
| Akzeptanzkriterien geprüft | 41 von 41 (alle in Durchlauf 2 ausgeführt) |
| davon bestanden | 41 — davon 9 mit durch die Reparatur gewollt geändertem Ist, Spec-Wortlaut veraltet (AK-06, 09, 11, 16, 18, 22, 24, 32, 33 → H-1); AK-34 ⚠ Befund behoben; AK-26 und AK-35 nur lokal (live → BUG-01) |
| davon durchgefallen | 0 |
| **nicht prüfbar** | 0 |
| Edge Cases belegt | 12 von 15 (EC-02 neu ausgeführt); nicht prüfbar: EC-04, EC-05, EC-10 |
| BUGs aus Durchlauf 1 | 8 behoben ✅ (02, 05, 06, 07, 08, 09, 10, 11) · 1 teilweise (04) · 2 nicht behoben ❌, Begründung bestätigt (01, 03) |
| Neue BUGs | 6 (BUG-12 mittel; BUG-13 bis BUG-17 niedrig) |
| Tests neu geschrieben | 18 in 2 Dateien (`qa2.release-claims.test.mjs` 16, `qa2.isr-outage.test.mjs` 2), davon 5 `todo` für neue Befunde |
| Tests grün | Gesamtlauf 86 Tests: 79 bestanden, 0 fehlgeschlagen, 7 `todo` (BUG-01, 03, 12, 13, 14, 15, 16) |

## Durchlauf 2 · BUGs aus Durchlauf 1 erneut ausgeführt

| BUG | Grad | Ergebnis | Nachweis (ursprüngliche Reproduktion, erneut ausgeführt) |
|---|---|---|---|
| BUG-01 | hoch | **nicht behoben ❌** — Begründung stimmt (Vercel, OF-04) | 2026-09-30 20:16 UTC, nur GET/HEAD, `L::FB-15` weiter `todo`: `mikaplus-player.vercel.app/privacy` → 404 `x-vercel-error: DEPLOYMENT_NOT_FOUND`; `mikaplus-player-6lgqlbhlm-…`, `…-bgidneikr-…` und `mikaplus-player-daumedia.vercel.app` → 302 `vercel.com/sso-api`, `set-cookie: _vercel_sso_nonce=…; Max-Age=3600`, `x-robots-tag: noindex`; `curl -L` endet auf „Login – Vercel“, 0 × „What leaves your Mac“; `dig mikaplusplayer.com` → NXDOMAIN; Repository-Homepage laut API weiter `https://mikaplus-player.vercel.app`. **Neu:** GitHub-Deployment `6684493699` (Production, 2026-09-26) steht auf `47a90c3` — dort gilt noch die alte Datenschutzseite („They stay in the app's own storage“ 1 Treffer im Build dieses Stands) |
| BUG-02 | hoch | **behoben ✅** — Restlücken neu als BUG-13, BUG-14, BUG-17 (niedrig) | Schritt 1 (Seiten): „nothing goes to us“, „own storage“, „no copy anywhere else“, „deleting the app removes all of it“, „goes to the host you entered“, „send your data anywhere“, „all on your Mac, all local“, „Nowhere.“, „Neither of those tells us who you are“ → **0** auf `/`, `/privacy`, `/support`, `/changelog` (HTML + RSC); „no server“ nur als „no server to run“ (Einrichtung, anderer Sinn). Schritte 2–5 (App v1.1, unverändert): DMG `app-sandbox => false`; v1.1-Sonde → gespeicherte Adresse `http://…/player_api.php?username=qa-user&password=qa-pass-123`, Stream `…/live/qa-user/qa-pass-123/101.ts`; M3U mit Streams auf `streams.third-host.example`, `cdn.fourth-host.example`, Logos auf `logos.other-host.example`, `203.0.113.9`. Die Seite beschreibt das jetzt zutreffend, Satz für Satz unten |
| BUG-03 | hoch | **nicht behoben ❌** — Begründung stimmt (Angaben des Nutzers) | Suche auf allen vier Seiten ohne Skripte: E-Mail 0, Imprint/Impressum/Legal notice 0, Controller/Verantwortlich 0, Anschrift 0, Rechtsgrundlage 0, Speicherdauer 0, Betroffenenrechte/GDPR 0, Aufsicht/CNPD/Beschwerde 0 (Treffer „thousand“ für „USA“ als Fehlalarm geprüft); `docs/datenschutz.md` fehlt; `H::FB-16/FB-17/FB-18` weiter `todo`. Teilweise erledigt: „Neither of those tells us who you are“ ist ersetzt |
| BUG-04 | mittel | **teilweise** — Upstream behoben ✅, Limit je Client offen (OF-06) | `M::AK-34/FB-21` (Mock 403, Fenster in der Kopie 4 s): im Fenster 4 sequentielle + 60 parallele Aufrufe → **0** Upstream-Anfragen, 0 Warnzeilen; nach Ablauf 60 parallele → **1**. Kopie mit `api.github.invalid`: 6 × `/download` → 6 × 302 `…/releases/latest`, **1** Warnzeile. Gegen den eigenen Server: 60 parallele `/download` → 60 × 302, **kein 429** |
| BUG-05 | mittel | **behoben ✅** für die gemeldeten Advisories — neue Advisory → **BUG-12** | `npm ls`: `next@16.3.3`, `sharp@0.35.4`, `postcss@8.5.23`, `nanoid@3.3.19`; GHSA-2xp9-vwfh-vxw4, GHSA-p293-qw3h-jr36, die `sharp`-, `postcss`- und `nanoid`-Advisories erscheinen nicht mehr. `npm audit --omit=dev` ist aber **nicht** leer: `next 16.2.0 - 16.3.5 · Severity: critical · GHSA-vcvr-r3jv-pc5j` |
| BUG-06 | mittel | **behoben ✅** (Website-Teil) — Notarisierung bleibt B09 BUG-03, neue Randlücke BUG-16 | v1.1 aus dem DMG: `Signature=adhoc`, `TeamIdentifier=not set`, `spctl --assess` → `rejected`. Seiten: „SHA-256/checksum/shasum“ `/` 3, `/support` 4, `/changelog` 3; „System Settings“ `/` 1, `/support` 3; „Open Anyway“ `/` 1, `/support` 2; „right-click“ 0. Angezeigte Prüfsumme `8da0620e…845a272c` = `shasum -a 256 dist/MikaPlusPlayer-v1.1.dmg` = API-`digest`. Klickweg „Open Anyway“ weiter nicht ausgeführt (keine Finder-Automatisierung, Tonvorgabe) |
| BUG-07 | mittel | **behoben ✅** — Lizenzentscheidung offen (OF-09) | Je Punkt gegen v1.1: FB-02 `git grep PictureInPicture v1.1 -- Sources` 0 → Seiten 0 × „Picture in Picture“, keine Taste P; FB-01 kein `onOpenURL` in v1.1 → „does not import it in version 1.1“; FB-10/FB-09 siehe BF-16; FB-12 DMG `CFBundleName = MikaPlusPlayer` → Schritte nennen `MikaPlusPlayer`; FB-13 API `license: None` → 0 × „open-source“; FB-14 v1.1 ohne `.lproj`, `Datei`, `Nach Updates suchen …` → „The app's interface is in German.“ Gesichert durch 12 neue Abgleich-Tests (`qa2.release-claims`) |
| BUG-08 | mittel | **behoben ✅** | Kopie mit `api.github.invalid`: Build `[releases] request failed … ENOTFOUND` für beide Abfragen, Exit 0; `/`: beide Schaltflächen `…/releases/latest`, Beschriftung „Latest release on GitHub · macOS 14 Sonoma or later“, keine Prüfsumme, kein v1.1-Link; `/changelog`: „could not be loaded from GitHub just now“, 0 `<article>`. Mit `GITHUB_TOKEN=invalid` gegen das echte GitHub dasselbe (2 × `-> 401`). Hinweis: v1.1 selbst trägt weiter `get-task-allow=true` (DMG, B09 BUG-02) und ist das reguläre neueste Release |
| BUG-09 | niedrig | **behoben ✅** — Restrisiko `'unsafe-inline'` (OF-05) | `curl -sI /changelog`: `Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; … frame-ancestors 'none'`, `Permissions-Policy: accelerometer=(), … browsing-topics=()`; Browser `B::FB-20`: `/`, `/changelog`, `/privacy`, `/support` je **0** `securitypolicyviolation`, 0 Konsolenfehler, Hydration läuft |
| BUG-10 | niedrig | **behoben ✅** | `M::EC-07` am echten Build mit `# Heading`/Links: 0 × `node="[object Object]"` |
| BUG-11 | niedrig | **behoben ✅** | `curl /changelog|/privacy|/support`: `og:url`, `og:title`, `og:description`, `canonical` der Unterseite, `og:image` weiter vorhanden |

## Durchlauf 2 · Umgestellte Tests auf Aufweichung geprüft

| Test | Änderung in Teil 2 | Prüfung | Ergebnis |
|---|---|---|---|
| `M::AK-34 (BUG-08)` | statt „kein ‚Version 1.1‘ im HTML“ jetzt: kein v1.1-DMG-Link, kein „Version 1.1 · “ im Text, zweimal „Latest release on GitHub · macOS 14 Sonoma or later“ | Drei Negativkontrollen in einer Kopie (`…/wt/b10qa2-neg`): **A** fest verdrahtetes v1.1-Ersatz-Release in `getLatestRelease` → rot („Expected values to be strictly equal“, `/download`-Ziel); **B** Beschriftung „Version 1.1“ ohne Release-Daten → rot (`/Latest release on GitHub/`); **C** „Latest release on GitHub · Version 1.1“ → rot mit genau der neuen Zusicherung „keine fest verdrahtete v1.1-Beschriftung unter der Schaltfläche“ | nicht aufgeweicht; die neue Zusicherung greift allein |
| `H::AK-05/AK-06/AK-07` (Fußzeile) | neuer Wortlaut, weiter exakt | gegen den alten Stand (`47a90c3`) ausgeführt | rot („BUG-07 (FB-13): kein ‚open-source‘ ohne Lizenz“) |
| `H::AK-11/AK-12` | 8 → 7 Funktionen, neue Überschrift, weiter exakt | alter Stand | rot („Seventeen thousand channels, searchable“ fehlt) |
| `H::AK-18/AK-19` | neuer Satz zum Update-Weg, exakt | alter Stand | rot |
| `H::AK-22/AK-23` | App-Name, fünf Tasten, `deepEqual` bleibt | alter Stand | rot („01 Open the DMG and drag MikaPlusPlayer …“) |
| `H::AK-24/AK-25/AK-26` | Datum | alter Stand | rot („Last updated 30 September 2026“) |
| `H::FB-03/FB-04/FB-05`, `H::BUG-02 (Soll)`, `H::BF-12/BF-16`, `H::BUG-07 / …` | `todo` entfernt, erweitert bzw. neu | alter Stand | alle 4 rot |
| `B::AK-23/EC-11` | FAQ-Satz, exakt | Vergleich der Zusicherung | gleich streng |

Alle 9 H-Tests zusammen gegen den alten Stand: **9 von 9 rot**. Am aktuellen Stand grün.

## Durchlauf 2 · Datenschutzseite Satz für Satz gegen v1.1

`web/app/privacy/page.tsx` im Arbeitsbaum. „v1.1“ = `git show v1.1:…` bzw. DMG. „Sonde“ = v1.1-Quellen gegen den lokalen
Mock, „Kopfzeilen-Sonde“ = Bundle wie v1.1 (siehe oben). Nachweise aus anderen Features stammen aus deren ausgeführten
QA-Läufen an Code, der in den betroffenen Dateien gleich v1.1 ist (`git diff v1.1 c01f1cf -- Sources`: nur Bild-in-Bild,
Überschriften, Kommentar, Symbol, `Info.plist`-Anzeigename und Feed).

| # | Aussage (Zeile) | Beleg | Ergebnis |
|---|---|---|---|
| 1 | Kurzfassung: kein Konto, keine Telemetrie, keine Analyse, „sends nothing to the people who make it“ (`:34-35`) | DMG: Frameworks nur `Sparkle.framework`, `VLCKit.framework`; `strings` im Binary ohne Analytics/Telemetry/Crashlytics/Sentry/Firebase; v1.1-Quellen ebenso (`qa2::keine Kanäle, keine Telemetrie`); B06 AK-32: nur der Host der Adresse erhält Anfragen; B09 AK-23: Sparkle nur an den Feed-Host | stimmt |
| 2 | „talk to other servers — your provider, … streams and channel logos, and GitHub“ (`:35-37`) | Sonde (Hosts), B09 AK-03; Weiterleitungsziele in Satz 20 | stimmt |
| 3 | „keeps your provider credentials unencrypted on your Mac“ (`:37`) | Sonde: gespeicherte `sourceURL` = `http://panel.qa.example:8443/player_api.php?username=qa-user&password=qa-pass-123`; v1.1 ohne `SecItem`/`Keychain` | stimmt |
| 4 | „describes version 1.1 …, the version offered for download“ (`:37-39`) | GitHub-API: einziges Release `v1.1`; `/download` → `…/v1.1/MikaPlusPlayer-v1.1.dmg`; Prüfsumme = `dist/`-DMG | stimmt (Kopplung an das Release: OF-10) |
| 5 | Datenbank `~/Library/Application Support/default.store` (`:54-55`) | v1.1: `app-sandbox => false` (DMG), `ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)` ohne Name/URL; B01 AK-28 ausgeführt: Standardkonfiguration → genau dieser Pfad | stimmt |
| 6 | Inhalt: „playlist names and addresses, channel names, stream and logo addresses, groups and favourites“ (`:55-56`) | v1.1 `Playlist.swift`: zusätzlich `createdAt`, `lastRefreshed`, `isXtream`, `xtreamOutput`, `channelCount`; `Channel.swift`: zusätzlich `tvgID` | **unvollständig** — Import- und Aktualisierungszeitpunkte fehlen → **BUG-14** |
| 7 | „not encrypted, … does not use the macOS Keychain“ (`:56-57`) | v1.1 ohne `SecItem`, `kSecClass`, `Keychain`; B01 BUG-01 | stimmt |
| 8 | Xtream-Zugangsdaten im Klartext in der Playlist-Adresse und in jeder Sender-Adresse (`:57-59`) | Sonde: `http://127.0.0.1:38933/live/qa-user/qa-pass-123/101.ts` | stimmt |
| 9 | M3U-Link „exactly as you entered it, including any token“ (`:59-60`) | v1.1 `importFromURL`: `URL(string:)` der Eingabe, nur Leerzeichen am Rand entfernt, als `sourceURL` gespeichert; B02 BUG-01 | stimmt |
| 10 | „Any program running under your macOS user account can read the file“ (`:60-61`) | gilt für Programme ohne Sandbox; Programme in der Sandbox erreichen die Datei nicht | stimmt, vorsichtig überzeichnet → H-4 |
| 11 | „Time Machine backs it up“ (`:61`) | v1.1 ohne `isExcludedFromBackup`; B01 AK-28: `tmutil isexcluded` → `[Included]` | stimmt |
| 12 | Cache `~/Library/Caches/lu.daumedia.MikaPlusPlayer` mit Xtream-Anfragen samt Zugangsdaten, Antworten, M3U-Listen, Logos (`:66-68`) | v1.1 nutzt `URLSession.shared`, `.reloadIgnoringLocalCacheData` verhindert nur das Lesen; B01 BUG-03/AK-25 (3 Schlüssel mit Zugangsdaten, 1 Antwortkörper mit Passwort), B02 BUG-02, B04 BUG-07; Kopfzeilen-Sonde legte `~/Library/Caches/<Bundle-ID>` an (danach gelöscht) | stimmt |
| 13 | Cookies unter `~/Library/HTTPStorages/…` und `….binarycookies` (`:71-73`) | B02 AK-36: `Set-Cookie` wird beim nächsten Import und beim Aktualisieren zurückgeschickt; auf diesem Mac existieren `HTTPStorages/lu.daumedia.MikaPlusPlayer` und `…binarycookies` (nur Namen) | stimmt |
| 14 | Einstellungen `~/Library/Preferences/lu.daumedia.MikaPlusPlayer.plist`, „such as when the app last checked for updates“ (`:76-77`) | B09 AK-24 (`SULastCheckTime`), B06 REL-10 (zusätzlich `VLCParams`, Fensterrahmen) | stimmt |
| 15 | „no sync and no cloud service“ (`:81`) | v1.1-Entitlements nur `app-sandbox` und `disable-library-validation`, kein iCloud/CloudKit | stimmt |
| 16 | Playlist löschen entfernt Sender aus der Datenbank, nicht aus dem Cache; Reste in der Datei (`:81-83`) | v1.1 `deleteRule: .cascade`; B03 BUG-06 (Adresse samt Token und Liste im Cache), B03 BUG-07 (Namen und Adressen als Bytes) | stimmt |
| 17 | „Deleting the app does not remove any of this“, Löschweg mit vier Orten samt `-shm`/`-wal` (`:90-110`) | B06 REL-10 (Release-Lauf, VLCKit 3.0.21 wie im v1.1-DMG): libVLC legt `Library/Preferences/<Bundle-ID>/vlcrc` an; auf diesem Mac existiert `~/Library/Preferences/lu.daumedia.MikaPlusPlayer/` mit `vlcrc` und `vlcrc.55948` (nur Namen) | **unvollständig** — der Ordner fehlt im Löschweg → **BUG-14**; Fensterzustand in `$TMPDIR` → H-7 |
| 18 | Warnung: `default.store` ist der SwiftData-Standardname, andere Apps ohne Sandbox können ihn teilen (`:112-115`) | B01 BUG-04; Tatsache über SwiftData | stimmt |
| 19 | Kopien in Time Machine bleiben (`:116`) | folgt aus Satz 11 | stimmt |
| 20 | „Every connection … carries your IP“; eigene Anfragen nennen App, Build und „the version of macOS’s network components“ im User-Agent und senden die Systemsprache (`:123-126`) | Kopfzeilen-Sonde: `User-Agent: MikaPlusPlayer/2 CFNetwork/3896.100.1.1.1 Darwin/27.0.0`, `Accept-Language: de-DE,de;q=0.9` (System `de-LU`); v1.1-Sonde gegen Mock ebenso `… Darwin/27.0.0` | App, Build, CFNetwork, Sprache stimmen; **`Darwin/27.0.0` (macOS-Version) fehlt → BUG-13** |
| 21 | Anbieter: Liste und jedes Aktualisieren vom eingegebenen Host (`:130-132`) | v1.1 `refresh` rekonstruiert aus der gespeicherten Adresse; Sonde: 3 Anfragen an den eingegebenen Host | stimmt |
| 22 | Weiterleitung: „sends the same request, credentials included, to the new address“ (`:133-135`) | B01 BUG-10 (302 mit gleicher Adresse auf anderem Port → Ziel erhält alle 3 Anfragen mit Zugangsdaten), B02 AK-11 | stimmt für Weiterleitungen, die Pfad und Query übernehmen → H-2 |
| 23 | Cookies werden behalten und zurückgeschickt (`:135-136`) | B02 AK-36 | stimmt |
| 24 | Stream-Server: Adresse aus der Playlist, bei Xtream mit Zugangsdaten, bei M3U beliebig; der Server sieht IP und Sender (`:139-142`) | Sonde (Stream-Adresse mit Zugangsdaten; M3U-Streams auf fremden Hosts). Kopfzeilen-Sonde, `AVURLAsset`: `User-Agent: AppleCoreMedia/1.0.0.26A428 (Macintosh; U; Intel Mac OS X 27_0; de_de)`, `Accept-Language`, `x-playback-session-id`; B06 AK-32, VLC: `VLC/3.0.21 LibVLC/3.0.21` (VLCKit 3.0.21 im v1.1-DMG) mit `Accept-Language` | stimmt, aber **unvollständig**: macOS-Version, Sprache und Player-Version fehlen → **BUG-13** |
| 25 | Logo-Hosts: automatisch in Liste und Favoriten, auch HTTP und Weiterleitungen; erfahren Liste, Suche, Filter und bei jedem Öffnen des Favoriten-Tabs die Favoriten; kein Schalter (`:145-152`) | v1.1 `AsyncImage(url: channel.logoURL)` in `ChannelRowView`, dieselbe Karte im Favoriten-Tab, `NSAllowsArbitraryLoads`, kein `@AppStorage`; B04 BUG-06, B05 BUG-03 (je Öffnen 3 Anfragen, genau die Favoriten) | stimmt; „every time“ bei Antworten ohne Cache-Freigabe → H-3 |
| 26 | Sparkle prüft automatisch etwa einmal täglich, erstmals direkt nach dem ersten Start, ohne Rückfrage (`:155-157`) | v1.1 `Info.plist`: `SUEnableAutomaticChecks = true`, kein `SUScheduledCheckInterval`; DMG: Sparkle 2.9.3; B09 AK-03 ausgeführt: 2 s nach dem ersten Start `GET` auf den Feed, kein Dialog | stimmt |
| 27 | „Version 1.1 has no switch to turn this off“ (`:157-158`) | v1.1: keine Einstellungsansicht, nur Menüeintrag „Nach Updates suchen …“ | stimmt |
| 28 | Feed von `raw.githubusercontent.com`; User-Agent mit App-Name, Version und Sparkle-Version (`:158-161`) | v1.1 `SUFeedURL` Host `raw.githubusercontent.com`; B09 AK-23 (`…/1.1 Sparkle/2.9.3`) | stimmt; `Accept-Language` bei Sparkle nicht mitgeschnitten → H-8 |
| 29 | kein Systemprofil, nichts aus der Bibliothek (`:161`) | v1.1 ohne `SUSendProfileInfo`; B09 AK-23: keine Query-Parameter | stimmt |
| 30 | Update wird „from github.com“ geladen (`:161-162`) | `appcast.xml`-Enclosure `https://github.com/…/v1.1/…dmg`; `curl -sI` → 302 auf `release-assets.githubusercontent.com` | stimmt (beides GitHub) → H-5 |
| 31 | Xtream über `http://`, `https://` wird umgeschrieben (`:170-172`) | Sonde: `https://panel.qa.example:8443` → `http://panel.qa.example:8443` | stimmt |
| 32 | „because most panels serve nothing else“ (`:172-173`) | im Projekt nur ein Anbieter dokumentiert (Code-Kommentar zu Telecasty) | **nicht belegbar** → **BUG-17** |
| 33 | Zugangsdaten unverschlüsselt bei jeder Anfrage: Liste, Aktualisieren, jeder Stream; ebenso `http://`-M3U-Links (`:173-177`) | Sonde, Mock-Protokoll: 3 × `/player_api.php?username=qa-user&password=qa-pass-123` über HTTP, obwohl `https://` eingegeben war; Stream-Adresse mit Zugangsdaten | stimmt |
| 34 | „That is a property of IPTV panels rather than a choice we would defend“ (`:177-178`) | Die Umschreibung erzwingt v1.1 selbst (`XtreamCodes.baseURL`), auch bei einem Panel, das HTTPS kann (Sonde; B01 BUG-02) | **irreführend** → **BUG-17** |
| 35 | „No cookies, no analytics, no tracking scripts, no fonts loaded from third parties“ (`:185`) | lokal: `H::AK-35` (kein `Set-Cookie` auf 11 Routen), `B::AK-36` (0 Fremdanfragen); live: `_vercel_sso_nonce` | lokal stimmt, **live falsch → BUG-01** |
| 36 | „hosted on Vercel, which keeps standard server logs“ (`:185-186`) | Vercel-Projekt nicht einsehbar, Seite nicht öffentlich | **nicht belegbar** → BUG-01, BUG-03 (Speicherdauer) |
| 37 | Download-Schaltfläche zeigt auf GitHub, das Downloads je Release zählt; beide erhalten die IP (`:186-188`) | `href` direkt `https://github.com/…/MikaPlusPlayer-v1.1.dmg` (`B::AK-37`), API `download_count` | stimmt |
| 38 | `/download` ist eine Server-Funktion, die „to the newest file on GitHub“ weiterleitet (`:188-189`) | Build: `ƒ /download`; 302 auf das v1.1-DMG; bei Störung oder ohne DMG auf die Release-Seite | stimmt im Normalfall → H-6 |
| 39 | keine Sender, keine Abos (`:196-197`) | v1.1 ohne mitgelieferte Playlist (`qa2::keine Kanäle`) | stimmt |
| 40 | „Last updated 30 September 2026“ (`:202`) | Datum der Änderung; feste Konstante | stimmt |
| 41 | Fragen „in a GitHub issue“ (`:202-210`) | einziger Kontaktweg öffentlich | → BUG-03 (FB-18), weiterhin offen |

## Durchlauf 2 · Start, Funktionen, FAQ, Support und Changelog gegen v1.1

| Seite · Aussage | Beleg | Ergebnis |
|---|---|---|
| `/` Hero: Xtream oder M3U-Datei, 17.000 Sender durchsuchbar (`app/page.tsx:30-32`) | v1.1 Reiter „Xtream“, „URL“, „Datei“; B04 AK-33/34 | stimmt |
| `/` Multiview-Bildunterschrift, MPEG-TS bleibt schwarz bis Raster und zurück (`:44-47`) | B08 BUG-02 (Code gleich v1.1): Schwarzanteil 0,00 → 1,00, HLS 0,00, erst Raster ↔ Fokus bringt das Bild | stimmt |
| `/` „The app adds … two playback engines … no account, no cloud“ (`:66-67`) | v1.1 `StreamType`, Sonde; keine Cloud (Satz 15) | stimmt |
| `/` „It never does … send anything to the people who make it … talks to the servers your playlist names and to GitHub“ (`:73-79`) | Datenschutz Satz 1–2; Weiterleitungsziele nennt die verlinkte Datenschutzseite | stimmt |
| `/` Messwerte 0,9 s bzw. 0,3–0,6 s (`:115-120`) | B04 BUG-13 (Release): Öffnen 681/895 ms, Suchfeld leeren 304–444 ms, Chip abwählen 565 ms, erstes Zeichen 153–312 ms | stimmt gerundet; erstes Zeichen teils unter 0,3 s → H-12 |
| `/` ⊞-Knopf, Multiview-Abschnitt, nur der Fokus hat Ton (`:123`, `:164-166`) | v1.1 `ChannelRowView.multiviewButton`, `MultiviewSession.maxSlots = 4`, `setMuted(index != focusedIndex)` | stimmt |
| `/` Universal, DMG, Oberfläche Deutsch (`:183-184`) | `lipo -info` am DMG-Binary: `x86_64 arm64`; v1.1 ohne `.lproj` | stimmt |
| `/` iPhone/iPad: baut für iOS 17, nicht verteilt (`:197-198`) | v1.1 `project.yml` `iOS: "17.0"`; einziges Release hat nur ein DMG; B06 iOS-Simulator-Lauf | stimmt |
| `/` „full source is on GitHub“ (`:206`) | API `private: False` | stimmt (Lizenz OF-09) |
| Funktionen (`content/features.ts`) — sieben Stück | je Test in `qa2.release-claims.test.mjs` (Engine, Tasten, Favoriten, Doppelklick, Sprache, Updates); B01 BUG-12 / B02 BUG-04 für die Importdauer | stimmen; „arrow keys“ meint nur ↑/↓ → H-9; „Many panels block get.php and HLS“ → **BUG-17** |
| Einrichtung „Datei (file)“, Name optional (`content/setup-steps.ts:12`) | v1.1 `case file = "Datei"`, „Name (optional)“ | stimmt |
| FAQ Gatekeeper (`content/faq.ts:10`) | DMG-App `adhoc`, `spctl` → `rejected`; Weg laut Apple-Quellen (Build-Bericht Teil 1) | stimmt; Klickweg nicht ausgeführt (wie Durchlauf 1) |
| FAQ Formate, Xtream-Fehler, MPEG-TS (`:20-30`) | Sonde (`tvg-id`, `tvg-logo`, `group-title`, Name mit Komma; `.ts`/`.mpegts`/`.mts`/`.m2ts` → `transportStream`) | stimmt; „often with an HTTP 407“ → **BUG-17** |
| FAQ Listengröße: etwa 4½ min Import/Aktualisieren, bis etwa 2 min Löschen (`:35`) | B01 BUG-12 285,0 s, B02 BUG-04 ≈ 282 s, B03 BUG-01 280,5 s bzw. 132,6 s | stimmt gerundet (≈ 4¾ bzw. 2¼ min) → H-12 |
| FAQ „Where does my data go?“ (`:40`) | Datenschutz Satz 1–35 | stimmt; „lists every detail“ → BUG-13, BUG-14 |
| FAQ „How do updates arrive?“: „If there is one, it shows the release notes“ (`:50`) | `appcast.xml` ohne `<description>` und ohne `releaseNotesLink` (HEAD und v1.1); B09 AK-06: Update-Fenster „ohne Versionshinweise, weil der Feed keine enthält“ | **falsch → BUG-15**; Rest (Installieren/Überspringen/Später, Kontrollkästchen, EdDSA, Menüeintrag) stimmt |
| Support: Name `MikaPlusPlayer`, Schritte, Tastatur, Rückmeldung (`app/support/page.tsx`) | DMG `CFBundleName`, v1.1 `PlayerView` (Tests `qa2::Tastatur`, `qa2::App-Name`) | stimmt; Reihenfolge Schritt 01/02 → H-10; Testliste → H-11 |
| Changelog: „does not read this page: Sparkle checks a separate update feed“ (`app/changelog/page.tsx:21`) | v1.1 `SUFeedURL` → `appcast.xml` mit nur 1.1 | stimmt |
| v1.1-Notizen inkl. „Known issue in 1.1“ (`content/changelog-overrides.ts`) | v1.1 `MultiviewScreen` (Kacheln oben rechts, Raster 2 × 2), B08 BUG-02 | stimmt |
| Fußzeile „An IPTV player with its source on GitHub“ | Repository öffentlich | stimmt |

## Durchlauf 2 · Akzeptanzkriterien im Einzelnen

Testdateien wie in Durchlauf 1 (`U`, `H`, `B`, `M`, `L`), dazu `Q` = `qa2.release-claims.test.mjs`, `I` =
`qa2.isr-outage.test.mjs`. „gewollt geändert“ = die Reparatur hat das beschriebene Ist absichtlich ersetzt; geprüft
wurde das neue Ist, der Spec-Wortlaut ist veraltet (H-1, OF-07/OF-08).

| AK | Ergebnis | Nachweis |
|---|---|---|
| AK-01 | ✅ bestanden | Build 2026-09-30: `/`, `/changelog` Revalidate `1h`/Expire `1y`, `ƒ /download`, übrige `○`, Exit 0, keine Warnung; `H::AK-01` |
| AK-02 | ✅ bestanden | `H::AK-02`; `curl -sI /changelog`: vier Header exakt, kein `X-Powered-By` (zusätzlich CSP, Permissions-Policy) |
| AK-03 | ✅ bestanden | `H::AK-03`; `/changelog` `s-maxage=3600, stale-while-revalidate=31532400` |
| AK-04 | ✅ bestanden | `H::AK-04`; `/.env`, `/package.json`, `/.next/BUILD_ID`, `/_next/static/..%2F..%2Fpackage.json` → 404 |
| AK-05 | ✅ bestanden | `B::AK-05`, `H::AK-05/AK-06/AK-07` |
| AK-06 | ✅ bestanden (gewollt geändert, FB-13 → OF-09) | `H::AK-05/AK-06/AK-07`: „An IPTV player with its source on GitHub. It plays the playlist you bring and is not affiliated with any provider.“, Links wie spezifiziert, kein Anbieter (BUG-03) |
| AK-07 | ✅ bestanden | `B::AK-07` |
| AK-08 | ✅ bestanden | `B::AK-08` |
| AK-09 | ✅ bestanden (gewollt geändert, BUG-06) | `H::AK-09`: Hero, „Download for macOS“ direkt auf das DMG, „Version 1.1 · 34.8 MB · macOS 14 Sonoma or later“, SHA-256; „First launch“ nennt Systemeinstellungen/Open Anyway statt Rechtsklick |
| AK-10 | ✅ bestanden | `B::AK-10` (Fokus und Raster, 0 Fremdanfragen), `H::AK-10` |
| AK-11 | ✅ bestanden (gewollt geändert, BUG-07) | `H::AK-11/AK-12`: Reihenfolge wie spezifiziert, „Seventeen thousand channels, searchable“, **sieben** Funktionen (Library 3, Playback 2, System 2) |
| AK-12 | ✅ bestanden | `H::AK-11/AK-12` |
| AK-13 | ✅ bestanden | `H::AK-13` |
| AK-14 | ✅ bestanden | `H::AK-14`; `curl`: `?url=https://evil.example`, `?redirect=//evil.example` → 302 auf das v1.1-DMG; `POST/PUT/DELETE/PATCH` → 405 |
| AK-15 | ✅ bestanden | `M::AK-15`; echtes GitHub: `rate_limit.core.remaining` vor/nach 6 Aufrufen 38 → 38, nach 60 parallelen 38 |
| AK-16 | ✅ bestanden (gewollt geändert, BUG-08) | `U::AK-16/EC-03`: neues Release ohne DMG → dessen Release-Seite, kein v1.1-Link |
| AK-17 | ✅ bestanden | `U::AK-14/AK-17`, `U::AK-17` |
| AK-18 | ✅ bestanden (gewollt geändert, BF-16) | `H::AK-18/AK-19`, `M::AK-18/EC-04`: Satz „The Mac app does not read this page …“, Entwurf fehlt, Vorabversion bleibt, Reihenfolge der API, Links |
| AK-19 | ✅ bestanden | `U::AK-19`, `M::AK-18/EC-04` |
| AK-20 | ✅ bestanden | `M::AK-20` |
| AK-21 | ✅ bestanden | `H::AK-21` |
| AK-22 | ✅ bestanden (gewollt geändert, BUG-06/BUG-07) | `H::AK-22/AK-23`: fünf Erststart-Schritte mit `MikaPlusPlayer`, drei Einrichtungsschritte, Beispiel-Link, **fünf** Tasten ohne P, neun Fragen |
| AK-23 | ✅ bestanden | `B::AK-23`, `B::AK-23/EC-11` |
| AK-24 | ✅ bestanden (gewollt geändert, BUG-02) | `H::AK-24/AK-25/AK-26`: Abschnitte in Reihenfolge, zusätzlich „Removing everything“ und „Stream servers.“, „Last updated 30 September 2026“, „a GitHub issue“. Inhaltliche Lücken: BUG-13, 14, 17 |
| AK-25 | ✅ bestanden | Seitentext per `H`, `Q::Xtream über HTTP`; v1.1-Sonde: `https://…:8443` → `http://…:8443`, Zugangsdaten in allen 3 Anfragen im Klartext |
| AK-26 | ✅ bestanden (lokal) | Wortlaut per `H`; lokal kein Cookie, keine Fremdressource (AK-35, AK-36); live → BUG-01 |
| AK-27 | ✅ bestanden | `H::AK-27/AK-28` |
| AK-28 | ✅ bestanden | `H::AK-13/27/29`, `U::AK-28/EC-09` |
| AK-29 | ✅ bestanden | `H::AK-28/AK-29` |
| AK-30 | ✅ bestanden | `H::AK-30` |
| AK-31 | ✅ bestanden | `U::AK-31` ×2, `M::AK-31/AK-37` |
| AK-32 | ✅ bestanden (gewollt geändert, BUG-08) | Kopie, `GITHUB_TOKEN=invalid` gegen das echte GitHub: `[releases] /repos/daumedia/MikaPlusPlayer/releases?per_page=20 -> 401; rate limit remaining: null` und dieselbe Zeile für `/releases/latest`, Exit 0; Ersatz ist jetzt „Latest release on GitHub“ bzw. der Changelog-Hinweis statt v1.1 |
| AK-33 | ✅ bestanden (gewollt geändert, BUG-08) | Kopie, `api.github.invalid`: 2 × `[releases] request failed: … [TypeError: fetch failed] { [cause]: Error: getaddrinfo ENOTFOUND …`, Exit 0, Ersatz wie AK-32 |
| AK-34 ⚠ | ✅ bestanden (Befund behoben) | `M::AK-34`, `M::AK-34/FB-21`; Kopie mit `api.github.invalid`: 6 Aufrufe → 6 × 302 auf `…/releases/latest`, **1** Warnzeile statt 6. Limit je Client weiter offen (BUG-04, OF-06) |
| AK-35 | ✅ bestanden (lokal) | `H::AK-35`; live → BUG-01 |
| AK-36 | ✅ bestanden | `B::AK-36`, `H::AK-36` |
| AK-37 | ✅ bestanden | `B::AK-37`, `H::AK-37` |
| AK-38 | ✅ bestanden | `H::AK-38`, `M::AK-38`; `grep -rlE 'GITHUB_TOKEN|api\.github\.com|x-ratelimit' .next/static` → 0; `git log -p --all -- web/` (4 Commits): nur `GITHUB_TOKEN=invalid` im README, kein `ghp_`/`github_pat_`; `.env*` in `.gitignore` |
| AK-39 | ✅ bestanden | `U::AK-32/AK-39`, `U::AK-39`, `M::AK-39`; Serverprotokolle unten |
| AK-40 | ✅ bestanden | `H::AK-40`; `curl` fremde und Traversal-URL → 400 |
| AK-41 | ✅ bestanden | `H::AK-41` |

## Durchlauf 2 · Edge Cases

| EC | Ergebnis | Nachweis |
|---|---|---|
| EC-01 | ✅ belegt (gewollt geändert) | `M::AK-34/FB-21` (Mock 403, `x-ratelimit-remaining: 0`): Seiten und `/download` auf die Release-Seite, höchstens 1 Anfrage je Fenster; Vercel selbst nicht beobachtet |
| EC-02 | ✅ belegt (**neu ausgeführt**) → BUG-16 | `I::EC-02`, Kopie mit Revalidate 4 s: nach dem Build DMG-Link, Prüfsumme, 1 Changelog-Eintrag; ein 503 bei der Neuberechnung → beide Schaltflächen `…/releases/latest`, **keine Prüfsumme**, 0 Einträge, Changelog-Hinweis; nach der Erholung wieder DMG-Link. Mock-Folge: `per_page=20=200, latest=200, latest=503, per_page=20=503, latest=200, per_page=20=200`. Vorab dasselbe von Hand mit `x-nextjs-cache: HIT` beobachtet |
| EC-03 | ✅ belegt (gewollt geändert) | `U::AK-16/EC-03` |
| EC-04 | ⚠️ nicht prüfbar | Website-Teil: `M::AK-18/EC-04`; dass `/` und `/download` Vorabversionen auslassen, liegt bei GitHubs `releases/latest`, ohne echte Vorabversion nicht beobachtbar |
| EC-05 | ⚠️ nicht prüfbar | ein einziges Release; `per_page=20` per `U::AK-18/EC-04` |
| EC-06 | ✅ belegt | `M::AK-20`, `U::AK-19` |
| EC-07 | ✅ belegt (Befund behoben) | `M::EC-07`: 0 × `node=` |
| EC-08 | ✅ belegt | Kopie mit totem Proxy: `next/font: error: Failed to fetch Archivo / IBM Plex Mono / IBM Plex Sans from Google Fonts.`, `Turbopack build failed with 3 errors`, Exit 1 |
| EC-09 | ✅ belegt | `H::AK-27/AK-28`, `U::AK-28/EC-09` |
| EC-10 | ⚠️ nicht prüfbar | Vercel-Vorschau nicht zugänglich |
| EC-11 | ✅ belegt | `B::AK-23/EC-11` |
| EC-12 | ✅ belegt | Build mit Node 26.10.0 (außerhalb `engines`), Exit 0, keine Warnung |
| EC-13 | ✅ belegt | `U::EC-13` |
| EC-14 | ✅ belegt | `U::EC-14` |
| EC-15 | ✅ belegt (gewollt geändert, BUG-08) | Ohne Release-Daten zeigt die Schaltfläche jetzt auf die Release-Seite (Kopien AK-32/AK-33) — die Spec-Aussage „fällt nie zurück“ gilt nicht mehr |

## Durchlauf 2 · Sicherheitsprüfung

| Prüfung | Ergebnis | Beleg |
|---|---|---|
| 1 · Fremder Zugriff (IDOR) | bestanden (keine Datensätze; Parameter manipuliert) | `/download?url=https://evil.example`, `?redirect=//evil.example` → 302 aufs DMG; `/_next/image?url=https://evil.example/x.png` → 400; `…url=%2F..%2F..%2Fetc%2Fpasswd` → 400 |
| 2 · Zugriffsregeln serverseitig | bestanden | `/.env`, `/package.json`, `/.next/BUILD_ID`, `/_next/static/..%2F..%2Fpackage.json` → 404; `POST/PUT/DELETE/PATCH /download` → 405; `*.js.map` → 404 (`H::AK-38`) |
| 3 · Rate Limit | **BUG-04 (Teil)** | 60 parallele `/download` → 60 × 302, kein 429; GitHub-Seite geschützt: 0 Anfragen im Erfolgsfall (38 → 38), 1 je Fenster im Fehlerfall |
| 4 · Personendaten in Protokollen | bestanden | Serverprotokoll nach dem Gesamtlauf mit Fuzzing (7 Zeilen): nur Startmeldungen und zwei abgewiesene Bildanfragen (`/download`, `/../../etc/passwd`), keine IP, kein User-Agent, kein Cookie; `M::AK-39`: Token und Besucher-Marker weder im Build- noch im Serverprotokoll; Warnzeilen nur Pfad/Status/Restkontingent bzw. Fehlerobjekt |
| 5 · Personendaten an externe Dienste | bestanden | Tatsächlicher Payload am GitHub-Mock (`M::AK-31/AK-37`): nur feste Header und Bearer-Token, Pfad ohne Query, 0 Besucher-Marker; Browser: Download-Klick sendet an GitHub nur `Referer` = Ursprung (`B::AK-37`) |
| 6 · Geheimnisse | bestanden | `.next/static` ohne Token/API-Host/`x-ratelimit`; Git-Verlauf `web/` ohne Token; `.env*` ignoriert; einzige `NEXT_PUBLIC_`-Variable ist die Site-URL |
| 7 · Eingaben | bestanden | `H::Angriff/Eingaben` (leer, 10.000 Zeichen, Emoji, SQL, `<script>`, Traversal × 5 Routen): kein 5xx, keine Reflexion. `/opengraph-image?title=<svg onload=…>&x=<script>` → byte-gleich zur Anfrage ohne Query (SHA-256 `65565e49…`), `x-nextjs-cache: HIT` |
| 8 · Löschen | trifft nicht zu / **BUG-03** | Website speichert nichts; für Vercel-Logs kein Auskunfts- oder Löschweg außer öffentlichen Issues |
| CSP im Browser | bestanden | `B::FB-20`: 0 Verstöße auf 4 Seiten, 0 Konsolenfehler |
| `/download` bei GitHub-Störung | bestanden | siehe BUG-04, AK-34 |
| Sicherheits-Header | bestanden | sechs Header auf allen Routen (`H::AK-02`, `H::FB-20`) |
| Abhängigkeiten | **BUG-12** | `npm audit --omit=dev`: 1 kritisch (`next`, GHSA-vcvr-r3jv-pc5j). Mit Dev-Abhängigkeiten zusätzlich hoch: `brace-expansion` (GHSA-q2hr-2g5m-vwhr u. a.), `js-yaml` 4.0.0–4.3.1 — nur über ESLint, nicht im Produktionsbaum → H-13 |
| Live-Umgebung | **BUG-01** | siehe oben |

## Durchlauf 2 · Neue Fehler

### BUG-12 · `next` 16.3.3 mit kritischer Advisory GHSA-vcvr-r3jv-pc5j — mittel

**Betrifft:** Katalog 4 (Abhängigkeiten); Nachfolger von BUG-05 · Test `Q::BUG-12 (Soll)` (`todo`)
**Reproduktion:** `cd web && npm audit --omit=dev` → `next 16.2.0 - 16.3.5 · Severity: critical · Next.js: Remote Code
Execution in next/og ImageResponse · GHSA-vcvr-r3jv-pc5j`. Advisory vom 2026-09-22, CVSS 9.5, behoben ab 16.3.6. `npm`
schlägt 16.3.8 vor, außerhalb der exakten Pinnung `"next": "16.3.3"` (`web/package.json:15`).
**Angriffsfläche**, ausgeführt, kein Exploit:
- Laut Advisory ist nur die Node-Implementierung von `ImageResponse` betroffen, und nur wenn angreiferkontrollierte Werte
  in SVG-Inhalt, Attribute oder Stile gelangen.
- Die Seite nutzt `ImageResponse` genau einmal (`web/app/opengraph-image.tsx`) mit festen Werten und statischem Rendering
  (`○ /opengraph-image`).
- `curl` mit `?title=<svg onload=…>&x=<script>` → byte-gleiche Antwort, `x-nextjs-cache: HIT`.

**Erwartet:** Keine Produktionsabhängigkeit mit bekannter kritischer Lücke, für die ein Patch existiert (Maßstab aus BUG-05).
**Tatsächlich:** Die Lücke ist heute nicht erreichbar. Jede künftige Vorschaubild-Route mit Parametern, zum Beispiel ein
Vorschaubild je Release, würde sie öffnen.
**Ort:** `web/package.json:15`, `web/package-lock.json`
**Vorschlag:** `next` und `eslint-config-next` auf ≥ 16.3.6 anheben, danach `npm audit --omit=dev` erneut.

### BUG-13 · Datenschutzseite verschweigt macOS-Version und Stream-Kopfzeilen — niedrig

**Betrifft:** AK-24 (Inhalt), Katalog 1/2 · Nachfolger von BF-12 · Test `Q::BUG-13 (Soll)` (`todo`)
**Reproduktion:**
1. Kopfzeilen-Sonde (Bundle wie v1.1) gegen lokalen Mock: `URLSession` → `User-Agent: MikaPlusPlayer/2
   CFNetwork/3896.100.1.1.1 Darwin/27.0.0`, `Accept-Language: de-DE,de;q=0.9`. Die v1.1-Sonde sendet an das Xtream-Panel
   ebenso `… Darwin/27.0.0`.
2. `AVURLAsset` auf eine `.m3u8`-Adresse, nur geladen, nicht abgespielt: `User-Agent: AppleCoreMedia/1.0.0.26A428
   (Macintosh; U; Intel Mac OS X 27_0; de_de)`, dazu `Accept-Language` und `x-playback-session-id`.
3. VLC laut B06 AK-32: `VLC/3.0.21 LibVLC/3.0.21` mit `Accept-Language`. VLCKit 3.0.21 steckt auch im v1.1-DMG.
4. `/privacy` lesen: Der Abschnitt „What the app connects to“ nennt App, Build und „the version of macOS’s network
   components“. „Stream servers.“ nennt nur IP-Adresse und Sender.

**Erwartet:** Die Seite nennt, was die Kopfzeilen tatsächlich verraten.
**Tatsächlich:** Die macOS-Version (`Darwin/27.0.0` bzw. `Mac OS X 27_0` samt Build) fehlt überall. Bei Streams fehlen
Sprache und Player-Version.
**Ort:** `web/app/privacy/page.tsx:123-126`, `:139-142`
**Vorschlag:** In beiden Absätzen macOS-Version und Sprache nennen, bei Streams zusätzlich den Player (AVFoundation bzw. VLC).

### BUG-14 · Löschweg und Speicherliste unvollständig — niedrig

**Betrifft:** AK-24 (Inhalt), Katalog 5 · Nachfolger von FB-04 · Test `Q::BUG-14 (Soll)` (`todo`)
**Reproduktion:**
1. B06-Release-Lauf `qa/REL-10-release-lauf-protokoll.txt`: Nach der Wiedergabe liegt `Library/Preferences/<Bundle-ID>/vlcrc`
   im QA-Home. libVLC legt den Ordner an, VLCKit 3.0.21 wie im v1.1-DMG.
2. Auf diesem Mac existiert `~/Library/Preferences/lu.daumedia.MikaPlusPlayer/` mit `vlcrc` und `vlcrc.55948`. Nur die
   Namen gelistet.
3. `/privacy`, „Removing everything“: nennt nur `…/Preferences/lu.daumedia.MikaPlusPlayer.plist`.
4. v1.1 `Playlist.swift` speichert zusätzlich `createdAt` und `lastRefreshed`, `Channel.swift` die `tvgID`. „What the app
   stores“ zählt sie nicht auf.

**Erwartet:** Unter der Überschrift „Removing everything“ steht jeder Ort, den v1.1 anlegt, und die Aufzählung der
Datenbank nennt auch die Zeitpunkte von Import und Aktualisierung.
**Tatsächlich:** Nach dem beschriebenen Löschweg bleibt der Ordner mit `vlcrc` stehen. Laut B06 enthält er nur
Audiogerät und Lautstärke. Die Nutzungszeitpunkte in der Datenbank werden nicht erwähnt.
**Ort:** `web/app/privacy/page.tsx:54-56`, `:95-110`
**Vorschlag:** Den Ordner `~/Library/Preferences/lu.daumedia.MikaPlusPlayer/` in beide Listen aufnehmen und die Aufzählung um
„when you added and last refreshed each playlist“ und die tvg-id ergänzen.

### BUG-15 · FAQ verspricht Versionshinweise im Update-Fenster — niedrig

**Betrifft:** Katalog 2 (Transparenz des Update-Wegs) · Nachfolger von BF-16 · Test `Q::BUG-15 (Soll)` (`todo`)
**Reproduktion:**
1. `/support` → „How do updates arrive?“: „If there is one, it shows the release notes and you choose …“.
2. `appcast.xml` (Arbeitsbaum und `v1.1`): kein `<description>`, kein `sparkle:releaseNotesLink`.
3. `scripts/release.sh` erzeugt keine Notizen.
4. B09 AK-06 hat das Fenster beobachtet: „ohne Versionshinweise, weil der Feed keine enthält“.

**Erwartet:** Die FAQ beschreibt das Update-Fenster so, wie es erscheint.
**Tatsächlich:** Das Fenster zeigt keine Versionshinweise.
**Ort:** `web/content/faq.ts:50`
**Vorschlag:** „shows the release notes“ streichen oder auf den Changelog verweisen. Alternativ Notizen in den Feed
aufnehmen (B09).

### BUG-16 · Ein GitHub-Fehler bei der Neuberechnung entfernt Prüfsumme, DMG-Link und Changelog — niedrig

**Betrifft:** EC-02, EC-01, BUG-06 (Prüfschritt) · Test `I::BUG-16 (Soll)` (`todo`), Beleg `I::EC-02`
**Reproduktion:**
1. `node --test --test-timeout=300000 tests/qa2.isr-outage.test.mjs`. Die Kopie hat Revalidate 4 s statt 3600 s.
2. Nach dem Build mit gesundem Mock: DMG-Link, SHA-256, 1 Changelog-Eintrag.
3. Mock liefert 503; nach Ablauf löst ein Abruf die Neuberechnung aus.
4. Danach: beide Schaltflächen auf `…/releases/latest`, keine Prüfsumme, 0 Changelog-Einträge.
5. Erst eine spätere erfolgreiche Neuberechnung stellt den alten Zustand wieder her.

**Erwartet:** Support-Schritt 02 verweist auf „the SHA-256 shown under the download button on the home page and in the
changelog“. Ein einzelner Fehler sollte den letzten guten Stand stehen lassen.
**Tatsächlich:** Im Produktcode fehlen Prüfsumme und Direktlink bis zur nächsten erfolgreichen Neuberechnung, also
mindestens eine Stunde. Ohne `GITHUB_TOKEN` auf geteilten Vercel-IPs (EC-01, OF-06) kann das der Dauerzustand sein. Der
Support-Schritt ist dann nicht ausführbar, die Seite sagt nicht, wo die Prüfsumme sonst steht. Die GitHub-Release-Seite
zeigt sie, belegt im Build-Bericht Teil 1.
**Ort:** `web/lib/releases.ts:119-122,150-157` (Fehler → `null`, Seite rendert den Ersatzzustand), `web/app/page.tsx:15`,
`web/app/changelog/page.tsx:14`
**Vorschlag:** Bei einer Neuberechnung einen GitHub-Fehler als Fehler werfen, damit Next.js die letzte gute Seite behält; nur
beim Build auf den Ersatzzustand gehen. Alternativ im Ersatzzustand auf die Prüfsumme der GitHub-Release-Seite verweisen.

### BUG-17 · Xtream-Abschnitt schiebt die erzwungene HTTP-Umschreibung auf die Panels; unbelegte Anbieteraussagen — niedrig

**Betrifft:** AK-25 (Inhalt), Katalog 1 · Kein automatischer Test (Wortlaut)
**Reproduktion:**
1. `/privacy`: „rewrites an https:// host to plain HTTP, because most panels serve nothing else. … That is a property of
   IPTV panels rather than a choice we would defend“.
2. v1.1-Sonde: Eingabe `https://127.0.0.1:<Port>` → die App spricht das Panel über `http://` an, Zugangsdaten in allen
   3 Anfragen im Klartext. Das gilt auch für ein Panel, das HTTPS kann; B01 BUG-02 belegt dasselbe.
3. „most panels serve nothing else“ (`/privacy`), „Many panels block get.php and HLS“ (`/`) und „often with an HTTP 407“
   (FAQ): Im Projekt ist genau ein Anbieter dokumentiert, ein Code-Kommentar zu Telecasty.

**Erwartet:** Die Seite nennt die Umschreibung als Entscheidung der App, und Aussagen über Anbieter sind belegt oder als
Erfahrung gekennzeichnet.
**Tatsächlich:** Der Klartext-Versand wird als Eigenschaft der Panels dargestellt, obwohl v1.1 ihn selbst erzwingt.
**Ort:** `web/app/privacy/page.tsx:170-178`, `web/content/features.ts:29`, `web/content/faq.ts:25`
**Vorschlag:** „Version 1.1 always uses plain HTTP for Xtream, even if the panel supports HTTPS“ und die Panel-Aussagen als
„some panels we tested“ fassen.

## Durchlauf 2 · Hinweise (kein Fehler)

- **H-1 · Spec-Wortlaut veraltet (bestätigt OF-07/OF-08).** AK-06, AK-09, AK-11, AK-16, AK-18, AK-22, AK-24, AK-32 und
  AK-33, dazu EC-01, EC-03 und EC-15, beschreiben den Stand vor der Reparatur. Das neue Ist ist oben geprüft und bestanden.
  AK-34 ⚠ beschreibt einen behobenen Fehler. Vorschlag zur Neufassung für `/sdd-klaeren`:
  - AK-06: Fußzeile „An IPTV player with its source on GitHub …“
  - AK-09 und AK-22: Erststart über Systemeinstellungen samt SHA-256-Schritt, `MikaPlusPlayer`, fünf Tasten
  - AK-11: sieben Funktionen, „searchable“
  - AK-16, AK-32, AK-33, EC-15: Release-Seite statt v1.1
  - AK-18: neuer Satz zum Update-Weg
  - AK-24: Abschnitte inkl. „Removing everything“, vier Empfängerpunkte, Datum
  - AK-34: höchstens eine Anfrage je 5-Minuten-Fenster
  - OF-01 ist gegenstandslos.
- **H-2** Weiterleitung „credentials included“ gilt, wenn die Zieladresse Pfad und Query übernimmt. So ist es in B01 BUG-10
  und B02 AK-11 reproduziert. URLSession fügt nichts hinzu.
- **H-3** „every time you open the Favourites tab“ ist mit Logo-Antworten ohne Cache-Freigabe belegt (B05 BUG-03). Bei
  cachebaren Logos kann die Anfrage entfallen.
- **H-4** „Any program running under your macOS user account“: Programme in der Sandbox erreichen die Datei nicht. Die
  Warnung ist vorsichtig überzeichnet.
- **H-5** Der Update-Download geht an `github.com` und wird per 302 auf `release-assets.githubusercontent.com` umgeleitet.
- **H-6** `/download` „forwards to the newest file“: Bei Störung oder ohne DMG leitet er auf die Release-Seite.
- **H-7** macOS legt den Fensterzustand unter `$TMPDIR/lu.daumedia.MikaPlusPlayer.savedState` ab, auf diesem Mac vorhanden
  (nur Namen). Dazu kommen Systemcaches unter `DARWIN_USER_CACHE_DIR/lu.daumedia.MikaPlusPlayer`. v1.1 setzt Playlist- und
  Sendernamen als Fenstertitel (`navigationTitle`). Ob der Titel im Zustand steht, ist ohne Lesen von Nutzerdaten nicht
  belegt. Das System leert `$TMPDIR` selbst.
- **H-8** `Accept-Language` bei Sparkle-Anfragen ist nicht mitgeschnitten, B09 protokollierte nur den User-Agent.
- **H-9** „arrow keys“ in „Hands on the keyboard“ meint nur ↑/↓, ←/→ tun nichts. Die Tastentabelle ist genau.
- **H-10** Support-Schritt 01 „Open the DMG and drag …“ steht vor Schritt 02 „Check the download before you open it“. Die
  Prüfung schützt so den Start der App, nicht das Einhängen des DMG.
- **H-11** Die empfohlene Testliste `iptv-org…/index.m3u` hat am 2026-09-30 11.023 Einträge auf 4.249 Stream-Hosts (per GET
  gezählt). Nach der B02-Messreihe (6.000 → 35 s, 17.000 → 282 s) friert v1.1 beim Import deutlich über eine Minute ein.
  Neben der Empfehlung steht kein Hinweis darauf.
- **H-12** Die Messwerte sind gerundet:
  - erstes Zeichen 0,15–0,31 s statt „0.3 to 0.6“
  - Import 282–285 s, also eher 4¾ als „four and a half“ Minuten
  - Löschen bis 132,6 s statt „about two minutes“
- **H-13** Nur Dev-Abhängigkeiten, nicht im Produktionsbaum: `brace-expansion` (GHSA-q2hr-2g5m-vwhr, GHSA-qhr7-859c-m2p7,
  GHSA-6j4f-fj2g-mc7p) und `js-yaml` 4.0.0–4.3.1 (hoch).
- **H-14** Das Code-Review (Konfidenz < 80, nicht als Fehler geführt) merkt an: `toRelease()` hat keine Formprüfung. Eine
  200-Antwort ohne `tag_name` würde `/download` mit 500 beenden. Dafür müsste die GitHub-API fehlerhaft antworten.
- **H-15** Weiterhin offen und korrekt als Nutzerfrage geführt:
  - OF-11: Absturz im Multiview-Raster beim Schließen oder Entfernen, B08 BUG-01, kritisch, in v1.1 enthalten
  - v1.1 mit `get-task-allow=true` (B09 BUG-02) ist das Release, auf das `/download` regulär zeigt

## Durchlauf 2 · Code-Review

Der `code-reviewer`-Agent hat die Änderungen an `web/` seit `c01f1cf` geprüft (Teil 1 und Teil 2, samt geänderter
Tests). Dabei hatte er `design.md`, `build-bericht.md` und `spec.md` als Stand. Er fand **keine** Befunde mit Konfidenz ≥ 80.
Ausdrücklich geprüft hat er:
- Fehlerfenster und geteilte Anfrage in `getLatestReleaseForDownload` (ohne Wettlauf)
- Weiterleitungsziele von `/download` (nur aus der API und einer Konstante)
- CSP-Abdeckung
- `withoutNode()`
- Metadaten der Unterseiten
- Widerspruchsfreiheit der Texte über die Seiten hinweg
- keine aufgeweichten Zusicherungen in den Tests

Sein einziger Nebenfund steht als H-14 oben. Die Befunde BUG-12 bis BUG-17 stammen aus der eigenen Prüfung.

## Durchlauf 2 · Neue Tests

Unter `web/tests/`, ohne neue Abhängigkeit. Der Aufruf steht jeweils im Dateikopf.

| Datei | Fälle | Deckt ab | Ausführen |
|---|---|---|---|
| `qa2.release-claims.test.mjs` | 16 (4 `todo`) | Datenschutzseite, Funktionen, FAQ, Support gegen `git show v<Version>:…`: Speicherort, Klartext, HTTP, Logo-Hosts, Update-Prüfung, Telemetrie, Engine-Wahl, Tastatur, App-Name, Doppelklick/Bild-in-Bild, Sprache, Favoriten; BUG-12, 13, 14, 15 | Server wie `site.http`, dann `BASE_URL=http://127.0.0.1:3941 node --test tests/qa2.release-claims.test.mjs` (braucht Git und den Tag) |
| `qa2.isr-outage.test.mjs` | 2 (1 `todo`) | EC-02 (neu belegt), BUG-16 | `node --test --test-timeout=300000 tests/qa2.isr-outage.test.mjs` — Temp-Kopie gegen lokalen Mock, ca. 30 s, räumt auf |

Die Version für den Abgleich liest `qa2.release-claims` aus `DESCRIBED_VERSION` in `app/privacy/page.tsx`. Beschreibt die
Seite ein neues Release, gleicht der Test automatisch gegen dessen Tag ab. Der Abgleich ist ein Baustein für OF-10.

Verifikation (Durchlauf 2):

```
npx tsc --noEmit            → tsc exit 0
npm run lint                → lint exit 0 (einschließlich der neuen Tests)
npm run build               → build exit 0 (Route-Tabelle wie AK-01, keine Warnung, GitHub erreichbar)
BASE_URL=http://127.0.0.1:3941 node --test --test-timeout=600000 tests/   → suite exit 0
ℹ /: CSP-Verstöße 0   ℹ /changelog: CSP-Verstöße 0   ℹ /privacy: CSP-Verstöße 0   ℹ /support: CSP-Verstöße 0
ℹ Konsole/Log/Netz: 0 Fehler oder Warnungen
ℹ im Fenster: 4 sequentielle Aufrufe → 0 Upstream-Anfragen; 60 parallele Aufrufe → 0 Upstream-Anfragen; Status: 302; neue Warnzeilen: 0
ℹ nach Ablauf des Fensters: 60 parallele Aufrufe → 1 Upstream-Anfrage(n)
ℹ tests 86
ℹ pass 79
ℹ fail 0
ℹ todo 7
```

Vorher (Build-Bericht Teil 2): 68 Tests, 66 bestanden, 2 `todo`. Die 18 neuen Tests: 13 bestanden, 5 `todo`
(BUG-12, 13, 14, 15, 16).

**Aufgeräumt:**
- `next start` auf 3941 beendet (Port antwortet nicht mehr), ebenso die Hilfsserver auf 3943, 3944 und 3945, die Mocks
  und `chrome-headless-shell`; keine übrigen Prozesse.
- Kopien `…/wt/b10qa2-copy`, `…/wt/b10qa2-neg` und der Worktree `…/wt/b10qa2-head` sind entfernt.
- Das v1.1-DMG ist ausgehängt (`dist/` unverändert).
- Die Temp-Kopien der Tests (`b10-qa-*`, `b10-qa2-isr-*`) sind weg.
- Die Sonden-Ordner unter `~/Library/Caches` und `~/Library/HTTPStorages` sind gelöscht.
- Die heruntergeladene Testliste ist gelöscht.
- Nicht angefasst: 8 leere `b10-src-*` in `$TMPDIR` aus einem früheren Lauf, schon im Build-Bericht Teil 2 als fremd
  vermerkt.

## Durchlauf 2 · Nächster Schritt

1. **`/sdd-klaeren B10`.** Zu entscheiden:
   - OF-04: öffentliche Adresse
   - OF-06: Vercel-Firewall-Limit und `GITHUB_TOKEN`
   - OF-07/OF-08: Neufassung der Kriterien, siehe H-1
   - OF-09: Lizenz
   - OF-10: Website-Abgleich im Release-Ablauf
   - OF-11: bekannte Fehler von v1.1 nennen
   - BUG-03: Name, Anschrift und nicht öffentliche Kontakt-E-Mail des Verantwortlichen, Speicherdauer der Vercel-Logs,
     Rechtsgrundlagen, Auftragsverarbeitung
2. **`/sdd-build B10`** mit BUG-12 bis BUG-17, dazu BUG-01 und BUG-03 nach den Entscheidungen. Bei BUG-01 gehört das
   Deployment der Teil-2-Texte in denselben Schritt wie das Abschalten des Schutzes. Sonst geht die alte, widerlegte
   Datenschutzseite von `47a90c3` online.
3. **`/sdd-qa B10`** (Durchlauf 3). **Die Erfassung wartet**, solange BUG-01 und BUG-03 (hoch) offen sind.

## Durchlauf 2 · Für befunde.md

| Befund | Grad | Fundstelle | BUG-Nr. | Status |
|---|---|---|---|---|
| BF-19 · Website öffentlich nicht erreichbar; neuestes Production-Deployment `47a90c3` ohne Teil-2-Texte | hoch | Vercel-Projekt, Repository-Homepage | BUG-01 | weiterhin offen |
| BF-20 · Datenschutzerklärung widerspricht dem App-Verhalten | hoch | `web/app/privacy/page.tsx`, `web/app/page.tsx`, `web/content/faq.ts` | BUG-02 | behoben 2026-09-30 (nicht ausgeliefert; Restlücken → BUG-13, 14, 17) |
| BF-21 · Pflichtangaben fehlen | hoch | `web/app/privacy/page.tsx`, `web/components/site-footer.tsx` | BUG-03 | weiterhin offen |
| BF-22 · `/download` ohne Cache im Fehlerfall und ohne Limit | mittel | `web/lib/releases.ts:124-147` | BUG-04 | weiterhin offen, nur noch Limit je Client (OF-06); Upstream-Teil behoben 2026-09-16 |
| BF-23 · `next` 16.2.12 mit kritischer Advisory | mittel | `web/package.json:15` | BUG-05 | behoben 2026-09-16 (Nachfolger BUG-12) |
| BF-24 · Gatekeeper-Anleitung, keine Prüfsumme | mittel | `web/app/support/page.tsx`, `web/components/gatekeeper-note.tsx`, `web/content/faq.ts` | BUG-06 | behoben 2026-09-16 (Website-Teil; Notarisierung → BF-03) |
| BF-25 · Werbeaussagen, die v1.1 nicht erfüllt | mittel | `web/content/features.ts`, `web/app/support/page.tsx`, `web/components/site-footer.tsx` | BUG-07 | behoben 2026-09-30 (Lizenz OF-09) |
| BF-26 · Ersatz-Release fest auf v1.1 | mittel | `web/lib/releases.ts` | BUG-08 | behoben 2026-09-16 |
| BF-27 · Keine CSP, keine Permissions-Policy | niedrig | `web/next.config.ts` | BUG-09 | behoben 2026-09-16 (Restrisiko OF-05) |
| BF-28 · `node="[object Object]"` in Release-Notizen | niedrig | `web/components/release-notes.tsx` | BUG-10 | behoben 2026-09-16 |
| BF-29 · Open-Graph der Unterseiten | niedrig | `web/lib/metadata.ts` | BUG-11 | behoben 2026-09-16 |
| BF-12 · (B09) User-Agent und automatische Prüfung nicht genannt | mittel | `web/app/privacy/page.tsx:155-162` | B09 BUG-12 | behoben 2026-09-30 (Nachfolger BUG-13) |
| BF-16 · (B09) Update-Weg ungenau | niedrig | `web/app/changelog/page.tsx:21`, `web/content/features.ts:43`, `web/content/faq.ts:50` | B09 BUG-16 | behoben 2026-09-30 (Nachfolger BUG-15) |
| BF-81 · (B04) „responds immediately“ widerlegt | mittel | `web/content/features.ts`, `web/app/page.tsx` | B04 BUG-13 | Website-Teil behoben 2026-09-30 (Texte = Messwerte); App-Leistung bleibt B04 |
| BF-103 · (B06) Rückmeldung für jede Taste versprochen | niedrig | `web/content/features.ts:39`, `web/app/support/page.tsx:146` | B06 BUG-05 | Website-Teil behoben 2026-09-30 |
| BF-107 · (B07) Bild-in-Bild beworben | mittel | `web/content/features.ts` | B07 BUG-04 | Website-Teil behoben 2026-09-30 (Bild-in-Bild nicht mehr beworben) |
| `next` 16.3.3 mit kritischer Advisory GHSA-vcvr-r3jv-pc5j (RCE in `next/og`), heute nicht erreichbar | mittel | `web/package.json:15` | BUG-12 | neu |
| Datenschutzseite verschweigt macOS-Version im User-Agent und Kopfzeilen der Stream-Anfragen | niedrig | `web/app/privacy/page.tsx:123-126,139-142` | BUG-13 | neu |
| Löschweg ohne `~/Library/Preferences/lu.daumedia.MikaPlusPlayer/` (vlcrc); Speicherliste ohne Import-/Aktualisierungszeitpunkte | niedrig | `web/app/privacy/page.tsx:54-56,95-110` | BUG-14 | neu |
| FAQ verspricht Versionshinweise im Update-Fenster, Feed enthält keine | niedrig | `web/content/faq.ts:50` | BUG-15 | neu |
| Ein GitHub-Fehler bei der ISR-Neuberechnung entfernt Prüfsumme, DMG-Link und Changelog bis zur nächsten Neuberechnung | niedrig | `web/lib/releases.ts:119-122,150-157` | BUG-16 | neu |
| Erzwungene HTTP-Umschreibung als Eigenschaft der Panels dargestellt; unbelegte Anbieteraussagen | niedrig | `web/app/privacy/page.tsx:170-178`, `web/content/features.ts:29`, `web/content/faq.ts:25` | BUG-17 | neu |

**Muster:**
- „Außendarstellung läuft dem Code voraus“ (BF-12, BF-16, BF-20, BF-25, BF-26) hat sich umgekehrt. Die Seite ist jetzt fest
  an v1.1 gebunden, die Schaltfläche folgt aber jedem neuen Release (OF-10). `qa2.release-claims.test.mjs` hält die
  Aussagen gegen den beschriebenen Tag und ist der erste technische Baustein für den fehlenden Abgleichschritt.
- „Logos als stiller Datenabfluss“ (BF-78, 79, 88, 20): Die Datenschutzseite benennt ihn jetzt. Verbleibend ist die
  macOS-Version in allen Kopfzeilen (BUG-13).

---

# Durchlauf 1 · 2026-09-15 (unverändert, mit den Vermerken aus `sdd-build` Teil 1 und Teil 2)

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

**Nicht behoben (Teil 2, 2026-09-30):** Weiter eine Vercel-Einstellung (Deployment Protection, Domain) und die
Repository-Homepage auf GitHub; beides schließt der Auftrag aus, die öffentliche Adresse entscheidet der Nutzer (OF-04).
Nachstellung am 2026-09-30 (`L::FB-15`, weiter `todo`): `mikaplus-player.vercel.app/privacy` → 404
`DEPLOYMENT_NOT_FOUND`; das neueste Production-Deployment (`mikaplus-player-6lgqlbhlm-daumedia.vercel.app`) → 302 auf
`vercel.com/sso-api` mit `_vercel_sso_nonce`; `mikaplusplayer.com` → `ENOTFOUND`. Die jetzt korrigierte
Datenschutzerklärung (BUG-02) ist damit weiter für niemanden abrufbar.

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

**Behoben 2026-09-30 (Teil 2):** Maßstab ist das Release, das man herunterladen kann: v1.1 (Tag `v1.1`,
`appcast.xml`, `dist/MikaPlusPlayer-v1.1.dmg`). Die Reparaturen aus B01 (Schlüsselbund, eigener Speicherort,
Cache) liegen nur auf `main` bzw. im Arbeitsbaum und sind **nicht** veröffentlicht. Die Seite beschreibt deshalb
v1.1 und sagt das. Künftige Verbesserungen erwähnt sie nicht.

Jede Aussage ist gegen `git show v1.1:…` abgeglichen. Unverändert gegenüber `c01f1cf` sind dort Speicher-, Netz- und
Listencode (`git diff v1.1 c01f1cf -- Sources`: nur Bild-in-Bild-Code, drei Überschriften, ein Kommentar, App-Symbol und `Info.plist` mit Anzeigename und Feed).
Die Messwerte stammen aus den Durchläufen 1 von B01, B02, B03, B04, B05, B08 und B09.

Geändert:
- **`web/app/privacy/page.tsx`**, neu geschrieben, Aufbau nach AK-24 erhalten:
  - *Kurzfassung* (`:34`): kein Konto, keine Telemetrie, nichts an die Hersteller. Sie nennt aber alle Empfänger und
    die unverschlüsselt gespeicherten Zugangsdaten. Geltungsbereich „version 1.1 of the Mac app“, Link auf den
    Quelltext `tree/v1.1`.
  - *What the app stores* (`:52`):
    - `~/Library/Application Support/default.store`, nicht verschlüsselt, kein Schlüsselbund (B01 BUG-01/04).
    - Xtream-Benutzer und -Passwort im Klartext in der Playlist-Adresse und in jeder Sender-Adresse; M3U-Link samt
      Token (B02 BUG-01).
    - für jeden Prozess des Benutzers lesbar, in Time Machine enthalten (B01 BUG-04).
    - Zweite Kopie in `~/Library/Caches/lu.daumedia.MikaPlusPlayer`: Xtream-Anfragen mit Zugangsdaten, Antworten,
      M3U-Listen, Logos (B01 BUG-03, B02 BUG-02, B04 BUG-07).
    - Cookies in `~/Library/HTTPStorages/lu.daumedia.MikaPlusPlayer` (+ `.binarycookies`) (B02 AK-36).
    - `~/Library/Preferences/lu.daumedia.MikaPlusPlayer.plist` (B09 AK-24).
    - Playlist löschen entfernt nichts aus dem Cache, Reste im Datenbankfile (B03 BUG-06/07).
  - *Removing everything* (`:88`, neu): Die App zu löschen entfernt nichts davon. Schritt-für-Schritt über
    „Go → Go to Folder…“ mit allen vier Orten samt `-shm`/`-wal`.
    - Warnung: `default.store` ist der SwiftData-Standardname, den eine andere App ohne Sandbox teilen kann.
    - Time-Machine-Kopien bleiben (B03 BUG-09).
  - *What the app connects to* (`:121`): Jede Verbindung trägt die IP. Eigene Anfragen senden User-Agent mit App-Name,
    Build und Netzwerk-Komponenten sowie die Systemsprache (B02 AK-36, B04 BUG-06).
    - *Your provider.*: Weiterleitungen werden samt Zugangsdaten befolgt (B01 BUG-10, B02 AK-11); Cookies.
    - *Stream servers.* (neu): Xtream-Adresse mit Zugangsdaten; M3U kann jeden Sender auf jeden Server legen (FB-05).
    - *Channel logo servers.*: beliebige Hosts, automatisch, auch über HTTP und Weiterleitungen. Der Host erfährt aus
      der Auswahl Liste, Suche und Filter und bei jedem Öffnen des Favoriten-Tabs genau die Favoriten. In v1.1 nicht
      abschaltbar (B04 BUG-06, B05 BUG-03).
    - *GitHub.*: siehe BF-12 unten.
  - *Xtream logins travel over plain HTTP*: ergänzt um „with every request to the panel … every stream you play“ und
    M3U-Links mit `http://`.
  - *This website*: „Neither of those tells us who you are“ ersetzt durch „Both receive your IP address, as any web
    server does“. `/download` als kleine Server-Funktion benannt, statt „no server“.
  - „Last updated 30 September 2026“.
- **Startseite `web/app/page.tsx`**: „all on your Mac, all local“ → „Your library is kept on your Mac — no account, no
  cloud“ (`:67`). „send your data anywhere“ → „send anything to the people who make it … It talks to the servers your
  playlist names and to GitHub for updates“, mit Link auf `/privacy` (`:73`).
- **FAQ `web/content/faq.ts:40`**: „Nowhere.“ → „To the servers your playlist names and to GitHub — not to us.“, dazu
  alle Empfängerarten, unverschlüsselte Speicherung und der Hinweis, dass Löschen der App nichts entfernt.

**BF-12 (B09 BUG-12) — behoben.** Punkt *GitHub.* (`web/app/privacy/page.tsx:155`) nennt:
- die automatische Prüfung „about once a day — the first time right after the first launch, without asking first“
  (B09 AK-03)
- dass es in v1.1 keinen Schalter dafür gibt
- den Feed auf `raw.githubusercontent.com` und den User-Agent mit App-Name, App-Version und Sparkle-Version (B09 AK-23)
- dass kein Systemprofil gesendet wird (`SUSendProfileInfo` fehlt)
- den Download des Updates von `github.com`

Die Feed-Adresse von v1.1 (alter Kontoname) steht bewusst nicht auf der Seite, siehe B09 BUG-01 (Sicherheitsbefund, keine
Datenschutzfolge). Den Hinweis aus B09 BUG-12 auf den signierten Feed ab dem nächsten Release nimmt die Seite nicht
auf, weil dieses Release unveröffentlicht ist.

**BF-16 (B09 BUG-16) — behoben.**
- Changelog: „The Mac app does not read this page: Sparkle checks a separate update feed, and a version reaches the app
  only once it is listed there“ (`web/app/changelog/page.tsx:21`, FB-10).
- Funktion „Updates through Sparkle“: prüft automatisch und fragt vor der Installation. Selbst installiert wird nur nach
  Zustimmung im Update-Fenster (`web/content/features.ts:43`, FB-09).
- FAQ „How do updates arrive?“ mit Installieren/Überspringen/Später, dem Kontrollkästchen für automatische Installation,
  EdDSA und dem echten Menüeintrag „Nach Updates suchen …“ (`web/content/faq.ts:50`).

Nachweis:
- `H::FB-03/FB-04/FB-05 (BUG-02 behoben)`: `todo` entfernt, um 5 Negativprüfungen erweitert (FAQ „Nowhere.“, „all
  local“, „no copy anywhere else“, „no server“, „Neither of those …“).
- **neu** `H::BUG-02 (Soll)`: Pfade, Klartext, Schlüsselbund, Time Machine, Cache, Cookies, Einstellungen,
  Weiterleitung, Stream-Server, Logo-Hosts samt Favoriten-Tab, Löschweg mit SwiftData-Warnung — in dieser Reihenfolge.
- **neu** `H::BF-12/BF-16`.
- Vor der Änderung gegen den alten Build ausgeführt: alle drei rot, erste Meldung „FB-03: „nothing goes to us““ bzw.
  „Seite nennt die beschriebene Version“ bzw. „BF-12: automatische Prüfung genannt“. Danach grün.
- Alter Build, Treffer je Seite (HTML + RSC-Nutzlast):
  - „nothing goes to us“, „own storage“, „no copy anywhere else“, „deleting the app removes all of it“, „goes to the host
    you entered“ je 2 auf `/privacy`
  - „send your data anywhere“ und „all on your Mac, all local“ je 2 auf `/`
  - „Nowhere.“ 2 auf `/support`
  - „checks this list for itself“ 2 auf `/changelog`
  - `default.store`, `Caches`, `User-Agent` je 0
- Seite in 390 px Breite gesichtet: lange Pfade brechen um, kein horizontaler Überlauf.
- **Nicht in der Website lösbar:** Das Verhalten selbst (Klartext, Cache, Logos ohne Wahl) behebt erst das nächste
  Release. Mit ihm muss die Seite erneut angepasst werden (OF-10).

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

**Nicht behoben (Teil 2, 2026-09-30):** Braucht Angaben des Nutzers: Name und Anschrift des Verantwortlichen, eine
nicht öffentliche Kontakt-E-Mail, Speicherdauer der Vercel-Logs, Rechtsgrundlagen, gegebenenfalls
Auftragsverarbeitung mit Vercel. Dazu seine rechtliche Bewertung. Nichts davon wurde erfunden, es gibt keine sichtbaren
Platzhalter. Test `H::FB-16/FB-17/FB-18` bleibt `todo`. **Teilweise erledigt** ist nur der irreführende Satz aus FB-17:
„Neither of those tells us who you are“ ist ersetzt durch „Both receive your IP address, as any web server does“ (im
Rahmen von BUG-02). Kontaktweg bleibt „a GitHub issue“ (FB-18).

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

**Behoben 2026-09-30 (Teil 2), Lizenz offen (OF-09):** Maßstab ist das Release v1.1, das man herunterladen kann.
Funktionen, die nur auf `main` bzw. im Arbeitsbaum existieren, stehen nicht auf der Seite, auch nicht als „coming soon“.
- **FB-02 Bild-in-Bild und Taste P** (BF-25; mit **BF-107**, B07 BUG-04):
  - Funktion „Picture in Picture“ entfernt. „What it does“ hat jetzt sieben statt acht Funktionen: Library 3, Playback 2,
    System 2 (`web/content/features.ts`).
  - Taste P aus der Tastentabelle (`web/app/support/page.tsx:65-71`) und aus „Hands on the keyboard“ entfernt.
  - Die Einschränkung „nur HLS“ (BF-107) entfällt damit für v1.1: Dort gibt es gar kein Bild-in-Bild
    (`git show v1.1:Sources/Views/PlayerView.swift` ohne Fall `"p"`).
- **FB-01 Doppelklick-Import** (B02 BUG-06, Hinweis im B02-Bericht):
  - „registers as a handler … double-clicking one opens it here“ ersetzt durch „open a playlist file from inside the app.
    Double-clicking a playlist in Finder does not import it in version 1.1“ (`features.ts:48`).
  - v1.1 hat keinen `onOpenURL`, erst `main` (unveröffentlicht).
- **FB-08 / BF-103** (B06 BUG-05): „On-screen feedback confirms each one“ ersetzt durch „Play/pause, volume and mute show
  a short on-screen confirmation“ (`features.ts:38`). Unter der Tastentabelle: „Space, the volume keys and M confirm with
  a short on-screen indicator; F and Esc only switch full screen“ (`support/page.tsx:146`). Abgeglichen mit
  `v1.1:PlayerView.swift` (`showHUD` nur bei Play/Pause, Stumm, Lautstärke).
- **FB-06 / BF-81 Leistungsaussagen** (B04 BUG-13/14; dazu B01 BUG-12, B02 BUG-04 und B03 BUG-01 für Import, Aktualisieren
  und Löschen). Entfernt: „responds immediately“, „narrows as fast as you can type“, „stay responsive“, „takes a few
  seconds“, „in the database rather than in memory“, „still usable“. Ersetzt durch die Messwerte:
  - Öffnen bis 0,9 s; erstes Zeichen, Suche leeren, Chip abwählen 0,3–0,6 s (`web/app/page.tsx:112-118`)
  - „opening one takes up to about a second, and importing 17,000 channels takes several minutes“ (`features.ts:18`)
  - FAQ: Import und Aktualisieren etwa viereinhalb Minuten, Löschen bis etwa zwei Minuten, die App reagiert währenddessen
    nicht (`faq.ts:35`)
  - Überschrift „Seventeen thousand channels, searchable“
- **FB-07 Favoriten** (B05 H-5): „matches favourites by their tvg-id“ ersetzt durch „same tvg-id — or, if it has none,
  the same name. If the provider changes that id or name, the star is gone, and channels that share one all get the star“
  (B05 BUG-01/05, `v1.1:Channel.swift` `favoriteKey`). „Star a channel anywhere“ → „Star a channel in the list“, denn im
  Player gibt es keinen Stern.
- **FB-09 / FB-10**: siehe BF-16 unter BUG-02.
- **FB-12 App-Name:** Die Erststart-Schritte nennen `MikaPlusPlayer` („drag MikaPlusPlayer to Applications“, „Open
  MikaPlusPlayer …“, „Control-clicking MikaPlusPlayer“). Der Einleitungssatz sagt „In the Finder and in the warning the app
  is called MikaPlusPlayer“ (`support/page.tsx:24,45,88,103`), belegt durch `v1.1:project.yml` `PRODUCT_NAME:
  MikaPlusPlayer` und `CFBundleName $(PRODUCT_NAME)`. Die Datenschutzseite nennt beim Löschweg ebenfalls `MikaPlusPlayer`.
- **FB-13 „open-source“:** Fußzeile → „An IPTV player with its source on GitHub.“ (`web/components/site-footer.tsx:14`).
  Das Repository hat keine Lizenz; welche vergeben wird, entscheidet der Nutzer (OF-09).
- **FB-14 Sprache:** „The app's interface is in German.“ in der Karte „macOS 14 Sonoma or later“ (`page.tsx:184`). Der
  Einrichtungsschritt nennt den Reiter „Datei (file)“ (`content/setup-steps.ts:12`), die FAQ den Menüeintrag „Nach
  Updates suchen …“. Das ist eine Tatsachenangabe zu v1.1; ob die App übersetzt wird, bleibt PRD-Frage. Die englischen
  Nachbauten (Senderliste, Multiview) sind unverändert.
- **B08 BUG-02 „das große Bild wandert mit“**: Die Bildunterschrift des Multiview-Nachbaus sagt jetzt: „In version 1.1
  the picture follows for HLS streams; after a click, an MPEG-TS stream (the Xtream default) can stay black in the large
  tile while its sound plays, until you switch to grid and back“ (`page.tsx:44`). Die Notizen zu v1.1
  (`web/content/changelog-overrides.ts:14`) haben dazu eine Zeile „Known issue in 1.1: …“.

Nachweis:
- **neu** `H::BUG-07 / BF-25 / BF-81 / BF-103 / BF-107` mit 39 ausgeführten Prüfungen auf `/`, `/support` und `/changelog`, gegen den
  alten Build zuerst rot („/: Bild-in-Bild ist nicht im Release v1.1“), danach grün.
- Alter Build, Treffer je Seite (HTML + RSC):
  - „Picture in Picture“ 5 auf `/`, 2 auf `/support`; `>P<` 1
  - „double-clicking one opens it here“, „On-screen feedback confirms each one“, „responds immediately“, „as fast as you
    can type“, „matches favourites by their tvg-id“, „the same way they do in the app“ je 2 auf `/`
  - „install themselves“ 3 auf `/`
  - „stay responsive“, „takes a few seconds“, „can install them on its own“, „drag Mika+Player“ je 2 auf `/support`
  - „open-source“ je 2 auf allen vier Seiten
- Angepasst, weil sich das geprüfte Ist ändert:
  - `H::AK-05/AK-06/AK-07` (Fußzeile)
  - `H::AK-11/AK-12` (sieben Funktionen, neue Überschrift)
  - `H::AK-18/AK-19` (Changelog-Satz)
  - `H::AK-22/AK-23` (App-Name, fünf Tasten)
  - `H::AK-24/AK-25/AK-26` (Datum)
  - `B::AK-23/EC-11` (FAQ-Wortlaut)
  - `M::AK-34 (BUG-08)`: prüft die Download-Beschriftung, nicht mehr jedes „Version 1.1“ im Text. Die Gegenprobe mit
    Release-Daten findet „Version 1.1 · “ weiterhin.
- Die Spec-Kriterien selbst sind unverändert, siehe OF-08.

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
