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

---

# Durchlauf 2 · 2026-10-02 — Fehlerauftrag und Zielentwurf

Eingang: Fehlerauftrag (`qa-report.md` Durchlauf 2, Status `review`) mit den am 2026-10-01/02 zur Behebung freigegebenen
Befunden BF-01, BF-03, BF-05, BF-07, BF-08, BF-09, BF-18, BF-47, BF-48, BF-49, BF-50, BF-51, BF-119 **und** der Zielentwurf
`design.md` vom 2026-10-02 (AK-01, AK-02, AK-12, AK-31, OF-08), vom Betreiber am 2026-10-02 ausdrücklich als Bauauftrag
freigegeben. Nicht im Auftrag: BF-06 (eigener Schlüssel, eigener Bau nach 1.2), OF-11 bis OF-14 (bis nach dem Bau
zurückgestellt; der Bau folgt dem Entwurf). Branch `sdd/b09-bau` auf dem Stand von PR #12 (`e12fff8`), nicht committet.
Bestandsfeature ohne `tasks.md`: Arbeitsplan und Abschlussbericht stehen hier (Konvention der Durchläufe in diesem Projekt).

## Arbeitsplan (wird während des Baus abgehakt)

**Ebene 1 · Konfiguration**
- [x] E1.1 `project.yml`: Entwicklungssprache `de`; Debug-Bundle-ID `lu.daumedia.MikaPlusPlayer.debug` nur am macOS-Target; Release-Signatur Developer ID; Vorgabe automatische Prüfung je Konfiguration; `MARKETING_VERSION` 1.2; Testaktion mit „Fensterzustand ignorieren“ und Umgebungsmarke (BF-03, BF-119, OF-01, OF-06, OF-10)
- [x] E1.2 `Info.plist`: `CFBundleLocalizations [de]`, `SURequireSignedFeed`, `SUEnableAutomaticChecks` aus der Build-Einstellung (AK-01, AK-02, AK-12, BF-08)
- [x] E1.3 Entitlements ohne `disable-library-validation` (BF-09)
- [x] E1.4 Git-Attribut für `appcast.xml`; Exportoptionen unter `scripts/` (AK-12, BF-03)
- [x] E1.5 Tests: `B09ReleaseConfigTests` streng (FB05 nur Release-Block, FB08, FB04), neue Konfigurationstests — zuerst rot

**Ebene 2 · App-Code**
- [x] E2.1 `SparkleUpdater`: vier gespiegelte Werte, Schreibwege nur auf Nutzeraktion, Start nicht im Test-Host (BF-18, BF-49, AK-31)
- [x] E2.2 Update-Menü als eigene Ansicht mit Schaltfläche und zwei Schaltern (BF-18, AK-01, AK-31)
- [x] E2.3 Test-Host-Erkennung zusätzlich über die Umgebungsmarke (BF-119)
- [x] E2.4 Schlüsselbund-Dienstname aus der Bundle-ID (Test-Host unverändert) (BF-119)
- [x] E2.5 Altbestands-Übernahme nur für die übergebene Release-ID; Hinweistexte nach OF-08
- [x] E2.6 Tests je Punkt, zuerst rot

**Ebene 3 · Release-Skripte**
- [x] E3.1 `release.sh`: Projekt erzeugen, Archivieren, Exportieren, DMG signieren, Notarisieren (Ergebnis „Accepted“, Protokoll), Heften, `generate_appcast` mit Obergrenze, Feed signieren, Folgeschritte samt Pflichtproben; fehlendes `generate_appcast` gemeldet (BF-03, BF-05, BF-47, BF-51, BF-01)
- [x] E3.2 `b09_release_check.sh`: Stufen vor-build, nach-build, nach-heften, feed, nach-merge; „offen“ → Befund; leere Version, fremde Download-Adressen, Eintragszahl (BF-03, BF-09, BF-47, BF-48, BF-50, BF-01)
- [x] E3.3 Prüfnähte und Probemodus; Release-Skript-Tests und `B09QA2Tests` streng — zuerst rot

**Ebene 4 · Folgen für andere Features und Tests**
- [x] E4.1 Tests mit englischen Systemtexten und Bedienungshilfe-Namen sprachfest (Lokalisierung `de`)
- [x] E4.2 Tests mit fester Bundle-ID bzw. Schlüsselbund-Dienst (Debug-ID)
- [x] E4.3 `B09QA2Tests`: Menü am Test-Host inaktiv, EC-01 mit Debug-ID
- [x] E4.4 Gesamtlauf macOS, iOS-Bau, Warnungen

**Ebene 5 · Echte Signatur und Selbsttest**
- [x] E5.1 Archivieren und Exportieren mit Developer ID, Gegenprüfung nach-build
- [ ] E5.2 DMG signieren ✅, Test-Notarisierung (nicht veröffentlicht) ❌ offen – notarytool-Profil nicht vorhanden, Heften ❌, Gegenprüfung nach-heften (ausgeführt, meldet genau die fehlende Notarisierung)
- [x] E5.3 Selbsttest am Debug-Build (eigene ID): Menü, Schalter, Sprache (auch mit englischer Systemsprache)

**Ebene 6 · Dokumentation**
- [x] E6.1 `CLAUDE.md` und README nachführen (OF-10, Signatur, Sprache)
- [x] E6.2 Vermerke in `qa-report.md`, Abschlussbericht hier

## 1 · Umgesetzt (Durchlauf 2)

Je Punkt: was, wo, welcher Test war vorher rot. „Rot“ heißt: gegen den Stand vor der Änderung ausgeführt und
fehlgeschlagen (Ebene 1: alte Konfiguration; Ebene 2: Platzhalter mit neuer Schnittstelle und altem Verhalten;
Ebene 3: neue Tests gegen die alten Skripte aus `HEAD`).

**Ebene 1 · Konfiguration** (rot: 14 Fehlschläge in 9 Tests von `B09ReleaseConfigTests`, danach 18/18 grün)
- **BF-03 / BF-05** · `project.yml`: macOS-Release `CODE_SIGN_IDENTITY: "Developer ID Application"` (Team `CWJM4J4HFN`,
  manuell); Debug und Test-Bundle bleiben ad hoc. `scripts/ExportOptions-DeveloperID.plist` (Methode `developer-id`,
  Ziel Export, Team, manuelle Signatur, Zertifikat „Developer ID Application“, keine Geheimnisse). Tests
  `testFB05_releaseSignedWithDeveloperID` (vorher `XCTExpectFailure`, jetzt auf den Release-Block beschränkt),
  `testBF03_exportOptionsForDeveloperID`.
- **BF-09** · `MikaPlusPlayer.entitlements` ohne `disable-library-validation`. Test `testFB04_libraryValidationNotDisabled`
  (vorher `XCTExpectFailure`).
- **BF-08 / AK-12** · `Info.plist` `SURequireSignedFeed = true` (zusammen mit `SUVerifyUpdateBeforeExtraction`, sonst
  startet Sparkle nicht); `SUSignedFeedFailureExpirationInterval` bewusst nicht gesetzt (20 Tage, OF-15). `.gitattributes`
  `appcast.xml -text`. Tests `testFB08_signedFeedRequired` (vorher `XCTExpectFailure`), `testAK12_appcastIsNotTransformedByGit`.
- **OF-01 / AK-01 / AK-02** · `options.developmentLanguage: de`, `Info.plist` `CFBundleLocalizations [de]`, kein
  `CFBundleAllowMixedLocalizations`. Test `testAK01_appDeclaresGermanOnly`. Am gebauten Bundle: `CFBundleDevelopmentRegion`
  löst zu `de` auf (Debug, Release, iOS).
- **BF-119 / OF-10** · Debug-Bundle-ID `lu.daumedia.MikaPlusPlayer.debug` nur unter `configs.Debug` des macOS-Targets;
  Testaktion mit `-ApplePersistenceIgnoreState YES` und `MIKA_TEST_HOST=1`. Tests `testBF119_debugUsesOwnBundleID`,
  `testBF119_testActionIgnoresSavedStateAndMarksTestHost`.
- **Entwurf Entscheidung 8 / AK-03** · Vorgabe der automatischen Prüfung je Konfiguration über die Build-Einstellung
  `MIKA_SPARKLE_AUTOMATIC_CHECKS` (Template `YES`, macOS-Debug `NO`), `Info.plist` `SUEnableAutomaticChecks =
  $(MIKA_SPARKLE_AUTOMATIC_CHECKS)` – Sparkle liest Text als Wahrheitswert (`SUHost.m` `convertObjectToBoolNumber`,
  gelesen). Der Entwurf ließ den Weg offen (Build-Einstellung oder Startargument); gewählt ist die Build-Einstellung,
  weil sie im exportierten Bundle steht. Test `testAK03_automaticChecksDefaultPerConfiguration`; am Bundle: Debug `NO`,
  Release `YES`.
- **OF-06** · `MARKETING_VERSION` 1.2 (Build bleibt 3). Test `testOF06_marketingVersionIs12`.

**Ebene 2 · App-Code** (rot: 15 Tests gegen Platzhalter, danach alle B09-Suiten grün)
- **BF-18 / AK-31** · `SparkleUpdater` spiegelt vier Werte per KVO (Prüfung möglich, automatisch prüfen, automatisch
  installieren, automatisch installieren erlaubt); Schreibwege `setAutomaticallyChecksForUpdates`/`…DownloadsUpdates`
  setzen nur Sparkles eigene Einstellung, nur auf Nutzeraktion, nie beim Start (Entscheidung 7). Neue Ansicht
  `Sources/Views/UpdateMenu.swift` mit „Nach Updates suchen …“, „Automatisch nach Updates suchen“, „Updates automatisch
  installieren“ (gesperrt ohne Häkchen, solange Sparkle automatisches Installieren nicht erlaubt); liest den Zustand im
  eigenen Rumpf (Entscheidung 6). Tests `B09UpdaterTests` (+5): vier Werte gespiegelt, nichts beim Anlegen geschrieben,
  Menüzustände, jede der vier Änderungen macht den Rumpf der Menü-Ansicht ungültig.
- **BF-49** · Sparkle wird im Test-Host angelegt, aber nicht gestartet; Menü dann inaktiv, Schreibwege wirkungslos.
  Tests `testBF49_…`, `B09QA2Tests.testEC01_BUG21_…` (vorher `XCTExpectFailure`), `testAK01_AK31_…` (drei Einträge
  direkt unter „Über …“, im Test-Host inaktiv).
- **BF-119** · `AppEnvironment`: Erkennung zusätzlich über `MIKA_TEST_HOST=1`, `releaseBundleID`, `bundleID`;
  `XtreamCredentialStore.serviceName(bundleID:isRunningTests:)` = `<Bundle-ID>.xtream` (Release unverändert, keine
  Migration; Test-Host unverändert `…xtream.tests.<UUID>`); `AppPersistence.prepareStore` übernimmt die alte
  `default.store` nur für die übergebene Release-ID (neuer Ausgang `.otherBundleID`). Tests `B09Bau2Tests` (3).
- **OF-08** · Hinweise „Datenbank neu angelegt“ / „Datenbank nicht verfügbar“ nennen die Zugangsdaten im Schlüsselbund
  und „Alle Daten entfernen …“ (macOS: App-Menü; iOS: Menü der Playlist-Übersicht, ohne Pfad und ohne Ordner); ist das
  Beiseitelegen gescheitert, sagt der Hinweis „liegt unverändert am bisherigen Ort“ (neuer Wert `keptInPlace` am
  Ausgang `.inMemoryFallback`, nur wenn eine Datei da war). Tests `B09Bau2Tests` (4), `B09PersistenzTests` (angepasst),
  `testEC07_BUG20_…` (Hinweis jetzt positiv geprüft).

**Ebene 3 · Release-Skripte** (rot: 14 Tests gegen die Skripte aus `HEAD`, danach 22/22 grün)
- **BF-03 / BF-05** · `build-macos.sh`: `xcodegen` → `xcodebuild archive` → `-exportArchive` mit den Exportoptionen →
  `build/MikaPlusPlayer.app` (per `ditto`). `release.sh`: vor-build → Build → nach-build → DMG → DMG mit Developer ID,
  Zeitstempel und Bezeichner `lu.daumedia.MikaPlusPlayer.dmg` signieren → `notarytool submit --keychain-profile
  "$NOTARY_PROFILE" --wait --output-format json`, Auswertung des Felds `status` („Accepted“), Protokoll immer nach
  `dist/notarisierung-v<Version>.json` → `stapler staple` + `validate` → nach-heften → `generate_appcast` → `sign_update`
  → feed → Folgeschritte (Pflichtproben, Release, PR, nach-merge). Prüfnähte `NOTARYTOOL`, `STAPLER`, `CODESIGN`,
  `DMG_SIGN_IDENTITY`; `PROBEMODUS=1` ohne Developer ID und Notarisierung. Tests: `testBF03_ReleaseNotarisiertUndHeftetVorDemFeed`
  (Reihenfolge der sechs Schritte, genaue Einreichung, Protokoll, DMG-Bezeichner), `testBF03_ReleaseBrichtAbWennNotarisierungAbgelehnt`
  („Invalid“ bei Exit 0 → Abbruch, Protokoll da, kein Heften, Feed unverändert).
- **b09_release_check.sh** · „offen“ wird Befund (außer im Probemodus): je Komponente (App, Sparkle, Autoupdate,
  Updater.app, beide XPC-Dienste, VLCKit) Developer ID, Team, sicherer Zeitstempel, Runtime bei Programmen; Entitlements
  ohne `get-task-allow` und `disable-library-validation`; Bundle-ID, Feed-Pflicht, Sprache `de`/`[de]`. Neue Stufen
  **nach-heften** (DMG = geprüftes Bundle, Developer ID, Ticket, Gatekeeper für DMG und App) und **nach-merge**
  (ausgelieferte Datei an daumedia- und Mukaarts-Adresse byte-gleich mit der gemergten, Signatur gültig, bis 330 s Warten
  auf den Zwischenspeicher, Adressen über `FEED_URLS` ersetzbar); vor-build verlangt ein gültiges Notar-Profil
  (`NOTARY_PROFILE`). Tests `testBF03_VorBuildVerlangtNotarProfil`, `testBF03_BF09_NachBuildStrengOhneProbemodus`,
  `testOF01_BF08_NachBuildPrueftSpracheFeedPflichtUndBundleID`, `testBF03_NachHeftenVerlangtSignaturTicketUndGatekeeper`,
  `testAK12_NachMergeVergleichtAusgelieferteDateiUndSignatur` (CRLF-Fassung wird erkannt).
- **BF-47** · `generate_appcast --maximum-versions 0` (behält alle Einträge); Feed-Prüfung unverändert „versionierter
  Feed + neuer Eintrag“. Test `testBUG19_…` (vorher `XCTExpectFailure`).
- **BF-48** · alle Enclosure-Adressen in versioniertem und neuem Feed unter `…/releases/download/v<…>/<datei>`.
  Test `testBUG23_…` (vorher `XCTExpectFailure`).
- **BF-50** · leere oder nicht numerische Anzeigeversion ist Befund. Test `testBUG22_…` (vorher `XCTExpectFailure`).
- **BF-51** · Werkzeugsuche scheitert nicht mehr stumm; Meldung direkt nach dem Build. Test `testBF51_…`.
- **BF-01** · Übergangs-Release vorbereitet: Version 1.2, Feed-Pflicht, nach-merge prüft auch die Mukaarts-Adresse.
  Veröffentlicht wird erst mit `/sdd-deploy` (nicht Teil des Baus).
- **BF-07** · nicht im Code: Ruleset auf `main` ist eine GitHub-Einstellung (nur auf Anweisung per `gh`) → offen, Abschnitt 2.

**Ebene 4 · Folgen** · Tests von B01–B08 nehmen englischen **oder** deutschen Systemwortlaut an; gemeinsame Hilfe
`Tests/Support/SystemSprache.swift` (deutsche Fassungen am Test-Host beobachtet: Sonde und Gesamtlauf 1, z. B.
„Verbindung zum Server konnte nicht hergestellt werden.“, Symbol `plus` → „Hinzufügen“, `rectangle.split.2x2` → „In Zwei
Mal Zwei Geteiltes Rechteck“, `speaker.wave.2.fill` → „Laut“, `speaker.slash.fill` → „Ton Aus“, Suche → „Keine Ergebnisse
für „…““, Menü „Fenster“). Angepasst: `B01ImportTests`, `B01LangsamTests`, `B01OberflaecheTests`, `B01QA2OberflaecheTests`,
`B01SicherheitTests` (Pfad mit Debug-ID), `B01QA2Tests` (Debug-Dienst als App-Dienst), `B02LangsamTests`,
`B02OberflaecheTests`, `B02URLImportTests`, `B03AktualisierenTests`, `B03OberflaecheTests`, `B04GruppenTests`,
`B04SucheTests`, `B05SternTests`, `B05TabTests`, `B06EngineZustandTests`, `B06PlayerViewTests`, `B08HauptfensterTests`,
`B08NachtragTests`, `B08OberflaecheTests`, `B08Support`.

**Ebene 6 · Dokumentation** · `CLAUDE.md` (Signing Debug/Release, Debug-Bundle-ID, Sprache, Release-Befehl), `README.md`
(Code-Signing, Tests, Entitlements, Release-Abschnitt neu), Vermerke in `qa-report.md` (BUG-18 bis BUG-24).

## 2 · Offene Kriterien und nicht behobene Befunde (Durchlauf 2)

- **Notarisierung nicht ausgeführt (BF-03, Teil)** · Das notarytool-Profil „MikaPlusPlayer“ ist auf diesem Rechner nicht
  vorhanden („No Keychain password item found for profile: MikaPlusPlayer“, mehrfach geprüft, auch ohne Sandbox; im
  Anmelde-Schlüsselbund kein Eintrag des Notardienstes). Ein Anlegen über `!` scheitert, weil `store-credentials` interaktiv
  fragt. Belegt ist der Weg bis zum **signierten, nicht notarisierten** DMG; `nach-heften` meldet genau die drei
  erwarteten Befunde (kein Ticket, Gatekeeper lehnt DMG und App ab). Schritte: Profil im Terminal anlegen (App-spezifisches
  Passwort), dann Test-Notarisierung nachholen – spätestens `/sdd-deploy` (`release.sh` verlangt das Profil in vor-build).
- **Pflichtproben vor dem Veröffentlichen** · Kurztest Wiedergabe mit dem echten Anbieter (OF-09, Betreiber),
  Übergangsprobe 1.1 → 1.2 über einen Test-Feed (Entscheidung 14), Offline-Erststart (Entscheidung 2) – brauchen ein
  notarisiertes DMG; nicht ausgeführt. `release.sh` nennt sie als Schritt a).
- **BF-07** · Ruleset auf `main` nicht angelegt (GitHub-Einstellung, nur auf Anweisung).
- **BF-06** · nicht im Auftrag (eigener Schlüssel ab dem Release nach 1.2).
- **BUG-20 (= B01 BF-46)** · verwaiste Schlüsselbund-Einträge nach dem Beiseitelegen: nicht im Auftrag, `XCTExpectFailure` bleibt.
- **BUG-23, zweiter Teil** · Vergleich bestehender Feed-Einträge mit dem Stand des letzten Release-Tags: nicht umgesetzt
  (Entwurf verlangt nur die Adressprüfung).
- **OF-11 bis OF-14** · bis nach dem Bau zurückgestellt; der Bau folgt dem Entwurf: Während einer **vom Nutzer gestarteten**
  Prüfung bleibt „Nach Updates suchen …“ aktiv (beobachtet, OF-11); Sparkles Fehlermeldung zur Feed-Pflicht ist englisch
  („The update feed is improperly signed …“, Titel und Knopf deutsch, beobachtet, OF-13); das Installationsfenster
  (Updater.app) ließ sich ohne echtes Update nicht beobachten (OF-13). → `/sdd-klaeren B09` vor der QA.
- **Gesamtlauf** · 2 Tests rot, einzeln nachgeprüft grün (Abschnitt 5).

## 3 · Getroffene Annahmen (Durchlauf 2)

1. `xcodegen` läuft weiter in `build-macos.sh`, nicht als eigener Schritt 0 in `release.sh` vor der Gegenprüfung; vor-build
   liest nur `project.yml`, `Info.plist`, `appcast.xml` und Git, die Reihenfolge ist daher gleichwertig, und die
   Attrappen-Tests ersetzen `build-macos.sh` als Ganzes.
2. Die Sparkle-Werkzeuge werden **nach** dem Build gesucht (die Paketauflösung legt sie an), aber vor DMG und Notarisierung.
3. Im Probemodus wird das DMG ad hoc signiert (`codesign --sign -` auf ein DMG funktioniert, geprüft); Notarisieren und
   Heften laufen dort nur mit übersteuerten Werkzeugen.
4. vor-build prüft das Notar-Profil mit `notarytool history` (Netzabfrage, prüft auch die Gültigkeit), nicht über den
   Schlüsselbund direkt.
5. nach-merge wartet bis 330 s (GitHub `max-age=300` + Puffer) je Adresse, Abfrage alle 30 s.
6. `TeamIdentifier=not set` (ad hoc) wird als „kein Team“ gemeldet.
7. Die Hinweistexte sprechen von „Zugangsdaten der bisherigen Playlists“ (Xtream **und** M3U mit Zugangsdaten, B02),
   nicht nur von Xtream wie im Entwurf.
8. Englische Erwartungswerte in fremden Tests bleiben stehen; die Hilfe übersetzt beobachtete deutsche Systemtexte zurück
   (Kriterien anderer Features werden nicht still umformuliert; deren Sprachfragen klärt `/sdd-klaeren`).

## 4 · Systemweite Änderungen (Durchlauf 2)

| Datei / Stelle | Feature | Änderung |
|---|---|---|
| `project.yml` `options.developmentLanguage: de` | **alle, iOS** | Systemtexte (Fehlermeldungen von Foundation/AVFoundation, Bedienungshilfe-Namen von Symbolen, Systemmenüs, Suchleerzustand) erscheinen deutsch – auch bei englischer Systemsprache (beobachtet mit `-AppleLanguages (en)`). Apples deutsche Systemtexte duzen („Du bist nicht berechtigt …“, „Überprüfe die Schreibweise …“). |
| `Sources/Resources/Info.plist` | alle (iOS ignoriert `SU*`) | `CFBundleLocalizations [de]`, `SURequireSignedFeed`, `SUEnableAutomaticChecks` aus Build-Einstellung |
| `project.yml` macOS-Debug `PRODUCT_BUNDLE_IDENTIFIER` | **alle macOS-Tests** | Test-Host und Debug-Build `lu.daumedia.MikaPlusPlayer.debug`: eigene Einstellungen, Datenbank, Caches, Schlüsselbund-Dienst; Debug-Builds erscheinen im Finder unter „Öffnen mit“ für `.m3u` als weitere „Mika+Player“ (Standard bleibt Music; geprüft per `NSWorkspace`) |
| `project.yml` Testaktion | alle Tests | eigene Startargumente/Umgebung: Argumente der Run-Aktion gelten im Test nicht mehr |
| `project.yml` Release `CODE_SIGN_IDENTITY` + Entitlements | **B06, B07, B08**, Messungen | Release braucht das Developer-ID-Zertifikat; ein ad-hoc-signierter Release-Build startet ohne `disable-library-validation` nicht (VLCKit) – Release-Messungen nur mit Developer ID oder als Kopie mit eigener Bundle-ID (so im Selbsttest) |
| `Sources/App/AppEnvironment.swift` | alle | `detectTests`, `testHostMarker`, `releaseBundleID`, `bundleID` |
| `Sources/Services/XtreamCredentialStore.swift` | B01, B02, B03 | Dienstname aus der Bundle-ID; Release unverändert |
| `Sources/Services/AppPersistence.swift` | alle | Altbestand nur für Release-ID (`.otherBundleID`), `.inMemoryFallback(movedTo:keptInPlace:reason:)`, Hinweise je Plattform (`notice(for:)`) |
| `Sources/Services/SparkleUpdater.swift`, `Sources/Views/UpdateMenu.swift` (neu), `MikaPlusPlayerApp.swift` | B09 | vier gespiegelte Werte, Menü-Ansicht, kein Start im Test-Host |
| `scripts/*.sh`, `scripts/ExportOptions-DeveloperID.plist` (neu), `.gitattributes` (neu) | Release | siehe Abschnitt 1; `release.sh` braucht künftig `NOTARY_PROFILE` |
| `Tests/Support/SystemSprache.swift` (neu) + 21 Testdateien B01–B08 | Tests | englisch **oder** deutsch |
| `README.md`, `CLAUDE.md` | Doku | nachgeführt |
| `features/B09-auto-update/qa-report.md` | Doku | nur Vermerke (BUG-18 bis BUG-24), kein Umschreiben |
| `features/index.md` | Doku | Status `building` |

Nicht angefasst: `appcast.xml`, `web/`, `spec.md`, `design.md`, `befunde.md`, Schlüsselbund-Einträge des Nutzers,
EdDSA-Schlüssel (nicht benutzt), Datenbank und Einstellungen der installierten App. `dist/` vor dem DMG-Schritt gesichert
und danach prüfsummengleich zurückgelegt (`make-dmg.sh` löscht `dist/*.dmg`, auch das v1.1-DMG – Bestandsverhalten).
`build/dd` (veraltet, vom alten Repo-Pfad `…/DEV/SwiftProjects/…`, Archivieren scheiterte daran mit „There is no
XCFramework found at …/SwiftProjects/…“) nach `build/dd-alt-swiftprojects` beiseitegelegt, **nicht** gelöscht (bestand vor
dem Bau; zum Löschen freigegeben, sobald der Betreiber zustimmt). Eigene Hilfsordner `build/dd-b09`, `build/dd-b09g`,
`build/dd-ios` entfernt (vorher bei LaunchServices abgemeldet). Neu unter `build/`:
`dd` (frisch), `MikaPlusPlayer.xcarchive`, `export/`, `MikaPlusPlayer.app` (Developer ID, nicht notarisiert).

## 5 · Tests und Selbsttest (Durchlauf 2)

**Ausgang** (vor dem Bau): B09-Suiten 35 Tests, 0 Fehlschläge, 8 erwartete Fehlschläge; Warnungen in `Sources/` 0,
in `Tests/` 21 (alle vorbestehend).

**Gesamtlauf 1** (nur Ebene 1): 526 Tests, 36 rot – alle aus den erwarteten Folgen (englische Systemtexte, Debug-ID,
B09-Tests gegen die schon geänderten Skripte) bis auf `B03OberflaecheTests.testAK14_…` (zeitabhängig, s. u.).

**Gesamtlauf 2** (Ebenen 1–4): **546 Tests, 19 übersprungen, 2 rot** (4 Prüfungen): `B03OberflaecheTests.testAK12_AK13_EC09_…`
und `B06ReparaturTests.testBUG06_…` („SYSTEMBEEP-UNTERDRUECKT NSWindow keyDown“). Einzeln je zweimal nachgeprüft:
B06 zweimal grün; B03 einmal rot (204 s), einmal grün (73 s). Die B03-Oberflächentests sind zeitabhängig unzuverlässig:
Laufzeiten schon vor B09 zwischen 66 und 472 s (B05-Läufe vom 2026-10-01: AK-14 215–394 s, AK-22 bis 336 s), in jedem der
vier Gesamtläufe dieses Baus und davor scheiterte höchstens einer davon, jeweils ein anderer. Keine neuen Warnungen
(`Sources/` 0, `Tests/` unverändert 21). iOS-Simulator-Build grün, 0 Warnungen. B09: **62 Tests** (vorher 35).

**Echte Signatur (Ebene 5)** · `build-macos.sh`: Archivieren und Export mit Developer ID in 1½ min (ohne Profil,
ohne Schlüsselbund-Rückfrage). `b09_release_check.sh nach-build` streng: **keine Beanstandung** – App, Sparkle.framework,
Autoupdate, Updater.app, Downloader.xpc, Installer.xpc und VLCKit.framework je „Developer ID Application“, Team
`CWJM4J4HFN`, sicherer Zeitstempel, Runtime bei Programmen; Entitlements nur `app-sandbox=false`; Bundle-ID, Version 1.2/3,
Feed-Pflicht, `de`/`[de]`; Release `SUEnableAutomaticChecks=YES`; universell (x86_64, arm64). Damit belegt: Der Export
ergibt für das XcodeGen-Projekt ein App-Archiv und signiert Sparkles Hilfsprogramme (Risiken aus dem Entwurf). Sparkles
Downloader-Dienst hat schon im Paket keine Entitlements (nichts verloren). DMG mit Developer ID, Zeitstempel, Bezeichner
signiert; `nach-heften`: DMG = geprüftes Bundle (CDHash), Developer ID, Team ok; Ticket und Gatekeeper fehlen (nicht notarisiert).

**BF-09 am Start belegt** · Kopie des exportierten Bundles mit Bundle-ID `….b09probe`, äußere Signatur mit Developer ID
erneuert (Runtime, Entitlements der App), `HOME` im Arbeitsordner, `-SUEnableAutomaticChecks NO`, Feed auf einen toten
Port: läuft nach 8 s, `Sparkle.framework/Versions/B/Sparkle` und `VLCKit.framework/Versions/A/VLCKit` geladen, kein
dyld-Fehler, 0 Netzverbindungen. Danach Einstellungsdomäne, Registrierung und Kopie entfernt. Wiedergabe unter
Runtime nicht geprüft (OF-09-Kurztest, Betreiber).

**Selbsttest am Debug-Build** (`build/dd-test`, Bundle-ID `….debug`, lokaler Feed `127.0.0.1:18931` mit 12 s Verzögerung,
unsigniert; Menü über die Bedienungshilfen gelesen und bedient; Debug-Einstellungen vorher gesichert und danach
zurückgespielt):
- App-Menü: „Über „Mika+Player““, „Nach Updates suchen …“, „Automatisch nach Updates suchen“, „Updates automatisch
  installieren“, Trenner, „Alle Daten entfernen …“, „Dienste“, „„Mika+Player“ ausblenden“ … – **deutsch** (AK-01).
- Ruhezustand Debug: Suchen aktiv, automatisch prüfen **ohne** Häkchen (Vorgabe Debug „aus“ greift), Installieren ausgegraut.
- Schalter: automatisch prüfen an → ✓, `SUEnableAutomaticChecks=1`, Installieren bedienbar; Installieren an → ✓,
  `SUAutomaticallyUpdate=1`; automatisch prüfen aus → Installieren ausgegraut ohne ✓, `SUAutomaticallyUpdate` bleibt 1;
  wieder an → Installieren ✓ zurück (Entwurf, OF-12).
- **BF-18 an der echten Menüleiste:** Beim Einschalten startete Sparkle sofort eine Hintergrundprüfung (Feed-Abruf
  13:30:40, User-Agent `Mika+Player/1.2 Sparkle/2.9.3`) – „Nach Updates suchen …“ **inaktiv**, danach wieder aktiv.
  Zeitreihe bei der geplanten Prüfung beim Start (letzte Prüfung zurückdatiert, Abruf 13:32:27): +3, +6, +9, +12 s inaktiv,
  ab +15 s aktiv.
- Feed-Pflicht wirkt: unsignierter Feed im Hintergrund still verworfen, `SUInitialFailedFeedSigningValidationDate` gesetzt
  (Beginn der 20-Tage-Frist, OF-15).
- Manuelle Prüfung: Fenster „Softwareupdate“ / „Nach Updates suchen …“ / „Abbrechen“ (**deutsch**, AK-02); Eintrag während
  dieser Prüfung **aktiv** (Sparkle, OF-11); danach Dialog „Fehler beim Aktualisieren!“ mit englischem Text „The update
  feed is improperly signed and could not be validated. …“ und Knopf „Aktualisierung abbrechen“ (OF-13).
- **Englische Systemsprache** (`-AppleLanguages (en)`): Menüleiste „Ablage, Bearbeiten, Darstellung, Fenster, Hilfe“,
  App-Menü und Sparkle-Fenster weiter deutsch.
- Startprotokolle ohne Fehler. Keine Wiedergabe, kein Ton.

**Aufräumen** · Selbsttest-Prozesse und Feed-Server beendet, Debug-Einstellungen zurückgespielt (wieder nur
`SUHasLaunchedBefore`), Arbeits-`HOME` gelöscht; zusätzliche DerivedData-Ordner siehe Abschnitt 4 und Übergabe.

## Übergabe

Status bleibt `building`. Nächste Schritte: (1) notarytool-Profil im Terminal anlegen, Test-Notarisierung nachholen
(eigener kurzer Auftrag oder beim Deploy); (2) `/sdd-klaeren B09` für OF-11 bis OF-14 (Auslöser erfüllt: Bau
abgeschlossen); (3) danach `/sdd-qa B09` **in einer neuen Session**.
