# B02 · M3U-Import — Testbericht

Durchlauf 1 · Stand: 2026-09-16 · Geprüft gegen `spec.md` vom 2026-09-16 (Rekonstruktion, Stand `c01f1cf` + Reparatur B01) ·
Code-Stand `c01f1cf` + Reparatur B01 + Reparatur B09 (Arbeitsbaum, nicht committet)

## Fazit

**Production-ready: nein** — höchster Schweregrad **hoch** (BUG-01, BUG-04).

Der fachliche Kern von B02 arbeitet so, wie die Rekonstruktion ihn beschreibt. Das ist ausgeführt, nicht gelesen:
Parser (quote-sicherer Name, Attribute, `#EXTGRP`, Zeilenenden, Kodierung), URL-Abruf (Trimmen, Prozentkodierung,
Statuscodes, Weiterleitungen, Basic-Auth, Kopfzeilen, Cookies) und Datei-Import (Namen, Endungen, Rechte, Symlinks,
Named Pipe). Das Sheet ist in einem echten Fenster bedient, auch der Datei-Reiter über den Systemdialog. Alle zehn
⚠-Kriterien, die die Spec als Fehler einstuft, sind reproduziert und jetzt belegt:

- **BUG-01 (hoch)** — Ein `get.php?username=…&password=…`-Link legt das Passwort im Klartext in `sourceURL` und in
  **jeder** Stream-Adresse ab (SQLite: 1 von 1 bzw. 3 von 3). Der Schlüsselbund-Schutz aus B01 greift nicht: kein
  Eintrag, die Umstellung meldet 0, der Resolver gibt die Adresse mit Passwort weiter. Die Datenbank ist nicht vom
  Backup ausgeschlossen.
- **BUG-04 (hoch)** — 17.000 Sender per URL frieren die Oberfläche **282 s** ein. Im **Release-Build** sind es
  ebenfalls **282,5 s**: Der Aufwand steckt in SwiftData, nicht in fehlender Optimierung. Er wächst quadratisch
  (Faktor 3,9 bei doppelter Menge). Der Parser allein braucht 0,15 s.
- **BUG-02, BUG-03, BUG-05, BUG-06, BUG-08 (mittel), BUG-07, BUG-09 (niedrig)** — Plattencache mit Zugangsdaten
  übersteht das Löschen; keine Grenzen (52 MB, 100 s Tröpfeln); jedes Schema landet in der Datenbank; „Öffnen mit"
  erzeugt nur leere Fenster; Registrierung für alle Text-Typen; „Abbrechen" bricht weder URL- noch Datei-Import ab,
  ein späterer Fehler erscheint in einem losgelösten Fenster; Doppelklick startet zwei Importe.

Die B09-Reparatur hat an B02 nichts verändert. Der Import läuft auch über `AppPersistence.diskContainer` mit
versioniertem Schema. Der `code-reviewer` fand nichts Neues (siehe *Codequalität*).

Nächster Schritt: `/sdd-build B02` mit BUG-01 bis BUG-09, zuerst BUG-01 und BUG-04. **Die Rückerfassung wartet**
nach der Regel für Bestandsfeatures, bis die Funde mit dem Grad *hoch* behoben und erneut geprüft sind.

Nicht als Fehler gewertet, aber offen (Entscheidung des Nutzers):
- **OF-01** · Ein erneuter Import derselben URL legt eine zweite Playlist an (AK-15). Zurückgestellt wie B01 AK-09.
- **OF-02** · `file:`- und `data:`-Adressen im URL-Feld werden importiert (AK-13); bei `data:` steht die ganze Liste als
  Adresse in der Datenbank.

Nicht prüfbar:
- **AK-02** und **AK-19**: jeweils der iOS-Teil. Für den Simulator gibt es hier keine Tipp-Automatisierung.
  Die macOS-Teile sind bestanden.
- **EC-18** (iCloud), **EC-23** (iOS „Öffnen in") und **EC-24** (öffentliche Liste, kein Netzzugriff auf fremde Listen).
- **EC-22** ist ausgeführt, aber **nicht reproduziert**: Nach dem Neustart erscheint nur 1 Fenster (Spec-Korrektur).

| | Anzahl |
|---|---|
| Akzeptanzkriterien geprüft | 41 von 43 |
| davon bestanden | 29 |
| davon durchgefallen | 12 — 10 ⚠-Kriterien reproduziert → BUG-01 … BUG-09; 2 ⚠-Kriterien reproduziert, zurückgestellt bis OF-01/OF-02 (AK-15, AK-13) |
| **nicht prüfbar** | 2 (AK-02, AK-19 — jeweils iOS-Teil) |
| Edge Cases belegt | 20 von 24 · 1 abweichend (EC-22 nicht reproduziert) · 3 nicht prüfbar (EC-18, EC-23, EC-24) |
| BUGs | 9: 2 × hoch, 5 × mittel, 2 × niedrig |
| Tests neu geschrieben | 65 in 6 Testdateien plus `B02Support.swift` (`Tests/B02/`) |
| Tests grün | Gesamtlauf Debug: **68 ausgeführt, 0 Fehlschläge** (65 minus 1 später ergänzter Dialog-Test = 64 B02-Tests + 4 `M3UParserTests`), 570 s, `** TEST EXECUTE SUCCEEDED **`. Nachlauf der beiden Dialog-Tests: 2 von 2 grün. Release-Messlauf: 4 von 4 grün. 12 Tests belegen Fehler per `XCTExpectFailure("BUG-NN …")` |

## Prüfumgebung

| Was | Wie |
|---|---|
| Build/Test | `xcodegen generate` einmal nach Anlage von `Tests/B02/`. `xcodebuild build-for-testing` / `test-without-building -scheme MikaPlusPlayer-macOS -derivedDataPath build/dd-qa-b02 -only-testing:` B02-Klassen + `M3UParserTests`. Größen für AK-40 über `TEST_RUNNER_B02_QA_SIZES=1500,3000,6000,17000`. Gesamtlauf 2026-09-16 22:45–22:55. Parallel liefen QA 2 von B09 und QA 1 von B03 → **Messwerte unter Last** (Load 4–6 bei 16 Kernen) |
| Release-Messung | `build/dd-qa-b02-release`, `-configuration Release` (im Log belegt: `-O -whole-module-optimization`). Zusätzlich `ENABLE_TESTABILITY=YES` sowie `ENABLE_HARDENED_RUNTIME=NO` und `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES`, nur damit der Test-Host startet. 23:00–23:07 |
| iOS | `xcodebuild build -scheme MikaPlusPlayer -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd-qa-b02-ios` → `** BUILD SUCCEEDED **`, Warnung zu `LSSupportsOpeningDocumentsInPlace` (EC-23). Nicht bedient |
| Server | `B02Server` (`Tests/B02/B02Support.swift`): HTTP auf 127.0.0.1. Schreibt jede Anfrage roh mit (Request-Zeile, alle Kopfzeilen) und zählt auch Verbindungen ohne HTTP-Anfrage. Antworten frei gebaut: Status, `Location`, `WWW-Authenticate`, `Set-Cookie`, `Cache-Control`, Stillstand, Tröpfeln. Kein echter Anbieter, keine öffentliche Liste |
| Daten | nur erfundene Zugangsdaten (`qa-user` / `qa-pass-b02…`). Datenbanken in-memory oder als Temp-Datei über den Produktionsweg `AppPersistence.diskContainer`. Die Datenbank des Nutzers wurde weder geöffnet noch gelesen |
| HTTP-Cache | Der Plattencache des Test-Hosts wäre der der echten App. Jeder Test lenkt `URLCache.shared` in einen Temp-Ordner um. Vorab mit einer Sonde belegt: `URLSession.shared` schreibt danach dorthin, auch nach früherer Nutzung. Eigene Schlüssel im Original-Cache werden zusätzlich entfernt |
| Cookies, Zugangsdatenspeicher | Test-Cookies `b02qa…` nur als Sitzungs-Cookies, am Ende gelöscht. **Vorfall, offen gelegt:** Eine frühe Fassung des Aufräumens versuchte, *alle* Einträge im gemeinsamen `URLCredentialStorage` für 127.0.0.1/localhost zu entfernen. Ein fremder, nicht vom Test stammender Eintrag war in den späteren Läufen weiterhin vorhanden, wurde also nicht entfernt. Das Aufräumen ist jetzt auf den Benutzer `qa-…` beschränkt. Fremde Einträge werden weder gelistet noch angefasst. Schlüsselbund: 0 Internet-Passwörter für `qa-user` (Abfrage nur der Attribute) |
| Oberfläche macOS | `PlaylistsView` → Sheet in einem echten Fenster des Test-Hosts: synthetische Mausklicks, Feld-Editor, Accessibility (`UIHarness`/`AX` aus `Tests/B01`), Fenster-Server (`CGWindowListCopyWindowInfo`), Aufnahmen einzelner eigener Fenster. Der Inhalt des Dateidialogs läuft in einem Systemdienst und ist nicht klickbar. Der Dialog wird deshalb über seinen Abschluss (`completeWithReturnCode:url:urls:`) mit einer Datei beendet; ab dort laufen der `fileImporter`-Handler und der Import unverändert |
| „Öffnen mit" | (b)(c) im Test-Host: das „Dokumente öffnen"-Ereignis über den AppKit-Handler des eigenen Prozesses. (a) und EC-22: Kopie der Debug-App mit Bundle-ID `lu.daumedia.MikaPlusPlayer.b02qa`, Sparkle-Prüfung aus, gestartet mit `open --env XCTestSessionIdentifier=…`, dadurch Datenbank im Speicher. Als Sicherheitsnetz lag vorab eine leere Store-Datei der Probe bereit, damit eine fremde `default.store` nie übernommen werden kann. Sie blieb 0 Byte, der Speichermodus ist also belegt. Danach alle Spuren entfernt, `lsregister -u` |
| Systemprotokoll | Sonde `b02logprobe`: mit `swiftc -O` aus den **unveränderten** Quellen `PlaylistImporter`, `M3UParser`, `Xtream*`, `StreamURLResolver`, `Playlist`, `Channel`, `AppEnvironment` übersetzt, aus der Shell gestartet, gegen einen Python-Mock auf 127.0.0.1; `log show --predicate 'process == "b02logprobe"'` |
| Codequalität | `code-reviewer`-Agent über die B02-Dateien mit Verweis auf `design.md` und die bekannten FB/OF |
| Kein Ton | keine Wiedergabe, Stream-Adressen auf den geschlossenen Port 9, keine Tastaturereignisse |
| Belege | `features/B02-m3u-import/qa/`: `testlauf-protokoll.txt` (alle Ausgaben, Temp-Pfade gekürzt), Messdateien je Kriterium, 9 Aufnahmen |

## Akzeptanzkriterien im Einzelnen

Testnamen ohne Pfad liegen unter `Tests/B02/`. Protokollzeilen stehen in `qa/testlauf-protokoll.txt`.

| AK | Ergebnis | Nachweis |
|---|---|---|
| AK-01 | ✅ bestanden | `B02OberflaecheTests.testAK01_ReiterURLUndDatei`: Reiter „URL \| 1", Texte „Name (optional)", „z. B. Mein IPTV-Anbieter", „Playlist-URL", „https://… .m3u8", Button „Von URL importieren", 2 Felder. Reiter „Datei": „Lokale Datei", „Datei auswählen (.m3u/.m3u8)", 1 Feld. Nach Datei → URL steht die URL noch im Feld. Aufnahmen `qa/AK-01-reiter-url.png`, `qa/AK-01-reiter-datei.png` |
| AK-02 | ⚠️ nicht prüfbar | macOS-Teil bestanden (`testAK02_KeineAutokorrekturImURLFeldMacOS`: URL-Feld `isAutomaticSpellingCorrectionEnabled = false`, Namensfeld `true`). iOS-Teil (Großschreibung, URL-Tastatur) ohne Tipp-Automatisierung nicht ausführbar |
| AK-03 | ✅ bestanden | `testAK03_ButtonZustaende`: leer → deaktiviert; `" "`, `"\t"`, `"x"`, URL → aktiv; wieder leer → deaktiviert; „Datei auswählen" aktiv; 0 Anfragen |
| AK-04 | ✅ bestanden | `testAK04_EC20_ZustandWaehrendDesURLImports` (Server antwortet nach 3 s): „Importiere…" plus Fortschrittsanzeige, „Von URL importieren" deaktiviert, „Abbrechen" aktiv. Danach schließt das Sheet, 1 Playlist |
| AK-05 | ✅ bestanden | `testAK05_Dateidialog`: Klick öffnet `NSOpenPanel` als Sheet, `allowsMultipleSelection = false`, `canChooseDirectories = false`. Erlaubte Typen am Dialog abgelesen: `public.m3u-playlist`, `public.plain-text`. Wählbar per Typkonformität: `m3u`, `m3u8`, `M3U8`, `txt`, `csv`, `swift`, `log`, `md`. Nicht wählbar: `json`, `html`, `pls`, `xspf`, ohne Endung. Abbrechen des Dialogs: kein Alert, 0 Playlists (`qa/AK-05-dateidialog.txt`) |
| AK-06 | ✅ bestanden | `testAK06_ErfolgSchliesstSheetNeuePlaylistOben`: zwei Importe, Reihenfolge „QA Zweite, 2 Sender" vor „QA Erste, 2 Sender", Globus-Symbol in `qa/AK-06-playlists-nach-url-import.png`. Daten: `B02URLImportTests.testAK06_…` (`isRemote`, `lastRefreshed`, `playlistID`) |
| AK-07 | ✅ bestanden | `testAK07_NameAusHostOderEingabe`: `127.0.0.1`, `localhost`, `file:` → „Playlist", `data:` → „Playlist", `"   "` und `"  Mein Name  "` exakt |
| AK-08 | ✅ bestanden | `testAK08_EingabeAnfrageUndGespeicherteAdresse`, 8 Fälle mit je genau 1 × GET. Gesendet `/mit%20leerzeichen.m3u`, `/%C3%BCmlaut.m3u`, `/liste.m3u` ohne Fragment. Gespeichert `HTTP://…/gross.m3u`, `…#fragment`, Query, Benutzerinfo |
| AK-09 | ✅ bestanden | `testAK09_AK25_ContentTypeUndKodierungUeberURL`: 5 Content-Types importiert. Kopfzeile `charset=iso-8859-1` bei UTF-8-Körper und `charset=utf-8` bei Latin-1-Körper → „ORF Eins Ä" / „Österreich" |
| AK-10 | ✅ bestanden | `testAK10_EC16_Statuscodes`: 200, 203 → Import; 204 und leerer Körper → „Die Playlist enthält keine gültigen Sender."; 300, 304, 400, 401, 403, 404, 407, 429, 500, 503 → „Netzwerkfehler: HTTP <n>"; 2 Playlists |
| AK-11 | ✅ bestanden | `testAK11_Weiterleitungen`: 301 → 2 Anfragen am Server. 302 auf `localhost:<anderer Port>` → Ziel `/ziel.m3u`. 307 → Ziel exakt `/ziel.m3u?username=qa-user&password=qa-pass-b02ak11`. Gespeichert jeweils die Eingabe. Schleife → 21 Anfragen, „too many HTTP redirects". `file:` → „You do not have permission to access the requested resource." |
| AK-12 | ✅ bestanden | `testAK12_EC17_OhneSchemaUndNichtAbrufbar`: `127.0.0.1:<port>/…`, `example.invalid/…`, `"   "`, `""` → „ungültig", **0 Verbindungen**. `localhost:<port>/…` und `javascript:` → „unsupported URL". `http://`, `http:///liste.m3u` → „Could not connect to the server.". `ftp://` → `B02LangsamTests`: „timed out" nach **60,02 s** (siehe H-2) |
| AK-13 ⚠ | ❌ durchgefallen (zurückgestellt → OF-02, kein BUG) | `testAK13_FileUndDataImURLFeld`: `file:` → „Playlist", `isRemote = true`, 2 Sender. `data:…;base64,…` → `sourceURL` = gesamte Eingabe. SQLite `ZSOURCEURL like 'data:%'` → 1 Zeile, identisch mit der Eingabe. 0 Anfragen |
| AK-14 | ✅ bestanden | `testAK14_BasicAuthAusBenutzerinfo`: ohne Challenge 1 Anfrage ohne `Authorization`; `/basic.m3u` → ohne, dann mit korrekter Basic-Auth; `/basic-redirect` (anderer Host) → ohne, mit, Ziel **ohne**. Beobachtung zum zweiten Abruf desselben Hosts → H-1 |
| AK-15 ⚠ | ❌ durchgefallen (zurückgestellt → OF-01, kein BUG) | `testAK15_DoppelterImportLegtZweitePlaylistAn`: 2 Playlists, 4 Sender, 2 Anfragen, verschiedene IDs, keine Warnung |
| AK-16 | ✅ bestanden | Über den Dialog (`testAK16_AK27_AK29_DateiImportUeberDialog`): Datei `qa-dialog.m3u` gewählt → Sheet schließt, Zeile „qa-dialog, 2 Sender", Dokument-Symbol (`qa/AK-16-datei-playlist-ueber-dialog.png`). Namen und Felder über den Importpfad (`B02DateiImportTests.testAK16_…`): `liste.v2`, `Sender & Ümlaut (Kopie)`, `.m3u`, `.versteckt`, Eingaben exakt; `sourceURL = nil`, `lastRefreshed = nil`. Kontextmenü (`B02OberflaecheTests.testAK16_DateiPlaylistSymbolUndKontextmenue`): Datei-Playlist `["Löschen"]`, URL-Playlist `["Aktualisieren", "Löschen"]`, Aufnahme `qa/AK-16-symbole-datei-und-url.png` |
| AK-17 | ✅ bestanden | `testAK17_InhaltStattEndung`: `.txt`, `.csv`, `.swift`, `.png`, ohne Endung (und `.json`) → importiert; `.txt` ohne `#EXTINF` → „keine gültigen Sender". Den Dialog passieren nur die Typen aus AK-05 |
| AK-18 | ✅ bestanden | `testAK18_EC19_NichtLesbareDateienUndSymlinks`: Rechte 000, Ordner 000, gelöscht, Ordner, Symlink ins Leere, Named Pipe → „Auf die ausgewählte Datei kann nicht zugegriffen werden."; Symlink → Name „verweis", Kette → „kette" |
| AK-19 | ⚠️ nicht prüfbar | iOS-Dateien-Dialog nicht bedienbar. macOS-Anteil (`testAK19_SecurityScopedAdresseMacOS`): Adresse aus Lesezeichen mit `.withSecurityScope` wird importiert, Zugriff danach erneut anforderbar, keine Sandbox |
| AK-20 | ✅ bestanden | `B02ParserTests.testAK20_EintragAusExtinfUndAdresszeile` (ohne `#EXTM3U`, Kommentar, `#EXTVLCOPT`, `#KODIPROP`, Leerzeilen, Tabs am Rand, `#EXTM3U` mitten in der Datei, Adresse ohne Schema → verworfen) |
| AK-21 | ✅ bestanden | `testAK21_NameQuoteSicherUndErsatzname`; Bestandstests `testQuoteSafeNameWithCommas`, `testMinimalEntry` grün |
| AK-22 | ✅ bestanden | `testAK22_AttributRegeln` (a)–(f): Großschreibung der Schlüssel, `tvg-name`/`tvg-chno` ignoriert, Leerzeichen um `=`, Tabs, letzter Wert gewinnt, leer → nil, `" News "` bleibt, ohne Anführungszeichen/Hochkommas nicht gelesen, Attribut nach dem Komma im Namen |
| AK-23 | ✅ bestanden | `testAK23_ExtgrpRegeln` (erste gilt, leere übersprungen, davor/klein/Folgesender ohne Wirkung, `group-title` gewinnt); Bestandstest `testExtGrpFallback` grün |
| AK-24 | ✅ bestanden | `testAK24_Zeilenenden`: LF = CRLF = CR = gemischt (je 2 Sender, gleiche Werte) |
| AK-25 | ✅ bestanden | Datei (`testAK25_EC07_EC08_EC09_KodierungUeberDatei`): UTF-8, UTF-8 mit BOM (auch direkt vor `#EXTINF`), Latin-1 → „ORF Eins Ä"/„Österreich". URL: `testAK09_AK25_…` |
| AK-26 | ✅ bestanden | Import (`testAK26_EC01_EC15_KeineGueltigenSenderLegtNichtsAn`): leer, Loginseite (HTML, 200), JSON, nur Adressen → Meldung, 0 Playlists, 0 Sender. Parser: `testAK26_KeineGueltigenEintraegeUndStillesVerwerfen` (ungültige fallen still weg); Bestandstest `testSkipsInvalidURL` grün |
| AK-27 | ✅ bestanden | URL (`testAK27_FehlerAlertEingabenBleiben`): Alert `["Fehler", "Netzwerkfehler: HTTP 404", "OK"]` bzw. „Die angegebene URL ist ungültig."; nach „OK" Felder `["QA Alert", <URL>]`, Button aktiv, Sheet offen, 0 Playlists. Datei (`testAK16_AK27_AK29_…`): Alert „Die Playlist enthält keine gültigen Sender.", Name bleibt, Button aktiv, 0 Playlists |
| AK-28 | ✅ bestanden | `testAK28_ServerNichtErreichbar`: Port zu → „Could not connect to the server.", unbekannter Host → „A server with the specified hostname could not be found."; `B02LangsamTests`: Stillstand → „The request timed out." nach 60,02 s |
| AK-29 ⚠ | ❌ durchgefallen → **BUG-08** | URL (`testAK29_EC21_AbbrechenBrichtURLImportNichtAb`): Playlists direkt nach „Abbrechen" 0, nach 4 s **1**. Bei Fehler: 2 neue Fenster auf dem Bildschirm (`SheetPresentationWindow` ohne Elternfenster + `_NSAlertPanel` „Netzwerkfehler: HTTP 500"), `qa/AK-29-losgeloestes-fenster-0.png`, `-1.png`. Datei: „Abbrechen" 0,5 s nach Start eines 3.000-Sender-Imports geklickt → Main-Thread 9,23 s blockiert, Import vollständig (`gross-3000=3000`) |
| AK-30 ⚠ | ❌ durchgefallen → **BUG-09** | `testAK30_DoppelklickAufVonURLImportieren`: zwei Klicks im selben Durchlauf → **2 Anfragen, 2 Playlists**; 150 ms Abstand → 1/1 |
| AK-31 ⚠ | ❌ durchgefallen → **BUG-06** | (a) Probe, Kaltstart mit `.m3u` → 1 Fenster. (b) laufend, `.m3u8`, `.txt`, `.m3u` → 2, 3, 4 Fenster, 1 Prozess (`qa/AK-31-32-oeffnen.txt`). (c) Test-Host (`testAK31_OeffnenEreignisErzeugtLeeresFensterOhneImport`): je Ereignis 1 neues Fenster „Playlists" mit „Keine Playlists", kein „Sender", kein „Fehler" (`qa/AK-31-leeres-fenster-nach-oeffnen.png`). (d) `testAK31d_AK32_OeffnerRegistrierung`: Standard-App `.m3u`/`.m3u8` = Music.app, `.txt` = TextEdit.app |
| AK-32 ⚠ | ❌ durchgefallen → **BUG-07** | `testAK31d_AK32_OeffnerRegistrierung`: Mika+Player unter den LaunchServices-Kandidaten für `m3u`, `m3u8`, `txt`, `json`, `html`, `csv`, `swift`, `md`, `log`, `pls` (12–18 Einträge, alle gebauten Kopien); nicht für `xspf` und ohne Endung. Gebautes `Info.plist`: `LSHandlerRank Default`, `public.m3u-playlist`, `public.text` |
| AK-33 | ✅ bestanden | `testAK33_FehlermeldungOhneZugangsdatenUndAdresse`, 9 Fälle (HTTP 404/500 mit Query, Schleife, leere Liste, Port zu, unbekannter Host mit Benutzerinfo, `ftp:` mit Benutzerinfo, Schema aus Benutzername, ohne Schema): 0 × Passwort, 0 × Benutzer, 0 × Adresse |
| AK-34 ⚠ | ❌ durchgefallen → **BUG-01** | `B02SicherheitTests.testAK34_ZugangsdatenAusM3ULinkImKlartext` auf Temp-Store-Datei: `ZSOURCEURL` mit Passwort **1**, `ZSTREAMURL` mit Passwort **3 von 3**, Bytes im `-wal` 4; Schlüsselbund (Testdienst) 0; `AppPersistence.migrateCredentials` → `0/0/0`, danach unverändert 1; `StreamURLResolver` → 3 von 3 Adressen mit Passwort; `isExcludedFromBackup = false`. Benutzerinfo-Variante: 1 (`testAK34_BenutzerinfoImKlartext`) |
| AK-35 ⚠ | ❌ durchgefallen → **BUG-02** | `testAK35_PlattencacheBehaeltZugangsdatenNachLoeschen`: nach Import 1 Cache-Eintrag, Antwortkörper mit Passwort, 8 Bytefolgen in `Cache.db-wal`; nach Löschen der Playlist unverändert 1 / 8; `Cache-Control: no-store` → 0 / 0. `purgeLegacyHTTPCacheOnce`: 1. Aufruf leert, neuer Import schreibt wieder, 2. Aufruf `false`, Eintrag bleibt |
| AK-36 | ✅ bestanden | `testAK36_KopfzeilenUndCookies`: Kopfzeilen genau `accept, accept-encoding, accept-language, connection, host, user-agent`; `User-Agent: Mika+Player/3 CFNetwork/3896.100.1.1.1 Darwin/27.0.0`, `Accept: */*`, `Accept-Language: de-DE,de;q=0.9`, `Accept-Encoding: gzip, deflate`; kein `Referer`. `Set-Cookie` → beim zweiten Import **und** beim Aktualisieren (`refresh`) als `Cookie` zurückgeschickt, 1 Cookie im Speicher |
| AK-37 ⚠ | ❌ durchgefallen → **BUG-03** | `testAK37_GrosseAntwortUndDateiOhneGrenze`: 52.062.788 Byte, 1.000 Sender, längster Name 52.004 Zeichen gespeichert. URL: 3,61 s (Release 1,76 s), Datei: 3,49 s (Release 1,79 s), Speicher des Prozesses bis 655 MB. Parser: 1 MB Name, 5 MB Logo, 2 MB Adresse, 1 MB Gruppe ungekürzt (`qa/AK-37-EC-13-grenzen.txt`) |
| AK-38 ⚠ | ❌ durchgefallen → **BUG-03** | `B02LangsamTests.testAK12_AK28_AK38_EC17_…`: 20 Sender in 10 Stücken alle 10 s → **„OK (20 Sender)" nach 100,30 s** |
| AK-39 ⚠ | ❌ durchgefallen → **BUG-05** | `testAK39_BeliebigeSchemataWerdenGespeichert`: SQLite-Schemata in `ZSTREAMURL`: `data, file, ftp, http, javascript, mailto, rtmp, rtp, rtsp, smb, udp, vlc, x-apple.systempreferences`; Logos `file:///etc/hosts`, `javascript:alert(1)`, `smb://…`, `logos/relativ.png` gespeichert; nur ohne Schema verworfen (`qa/AK-39-schemata.txt`) |
| AK-40 ⚠ | ❌ durchgefallen → **BUG-04** | `testAK40_GrosseListeBlockiertMainThread`, Tabelle unten; 17.000 Sender Debug **282,04 s** / Release **282,54 s**, Blockade jeweils ≈ Gesamtdauer; Parser allein 0,32 s / 0,15 s. Nur das Warten auf das Netz blockiert nicht (AK-04: „Importiere…" und Reiterwechsel während 3 s Serverwartezeit) |
| AK-41 | ✅ bestanden | Test-Host (`testAK41_ProtokollImTestHost`): 0 Einträge der App, 1 CFNetwork-Zeile mit Passwort im Klartext, Private-Data-Logging aktiv. Regulär aus der Shell gestartete Sonde mit dem App-Code: 579 Zeilen, **0** × Passwort, 0 × Benutzer, 31 × `<private>` (`qa/AK-41-protokoll.txt`). Wie in der Spec nicht geprüft: normal gestartete App selbst |
| AK-42 | ✅ bestanden | `testAK42_LoeschenEntferntKlartextErstNachDemSchliessen`: nach `PlaylistImporter.delete` Zeilen 0, `-wal` noch 4 Vorkommen; nach Schließen des Containers 0/0/0. Cache-Eintrag (1) und Cookie (1) bleiben (→ BUG-02, Angriff 8) |
| AK-43 | ✅ bestanden | `git log -p --all`, 19 Commits: `username=` nur `demo`, `u`, `…`; `password=` nur `secret`, `p`, `…`; `/live/<u>/<p>/` nur `user/pass`, `\(user)/\(pass)`; keine `.m3u`/`.m3u8`/`.pls`/`.xspf`-Datei eingecheckt; einziger Listen-Link `https://iptv-org.github.io/iptv/index.m3u` (öffentliche Sammlung). Arbeitsbaum: nur `qa-…`- und Beispielwerte |

### AK-40 · Messreihe (URL-Import, Main-Thread-Wächter)

| Sender | Debug gesamt | Debug längste Blockade | Release gesamt | Release längste Blockade |
|---|---|---|---|---|
| 1.500 | 2,30 s | 2,27 s | 2,32 s | 2,29 s |
| 3.000 | 8,86 s | 8,84 s | 8,99 s | 8,97 s |
| 6.000 | 35,31 s | 35,29 s | 35,22 s | 35,21 s |
| 6.000 (Store-Datei) | 35,46 s | 35,43 s | 35,80 s | 35,78 s |
| **17.000** | **282,04 s** | **282,02 s** | **282,54 s** | **282,51 s** |
| Faktor 3.000 → 6.000 | 3,98 | | 3,92 | |
| Parser allein, 17.000 | 0,32 s | | 0,15 s | |
| 300.000 Einträge (46 MB), nur Parser (EC-14) | 5,57 s | | 2,73 s | |

Apple M3 Max, 16 Kerne, macOS 27.0, Load 4–6 durch parallele QA-Läufe (`qa/AK-40-messung.txt`).

## Edge Cases

| EC | Ergebnis | Nachweis |
|---|---|---|
| EC-01 | ✅ belegt | `testEC01_EinfacheM3UOhneExtinf` → 0; Import → „keine gültigen Sender" (`testAK26_EC01_EC15_…`) → OF-03 |
| EC-02 | ✅ belegt | `testEC02_ExtinfKleinOderOhneDoppelpunkt` → 0 / 0 |
| EC-03 | ✅ belegt | `testEC03_VerbrauchteUndDoppelteEintraege` |
| EC-04 | ✅ belegt | `testEC04_UnbalancierteAnfuehrungszeichen`: Name „a.ts", Gruppe „News,Das Erste"; `tvg-id` = „abc group-title=" |
| EC-05 | ✅ belegt | `testEC05_HochkommasMitKomma` → „X',Name", keine Gruppe |
| EC-06 | ✅ belegt | `testEC06_SteuerzeichenImNamen`: U+2028, U+0085, VT, FF → 0 Sender; NUL, ESC-Sequenz, U+202E bleiben im Namen |
| EC-07 | ✅ belegt | `testAK25_EC07_…`: „Ã\u{84}rger TV" (U+00C3 U+0084), Gruppe „Ã\u{96}sterreich" → OF-06 |
| EC-08 | ✅ belegt | Windows-1252 `…` mitten im Namen → Sender verloren; `€` → U+0080 bleibt („Preis \u{80} TV") → OF-06 (Präzisierung siehe Spec-Korrekturen) |
| EC-09 | ✅ belegt | UTF-16 LE/BE mit BOM (Datei) und `charset=utf-16` (URL, `testEC09_UTF16UeberURL`) → „keine gültigen Sender" |
| EC-10 | ✅ belegt | `testEC10_RelativeUndSchemaaehnlicheAdressen` (`C:%5CVideos%5Ca.ts`, Schema „localhost"); in lokaler Datei neben existierender `stream.ts` → nur die absolute Adresse bleibt (`testEC10_RelativeAdresseNebenDerDatei`) → OF-04 |
| EC-11 | ✅ belegt | `testEC11_LogoAdressen` → `kein%20url%20mit%20leer%20zeichen` ohne Schema; `logos/a.png` relativ |
| EC-12 | ✅ belegt | `testEC12_DoppelterSender` → 2 |
| EC-13 | ✅ belegt | `testEC13_SehrLangeZeilenUngekuerzt`: je 0,09–0,68 s (Debug), alles ungekürzt → BUG-03 |
| EC-14 | ✅ belegt | `testEC14_DreihunderttausendEintraegeParser`: 45,4 MB, 300.000 Einträge, Parser 5,57 s (Release 2,73 s), Speicher +252 MB (Release +270 MB). Import in dieser Größe nicht ausgeführt (wie Spec) |
| EC-15 | ✅ belegt | Loginseite (HTML, 200) → „keine gültigen Sender" |
| EC-16 | ✅ belegt | 203 → Import, 304 → „Netzwerkfehler: HTTP 304" |
| EC-17 | ✅ belegt | `ftp://` → 60,02 s „timed out"; mit Benutzerinfo auf geschlossenem Port sofort „unknown error" |
| EC-18 | ⚠️ nicht prüfbar | iCloud-Datei nicht erzeugt und keine fremde gelesen (wie Spec) → OF-07 |
| EC-19 | ✅ belegt | Named Pipe mit Schreiber nach 3 s → sofort (0,00 s) Zugriffsmeldung, Blockade 0,00 s. Große Datei auf dem Main-Thread: 52 MB → 3,49 s Blockade (AK-37) |
| EC-20 | ✅ belegt | jetzt für URL ausgeführt: `testAK04_EC20_…` — „Importiere…" auf Datei- und Xtream-Reiter, Datei-Button deaktiviert, Import läuft weiter, 1 Anfrage |
| EC-21 | ✅ belegt | `testAK29_EC21_…`: nach dem losgelösten Fehler öffnet das Sheet normal, kein Alert am neuen Sheet |
| EC-22 | ❌ abweichend (nicht reproduziert) | Probe mit 4 bzw. 3 zusätzlichen Fenstern, beendet per SIGTERM (2×, einmal nach 20 s) und per `NSRunningApplication.terminate()` → nach Neustart jeweils **1** Fenster; kein gesicherter Fensterzustand der Probe. Siehe Spec-Korrekturen |
| EC-23 | ⚠️ nicht prüfbar | iOS „Öffnen in" nicht bedienbar. Belegt ist nur die Build-Warnung „supports opening files, but doesn't declare … LSSupportsOpeningDocumentsInPlace" (`build/dd-qa-b02-ios`) |
| EC-24 | ⚠️ nicht prüfbar | kein Abruf öffentlicher Listen. Dass `#EXTVLCOPT` ignoriert wird, belegt AK-20 |

## Sicherheitsprüfung

Aktiv angegriffen, nicht nur gelesen. Grundlage: `~/.claude/sdd/sicherheit.md`, Stufe B, übertragen auf eine lokale App
ohne Backend.

| Prüfung | Ergebnis | Beleg |
|---|---|---|
| 1 · Zugriff auf fremde ID (IDOR) | trifft nicht zu; Ersatzprüfung bestanden | Kein Server, keine Konten, keine per ID abrufbaren Ressourcen. Ersatz `testAngriff01_FremdeListeVeraendertVorhandenePlaylistNicht`: Eine präparierte zweite Liste hat dieselbe tvg-ID, denselben Namen und dieselbe Adresse, dazu die UUID der ersten Playlist als tvg-ID und Name. Playlist A bleibt bei 2 Sendern, 2 Favoriten und `channelCount` 2. Liste B hat 0 Favoriten, alle `playlistID` = B |
| 2 · Zugriffsregeln (Betriebssystem) | **BUG-01, BUG-02** | `codesign -d --entitlements` des gebauten Bundles: `app-sandbox = false`, `disable-library-validation = true`. Die Test-Datenbank und der Plattencache waren aus einem anderen Prozess desselben Benutzers per SQLite bzw. Dateizugriff lesbar, samt Passwort (AK-34, AK-35). Die App liest jede Datei, die der Benutzer lesen darf: `file:` im URL-Feld (AK-13), Symlinks (AK-18) |
| 3 · Rate Limit | trifft nicht zu; Ersatzprüfung, Hinweis H-3 | Keine Anmeldung der App, kein kostenpflichtiger Dienst (Katalog 4.1–4.3). `testAngriff03_WiederholteAbrufeOhneBremse`: 10 Importe gegen einen 401-Server mit Benutzerinfo ergeben 30 Anfragen, davon 10 mit `Authorization`, in 0,03 s. Keine Bremse, Meldung jeweils „Netzwerkfehler: HTTP 401" |
| 4 · PII in Protokollen | teils bestanden, Hinweis H-4 | Meldungen der App ohne Zugangsdaten (AK-33, 9 Fälle). App-eigene Log-Einträge: 0. Regulär gestartete Sonde mit dem App-Code: 0 Klartext, 31 × `<private>`. Test-Host unter `xcodebuild`: 1 CFNetwork-Zeile mit Passwort (Private-Data-Logging aktiv) |
| 5 · PII an externe Dienste | bestanden, mit BUG-01-Bezug | Tatsächlicher Payload (`qa/Angriff-05-payload.txt`): `GET /get.php?username=qa-user&password=qa-pass-b02a5&type=m3u_plus HTTP/1.1` mit `Host`, `Accept`, `Accept-Language: de-DE,de;q=0.9`, `Connection`, `Accept-Encoding`, `User-Agent: Mika+Player/3 CFNetwork/… Darwin/27.0.0`. Das Fragment wird nicht gesendet, sonst nichts entfernt. Logo- und Stream-Hosts der Liste: **0 Verbindungen** beim Import. Basic-Auth erst nach 401 und nie an ein Weiterleitungsziel (AK-14). Cookies nur an denselben Host (AK-36) |
| 6 · Geheimnisse | bestanden | `git log -p --all` (19 Commits) und Arbeitsbaum: nur Beispiel- und `qa-`-Werte (AK-43). `strings` über `MikaPlusPlayer` und `MikaPlusPlayer.debug.dylib` des Builds: 0 × `password=`/`username=`, 0 × `sk_live_`, `service_role`, `PRIVATE KEY`, `qa-pass`, `get.php?` |
| 7 · Eingaben | bestanden, Hinweis EC-06 | `testAngriff07_Eingaben` (`qa/Angriff-07-eingaben.txt`). URL-Feld mit leer, `x`, 10.000 Zeichen, Emoji, `'; drop table ZPLAYLIST; --`, `<script>…`, `../../etc/passwd`, `%00%0d%0a`, NUL: jeweils „Die angegebene URL ist ungültig.", kein Absturz. Namensfeld: alle Werte exakt gespeichert, leer ergibt den Host. Dieselben Werte als Sendernamen: 9 Sender, SQL- und Script-Text unverändert gespeichert, keine Wirkung. Steuerzeichen erreichen B04 (EC-06) |
| 8 · Löschen | teils bestanden, **BUG-02** | AK-42: Zeilen 0, `-wal` offen 4 Vorkommen, geschlossen 0. **Bleiben:** Plattencache-Eintrag mit Passwort (1) und Cookie (1). Das einmalige Leeren aus B01 wirkt nur einmal (AK-35) |

## Fehler

### BUG-01 · Zugangsdaten aus M3U-Links im Klartext in der Datenbank; der Schutz aus B01 greift nicht — hoch

**Betrifft:** AK-34, FB-01
**Reproduktion:**
1. Temp-Store über `AppPersistence.diskContainer` öffnen.
2. `PlaylistImporter.importFromURL("http://127.0.0.1:<port>/get.php?username=qa-user&password=qa-pass-b02ak34-…&type=m3u_plus&output=ts")`. Der Server liefert 3 Sender mit Adressen `…/live/qa-user/<pass>/101.ts`, `…/qa-user/<pass>/102`, `…/live/103.m3u8?token=<pass>`.
3. `select count(*) from ZPLAYLIST where instr(ZSOURCEURL, '<pass>') > 0` und dieselbe Abfrage auf `ZCHANNEL.ZSTREAMURL` ausführen.
4. `AppPersistence.migrateCredentials(...)`, `StreamURLResolver.playableURL(for:)` aufrufen, `isExcludedFromBackup` lesen.

**Erwartet:** kein Passwort in der Datenbank, wie seit B01 für Xtream. Zugangsdaten im Schlüsselbund, die abspielbare
Adresse erst beim Abspielen zusammengesetzt.
**Tatsächlich:** `ZSOURCEURL` 1 von 1, `ZSTREAMURL` 3 von 3 mit Passwort, 4 Bytefolgen im `-wal`. Kein
Schlüsselbund-Eintrag. Umstellung `migratedPlaylists: 0`, danach unverändert. Resolver: 3 von 3 abspielbaren Adressen
mit Passwort. `isExcludedFromBackup = false`, obwohl `AppPersistence` den fehlenden Ausschluss mit „enthält keine
Zugangsdaten mehr" begründet. Bei `http://user:pass@…` steht das Passwort ebenso in `sourceURL`. Bei 17.000 Sendern
aus einem `get.php`-Link bis zu 17.001 Kopien.
**Ort:** `Sources/Services/PlaylistImporter.swift:51-53, 63` (Eingabe unverändert als `sourceURL`), `:289-298`
(Stream-Adressen unverändert); `Sources/Services/StreamURLResolver.swift:25` (nur `isXtream`);
`Sources/Services/AppPersistence.swift:19-20` (Begründung Backup), `:271` (Umstellung nur `isXtream`)
**Vorschlag:** Zugangsdaten aus Query und Benutzerinfo der M3U-Adresse und den gleichlautenden Teilen der
Stream-Adressen wie bei Xtream in den Schlüsselbund verlagern, oder den Backup-Ausschluss und die Begründung an den
tatsächlichen Inhalt anpassen.

**Behoben 2026-09-26:** Zugangsdaten aus M3U-Adressen (Query `username`/`password`, Benutzerinfo `user:pass@`) liegen
je Playlist im Schlüsselbund (`M3USecret` im Dienst von `XtreamCredentialStore`, Konto = `Playlist.id`, mit der
eingegebenen Adresse für den Abruf). `Playlist.sourceURL` und jede Stream-Adresse tragen an diesen Stellen Platzhalter
(`Services/M3UCredentials.swift`: jeder Pfadabschnitt und Query-Wert gleich dem Passwort, der Benutzername direkt davor
bzw. in `username`/`user`, die Benutzerinfo). `StreamURLResolver` setzt sie erst beim Abspielen ein; `refresh` ruft die
Adresse aus dem Schlüsselbund ab; `AppPersistence.migrateCredentials` stellt vorhandene Datenbanken beim Start um
(Schlüsselbund, Platzhalter, dieselben Sender-Objekte, Verdichten), Altbestand zusätzlich beim Aktualisieren. Die
Begründung für den fehlenden Backup-Ausschluss trifft damit auch für M3U zu. Nachweis:
`B02SicherheitTests.testAK34_ZugangsdatenAusM3ULinkImSchluesselbund` (0/1 bzw. 0/3 Zeilen mit Passwort, 0 Bytes,
1 Eintrag, 3/3 Adressen abspielbar wie in der Liste), `testAK34_BenutzerinfoImSchluesselbund`,
`B02ReparaturTests.testBUG01_*` (Zerlegen/Wiederherstellen, Aktualisieren, fehlender Eintrag, Umstellung Temp-Datenbank
und v1.1-Vorlage). Nicht erfasst: `token=` und andere Parameter (→ spec.md OF-10).

### BUG-02 · M3U-Abruf schreibt Adresse samt Zugangsdaten und Antwort in den HTTP-Plattencache; Löschen entfernt sie nicht — mittel

**Betrifft:** AK-35, AK-42 (Angriff 8), FB-02
**Reproduktion:**
1. `URLCache.shared` auf einen Temp-Ordner lenken (dieselbe Instanz nutzt `URLSession.shared` der App).
2. `get.php`-Link mit Passwort importieren; der Server antwortet ohne `Cache-Control`.
3. `cachedResponse(for:)` abfragen und die Bytes im Ordner zählen.
4. Playlist über `PlaylistImporter.delete` löschen und erneut abfragen.
5. `AppPersistence.purgeLegacyHTTPCacheOnce` zweimal mit einem frischen `UserDefaults`-Suite aufrufen, dazwischen erneut importieren.

**Erwartet:** keine Kopie außerhalb der Datenbank; nach dem Löschen keine Spur der Zugangsdaten.
**Tatsächlich:** 1 Cache-Eintrag, Antwortkörper mit Passwort, 8 Bytefolgen in `Cache.db-wal`. Nach dem Löschen
unverändert 1 / 8. Nur `Cache-Control: no-store` verhindert den Eintrag. Das Leeren aus B01 läuft einmal: Nach dem
ersten Aufruf ist der Cache leer, ein neuer Import schreibt wieder, der zweite Aufruf gibt `false` zurück und der
Eintrag bleibt. Beim Aktualisieren (B03) entsteht er erneut.
**Ort:** `Sources/Services/PlaylistImporter.swift:307-311` (`URLSession.shared`, `.reloadIgnoringLocalCacheData`
verhindert nur das Lesen); `Sources/Services/AppPersistence.swift:361-366`
**Vorschlag:** Für M3U-Abrufe eine eigene Session ohne `urlCache` (und ohne gemeinsamen Cookie-/Zugangsdatenspeicher)
verwenden, wie B01 sie mit `XtreamHTTPLoader` gebaut hat.

**Behoben 2026-09-26:** M3U-Abrufe (Import und Aktualisieren) laufen über denselben Loader wie Xtream
(`Services/PlaylistHTTPLoader.swift`, vormals `XtreamHTTPLoader`: `ephemeral`, `urlCache = nil`, kein
`URLCredentialStorage`); Weiterleitungen folgen wie bisher (AK-11), Basic-Auth nie an ein anderes Ziel (AK-14).
Cookies leben nur im Arbeitsspeicher dieser Session (AK-36 bleibt erfüllt) und werden beim Löschen für den Host
entfernt. Das einmalige Leeren läuft mit neuem Merker `B02.legacyHTTPCachePurged` noch einmal; `delete` entfernt
zusätzlich einen etwaigen Alt-Eintrag der Adresse. Nachweis: `testAK35_KeinPlattencacheFuerM3UAbrufe` (0 Einträge,
0 Bytes – auch nach erneutem Import), `testAK42_LoeschenLaesstKeineZugangsdatenZurueck`,
`B02URLImportTests.testAK36_…`, `B03LoeschenTests.testAK33_…`.

### BUG-03 · Keine Größen-, Längen-, Mengen- oder Gesamtzeitgrenze für unvertraute Listen — mittel

**Betrifft:** AK-37, AK-38, EC-13, EC-14, FB-03
**Reproduktion:**
1. Server bzw. Datei mit 52.062.788 Byte: 1.000 Einträge mit je 52.000 Zeichen langem Namen.
2. Per URL und per Datei importieren.
3. Zweiter Fall: Der Server sendet eine Liste mit 20 Sendern in 10 Stücken, eines alle 10 s.

**Erwartet:** Ablehnung ab einer Grenze. B01 hat für Xtream 64 MiB, 100.000 Sender, 180 s und 512 Zeichen eingeführt.
**Tatsächlich:** Beide 52-MB-Importe gelingen, der längste gespeicherte Name hat 52.004 Zeichen. Blockade 3,61 s
bzw. 3,49 s (Release 1,76 s / 1,79 s), Prozessspeicher bis 655 MB. Die tröpfelnde Antwort wird nach 100,30 s
importiert. Der Parser übernimmt 1 MB Name, 5 MB Logo-Adresse und 2 MB Stream-Adresse ungekürzt. 300.000 Einträge
brauchen im Parser +252 MB.
**Ort:** `Sources/Services/PlaylistImporter.swift:199` (`Data(contentsOf:)`), `:311` (Antwort vollständig);
`Sources/Services/M3UParser.swift` (keine Kürzung)
**Vorschlag:** Grenzen für Bytes (auch Datei), Senderzahl, Feldlängen und Gesamtdauer analog zu
`XtreamClient.Limits` einziehen.

**Behoben 2026-09-26:** `PlaylistImporter.M3ULimits` (analog `XtreamClient.Limits`): 64 MB je Antwort und Datei
(Datei vor dem Lesen geprüft), 100.000 Sender (Parser hört danach auf), 180 s Gesamtfrist, 60 s Leerlauf (unverändert)
und ab 20 s ein Mindestdurchsatz von 2 KiB/s; der Parser kürzt Name, Gruppe und tvg-ID auf 512 Zeichen und verwirft
Stream-Adressen über 4.096 und Logo-Adressen über 2.048 Zeichen. Nachweis: `testAK37_GrosseAntwortUndDateiMitGrenze`
(längster Name 512), `B02LangsamTests.testAK12_AK28_AK38_EC17_…` (Tröpfeln endet vor 60 s mit „Der Server liefert
die Playlist zu langsam."; Leerlauf weiter 60 s), `B02ParserTests.testEC13_…`, `B02ReparaturTests.testBUG03_…`
(Größe URL/Datei, Menge, Frist). Werte → spec.md OF-11.

### BUG-04 · Der Import friert die Oberfläche ein; 17.000 Sender ≈ 282 s, auch im Release-Build — hoch

**Betrifft:** AK-40, EC-19, FB-04
**Reproduktion:**
1. Server liefert N Sender im Anbieterformat (≈ 146 Byte je Eintrag).
2. `PlaylistImporter.importFromURL` auf dem Main-Actor aufrufen, einen Main-Thread-Wächter mitlaufen lassen.
3. Mit `-configuration Release` wiederholen.

**Erwartet:** Die Oberfläche bleibt bedienbar. FAQ und README versprechen „a few seconds" bzw. „einige Sekunden".
Das PRD nennt Listen mit mehr als 17.000 Sendern als Zielgröße.
**Tatsächlich:** 17.000 Sender brauchen 282,04 s (Debug) bzw. 282,54 s (Release), die längste Blockade ist praktisch
gleich lang. Doppelte Menge ergibt die 3,9- bis 4-fache Zeit. Der Parser allein braucht 0,15–0,32 s. Weil Release
und Debug gleich sind, steckt der Aufwand in SwiftData (Beziehung je Sender), nicht im eigenen Code. Datei-Import und
Datei-Lesen laufen ebenfalls synchron auf dem Main-Thread (3.000 Sender: 9,23 s, AK-29 Datei).
**Ort:** `Sources/Services/PlaylistImporter.swift:22` (`@MainActor`), `:58-66`, `:197-212`, `:289-304`
(`Channel(playlist:)` + `playlist.channels.append` je Sender); Versprechen `web/content/faq.ts:35`, `README.md:307`
**Vorschlag:** Denselben Weg wie B01 · BUG-12 gehen: eigener `ModelContext` abseits des Main-Actors, Beziehung
blockweise per `append(contentsOf:)`, Lesen der Datei außerhalb des Main-Threads.

**Behoben 2026-09-26:** Abruf, Datei-Lesen, Parsen und Aufbereiten laufen abseits des Main-Actors
(`nonisolated` in `PlaylistImporter`), gespeichert wird über `PlaylistStore` (eigener `ModelContext`, Beziehung
blockweise per `append(contentsOf:)`) – derselbe Weg wie Xtream. 17.000 Sender per URL: 2,36 s gesamt (Store-Datei
2,45 s), längste Main-Thread-Blockade 0,00 s (vorher 282 s); per Datei 2,42 s / 0,00 s. Nachweis:
`B02LangsamTests.testAK40_…` (Standard 1.500/3.000/6.000 und `TEST_RUNNER_B02_QA_SIZES=17000`),
`B02ReparaturTests.testBUG04_DateiImportBlockiertDenMainThreadNicht`.

### BUG-05 · Stream- und Logo-Adressen werden ohne Schema-Prüfung übernommen — mittel

**Betrifft:** AK-39, FB-05
**Reproduktion:**
1. Liste mit Stream-Adressen `file:///etc/hosts`, `file:///Users/qa/Movies/privat.mp4`, `javascript:alert(1)`, `data:…`, `smb://…`, `udp://@239.0.0.1:1234`, `rtp:`, `rtsp:`, `rtmp:`, `ftp:`, `mailto:`, `vlc://quit`, `x-apple.systempreferences:…` und Logos `file:///etc/hosts`, `javascript:…`, `smb://…` per URL importieren.
2. SQLite-Abfrage der Schemata in `ZSTREAMURL` auf der Temp-Datenbank.

**Erwartet:** Nur für Wiedergabe bzw. Bildladen vorgesehene Schemata übernehmen (etwa `http`, `https`, ggf. `rtsp`,
`udp`), den Rest verwerfen.
**Tatsächlich:** Alle 17 Einträge gespeichert. Schemata in der DB: `data, file, ftp, http, javascript, mailto, rtmp,
rtp, rtsp, smb, udp, vlc, x-apple.systempreferences`. Verworfen wird nur eine Adresse ohne Schema. Was beim Antippen
bzw. Anzeigen passiert, entscheiden B06/B08 (VLCKit) und B04 (`AsyncImage`).
**Ort:** `Sources/Services/M3UParser.swift:48` (`url.scheme != nil`), `:53` (Logo ungeprüft)
**Vorschlag:** Erlaubte Schemata für Stream- und Logo-Adressen festlegen und im Parser prüfen.

**Behoben 2026-09-26:** `M3UParser` übernimmt nur Stream-Adressen mit `http`, `https`, `rtsp`, `rtsps`, `rtmp`, `rtmps`,
`rtp`, `udp`, `mms`, `mmsh` und Logos über `http`/`https`; alles andere (`file:`, `smb:`, `javascript:`, `data:`, `vlc:`,
`ftp:`, relative Logos …) fällt weg – auch in lokalen Dateien. Nachweis: `testAK39_NurErlaubteSchemataWerdenGespeichert`
(Schemata in der DB: http, rtmp, rtp, rtsp, udp; keine Logos), `B02ParserTests.testEC10_…`, `testEC11_…`,
`B02DateiImportTests.testEC10_…`. Auswahl → spec.md OF-12.

### BUG-06 · „Öffnen mit" importiert nicht; jedes Öffnen erzeugt ein leeres Fenster — mittel

**Betrifft:** AK-31, EC-23, FB-06
**Reproduktion:**
1. Kopie der App (eigene Bundle-ID, Datenbank im Speicher) mit `open -a <App> qa-doppelklick.m3u` starten.
2. Bei laufender App `.m3u8`, `.txt` und `.m3u` öffnen.
3. Im Test-Host dasselbe „Dokumente öffnen"-Ereignis über den AppKit-Handler zustellen und das neue Fenster über Accessibility lesen.

**Erwartet:** Die Website sagt „Mika+Player also registers as a handler for .m3u files, so double-clicking one opens it
here". Erwartet wird also ein Import oder zumindest das Import-Sheet mit der Datei.
**Tatsächlich:** Kaltstart 1 Fenster; danach 2, 3, 4 Fenster in einem Prozess. Jedes neue Fenster heißt „Playlists"
und zeigt „Keine Playlists", ohne „Sender" und ohne „Fehler". Der Doppelklick im Finder öffnet auf dem Prüfrechner
ohnehin Music.app (`.m3u`/`.m3u8`) bzw. TextEdit.app (`.txt`). iOS-Build: Warnung zu
`LSSupportsOpeningDocumentsInPlace`.
**Ort:** `Sources/Resources/Info.plist:76-90`; `Sources/App/MikaPlusPlayerApp.swift:29-35` (`WindowGroup` ohne
`handlesExternalEvents`/`onOpenURL`); Versprechen `web/content/features.ts:48`
**Vorschlag:** Entweder einen Handler bauen (`onOpenURL` → Import, ohne neues Fenster) oder Registrierung und
Website-Aussage entfernen.

**Behoben 2026-09-26:** `Views/PlaylistDocumentHandler.swift` (`onOpenURL`) importiert übergebene Dateien über
`importFromFile` (macOS „Öffnen mit"/Doppelklick, iOS „Öffnen in"); die Hauptszene nimmt Ereignisse im offenen Fenster
entgegen (`handlesExternalEvents(preferring:allowing:)`, Multiview-Fenster ausgenommen), statt je Ereignis ein leeres
Fenster zu erzeugen. `LSSupportsOpeningDocumentsInPlace = YES` (Datei wird an Ort und Stelle gelesen; beseitigt die
iOS-Build-Warnung aus EC-23). Nachweis: `B02OberflaecheTests.testAK31_OeffnenEreignisImportiertImOffenenFenster`
(höchstens 1 neues Fenster, 3 importierte Playlists sichtbar). Ob der Finder-Doppelklick Mika+Player oder Music.app
öffnet, entscheidet LaunchServices (→ spec.md OF-13, Website B10).

### BUG-07 · Mika+Player meldet sich als Öffner für alle Text-Typen — niedrig

**Betrifft:** AK-32, FB-07
**Reproduktion:** Für Dateien mit den Endungen `json`, `html`, `csv`, `swift`, `md`, `log`, `pls` die Kandidatenliste
von LaunchServices lesen (`NSWorkspace.urlsForApplications(toOpen:)`).
**Erwartet:** Angeboten nur für M3U-Playlists.
**Tatsächlich:** Mika+Player steht bei `m3u`, `m3u8`, `txt`, `json`, `html`, `csv`, `swift`, `md`, `log` und `pls` in der
Liste, nicht bei `xspf` und bei Dateien ohne Endung. Öffnen bewirkt nur ein leeres Fenster (BUG-06).
**Ort:** `Sources/Resources/Info.plist:87` (`public.text`), Rang `Default` (`:83`)
**Vorschlag:** `public.text` entfernen, Rang `Alternate` erwägen.

**Behoben 2026-09-26:** `Info.plist`: `CFBundleDocumentTypes` nur noch `public.m3u-playlist` (deckt `.m3u` und `.m3u8`),
`public.text` entfernt, Rolle `Viewer`. Nachweis: `testAK31d_AK32_OeffnerRegistrierung` prüft die Dokumenttypen des
gebauten Bundles (m3u, m3u8 ja; txt, json, html, csv, swift, md, log, pls, xspf, ohne Endung nein). LaunchServices
listet ältere gebaute Kopien in anderen Build-Ordnern weiter, bis sie neu registriert oder gelöscht werden.

### BUG-08 · „Abbrechen" bricht URL- und Datei-Import nicht ab; ein späterer Fehler erscheint in einem losgelösten Fenster — mittel

**Betrifft:** AK-29, EC-21, FB-08
**Reproduktion:**
1. Sheet, Reiter „URL", Server antwortet nach 2 s mit einer gültigen Liste.
2. „Von URL importieren", nach 0,4 s „Abbrechen", 4 s warten.
3. Wiederholen, der Server antwortet nach 2 s mit 500.
4. Datei-Reiter: im Dialog eine Datei mit 3.000 Sendern wählen, „Abbrechen" nach 0,5 s klicken.

**Erwartet:** Wie seit B01 · BUG-11 beim Xtream-Reiter desselben Sheets: Nach „Abbrechen" entsteht nichts und es
erscheint nichts.
**Tatsächlich:** (a) 0 Playlists direkt, **1 nach 4 s**. (b) Zwei neue Fenster auf dem Bildschirm: das geschlossene
Sheet ohne Elternfenster mit eingetragener URL und darauf der Alert „Fehler – Netzwerkfehler: HTTP 500"
(Aufnahmen `qa/AK-29-losgeloestes-fenster-0.png`, `-1.png`). (c) Datei: Main-Thread 9,23 s blockiert, der Klick kommt
erst nach dem Import an, die Playlist mit 3.000 Sendern ist angelegt. Das Sheet öffnet danach normal (EC-21).
**Ort:** `Sources/Views/ImportPlaylistView.swift:106`, `:208` (ungebundene `Task`), `:133-136` und `:154` (brechen nur
`xtreamImportTask` ab), `:192-202`, `:214-224` (Alert ohne Abbruchprüfung)
**Vorschlag:** URL- und Datei-Import wie `startXtreamImport` als gebundene, abbrechbare Aufgabe führen und nach Abbruch
weder speichern noch `errorMessage` setzen; für die Datei setzt das BUG-04 voraus.

**Behoben 2026-09-26:** `ImportPlaylistView.startImport` führt URL-, Datei- und Xtream-Import als eine gebundene
Aufgabe; „Abbrechen" und das Schließen des Sheets brechen sie ab, danach wird nichts gespeichert und kein Fehler mehr
angezeigt (`PlaylistStore.create` prüft den Abbruch je Block und räumt auf). Nachweis:
`testAK29_EC21_AbbrechenBrichtURLImportAb` (0 Playlists nach 4 s, kein losgelöstes Fenster),
`testAK16_AK27_AK29_DateiImportUeberDialog` (40.000-Sender-Datei, „Abbrechen" nach 0,5 s → keine zweite Playlist).

### BUG-09 · Zwei Klicks auf „Von URL importieren" vor dem Neuzeichnen starten zwei Importe — niedrig

**Betrifft:** AK-30, FB-09
**Reproduktion:**
1. Sheet, Reiter „URL", Server antwortet nach 1 s.
2. Zwei Mausklick-Ereignisse auf „Von URL importieren" im selben Durchlauf senden.

**Erwartet:** ein Import, wie seit B01 · BUG-09 beim Xtream-Reiter.
**Tatsächlich:** 2 Anfragen, 2 gleiche Playlists. Mit 150 ms Abstand bleibt es bei 1/1.
**Ort:** `Sources/Views/ImportPlaylistView.swift:105-110` (Aufgabe starten), `:193` (`isImporting` erst in der Aufgabe)
**Vorschlag:** `isImporting` vor dem Start der Aufgabe setzen und doppelten Start abweisen (Muster `startXtreamImport`).

**Behoben 2026-09-26:** `isImporting` wird in `startImport` vor dem Start der Aufgabe gesetzt, ein zweiter Start
wird abgewiesen (Muster aus B01 · BUG-09, jetzt für alle Reiter). Nachweis:
`testAK30_DoppelklickAufVonURLImportierenEinImport` (1 Anfrage, 1 Playlist).

## Hinweise (kein Kriterium durchgefallen)

- **H-1 · Basic-Auth wird ab dem zweiten Abruf sofort mitgeschickt.** Nach einer erfolgreichen Anmeldung schickt
  `URLSession.shared` die `Authorization`-Kopfzeile bei jedem weiteren Abruf desselben Hosts direkt mit, ohne 401
  (`testAK14_…`, Fall „3-basic-erneut": 1 Anfrage, mit Auth). Die Zugangsdaten liegen für die Sitzung im
  gemeinsamen `URLCredentialStorage` (Persistenz „Sitzung"), nicht im Schlüsselbund (0 Internet-Passwörter für
  `qa-user`). Fällt mit BUG-02 (eigene Session) weg.
- **H-2 · `ftp://` öffnet eine TCP-Verbindung zum Ziel** (1 Verbindung, keine HTTP-Anfrage) und wartet 60 s bis zur
  Meldung „timed out".
- **H-3 · Drei Anfragen je Versuch bei 401 mit Benutzerinfo** (ohne → mit → ohne Auth). Kein Kriterium, keine Grenze
  gefordert (Katalog 4.1 trifft nicht zu).
- **H-4 · Klartext-Adresse im Systemprotokoll bei aktivem Private-Data-Logging** (Test-Host unter `xcodebuild`:
  1 CFNetwork-Zeile). Regulär gestartet geschwärzt. Wie B01 H-2; nicht allein in der App behebbar, solange
  Zugangsdaten in der URL stehen.
- **H-5 · Datenschutzseite (FB-10, gehört zu B10).** `web/app/privacy/page.tsx:36-38` nennt als gespeicherte
  Zugangsdaten nur den Xtream-Login und sagt „no copy anywhere else". `:47-49` sagt „Every stream, channel list and
  logo request goes to the host you entered". Belegt widerlegt durch BUG-01 und BUG-02, Cookies (AK-36),
  Weiterleitungsziele (AK-11) sowie Stream- und Logo-Hosts aus der Liste (AK-39). Zur Korrektur an B10.
- **H-6 · Aussagen zur Importdauer:** `web/content/faq.ts:35` („takes a few seconds") und `README.md:307` gelten weiter,
  `README.md:299` empfiehlt weiter die große `iptv-org`-Liste. Die Support-Seite empfiehlt sie nicht mehr. Gehört zu
  BUG-04 und B10.
- **H-7 · Aufräumen der Testumgebung:** siehe *Prüfumgebung*, Zeile Cookies/Zugangsdatenspeicher. Zwei leere
  `UserDefaults`-Dateien eines früheren Laufs (`lu.daumedia.MikaPlusPlayerTests.b02.*`) wurden entfernt; der Test löscht
  sie jetzt selbst.

## Codequalität

`code-reviewer`-Agent über `M3UParser.swift`, die B02-Teile von `PlaylistImporter.swift` und `ImportPlaylistView.swift`,
`Info.plist` und `MikaPlusPlayerApp.swift`, mit Verweis auf `design.md` und die bekannten FB/OF. **Keine neuen Funde
mit hoher Konfidenz.** Einen eigenen Verdacht hat er selbst verworfen: Doppelte Einträge in der Beziehung durch
`Channel(playlist:)` plus `append`. Hier verifiziert: nicht reproduzierbar. `channels.count == channelCount == N` in
AK-06 (2) und AK-40 (`beziehung=17000`). Seine Aussage, die Zeilennummern deckten sich 1:1 mit `design.md`, stimmt für
`PlaylistImporter.swift`, `ImportPlaylistView.swift` und `M3UParser.swift`. Für `Info.plist` und `AppPersistence.swift`
stimmt sie nicht (siehe unten).

### Abweichung Spec ↔ Code (Korrekturen an der Rekonstruktion)

| Stelle | Spec/Design sagt | Ausgeführt bzw. aktueller Stand |
|---|---|---|
| Fundstellen nach der B09-Reparatur | `Info.plist:68-82`, `:79` (`public.text`), `:37-41` (ATS); `AppPersistence.swift:131`, `:16-17`, `:221-226` | `Info.plist:76-90`, `:87`, `:45-49`; `AppPersistence.swift:271`, `:19-20`, `:361-366`. Verhalten unverändert |
| B09-Einfluss | — | Start über `AppPersistence.openAppStore` mit versioniertem Schema und Wiederherstellung. Für B02 ohne Wirkung; Import über `diskContainer` mit Migrationsplan belegt (AK-13, AK-34, AK-39, AK-42) |
| AK-05 | „Dialog gelesen" | Dialog geöffnet; Typen am `NSOpenPanel` abgelesen |
| AK-12 / EC-17 | `ftp://`: Wartezeit „aus der Laufzeit abgeleitet" | gemessen 60,02 s; eine TCP-Verbindung zum Ziel (H-2) |
| AK-14 | „die erste Anfrage geht ohne `Authorization`" | gilt je Sitzung und Host; weitere Abrufe senden sofort (H-1) |
| AK-16, AK-27, AK-29 (Datei) | „Symbol und Menü gelesen", „für Datei gelesen" | ausgeführt (Dialog-Abschluss, Aufnahme, Kontextmenü, Alert, Abbrechen) |
| AK-36 | `Mika+Player/<Build>` (Erfassung: `/2`) | `Mika+Player/3` — `CURRENT_PROJECT_VERSION` seit B09 = 3 |
| AK-37 | Speicher +120 MB (Datei) / +223 MB (URL) | gemessen +54 MB (Datei, nach dem URL-Lauf) / +249 MB (URL); Richtwerte, abhängig vom Ausgangsspeicher |
| AK-40 | 286,6 s (Debug) | Debug 282,04 s, Release 282,54 s |
| AK-35 / Design „Außerhalb des Schemas" | `Cache.db` | die Bytes stehen in `Cache.db-wal` |
| EC-08 | „0x85 macht aus … einen Zeilentrenner; der Sender geht verloren" | nur wenn der Rest der Zeile keine Adresse ist (… mitten im Namen); am Zeilenende bleibt der Sender |
| EC-20 | „für URL gelesen" | ausgeführt |
| EC-22 | „macOS stellt alle zusätzlich geöffneten leeren Fenster wieder her (3 bzw. 4)" | nicht reproduziert: nach SIGTERM und nach normalem Beenden jeweils 1 Fenster |
| FB-04 | `web/app/support/page.tsx:121` empfiehlt eine große Liste | nicht mehr auf der Support-Seite; `README.md:299` weiter |

## Neue Tests

Alle unter `Tests/B02/`, dauerhaft, Testnamen mit AK-/EC-Nummer. Tests, die einen Fehler belegen, prüfen zuerst das
Ist und tragen für das Soll `XCTExpectFailure("BUG-NN …")`. Die Reparatur entfernt die Markierung, dann muss der Test
ohne sie grün sein.

| Datei | Fälle | Deckt ab |
|---|---|---|
| `B02Support.swift` | — | `B02Server` (Loopback-HTTP mit Rohmitschrift, frei gebauten Antworten, Stillstand, Tröpfeln), `B02TestCase` (umgelenkter Plattencache, Aufräumen von Cookies/Zugangsdaten nur `qa-…`), Temp-/In-Memory-Container über `AppSchema`/`AppPersistence`, SQLite, Belegdateien |
| `B02ParserTests.swift` | 18 | AK-20 … AK-24, AK-26, AK-40 (Parser), EC-01 … EC-06, EC-10 … EC-14 |
| `B02URLImportTests.swift` | 14 | AK-06 … AK-15, AK-25 (URL), AK-26, AK-28, AK-33, AK-36, EC-01, EC-15 … EC-17 |
| `B02DateiImportTests.swift` | 7 | AK-16 … AK-19, AK-25 (Datei), EC-07 … EC-10, EC-19 |
| `B02SicherheitTests.swift` | 11 | AK-34, AK-35, AK-37, AK-39, AK-41, AK-42; Angriff 1, 3, 5, 7, 8 · BUG-01, 02, 03, 05 |
| `B02OberflaecheTests.swift` | 13 | AK-01 … AK-06, AK-16, AK-27, AK-29 … AK-32, EC-20, EC-21 · BUG-06 … 09 |
| `B02LangsamTests.swift` | 2 | AK-12 (`ftp`), AK-28 (60 s), AK-38, AK-40, EC-17 · BUG-03, 04 — ≈ 100 s plus Messreihe; 17.000 nur mit `TEST_RUNNER_B02_QA_SIZES` |

Belege in `features/B02-m3u-import/qa/`: `testlauf-protokoll.txt`, `AK-05-dateidialog.txt`, `AK-31-32-oeffnen.txt`,
`AK-34-35-42-sqlite.txt`, `AK-37-EC-13-grenzen.txt`, `AK-39-schemata.txt`, `AK-40-messung.txt`, `AK-41-protokoll.txt`,
`Angriff-05-payload.txt`, `Angriff-07-eingaben.txt` und 9 Aufnahmen (`AK-01-…` ×2, `AK-06-…`, `AK-16-…` ×2,
`AK-29-…` ×2, `AK-31-…`). Die Aufnahmen des Dateidialogs sind leer (Inhalt aus einem Systemdienst) und deshalb nicht
abgelegt.

## Für befunde.md

| Befund | Grad | Fundstelle | BUG-Nr. |
|---|---|---|---|
| Zugangsdaten aus M3U-Links (`get.php?…password=`, `user:pass@`) im Klartext in `Playlist.sourceURL` und jeder `Channel.streamURL`; kein Schlüsselbund, Umstellung und Resolver greifen nur für Xtream; Datenbank nicht vom Backup ausgeschlossen | hoch | `PlaylistImporter.swift:51-53, 63, 289-298`, `StreamURLResolver.swift:25`, `AppPersistence.swift:19-20, 271` | BUG-01 |
| Import friert die Oberfläche ein, Aufwand quadratisch: 17.000 Sender 282 s in Debug **und** Release; Datei-Lesen ebenfalls auf dem Main-Thread | hoch | `PlaylistImporter.swift:22, 58-66, 197-212, 289-304` | BUG-04 |
| HTTP-Plattencache enthält Anfrage-Adresse mit Zugangsdaten und Antwortkörper, übersteht das Löschen; einmaliges Leeren aus B01 wirkt nur einmal | mittel | `PlaylistImporter.swift:307-311`, `AppPersistence.swift:361-366` | BUG-02 |
| Keine Größen-, Längen-, Mengen- und Gesamtzeitgrenze für Listen per URL und Datei (52 MB angenommen, 100 s Tröpfeln) | mittel | `PlaylistImporter.swift:199, 311`, `M3UParser.swift` | BUG-03 |
| Stream- und Logo-Adressen jedes Schemas (`file:`, `smb:`, `javascript:`, `vlc:` …) ungeprüft gespeichert | mittel | `M3UParser.swift:48, 53` | BUG-05 |
| „Öffnen mit"/Doppelklick importiert nicht, jedes Öffnen erzeugt ein leeres Fenster; Website verspricht den Doppelklick-Import | mittel | `Info.plist:76-90`, `MikaPlusPlayerApp.swift:29-35`, `web/content/features.ts:48` | BUG-06 |
| „Abbrechen" bricht URL- und Datei-Import nicht ab; späterer Fehler erscheint in losgelöstem Sheet-Fenster | mittel | `ImportPlaylistView.swift:106, 133-136, 154, 192-202, 208, 214-224` | BUG-08 |
| App meldet sich als Öffner (Rang Default) für alle Text-Typen (`public.text`) | niedrig | `Info.plist:83, 87` | BUG-07 |
| Zwei Klicks vor dem Neuzeichnen starten zwei URL-Importe (zwei gleiche Playlists) | niedrig | `ImportPlaylistView.swift:105-110, 193` | BUG-09 |
| Datenschutzseite beschreibt den M3U-Weg nicht zutreffend (Zugangsdaten in M3U-Links, Cache, Cookies, fremde Stream-/Logo-Hosts) | Hinweis an B10 | `web/app/privacy/page.tsx:36-38, 47-49` | — (H-5, FB-10) |
| Doppelter Import derselben URL legt zweite Playlist an | zurückgestellt | `PlaylistImporter.swift:50-68` | — (OF-01, AK-15) |
| `file:`/`data:` im URL-Feld gelten als aktualisierbare Remote-Playlist; `data:` speichert die ganze Liste als Adresse | zurückgestellt | `PlaylistImporter.swift:51-53` | — (OF-02, AK-13) |

**Muster (für `befunde.md` zu prüfen):** Drei Funde wiederholen, was B01 für den Xtream-Zweig bereits behoben hat.
Klartext-Zugangsdaten entsprechen B01 BUG-01, der Plattencache B01 BUG-03, die Main-Actor-Blockade B01 BUG-12.
Dazu kommen „Abbrechen" (B01 BUG-11) und der Doppelklick (B01 BUG-09). Die Reparaturen wurden je Importweg gebaut,
nicht im gemeinsamen Abruf- und Anlegepfad. Dasselbe Sheet verhält sich deshalb je Reiter unterschiedlich.

## Nächster Schritt

`/sdd-build B02` mit dem Auftrag, BUG-01 bis BUG-09 zu beheben. Zuerst die beiden Funde mit dem Grad *hoch*: BUG-01
(Zugangsdaten) und BUG-04 (Blockade). Naheliegend ist, die B01-Bausteine (Schlüsselbund, eigene Session ohne Cache,
Hintergrund-Kontext mit Blockspeicherung, gebundene Aufgabe) auf den M3U-Weg zu übertragen. Danach `/sdd-qa B02`
(Durchlauf 2): Die `XCTExpectFailure`-Markierungen fallen weg, die Tests müssen ohne sie grün werden. Die Messung
AK-40 mit `TEST_RUNNER_B02_QA_SIZES=17000` gehört wieder dazu, auch im Release-Build.

**Die Rückerfassung der übrigen Bestandsfeatures wartet** nach der Regel für Bestandsfeatures mit Befund *hoch*.
Der Code läuft bereits. Offen für Durchlauf 2 bleiben die iOS-Teile (AK-02, AK-19, EC-23), die Entscheidungen
OF-01/OF-02 sowie die Korrektur der Datenschutzseite in B10 (H-5).
