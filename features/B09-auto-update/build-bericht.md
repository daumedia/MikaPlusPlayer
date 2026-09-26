# B09 · Auto-Update — Build-Bericht

Durchlauf 1 · 2026-09-16 · Eingang: Fehlerauftrag (`qa-report.md`, BUG-01 bis BUG-18) · Branch `sdd/rueckerfassung`, nicht committet ·
setzt auf der B01-Reparatur auf (`AppPersistence`, `AppEnvironment`, geänderter App-Start)

## 1 · Umgesetzt

Das nächste Release ist gehärtet und erreicht bestehende Installationen: Die Konfiguration Release läuft mit Hardened Runtime
und ohne `get-task-allow` (der `lldb`-Angriff aus der QA wird jetzt abgewiesen), die Build-Nummer steht auf 3, Sparkle ist
auf 2.9.3 gepinnt und prüft die DMG-Signatur vor dem Einhängen. `release.sh` schreibt den Feed aus der versionierten
`appcast.xml` fort statt aus dem Altstand in `dist/`, signiert ihn und bricht bei jedem Befund der neuen Gegenprüfungen ab,
bevor `appcast.xml` geändert wird – vor dem Build, am Bundle/DMG und am neuen Feed, samt EdDSA-Gegenprobe nur mit dem
öffentlichen Schlüssel. Die Datenbank hat ein versioniertes Schema mit Migrationsplan; eine v1.1-Datenbank öffnet unverändert,
eine nicht zu öffnende wird beiseitegelegt statt die App mit `fatalError` zu beenden, und der Nutzer bekommt einen Hinweis.
Der Menüeintrag „Nach Updates suchen …“ folgt Sparkles Zustand. Der README-Weg zu Developer ID und Notarisierung steht in
richtiger Reihenfolge.

| BUG | Grad | Ergebnis | Wo | Nachweis |
|---|---|---|---|---|
| BUG-01 | kritisch | **offen** (Nutzer/GitHub/Release) | – | Schritte in 2 |
| BUG-02 | kritisch | behoben | `project.yml` (Release: `ENABLE_HARDENED_RUNTIME`, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS`) | Release-Build vorher/nachher, Start, `lldb`-Attach abgewiesen, VLCKit dekodiert; `testFB03_…`, `testBUG02_…` |
| BUG-03 | hoch | **offen** (Apple-Team) | – | Schritte in 2; `testFB05_…` behält `XCTExpectFailure` |
| BUG-04 | hoch | behoben (Build-Nummer); Anzeigeversion **offen** | `project.yml`, `b09_release_check.sh`, `release.sh`, `build-macos.sh`, README | `testFB02_…`, `testBUG04_…` |
| BUG-05 | hoch | **offen** (hängt an BUG-03) | – | Schritte in 2 |
| BUG-06 | hoch | **offen** (Schlüssel, Release) | – | Schritte in 2 |
| BUG-07 | hoch | **offen** (GitHub) | – | Schritte in 2 |
| BUG-08 | hoch | teilweise: Prüfung vor dem Entpacken behoben, Feed-Pflicht **offen** | `Info.plist` (`SUVerifyUpdateBeforeExtraction`), `release.sh` (Feed signieren), `b09_ed25519.swift` | Sparkle-Quelltext, `testFB08_updateVerifiedBeforeExtraction`, `testBUG10_…` (Feed signiert und gültig); `testFB08_signedFeedRequired` behält `XCTExpectFailure` |
| BUG-09 | mittel | **offen, belegt nötig** | Kommentar `MikaPlusPlayer.entitlements`, README | Start ohne Entitlement bricht ab („different Team IDs“); `testFB04_…` mit `XCTExpectFailure` |
| BUG-10 | hoch | behoben | `release.sh` | Attrappe altes vs. neues Skript; `testBUG10_ReleaseSchreibtVersioniertenFeedFort`, `testBUG10_VorBuild…`, `testFB10_releaseScriptDoesNotUseDistAppcast` |
| BUG-11 | mittel | behoben | `scripts/b09_release_check.sh` (neu), `scripts/b09_ed25519.swift` (neu), `release.sh` | 7 Tests in `B09ReleaseSkriptTests`, Attrappe mit falschem Schlüssel |
| BUG-12 | mittel | an B10 übergeben | – | `web/` nicht angefasst |
| BUG-13 | hoch | behoben | `Models/AppSchema.swift` (neu), `AppPersistence` (`openAppStore`, `openStore`), `MikaPlusPlayerApp`, `Views/StoreRecoveryAlert.swift` (neu), Vorlage `Tests/B09/Fixtures/v1.1-schema.store` | 7 Tests in `B09PersistenzTests` |
| BUG-14 | mittel | behoben | `project.yml` `exactVersion: "2.9.3"` | `testFB12_…`, `Package.resolved` nach `xcodegen generate` = 2.9.3 |
| BUG-15 | mittel | behoben | README *Öffentliche Distribution* | nicht ausgeführt (kein Apple-Team) |
| BUG-16 | niedrig | an B10 übergeben | – | `web/` nicht angefasst |
| BUG-17 | mittel | behoben | `Tests/B09/` (4 Dateien, 28 Tests), `scripts/b09_release_check.sh` | Gesamtlauf unten |
| BUG-18 | mittel | behoben | `Services/SparkleUpdater.swift` | 3 Tests in `B09UpdaterTests` inkl. Reproduktion des alten Musters |

Tests: 28 neue B09-Tests, davon 3 mit `XCTExpectFailure` für offene Befunde (BUG-03, BUG-08 Feed-Pflicht, BUG-09).
Gesamt 111 Tests (B01-Stand: 83), 0 Fehlschläge, 4 erwartete Fehlschläge (1 aus B01, 3 aus B09), 1 übersprungen (B01 AK-27, unverändert).

### Belege zu BUG-02 und BUG-09 (Release-Build in eigenem DerivedData)

`scripts/build-macos.sh` wurde **nicht** ausgeführt; `build/MikaPlusPlayer.app` und `dist/` sind unverändert.

**Vorher** (Ausgangsstand, `xcodebuild … -configuration Release -derivedDataPath build/dd-b09-release`):

```
"com.apple.security.app-sandbox" => false
"com.apple.security.cs.disable-library-validation" => true
"com.apple.security.get-task-allow" => true
CodeDirectory v=20400 size=4179 flags=0x2(adhoc) hashes=120+7 location=embedded
```

**Nachher** (`clean build`, gleicher Pfad):

```
** BUILD SUCCEEDED **
{ "com.apple.security.app-sandbox" => false
  "com.apple.security.cs.disable-library-validation" => true }
Identifier=lu.daumedia.MikaPlusPlayer
CodeDirectory v=20500 size=4315 flags=0x10002(adhoc,runtime) hashes=124+7 location=embedded
…/MikaPlusPlayer.app: valid on disk
…/MikaPlusPlayer.app: satisfies its Designated Requirement
CFBundleShortVersionString=1.1  CFBundleVersion=3  SUVerifyUpdateBeforeExtraction=true
Contents/Frameworks/Sparkle.framework: flags=0x10002(adhoc,runtime)
Contents/Frameworks/VLCKit.framework: flags=0x10002(adhoc,runtime)
Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate: flags=0x10002(adhoc,runtime)
Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app: flags=0x10002(adhoc,runtime)
```

**Start** (gleiche Einstellungen, nur `PRODUCT_BUNDLE_IDENTIFIER=lu.daumedia.MikaPlusPlayer.b09probe`; gestartet mit
`XCTestSessionIdentifier` → Test-Host-Modus mit In-Memory-Datenbank, keine Übernahme von `default.store`; in der eigenen
Einstellungsdomäne `SUEnableAutomaticChecks=NO` → keine Update-Prüfung; kein Ton; Domäne und Caches danach gelöscht):

```
PROZESS LÄUFT nach 8 s
…/MikaPlusPlayer.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle
…/MikaPlusPlayer.app/Contents/Frameworks/VLCKit.framework/Versions/A/VLCKit
Netzverbindungen des Prozesses: 0
beendet (exit 143 = SIGTERM durch das Skript)
```

**Angriff aus BUG-02 erneut** (derselbe Build, Nicht-Root):

```
EUID=501 pid=132 läuft=ja
(lldb) process attach --pid 132
error: attach failed: attach failed (Not allowed to attach to process. …)
```

**Wiedergabe unter Hardened Runtime** (Stichprobe, stumm): Kommandozeilenprogramm gegen das eingebettete
`VLCKit.framework` des Release-Builds, ad hoc mit `--options runtime` und denselben Entitlements signiert; Datei
`ffmpeg testsrc`, H.264 in MPEG-TS **ohne Tonspur**, VLC mit `--no-audio --vout=dummy`:

```
Hardened Runtime + DLV (wie Release)  VLC|state=2|isPlaying=true|zeit_ms=7865|dekodierteBilder=368
Kontrolle ohne Runtime                VLC|state=2|isPlaying=true|zeit_ms=7860|dekodierteBilder=368
Runtime ohne DLV                      Reason: tried: '…/VLCKit.framework/…' (… different Team IDs)
```

**BUG-09 – ohne `disable-library-validation`** (Release mit Hardened Runtime, eigene Entitlements-Datei nur mit
`app-sandbox=false`, eigene Bundle-ID):

```
CodeDirectory v=20500 size=4196 flags=0x10002(adhoc,runtime)
Abort trap: 6 … PROZESS BEENDET vor 8 s (exit 134)
dyld[32328]: Library not loaded: @loader_path/../Frameworks/VLCKit.framework/Versions/A/VLCKit
  Reason: tried: '…/VLCKit.framework/Versions/A/VLCKit' (code signature in <…> '…/VLCKit' not valid for use in process:
  mapping process and mapped file (non-platform) have different Team IDs)
```

### Belege zu BUG-10 und BUG-11 (Attrappe im Scratchpad, Test-Schlüssel)

Attrappen-Repository: echte Skripte, `project.yml` (1.2 / 3), `Info.plist` mit Test-`SUPublicEDKey`, echte `appcast.xml`,
Kopie des echten Altstands `dist/appcast.xml`; `build-macos.sh`/`make-dmg.sh` als Stubs (Minimal-App aus `/usr/bin/true`,
ad hoc mit Runtime signiert; DMG über `hdiutil`); `generate_appcast`/`sign_update` 2.9.3 aus `build/dd-test`, Schlüssel per
`--ed-key-file`; `CFFIXED_USER_HOME` im Scratchpad. Nie gegen das echte Repo oder den echten Schlüssel.

**Altes `release.sh`** (nur um `--ed-key-file` ergänzt):

```
<title>MikaPlusPlayer</title>
  1.2 / 3  …/daumedia/…/v1.2/MikaPlusPlayer-v1.2.dmg
  1.1 / 2  https://github.com/Mukaarts/MikaPlusPlayer/releases/download/v1.1/MikaPlusPlayer-v1.1.dmg
  1.0 / 1  https://github.com/Mukaarts/MikaPlusPlayer/releases/download/v1.0/MikaPlusPlayer-v1.0.dmg
```

**Neues `release.sh`** (Auszug, Exit 0):

```
== vor-build …  [ offen] SURequireSignedFeed fehlt (BUG-08) …  [  ok  ] Arbeitsverzeichnis sauber
== nach-build … [  ok  ] kein get-task-allow  [  ok  ] Hardened Runtime aktiv  [ offen] ad-hoc signiert …
                [  ok  ] App im DMG ist das geprüfte Bundle (CDHash 61aeabee…)
Wrote 1 new update, updated 0 existing updates, and removed 0 old updates in appcast.xml
== feed ·       [  ok  ] Kanaltitel unverändert („Mika+Player“)  [  ok  ] keine Mukaarts-URLs
                [  ok  ] Einträge = versionierter Feed + Build 3 (2 3 )  [  ok  ] bestehender Eintrag 2 unverändert
                [  ok  ] EdDSA-Signatur des DMG gültig gegen SUPublicEDKey  [  ok  ] Feed-Signatur gültig gegen SUPublicEDKey
== Ergebnis: keine Beanstandung ==
```

**Falscher Schlüssel** (Exit 1, `appcast.xml` vorher/nachher `45b1c9e9…`/`45b1c9e9…`):

```
Warning: SUPublicEDKey in the app … does not match key EdDSA in the Keychain. …
Wrote 1 new update, …
  [BEFUND] neuer Eintrag ohne sparkle:edSignature
  [BEFUND] Feed-Signatur ungültig
== Ergebnis: BEFUNDE — Release abbrechen ==
```

**Build-Nummer 2** (Exit 1, Abbruch vor dem Build): `[BEFUND] CURRENT_PROJECT_VERSION=2 ist nicht größer als die höchste sparkle:version 2 im Feed`.

**Echtes Repository, nur lesend** (`bash scripts/b09_release_check.sh vor-build`, Exit 1): alle Konfigurationsprüfungen `ok`;
Befunde `MARKETING_VERSION=1.1 ist schon veröffentlicht`, `Arbeitsverzeichnis nicht sauber (47 Einträge)`, `Tag v1.1 existiert
bereits`; offen `SURequireSignedFeed`. Das ist der erwartete Stand bis zur Entscheidung OF-06 und einem Commit.

`scripts/b09_ed25519.swift` gegen das veröffentlichte v1.1-DMG und seine Signatur aus `appcast.xml`: `gültig:
MikaPlusPlayer-v1.1.dmg (36455860 Byte)`; die ersten 1.000.000 Byte derselben Datei: `UNGÜLTIG`; `appcast.xml`: `Feed trägt
keinen Signaturblock` (Exit 2).

## 2 · Offene Kriterien und nicht behobene BUGs

- **BUG-01 · freier Namensraum `Mukaarts`** – nicht im Code lösbar (die Feed-Adresse steht in den ausgelieferten v1.1-Bundles),
  der Nutzer ist informiert. Schritte: (1) GitHub-Konto `Mukaarts` registrieren und halten, darin **kein** Repository
  `MikaPlusPlayer` anlegen (ein gleichnamiges Repository beendet GitHubs Weiterleitung), 2FA an. (2) Anzeigeversion festlegen
  (OF-06), committen, `bash scripts/release.sh`, DMG als Asset von `v<version>` hochladen, **danach** `appcast.xml` pushen – die
  v1.1-Installationen holen das Update über die Weiterleitung und fragen ab dann den daumedia-Feed ab. (3) Mika+FileScope genauso.
- **BUG-03 · Developer ID / Notarisierung** – braucht Apple-Developer-Team, Zertifikat „Developer ID Application“ und
  `notarytool store-credentials`. Danach README-Weg (BUG-15) gehen bzw. `release.sh` darauf umstellen, `CODE_SIGN_IDENTITY`
  umstellen, DMG signieren, BUG-09 nachziehen, `XCTExpectFailure` in `testFB05_…` streichen.
- **BUG-04, Teil Anzeigeversion** – `MARKETING_VERSION` bleibt 1.1 (Produktentscheidung, OF-06). Die Gegenprüfung blockiert
  ein Release, bis sie angehoben ist.
- **BUG-05 · Schlüsselwechsel** – hängt an BUG-03. Schritte: Privatschlüssel sichern (`generate_keys -x <datei>`, offline;
  OF-05); ein Release mit Developer-ID-signierter App **und** signiertem DMG an alle Installationen bringen – ab dann greift
  Sparkles Rückfallweg über die Team-ID (setzt `SUVerifyUpdateBeforeExtraction` voraus, jetzt gesetzt); im Ernstfall neues
  Paar, neuer `SUPublicEDKey`, Release mit Developer ID.
- **BUG-06 · familienweiter Schlüssel** – braucht neues Schlüsselpaar und Release, laut AK-30 erst nach BUG-03/05:
  `generate_keys --account mika-plus-player`, neuen `SUPublicEDKey`, `--account` in `release.sh`, Release mit Developer ID;
  die anderen Mika+-Apps einzeln.
- **BUG-07 · `main` ungeschützt** – GitHub-Einstellung: Ruleset/Branch-Schutz für `main` (Pull Request mit Review, kein
  Force-Push, kein Löschen), 2FA am Konto (OF-04).
- **BUG-08, Teil Feed-Pflicht** – `SURequireSignedFeed` nicht gesetzt: Mit ihm verwirft Sparkle 2.9.3 jeden unsignierten Feed
  („The update feed is improperly signed…“, `SUAppcastDriver.m:94-160`), die veröffentlichte `appcast.xml` ist unsigniert.
  Vorbereitet: `release.sh` signiert und prüft den Feed. Schritte: nächstes Release veröffentlichen, danach in einer Folgeversion
  den Schlüssel setzen (OF-07) und `XCTExpectFailure` in `testFB08_signedFeedRequired` streichen.
- **BUG-09 · `disable-library-validation`** – nicht entfernt, weil nachweislich nötig (Beleg in 1): ohne das Entitlement startet
  das gehärtete Release nicht. Entfernen nach BUG-03.
- **BUG-12, BUG-16 → B10** – Website, `web/` nicht angefasst. Für die B10-Reparatur zusätzlich: Die macOS-App ist weiter ad hoc
  signiert (Gatekeeper-Hinweis bleibt richtig); das nächste Release hat Build 3 und einen signierten Feed; die Aussage
  „Updates that install themselves“ und die Beschreibung, woher Sparkle den Feed liest, bleiben wie in BUG-16 beschrieben.
- **Nicht ausgeführt, nur aus dem Quelltext belegt:** Wirkung von `SUVerifyUpdateBeforeExtraction` in einem echten Update
  (Sparkle 2.9.3 `AppInstaller.m:270-296` prüft vor `unarchiveWithCompletionBlock`; ein Konfigurationsfehler entstünde nur
  ohne EdDSA-Schlüssel, `SPUUpdater.m:345-356`). Ein Update-Durchlauf bräuchte eine installierte App und Sparkles Installer-UI.
  Das Unified Log war in dieser Umgebung nicht lesbar (`log show` lieferte 0 Zeilen), eine Sparkle-Fehlermeldung beim Start
  des Release-Builds ist deshalb nicht ausgeschlossen, nur nicht beobachtet.
- **Nicht beobachtet:** der Hinweis-Dialog nach dem Beiseitelegen und der Menüeintrag in der echten Oberfläche (keine
  UI-Automatisierung); iOS nur gebaut, nicht ausgeführt (Wiederherstellungsweg ist plattformneutral und über die Tests belegt).
- **Wiedergabe unter Hardened Runtime** nur mit einer stummen H.264-Datei belegt (OF-09), nicht mit echten Anbieter-Streams.
- **Nebenwirkung des Testlaufs (vorbestehend, EC-01):** Der Test-Host startet Sparkle; `~/Library/Preferences/
  lu.daumedia.MikaPlusPlayer.plist` hat nach dem Gesamtlauf den Zeitstempel 15:03:05. Nicht Teil des Auftrags (OF-10).

## 3 · Getroffene Annahmen

Alle ohne Rückfrage (Zielmodus) und zur Bestätigung durch den Nutzer.

1. **Hardened Runtime nur für Release**, Debug unverändert (Debugger, Test-Host, Injektion von XCTest).
2. **Build-Nummer 3** (nächste freie nach v1.1 = 2), für iOS und macOS gemeinsam (Template `AppBase`).
3. **Gegenprüfung blockiert** bei: Feed-Adresse, Altstand im Feed, Build-Nummer ≤ Feed, bereits veröffentlichter
   Anzeigeversion (Tag- und DMG-Namenskollision), fehlender Härtung/Pin/`SUVerifyUpdateBeforeExtraction`, **unsauberem
   Git-Stand**, vorhandenem Tag (lokal), ungültiger Bundle-Signatur, `get-task-allow`, fehlender Runtime, abweichenden
   Versionen/Schlüsseln im Bundle, anderem Bundle im DMG, veränderten bestehenden Feed-Einträgen, falscher URL/Länge,
   ungültiger DMG- oder Feed-Signatur. **Nur `[ offen]`** (Apple-Team/Nutzer nötig): ad-hoc-Signatur, `spctl`, unsigniertes
   DMG, `disable-library-validation`, fehlendes `SURequireSignedFeed`; mit `STRENG=1` blockierend. Ohne diese Trennung wäre bis
   zur Developer ID gar kein Release möglich – auch nicht das, das BUG-01 entschärft.
4. **Feed wird ab jetzt signiert** (`sign_update` nach `generate_appcast`). Apps ohne `SURequireSignedFeed` ignorieren den
   Signaturblock; `sign_update` fügt oben einen Warnkommentar ein. Folge: `appcast.xml` nicht mehr von Hand ändern (README).
5. **EdDSA-Gegenprobe** mit CryptoKit per `xcrun swift scripts/b09_ed25519.swift` (Xcode ist für das Release ohnehin nötig),
   nur mit dem öffentlichen Schlüssel aus `Info.plist`.
6. **`dist/appcast.xml`** bleibt liegen (lokal, nicht versioniert, nicht angefasst) und wird nur als `[ skip ]` erwähnt; der
   QA-Test `testFB10_localDistAppcastNotStale` ist durch `testFB10_releaseScriptDoesNotUseDistAppcast` und den Attrappen-Lauf
   ersetzt.
7. **Umgebungsvariablen für `release.sh`:** `GENERATE_APPCAST`, `SIGN_UPDATE`, `SPARKLE_ED_KEY_FILE`, `STRENG` – für Probeläufe
   und andere DerivedData-Pfade; ohne sie verhält sich das Skript wie bisher (Werkzeuge aus `build/dd`, Schlüssel aus der Keychain).
8. **Schema-Version 1 = 1.0.0**, weil SwiftData genau diese Kennung in unversionierte Datenbanken schreibt
   (`NSStoreModelVersionIdentifiers = ["1.0.0"]` in der v1.1-Vorlage). Die Modellklassen bleiben top-level; beim ersten
   Schemawechsel werden sie laut Anleitung in `AppSchema.swift` als eingefrorene Kopie in `MikaPlusPlayerSchemaV1` verschoben.
9. **Wiederherstellung:** Jeder Fehler beim Öffnen führt zum Beiseitelegen (auch ein vorübergehender) – bewusst, weil nichts
   gelöscht wird und die App sonst gar nicht startet. Ort `Application Support/<Bundle-ID>/Beiseitegelegt/<yyyy-MM-dd_HH-mm-ss>/`
   mit `.store`, `-wal`, `-shm`, `.<Name>_SUPPORT`; bei Teilfehler zurückverschoben. Die beiseitegelegte Datei ist inhaltlich
   erhalten, die Kopfbytes kann der gescheiterte Öffnungsversuch von Core Data ändern (im Test beobachtet, daher prüft der Test
   den Datensatz). Keine automatische Bereinigung (OF-08). Nach dem Neuanlegen laufen die B01-Umstellungen wie gewohnt
   (auf leerer Datenbank ohne Wirkung).
10. **`fatalError` bleibt nur** für den Fall, dass selbst ein In-Memory-Container mit dem Modell scheitert (ungültiges Modell) –
    dann scheitert jeder Testlauf, weil der Test-Host genau diesen Container öffnet.
11. **Hinweistext** (Deutsch, wie der Menüeintrag): „Datenbank neu angelegt – Die gespeicherten Playlists ließen sich nicht
    öffnen. Die bisherige Datenbank wurde nicht gelöscht, sondern unverändert nach „<Ordner>“ verschoben. …“; macOS mit
    „Im Finder zeigen“. Gezeigt am Hauptfenster (`WindowGroup`), nicht am Multiview-Fenster.
12. **Protokoll:** `os.Logger` (Subsystem `lu.daumedia.MikaPlusPlayer`, Kategorie `Persistenz`), Fehlergrund `.private`
    (kann Pfade mit dem Benutzernamen enthalten).
13. **`SparkleUpdater`** nimmt ein beliebiges KVO-fähiges Objekt (Testbarkeit ohne echten Updater); Änderungen außerhalb des
    Main-Threads werden über den Main-Actor nachgereicht.
14. **v1.1-Vorlage im Repository** (`Tests/B09/Fixtures/v1.1-schema.store`, 77 KB, SHA-256 `27039975…`): erzeugt von einem
    Kommandozeilenprogramm aus `git show v1.1:Sources/Models/{Playlist,Channel}.swift` mit dem v1.1-Aufruf
    `Schema([Playlist.self, Channel.self])`; Inhalt nur erfunden (Playlist „B09 v1.1 Testliste“, `127.0.0.1`-Adressen). Das
    Repo ist öffentlich – die Datei enthält nichts Schützenswertes. XcodeGen legt sie als Ressource ins Testbundle; gelesen wird
    sie über `#filePath` und nur als Temp-Kopie geöffnet.

## 4 · Systemweite Änderungen

| Datei / Stelle | Feature | Änderung |
|---|---|---|
| `project.yml` | alle, **iOS** | `CURRENT_PROJECT_VERSION` 3 (auch iOS); Sparkle `exactVersion: "2.9.3"`; macOS-Target Release: `ENABLE_HARDENED_RUNTIME: YES`, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO` |
| `Sources/Resources/Info.plist` | B09 (iOS ignoriert) | neu `SUVerifyUpdateBeforeExtraction = true` mit Kommentar zu `SURequireSignedFeed` |
| `Sources/Resources/MikaPlusPlayer.entitlements` | B06–B09 | nur Kommentar (Begründung für `disable-library-validation` korrigiert) |
| Release-Bundle | **B06, B07, B08** | läuft mit Hardened Runtime: dynamisch nachgeladener oder zur Laufzeit erzeugter Code in VLCKit wäre betroffen – Stichprobe grün, echte Streams ungeprüft (OF-09) |
| `Sources/Models/AppSchema.swift` (neu) | **alle** | versioniertes Schema und Migrationsplan; **jede künftige Modelländerung** muss hier eine neue Version samt Stufe anlegen (Anleitung im Kopfkommentar), sonst legt die App die Datenbank der Nutzer beim Update beiseite |
| `Sources/Services/AppPersistence.swift` (B01) | alle | neu `openAppStore()`, `openStore(at:schema:now:)`, `diskContainer`, `inMemoryContainer`, `moveStoreAside`, `StoreOpenOutcome`, `StoreNotice`; `modelTypes` jetzt aus `AppSchema.current` (vorher feste Liste). `configuration(schema:)`, `prepareStore`, `finishLaunch` unverändert und weiter genutzt |
| `Sources/App/MikaPlusPlayerApp.swift` (B01) | alle | Container kommt aus `AppPersistence.openAppStore()` im `init()`; kein `fatalError` mehr beim Öffnen; `.storeRecoveryAlert(_:)` am Hauptfenster |
| `Sources/Views/StoreRecoveryAlert.swift` (neu) | alle | `StoreNoticeCenter` (`@Observable`) und Alert-Modifier; einziges neues UI-Element |
| `Sources/Services/SparkleUpdater.swift` | B09 | `canCheckForUpdates` gespeichert/beobachtet per KVO; neuer generischer Initialisierer; `init()` wie bisher |
| `scripts/release.sh` | Release | Gegenprüfungen, Feed aus versionierter `appcast.xml` in temporärem Ordner, `sign_update` für den Feed, Umgebungsvariablen (Annahme 7); **bricht jetzt bei unsauberem Git-Stand und bereits veröffentlichter Anzeigeversion ab** |
| `scripts/b09_release_check.sh`, `scripts/b09_ed25519.swift` (neu) | Release | Gegenprüfungen, EdDSA-Prüfung ohne Privatschlüssel |
| `scripts/build-macos.sh` | Release | Ausgabe nennt die Build-Nummer |
| `README.md` | Doku | Code-Signing (Release gehärtet), Entitlements-Begründung, Release/Gegenprüfungen, Veröffentlichen (Reihenfolge, Build-Nummer Pflicht), Öffentliche Distribution neu |
| `Tests/B09/` (neu) | Tests | 4 Testdateien, Vorlage `Fixtures/v1.1-schema.store`; `B09ReleaseSkriptTests` startet `bash`, `git`, `codesign`, `hdiutil`, `xcrun swift` und – falls unter `build/*/SourcePackages/artifacts` vorhanden – `generate_appcast`/`sign_update` (sonst übersprungen); Laufzeit ≈ 41 s |
| `features/B09-auto-update/spec.md` | Doku | nur *Offene Fragen*: OF-06 bis OF-10 |
| `CLAUDE.md` | Doku | **nicht geändert** – Vorschlag für den Orchestrator: bei *Signing-Konventionen* „Release mit Hardened Runtime, ohne `get-task-allow`; `disable-library-validation` bei ad-hoc-Signatur nachweislich nötig“; bei *Release* „`release.sh` prüft vorab (sauberer Git-Stand, Build-Nummer > Feed, neue Anzeigeversion) und signiert den Feed“; bei *SwiftData-Modelle* „Schemaänderung nur über `AppSchema.swift` (VersionedSchema + Migrationsstufe)“ |

Nicht angefasst: `appcast.xml`, `dist/`, `build/MikaPlusPlayer.app`, `web/`, `features/index.md`, `features/befunde.md`,
Keychain, Datenbank des Nutzers (`~/Library/Application Support/default.store`, Zeitstempel unverändert 2026-09-15 23:00:34).
Zusätzliche DerivedData-Ordner: `build/dd-b09-release` (Beleg-Build, bleibt zur Einsicht), `build/dd-b09-lvprobe` (gelöscht).
Die Probe-Einstellungsdomäne `lu.daumedia.MikaPlusPlayer.b09probe` und ihre Caches sind gelöscht.

## Verifikation

Stand 2026-09-16, letzter Lauf nach allen Änderungen. Ausgaben gefiltert, Protokolle vollständig im Scratchpad der Session.

**Baseline vor der Reparatur** (`xcodegen generate`, `clean build-for-testing` macOS, `clean build` iOS): macOS
`** TEST BUILD SUCCEEDED **`, Warnungen nur in B01-Testdateien (3 × `accessibilityAttributeValue`, 1 × Sendable in
`MockXtreamServer.swift`) und `appintentsmetadataprocessor`; iOS `** BUILD SUCCEEDED **` mit `LSSupportsOpeningDocumentsInPlace`-Hinweis
und `appintentsmetadataprocessor`. Keine Warnung in `Sources/`.

Zwischenstand: Ein erster Build meldete eine **neue** Warnung in `SparkleUpdater.swift:46` (Capture eines `KeyPath` in einer
`@Sendable`-Closure) – behoben (Wert aus `change.newValue`). Außerdem stürzte der Compiler (Swift 6.4) an
`schemas.map(\.versionIdentifier)` auf existenziellen Metatypen ab – im Test durch eine Closure ersetzt.

**1 · Projekt erzeugen**

```
$ xcodegen generate            → exit 0
```

**2 · macOS-Tests** — `xcodebuild clean test -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -derivedDataPath build/dd-test`

```
Test Suite 'B01AdressbildungTests' passed   Executed 16 tests, with 0 failures (0 unexpected)
Test Suite 'B01ImportTests' passed          Executed 18 tests, with 0 failures (0 unexpected)
Test Suite 'B01LangsamTests' passed         Executed 4 tests, with 0 failures (0 unexpected)
Test Suite 'B01OberflaecheTests' passed     Executed 10 tests, with 0 failures (0 unexpected)
Test Suite 'B01ReparaturTests' passed       Executed 11 tests, with 0 failures (0 unexpected)
Test Suite 'B01SicherheitTests' passed      Executed 10 tests, with 1 test skipped and 0 failures (0 unexpected)
Test Suite 'B09PersistenzTests' passed      Executed 7 tests, with 0 failures (0 unexpected)
Test Suite 'B09ReleaseConfigTests' passed   Executed 11 tests, with 0 failures (0 unexpected)
Test Suite 'B09ReleaseSkriptTests' passed   Executed 7 tests, with 0 failures (0 unexpected)
Test Suite 'B09UpdaterTests' passed         Executed 3 tests, with 0 failures (0 unexpected)
Test Suite 'M3UParserTests' passed          Executed 4 tests, with 0 failures (0 unexpected)
Test Suite 'PlaybackEngineTests' passed     Executed 6 tests, with 0 failures (0 unexpected)
Test Suite 'XtreamCodesTests' passed        Executed 4 tests, with 0 failures (0 unexpected)
	 Executed 111 tests, with 1 test skipped and 0 failures (0 unexpected) in 231.800 (231.845) seconds
** TEST SUCCEEDED **
Expected failure in -[MikaPlusPlayerTests.B01ImportTests testAK09_DoppelterImportLegtZweitePlaylistAn]            (B01 BUG-09, unverändert)
Expected failure in -[MikaPlusPlayerTests.B09ReleaseConfigTests testFB05_releaseSignedWithDeveloperID]            (BUG-03 offen)
Expected failure in -[MikaPlusPlayerTests.B09ReleaseConfigTests testFB08_signedFeedRequired]                       (BUG-08 Feed-Pflicht offen)
Expected failure in -[MikaPlusPlayerTests.B09ReleaseConfigTests testFB04_libraryValidationNotDisabled]             (BUG-09 offen)
Test Case '-[MikaPlusPlayerTests.B01SicherheitTests testAK27_KeinPasswortImSystemprotokoll]' skipped                (B01, unverändert)
```

Messzeilen aus dem Lauf:

```
B09BUILD|BUG-13|v1.1-Vorlage|opened
B09BUILD|BUG-13|kaputt|recovered(movedTo: …/Beiseitegelegt/2027-01-15_09-00-00/MikaPlusPlayer.store, reason: "SwiftData.SwiftDataError 1: …")
B09BUILD|BUG-13|inkompatibel|recovered(movedTo: …/Beiseitegelegt/2026-09-16_15-06-14/MikaPlusPlayer.store, …)   (Core Data 134140, „Source and destination attribute types are incompatible“)
B09BUILD|BUG-13|schreibgeschuetzt|inMemoryFallback(movedTo: nil, …)
B09BUILD|BUG-10|release.sh|exit=0|mukaarts=false|version1=false|titel=true|signiert=true
B09BUILD|BUG-11|falscherSchluessel|exit=1
```

Warnungen im Lauf, identisch mit der Baseline, keine in `Sources/`:

```
Tests/B01/B01OberflaecheTests.swift:24:12: warning: 'accessibilityAttributeValue' was deprecated in macOS 10.10 …
Tests/B01/B01OberflaecheTests.swift:28:19: warning: 'accessibilityAttributeValue' was deprecated in macOS 10.10 …
Tests/B01/B01OberflaecheTests.swift:65:30: warning: 'accessibilityAttributeValue' was deprecated in macOS 10.10 …
Tests/Support/MockXtreamServer.swift:108:51: warning: capture of 's' with non-Sendable type 'NSArray' …
appintentsmetadataprocessor warning: Metadata extraction skipped, no AppIntents.framework dependency found
```

Dazu eine Laufzeit-Meldung des Test-Hosts, keine Compiler-Warnung und vorbestehend (`CFBundleDocumentTypes` ohne
`CFBundleTypeRole`, nicht geändert): `NSDocumentController Info.plist warning: The values of CFBundleTypeRole entries must be …`.

**3 · iOS-Simulator-Build** — `xcodebuild clean build -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd-ios`

```
** BUILD SUCCEEDED **
warning: The application supports opening files, but doesn't declare whether it supports opening them in place. … (in target 'MikaPlusPlayer')   ← wie Baseline
appintentsmetadataprocessor warning: Metadata extraction skipped, no AppIntents.framework dependency found                                        ← wie Baseline
```

**4 · Release-Build macOS** — siehe *Belege zu BUG-02 und BUG-09* (`clean build`, `** BUILD SUCCEEDED **`, einzige Warnung
`appintentsmetadataprocessor`).

**5 · Sparkle-Auflösung** nach `xcodegen generate`: `Package.resolved` → `"identity" : "sparkle"`, `"version" : "2.9.3"`.

Keine neuen Warnungen auf beiden Plattformen. Kein Ton: keine Wiedergabe in der App, die VLC-Stichprobe lief mit einer Datei
ohne Tonspur und `--no-audio`.
