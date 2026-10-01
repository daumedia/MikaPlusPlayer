# B07 · Bild-in-Bild — Build-Bericht

Durchlauf 1 · 2026-09-27/28 · Eingang: Fehlerauftrag (`qa-report.md` QA 1, BUG-01, BUG-03, BUG-04, BUG-05; BUG-02 und BUG-06
warten auf OF-04 bzw. OF-03) · Branch `sdd/reparaturen`, aufgebaut auf der (verifizierten, noch nicht gereviewten)
B06-Reparatur im Arbeitsbaum, nicht committet

## 1 · Umgesetzt

Nach „Zurück“ mit aktivem Bild-in-Bild läuft die Wiedergabe im schwebenden Fenster weiter (B06, Annahme 3) und bleibt
steuerbar: „Schließen“ und „Zurück zur App“ im Fenster beenden sie samt Verbindung, `stopPictureInPicture()` aus der App
wirkt auch ohne Player, und sobald ein Player einen Sender startet oder fortsetzt, endet sie samt Fenster – nie zwei
Streams zugleich, danach 0 Anfragen. „Zurück zur App“ stellt bei offenem Player das Bild wieder her und beendet bei
verlassenem Player die Wiedergabe (`restoreUserInterfaceForPictureInPictureStop` implementiert). In der echten
Oberfläche erkannte der Player am Mac „Zurück“ aus der Senderliste bisher gar nicht (siehe 4, `ShellTabs`) – dort griff
weder die B06-Reparatur noch Bild-in-Bild; jetzt schon. Der Wiedergabezustand folgt dem Player, auch wenn das System ihn
anhält oder fortsetzt; der erste Druck setzt fort. Import-Sheet und Player sagen knapp auf Deutsch, dass es Bild-in-Bild
nur mit HLS gibt. Am iPad beendet ein zweiter Knopf „Bild-in-Bild beenden“ in der unteren Leiste das Fenster, ohne es zu
verschieben.

| BUG | Grad | Ergebnis | Wo | Nachweis |
|---|---|---|---|---|
| BUG-01 | hoch | behoben (Mac und iPad) | `PlayerView` (`startIfNeeded`, `stillInStack`), `DetachedPlayback` (`holds`, `stopAll` genutzt), `AVKitPlaybackEngine` (`endPictureInPicture`, `stopPictureInPicture`, Restore-Delegate), `ContentView` (`ShellTabs`) | V `testAK15a/b_…`, O `testAK15c_…`, S `testAK15d/e_…` ohne `XCTExpectFailure`; R `testBUG01_…` (5); iPad-Sonde |
| BUG-02 | mittel | **nicht gebaut** (wartet auf OF-04) | — | Stand beobachtet, siehe 2 |
| BUG-03 | mittel | behoben | `AVKitPlaybackEngine` (`observePlayback`, `syncPausedWithPlayer`, `togglePlayPause`) | S `testAK16_…AppZeigtAngehalten`, `testEC07_…`; V `testAK16_…`, `testAK17_EC10_…`; R `testBUG03_…`; iPad-Sonde |
| BUG-04 | mittel | App-Teil behoben, Website-Teil nicht (B10 Teil 2) | `XtreamOutput.hint`, `PlayerView.togglePiP` (HUD-Hinweis), `PlaybackEngineFactory.deviceSupportsPictureInPicture` | I `testAK09_ImportSheet…MitHinweisBildInBildNurHLS`, K `testAK09_TSUeberVLC_…PZeigtHinweisNurHLS`; iPad-Sonde |
| BUG-05 | mittel | behoben | `PlayerView.bottomControls` (nur iOS) | iPad-Sonde (Bilder `BUILD-IOS-ipad-02/03`) |
| BUG-06 | niedrig | **nicht gebaut** (wartet auf OF-03) | — | — |

Tests: alle 9 `XCTExpectFailure`-Blöcke in `Tests/B07` (in 11 Tests; QA 1: 19 erwartete Fehlschläge aus BUG-01, BUG-03, BUG-04) entfernt
und die Assertions auf das behobene Verhalten gestellt, nicht aufgeweicht; `B07` enthält keinen `XCTExpectFailure` mehr.
Fünf Tests umbenannt, weil ihr Name das alte Verhalten beschrieb (siehe 3, Punkt 12). Neu: `Tests/B07/B07ReparaturTests.swift`
mit 6 Tests. Ergebnis der Gesamtläufe siehe *Verifikation*.

## 2 · Offene Kriterien und nicht behobene BUGs

- **BUG-02 · iOS/iPadOS „Zurück“ mit Bild-in-Bild** — nicht gebaut, Zielverhalten wartet auf OF-04. **Beobachtet (iPad-Sonde):**
  Das Verhalten hat sich durch die B06-Reparatur geändert und gleicht jetzt dem Mac: Nach „Zurück“ läuft das schwebende
  Fenster weiter (vorher sofort weg), bis „Schließen“, „Zurück zur App“ oder ein anderer Sender es beendet. Den in QA 1
  zitierten Kommentar („nicht abwürgen“) erfüllt das; ob es so gewollt ist, entscheidet OF-04.
- **BUG-06 · englische Systemtexte** — nicht gebaut, wartet auf OF-03. Der neue Knopf „Bild-in-Bild beenden“ (iOS) und der
  neue Hinweis tragen sichtbaren deutschen Text; das Symbol des Hinweises ist für VoiceOver ausgeblendet, sonst läse es
  „Picture In Picture Window“ vor.
- **BUG-04, Website-Teil** — gehört zur B10-Reparatur Teil 2 (`web/content/features.ts`, `web/app/support/page.tsx`).
- **„Zurück zur App“ stellt den Player nicht wieder her**, wenn er verlassen wurde, sondern beendet die Wiedergabe. Der
  Auftrag lässt beides zu; Wiederherstellen bräuchte gebundene Navigationspfade → `spec.md` OF-05.
- **Kein fehlerfreier Gesamtlauf in einem Stück.** Lauf 2 (482 Tests) hatte 2 Fehlschläge durch fremde Tastenereignisse
  eines parallelen Test-Hosts, beide einzeln grün; ein dritter Lauf ohne parallelen Host scheiterte am gesperrten
  Bildschirm (siehe *Verifikation*). Empfehlung: Gesamtlauf wiederholen, wenn kein anderer Test-Host läuft und der
  Bildschirm entsperrt ist.
- **Kein Test im Test-Target für BUG-05** (iOS-only-Knopf, Tests nur macOS). Belegt über die iPad-Sonde. Die Lage
  „Fenster unten links, Knopf oben rechts frei“ ist gelesen, nicht nachgestellt.
- **Player-Hinweis nur per Taste P** — am iPad ohne Tastatur nie sichtbar (einen Knopf gibt es bei VLC nach AK-09 nicht)
  → OF-06. Am iPad erreicht P den Player weiterhin erst nach einem Tab (Sonde: `p` ohne Tab ohne Wirkung) – das ist
  B06 BUG-08 (dort „eingebaut, nicht nachgewiesen“); hiermit am Simulator als **nicht wirksam** beobachtet.
- **Nicht aus dem Auftrag, festgestellt** (nur der erste Punkt ist mitbehoben, weil BUG-01 davon abhängt):
  - **B06 BUG-02 griff in der echten Mac-Oberfläche nicht:** `@Environment(\.isPresented)` ist beim Verschwinden nach
    „Zurück“ aus der Senderliste (Stapeltiefe 2: Playlists → Senderliste → Player) noch wahr, `onChange` feuert nicht;
    der Player hielt sich für verdeckt und pausierte nur (Diagnose mit Protokollzeilen, drei Aufbauten: Playlists-Stapel
    ohne Tabs → wahr, Favoriten-Stapel (Tiefe 1) → falsch, `ContentView`/Favoriten → falsch). Die B06-Tests liefen nur mit
    Tiefe 1 und sahen das nicht. Mitbehoben über `ShellTabs` (siehe 3, Punkt 5, und 4). Für das B06-Review.
  - Multiview-Kacheln beenden eine verwaiste Bild-in-Bild-Wiedergabe nicht → OF-07; Löschen der Playlist beendet sie nicht
    → OF-08; Tabwechsel mit Bild-in-Bild, dann Sender im anderen Tab → beide laufen → OF-09 (alle gelesen, nicht gebaut).
  - Nach dem Ende einer HLS-Wiedergabe hält AVFoundation eine leere Keep-alive-Verbindung (0 Anfragen, wie B06 notiert);
    die System-Tests zählen sie als „offeneVerbindungen=1“.
  - Laufzeitwarnung H-1 („AVPictureInPicturePlayerLayerView as a subview of NSHostingView“) unverändert.

## 3 · Getroffene Annahmen

Alle ohne Rückfrage (Zielmodus), zur Bestätigung durch den Nutzer.

1. **Zielverhalten BUG-01** wie im Auftrag: Das verwaiste Fenster bleibt (B06) und ist steuerbar; es endet mit
   „Schließen“, „Zurück zur App“, `stopPictureInPicture()` oder dem Start bzw. Fortsetzen eines Players. OF-04 bleibt offen.
2. **Wer beendet:** `PlayerView.startIfNeeded()` ruft `DetachedPlayback.shared.stopAll()` – beim ersten Erscheinen und bei
   jeder Rückkehr (auch in einem anderen Tab oder Fenster). Multiview beendet nicht (OF-07).
3. **Fenster schließen ohne Player:** `stopPictureInPicture()` bleibt am Mac wirkungslos, wenn die Videofläche in keinem
   Fenster mehr hängt (QA 1, erneut belegt). `stop()` gibt deshalb den `AVPictureInPictureController` samt Delegate ab
   (Fenster zu nach 0,2–0,3 s); an einer übernommenen Engine tut `stopPictureInPicture()` dasselbe. Bei Bedarf entsteht
   ein neuer Controller (`setupPictureInPictureIfNeeded`).
4. **Restore-Delegate:** `completionHandler(true)`, solange die Engine nicht von `DetachedPlayback` gehalten wird (offener
   Player, Verhalten EC-08 unverändert), sonst `false` – das System beendet Bild-in-Bild ohne Rückkehr, `DetachedPlayback`
   stoppt beim Ende.
5. **„Zurück“ erkennen (`ShellTabs`):** In `ContentView` gilt der Player als verlassen, wenn beim Verschwinden sein eigener
   Tab weiter sichtbar ist; ist ein anderer Tab sichtbar, ist es ein Tabwechsel (nur Pause, AK-27). Ohne `ShellTabs`
   (eigene Fenster der Tests) gilt wie bisher `isPresented`. Der Tab wird beim ersten Erscheinen gemerkt.
6. **Pausenzustand (BUG-03):** beobachtet wird `timeControlStatus` (nicht `rate`); „wartet/puffert“ zählt als läuft. Ohne
   Element gilt der eigene Zustand (hält `PlaybackEngineTests.testTogglePlayPauseFlipsIsPaused` bei einer Engine ohne
   Stream); am Ende einer Datei (Position ≥ Dauer − 0,5 s) bleibt „läuft“ (B06 EC-04).
7. **Hinweistexte (BUG-04):** Import „Originalformat des Anbieters – benötigt VLCKit. Bild-in-Bild gibt es nur mit HLS.“,
   Player „Bild-in-Bild gibt es nur mit HLS, nicht mit MPEG-TS.“ (HUD mit Symbol `pip`, 3 s statt 0,9 s). Nur wenn das
   Gerät Bild-in-Bild kann und die Engine nicht (heute: VLC); Geräte ohne Unterstützung wie bisher still (AK-08).
8. **Knopf am iPad (BUG-05):** zusätzlich, nicht verschoben – der Knopf oben rechts (AK-01) bleibt; der neue erscheint nur
   auf iOS, nur bei aktivem Bild-in-Bild, als Kapsel mit Symbol und Text in der unteren Leiste (neue Variante neben den
   runden Symbolknöpfen, gleiche Farben: weiß auf Schwarz 50 %).
9. **Kein neuer Test-Target, `project.yml` unverändert** (Vorgabe); `B07ReparaturTests` liegt im bestehenden Target.
10. **Nachweise:** neue Bilder und Protokolle heißen `BUILD-…` in `features/B07-bild-in-bild/qa/`; von den Testläufen
    überschriebene QA-1-Bilder sind zurückgesetzt, zusätzlich entstandene Bilder ohne `BUILD-` gelöscht.
11. **Helfer für das Systemfenster:** die QA-Werkzeuge (`qa/werkzeuge/bridge2.sh`, `pipwin`, `pipax.js`) liefen aus einer
    Kopie im Scratchpad; ohne sie werden die fünf Systemfenster-Tests übersprungen (wie im B06-Gesamtlauf).
12. **Umbenannte Tests:** `testAK09_TSUeberVLC_KeinKnopf_PNurSteuerung_KeinHinweis` → `…_PZeigtHinweisNurHLS`;
    `testAK09_ImportSheetStandardMPEGTS_OhneHinweisAufBildInBild` → `…_MitHinweisBildInBildNurHLS`;
    V `testAK16_PauseImPiPFenster_AppZeigtWeiterLaeuft_ErsterDruckVerpufft` → `…_AppZeigtAngehalten_ErsterDruckSetztFort`;
    S `testAK16_PauseKnopfDesSystemfensters_AppZeigtWeiterLaeuft` → `…_AppZeigtAngehalten`;
    `testAK17_EC10_ZweiterPlayerStartetPiP_ErsterPausiertZeigtAberLaeuft` → `…_ErsterPausiertUndZeigtEs`.
    AK-09 liest die Texte jetzt direkt nach P (der Hinweis steht 3 s) und prüft zusätzlich, dass er wieder verschwindet;
    EC-07 prüft `isPaused == (rate == 0)` statt nur bei Rate 0; AK-15c prüft zusätzlich, dass das alte Fenster schließt.

## 4 · Systemweite Änderungen

**Achtung B06-Review:** `DetachedPlayback`, `PlayerView` und `AVKitPlaybackEngine` sind gegenüber dem gereviewten B06-Stand
geändert. Die B07-Änderungen daran vollständig:

| Datei / Stelle | Feature | Änderung gegenüber dem B06-Stand |
|---|---|---|
| `Sources/Services/DetachedPlayback.swift` | B06, **B07** | neu `holds(_:)`; Doku von Klasse und `stopAll()` (wer ruft es auf, wozu). Logik von `adopt`, `stopAll`, Beobachtung unverändert |
| `Sources/Views/PlayerView.swift` | **B06**, B07 | (1) `startIfNeeded()` ruft zuerst `DetachedPlayback.shared.stopAll()`; (2) **Verlassen-Erkennung:** `onDisappear` fragt `stillInStack` statt `isPresented` – mit `ShellTabs` (echte App) entscheidet der sichtbare Tab, sonst `isPresented` wie bisher; `ownTab` wird im ersten `onAppear` gemerkt. **Wirkt auf B06 BUG-02/AK-27:** „Zurück“ aus der Senderliste beendet jetzt auch in der echten Mac-Oberfläche die Wiedergabe (vorher nur Pause); Tabwechsel pausiert weiter; (3) `togglePiP()`: Hinweis-HUD bei VLC; (4) HUD-Art `.notice`, `showHUD(_:seconds:)` (Standard 0,9 s unverändert); (5) iOS: Knopf „Bild-in-Bild beenden“ in `bottomControls` |
| `Sources/Services/AVKitPlaybackEngine.swift` | **B06**, B07, **B08** | (1) `stop()` ruft `endPictureInPicture()` statt `stopPictureInPicture()` und gibt dabei den PiP-Controller ab – gilt für jeden `stop()`-Aufruf: Verlassen (B06), Playlist-Löschen (B03), Multiview `remove`/`clear` (B08); (2) `stopPictureInPicture()` beendet an einer übernommenen Engine endgültig; (3) `isPaused` folgt `timeControlStatus` (neuer Beobachter), `togglePlayPause()` gleicht vorher ab – **wirkt auf B06 (Play/Pause-Knopf, HUD) und B08 (Kacheln):** ein vom System oder durch Fehler angehaltener Player zeigt ▶; (4) Restore-Delegate; (5) `static deviceSupportsPictureInPicture` |
| `Sources/Services/PlaybackEngine.swift` | alle | `PlaybackEngineFactory.deviceSupportsPictureInPicture` (neu). Protokoll unverändert |
| `Sources/App/ContentView.swift` | **App-Shell**, alle | `TabView(selection:)` mit Tags, neue Klasse `ShellTabs` (sichtbarer Tab je Fenster) per `.environment`. Sichtbares Verhalten unverändert; jedes Hauptfenster hat seine eigene Instanz |
| `Sources/Services/XtreamCodes.swift` | **B01** | `XtreamOutput.hint` für MPEG-TS um „Bild-in-Bild gibt es nur mit HLS.“ ergänzt (B01-Tests prüfen per „enthält“, weiter grün) |
| `docs/app-shell.md`, `docs/design-system.md` | Doku | **nicht geändert, jetzt veraltet:** Player-Chrome „Verlassen …“ (siehe B06-Bericht), neu: iOS-Knopf „Bild-in-Bild beenden“ als Kapsel, HUD-Hinweis mit Text; `TabView` mit Auswahl |
| `features/B07-bild-in-bild/spec.md` | Doku | nur *Offene Fragen*: OF-05 bis OF-09 |
| `Tests/B07/*` | Tests | 9 `XCTExpectFailure`-Blöcke entfernt, 5 Tests umbenannt, neu `B07ReparaturTests` (6), zusätzliche Bilder `BUILD-BUG-04-…` in `B07KnopfTests` (AK-09) und `B07ImportHinweisTests` |
| `project.yml`, `Info.plist`, Entitlements, Abhängigkeiten | alle | **unverändert** |

Nicht angefasst: `features/index.md`, `features/befunde.md`, `appcast.xml`, `web/`, Schlüsselbund, die echte Datenbank,
`PlaylistsView`, `ChannelListView` (ein Versuch, das Sender-Ziel an die Wurzel des Stapels zu legen, half nicht und ist
zurückgenommen).

## Verifikation

Stand 2026-09-28. Ausgaben gefiltert; vollständige Protokolle nur im Scratchpad der Session (nicht im Repository). Nach einem Neustart der Umgebung
(28.09., `/private/tmp` geleert) wurden Helfer und Läufe neu aufgesetzt; die Stellen vom 27.09. sind als solche markiert.

**0 · Reproduktion vor der Reparatur** (27.09., B06-Stand im Arbeitsbaum, Helfer für das Systemfenster, `-only-testing`
V `testAK15b_…`, O `testAK15c_…`, S `testAK15d_…`, `testAK15e_…`):

```
AK-15c|Ergebnis: parallel≈45 s, altes Fenster weg=nein (45 s), engineA nach B=true
AK-15d|close: …|10 s danach: engine=true aktiv=false rate=0.0 segmente(8s)=0 …|Segmente in 20 s=0
AK-15e|restore: …|10 s danach: engine=true aktiv=false rate=0.0 segmente(8s)=0 …|Segmente in 40 s=0
AK-15d/e: error: Expected failure 'BUG-01 · Nach „Zurück“ bleibt eine Wiedergabe ohne Player …' but none recorded
AK-15b|stopPictureInPicture() an der verwaisten Engine|t=17.4s pipfenster=1 … aktiv=true rate=1.0
AK-15b|Ergebnis: weiterlaufend nach Zurück=true pipKnopfInApp=false fensterNachStopp=1 gleichzeitig≈60s altesFensterWeg=nein (bis 60 s)
Executed 4 tests, with 2 failures · ** TEST FAILED **     (die 2 = AK-15d/e: B06 hatte „Schließen“/„Zurück zur App“ schon behoben)
```

Diagnose „Zurück“ in der echten Oberfläche (27.09., Protokollzeilen im Player, danach entfernt):

```
Playlists → Senderliste → Player, „Zurück“:  onDisappear|QA Sender A|isPresented=true     (onChange feuert nicht)
Favoriten → Player (Tiefe 1), „Zurück“:       onDisappear|QA Diag f|isPresented=false
nach ShellTabs: onDisappear …|ownTab=playlists|selected=favorites  → Tabwechsel (Pause)
                onDisappear …|ownTab=playlists|selected=playlists  → verlassen (stop)
```

**1 · Projekt erzeugen** — `xcodegen generate` → `Created project at …/MikaPlusPlayer.xcodeproj`, exit 0.

**2 · Sauberer macOS-Build** — `xcodebuild clean build-for-testing … -derivedDataPath build/dd-test`

```
** CLEAN SUCCEEDED **
** TEST BUILD SUCCEEDED **
Warnungen in Sources/: 0 · in Tests/: 32 Stellen, keine in einer von B07 geänderten oder neuen Datei
(B07: nur die aus QA 1 bekannten B07Support.swift:49 CGWindowListCreateImage, B07DatenschutzTests.swift:121 commonMetadata)
```

**3 · macOS-Gesamtläufe** — `xcodebuild test -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -derivedDataPath build/dd-test -collect-test-diagnostics never`,
mit `TEST_RUNNER_B07_BRIDGE` (Helfer aus `qa/werkzeuge`, im Scratchpad gestartet) – die sieben B07-Systemfenster-Tests
laufen dadurch, statt übersprungen zu werden (Hinweis R-03 aus dem B06-Review: AK-15d/e mit Helfer ausgeführt, grün mit
Assertion statt `XCTExpectFailure`).

**Maßgeblich: Lauf 2** (28.09. 18:15–19:13; parallel lief die Gesamtsuite der B02+B03-Nacharbeit):

```
Test Suite 'B06PlayerViewTests' failed       Executed 17 tests, with 1 test skipped and 1 failure (0 unexpected)
Test Suite 'B06ReparaturTests' passed        Executed 8 tests, with 0 failures (0 unexpected)
Test Suite 'B07AngriffTests' passed          Executed 4 tests, with 0 failures (0 unexpected)
Test Suite 'B07AppOberflaecheTests' passed   Executed 1 test, with 0 failures (0 unexpected)
Test Suite 'B07DatenschutzTests' passed      Executed 5 tests, with 0 failures (0 unexpected)
Test Suite 'B07ImportHinweisTests' passed    Executed 1 test, with 0 failures (0 unexpected)
Test Suite 'B07KnopfTests' failed            Executed 11 tests, with 1 failure (0 unexpected)
Test Suite 'B07ReparaturTests' passed        Executed 6 tests, with 0 failures (0 unexpected)
Test Suite 'B07SystemfensterTests' passed    Executed 7 tests, with 0 failures (0 unexpected)     ← mit Helfer, keiner übersprungen
Test Suite 'B07VerlassenTests' passed        Executed 6 tests, with 0 failures (0 unexpected)
Test Suite 'B08OberflaecheTests' passed      Executed 14 tests, with 1 test skipped and 0 failures (0 unexpected)
Test Suite 'B08SessionTests' passed          Executed 18 tests, with 0 failures (0 unexpected)
Test Suite 'PlaybackEngineTests' passed      Executed 6 tests, with 0 failures (0 unexpected)
Test Suite 'All tests' failed
	 Executed 482 tests, with 23 tests skipped and 2 failures (0 unexpected) in 3495.217 (3495.478) seconds
** TEST FAILED **
B06PlayerViewTests.swift:57: error: -[… testEC12_ZweiPlayerZweiVerbindungenTastenNurImAktivenFenster] : XCTAssertEqual failed: ("["SYSTEMBEEP-UNTERDRUECKT NSWindow keyDown:"]") is not equal to ("[]")
B07KnopfTests.swift:195: error: -[… testAK05_TasteP_KleinUndGross_BlendetSteuerungEin_KeinHUD_KeinBeep] : XCTAssertEqual failed: ("["SYSTEMBEEP-UNTERDRUECKT NSWindow keyDown:"]") is not equal to ("[]")
```

Beide Fehlschläge sind fremde Tastenereignisse: Vor beiden ging `ohne-Empfaenger NSWindow keyUp:` ein – ein Tastenpaar
`keyDown`+`keyUp`, die Tests senden nur `keyDown` (dieselbe Störung durch einen parallelen Test-Host, die der B06-Bericht
beschreibt). Einzeln wiederholt, ohne parallelen Test-Host, beide grün:

```
B07KnopfTests testAK05_TasteP_KleinUndGross_BlendetSteuerungEin_KeinHUD_KeinBeep passed (12.062 seconds)   ** TEST SUCCEEDED **
B06PlayerViewTests testEC12_ZweiPlayerZweiVerbindungenTastenNurImAktivenFenster passed (4.518 seconds)      ** TEST SUCCEEDED **
   (Test-Host per System Events nach vorn geholt; allein gestartet meldet er sonst „Test-Host wurde nicht aktiv“ → skipped)
```

B07 enthält 0 erwartete Fehlschläge (QA 1: 19). Übersprungen (23): nur mit Umgebungsvariablen geschützte Tests (B01, B03,
B04, B05, B06 langsam/Deadlock/Erkundung, B08 Absturz/Neustart/Nachtrag, B08 AK-29) und B06 AK-22 (Hover, wie in QA 1);
kein B07-Test.

**Einen Gesamtlauf ganz ohne Fehlschlag gibt es nicht.** Ein dritter Lauf (19:21, ohne parallelen Test-Host) blieb nach
112 bestandenen Tests in `B02OberflaecheTests testAK16_…` stehen: Ab 19:31 war der Bildschirm des Rechners gesperrt
(`CGSSessionScreenIsLocked 1`, im Protokoll „Accessibility: Not vending elements because elementWindow(0) is lower than
shield(2001)“); abgebrochen, bis dahin 0 Fehlschläge. Die Bedienungshilfen-Tests laufen erst nach dem Entsperren wieder.

Frühere Läufe, eingeordnet: Lauf 1 (28.09. 17:24) wurde nach 361 bestandenen Tests von außen abgebrochen
(`** BUILD INTERRUPTED **` um 18:12:57, als der Review-Worktree seinen B07-Lauf startete); bis dahin 2 Fehlschläge in
`B03OberflaecheTests` (Kontextmenü brauchte unter Last 97 s statt 4–14 s) und 1 in `B06PlayerViewTests testAK01_AK14`
(Klick erreichte das Bild nicht) – alle drei in Lauf 2 grün.

Ein Zwischenlauf am 27.09. (B07 + B06-Player, 73 Tests) hatte in `B07VerlassenTests testAK16_…` und `testEC03_…`
Fehlschläge, als ein anderer Test-Host gleichzeitig Bild-in-Bild startete (das System hält dann das eigene Fenster an,
`pipActive=false` bei offenem fremdem Fenster); einzeln und in Lauf 2 grün.

**4 · Sauberer iOS-Build** — `xcodebuild clean build -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd-ios`

```
** CLEAN SUCCEEDED **
** BUILD SUCCEEDED **
einzige Warnung: appintentsmetadataprocessor … Metadata extraction skipped, no AppIntents.framework dependency found
```

**5 · Mock-Protokoll BUG-01 (macOS, Anfragen je Sekunde; A = alter Sender im schwebenden Fenster, B = neuer Sender)**

```
Test-Stapel (R testBUG01_ZurueckMitPiP_AndererSender_AltesEndetNieZweiStreams), ab 6 s vor dem Öffnen von B:
A=[2, 0, 2, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
B=[0, 0, 0, 0, 0, 0, 5, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0]
6 s nach Zurück: pipfenster=1 anfragenA=6 rateA=1.0 übernommen=true
B geöffnet: altes Fenster weg nach 0.2s|anfragenA nach erster Anfrage von B=0|anfragenA ab 0,5 s nach dem Öffnen=0|Sekunden mit Anfragen an A und B=0
B verlassen: Anfragen A+B 1–8 s danach=0|pipfenster=0

Echte ContentView (R testBUG01_EchteOberflaeche_ZurueckMitPiP_AndererSender_AltesEndet), ab 4 s vor dem Öffnen von B:
A=[2, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
B=[0, 0, 0, 0, 5, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0]
B spielt=true|altes Fenster weg nach 0.3s|anfragenA nach erster Anfrage von B=0|Sekunden mit A und B=0|übernommen=0

stopPictureInPicture() ohne Player (R testBUG01_BeendenOhnePlayer_…): fenster weg nach 0.3s|anfragen 1–9 s danach=0|element=false|protokoll=[2, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0]
Systemfenster „Schließen“ (S AK-15d):      2 s danach pipfenster=0 | rate=0.0 segmente(8s)=0, danach 4 × 5 s je 0
Systemfenster „Zurück zur App“ (S AK-15e): 2 s danach pipfenster=0 | rate=0.0 segmente(8s)=0, danach 8 × 5 s je 0
Restore-Delegate (R testBUG01_ZurueckZurApp_…): mit offenem Player=true | nach Zurück (übernommen=true)=false
Tabwechsel/Zurück (R testBUG01_EchteOberflaeche_TabwechselPausiert_ZurueckBeendet): Tabwechsel isPaused=true element=true | Zurück element=false anfragen 1–6 s danach=0
AK-15a/b: fensterNachStopp=0 gleichzeitig≈0s · AK-15c (echte Oberfläche): parallel≈0 s, altes Fenster weg=3.1 (Messraster 3 s)
BUG-03 (R testBUG03_…): Pause von außen → isPaused nach 0.05s|Play von außen → nach 0.05s|erster Druck setzt fort nach 0.00s
```

**6 · iPad (27.09.)** — eigener Simulator „B07-Build iPad Pro 11“ (iPad Pro 11-inch M4, iOS 26.5), am Ende gelöscht;
Debug-Build aus `build/dd-ios`, Playlist per URL-Import vom Mock `iosserver.py` auf 127.0.0.1:18937, Medien ohne Tonspur
(ffprobe: 0 Audiospuren), Bedienung mit AXe. Protokoll `qa/BUILD-IOS-sonde-protokoll.txt`, Bilder `qa/BUILD-IOS-ipad-01…09`:

```
BUG-05: PiP aktiv, Fenster oben rechts über „Maximise Video“ (710,152) · Button 'Bild-in-Bild beenden' (148,1134,207x43) frei
        Tipp → PIPUIView=0, oberer Knopf wieder 'Minimise Video'
BUG-01: 23:12:49 Zurück mit PiP → 6 s später PIPUIView=1 (läuft weiter, ios1 alle 2 s)
        23:13:07,6 erste Anfrage ios2 · letzte Anfrage ios1 23:13:06,3 · 10 s später PIPUIView=0
        23:13:51,9 „Zurück zur App“ im verwaisten Fenster → restoreUserInterfaceForPictureInPictureStop… 23:13:52,36,
        didStop 23:13:53,20 · letzte Anfrage ios2 23:13:51,8, danach keine · PIPUIView=0
BUG-03: Pause im Fenster → App 'Play' · erster Tipp auf ▶ → App 'Pause', Fenster ■, 3 Segmentabrufe in 4 s
BUG-04: Import-Sheet „… benötigt VLCKit. Bild-in-Bild gibt es nur mit HLS.“ · TS-Sender: p ohne Tab ohne Wirkung (B06 BUG-08),
        Tab + p → StaticText 'Bild-in-Bild gibt es nur mit HLS, nicht mit MPEG-TS.'
Tabwechsel im Player → Favoriten; zurück → Player 'Pause' (spielt) · Zurück ohne PiP → Anfragen 1–7 s danach: 0
```

**Aufräumen:** eigener iPad-Simulator am 27.09. gelöscht (`xcrun simctl delete`), iOS-Mock, Helfer (`bridge2.sh`) und
Testmedien beendet bzw. im Scratchpad gelöscht, keine eigenen Prozesse mehr; eine Diagnose-Testdatei und Protokollzeilen im
Player wieder entfernt. `git status features/` nach dem letzten Lauf: von den Testläufen überschriebene Nachweise der
Features B02, B03, B04, B06, B07 (QA-1-Bilder) und B08 mit `git checkout --` zurückgesetzt; vier `BUILD-…`-Bilder von B06, die
die B06-Tests neu geschrieben hatten, bytegleich aus dem B06-Stand (`3aaf142`) wiederhergestellt; zwei zusätzlich
entstandene B07-Bilder ohne `BUILD-` gelöscht. Neu sind nur `features/B07-bild-in-bild/qa/BUILD-…`, `build-bericht.md`,
Vermerke in `qa-report.md` und OF-05–OF-09 in `spec.md`. Verbleibend: `build/dd-test`, `build/dd-ios` (erlaubt), `build/dd`
(lag schon vorher). Datenbank und Schlüsselbund des Nutzers weder gelesen noch beschrieben, alles ohne Ton.


## Review 2026-09-29

Unabhängiges Review der B07-Reparatur (bisher ohne Review), gemeinsam mit B08. Geprüfter Stand: Commit-Objekt `bb7ccd5`
(B06-Stand `3aaf142` + B07 + B02/B03-Nacharbeit + B08), eigener Worktree mit eigener DerivedData, danach entfernt. Gelesen:
`git diff 3aaf142 bb7ccd5` für `AVKitPlaybackEngine`, `DetachedPlayback`, `PlayerView`, `ContentView` (`ShellTabs`),
`PlaybackEngine`, `XtreamCodes`, `Tests/B07`; `qa-report.md` mit den „Behoben“-Vermerken; dieser Bericht. Alle Streams von
127.0.0.1, Medien ohne Tonspur, keine hörbare Ausgabe. Systemfenster-Helfer (`qa/werkzeuge`: `bridge2.sh`, `pipwin`, `pipax.js`)
aus dem Worktree gestartet. Parallel lief zeitweise der Test-Host der B04-Reparatur. Gefilterte Protokolle und der eigene Prüftest
(`ReviewB07Tests`) liegen außerhalb des Repositorys unter `~/.claude/projects/…/e8de96ed-…/review-b08-belege/`.

**Läufe (Debug, `test-without-building`, mit Helfern):**

```
B07AngriffTests, B07AppOberflaecheTests, B07DatenschutzTests, B07KnopfTests, B07ImportHinweisTests, B07ReparaturTests,
B07SystemfensterTests, B07VerlassenTests: Executed 41 tests, with 4 tests skipped and 1 failure (0 unexpected)
  ← ab 19:39 lief ein fremder Test-Host (B04) parallel; Fehlschlag und Übersprünge nur in B07VerlassenTests, siehe unten
B07VerlassenTests einzeln wiederholt: Executed 6 tests, with 0 failures (0 unexpected) · ** TEST EXECUTE SUCCEEDED **
AK-15a + R testBUG01_BeendenOhnePlayer zweimal einzeln: 2 × 2 bestanden (fensterNachStopp=0; Fenster weg nach 0,3/0,4 s)
ReviewB07Tests (eigener Test): bestanden
iOS: xcodebuild build … 'generic/platform=iOS Simulator' → ** BUILD SUCCEEDED ** (nur gebaut, nicht ausgeführt)
```

**Belege zu den Prüfpunkten**

1. **Nie zwei Streams (Mock-Protokoll, Anfragen je Sekunde)** — R `testBUG01_ZurueckMitPiP_AndererSender_…`, ab 6 s vor dem
   Öffnen von B: `A=[2, 0, 2, 0, 2, 0, 0, 0, …]`, `B=[0, 0, 0, 0, 0, 0, 5, 0, 2, 0, 2, …]`; altes Fenster weg nach 0,2 s,
   Anfragen an A nach der ersten von B `0`, Sekunden mit A und B `0`, nach dem Verlassen von B 0 Anfragen. Echte `ContentView`
   (R `…EchteOberflaeche_…`): `A=[2, 0, 2, 0, 0, …]`, `B=[0, 0, 0, 0, 5, 0, 2, …]`, Fenster weg nach 0,2 s. O AK-15c: parallel
   ≈ 0 s. Eigener Test mit einem **VLC-Sender** als nächstem (HLS mit Bild-in-Bild → „Zurück“ → MPEG-TS): übernommen `true`,
   B verbunden nach 0,1 s, altes Fenster weg nach 0,2 s, 0 Anfragen an A danach, Element von A frei, TS nach „Zurück“ zu (0,1 s).
2. **Verwaistes Bild-in-Bild endet** — V AK-15a/b: `fensterNachStopp=0`, gleichzeitig ≈ 0 s, altes Fenster weg nach 3,1 s
   (Messraster 3 s); R `testBUG01_BeendenOhnePlayer_…`: Fenster weg nach 0,3 s, 0 Anfragen, Element frei.
3. **`restoreUserInterfaceForPictureInPictureStop`** — R `testBUG01_ZurueckZurApp_…`: mit offenem Player `true`, nach „Zurück“
   (übernommen) `false`; S AK-15e mit dem **echten** Knopf „Zurück zur App“ des Systemfensters: 50 s ohne Fenster, Rate 0,
   0 Segmente in 40 s; S EC-08 (Player offen): Bild kehrt zurück; S AK-15d „Schließen“: 30 s ohne Fenster, 0 Segmente.
4. **Zustand folgt `timeControlStatus`** — R `testBUG03_…`: Pause von außen → `isPaused` nach 0,05 s, Fortsetzen von außen nach
   0,05 s, erster Druck setzt sofort fort; S AK-16 (echter Pause-Knopf des Systemfensters) und V AK-16: Knopf „play.fill“, erster
   Druck Rate 1,0; V AK-17/EC-10: erster Player `isPaused=true`, Rate 0, Knopf „play.fill“; S EC-07: `isPaused == (rate == 0)`.
5. **Mitbehobener B06-Fehler (`ShellTabs`)** — R `testBUG01_EchteOberflaeche_TabwechselPausiert_ZurueckBeendet` (HLS, Stapeltiefe
   2): Tabwechsel `isPaused=true`, Element bleibt; „Zurück“ → Element frei, 0 Anfragen. Eigene Tests in der echten `ContentView`
   mit **VLC-Sender**: Playlists → Senderliste → Player und Favoriten → Player (Tiefe 1) – Tabwechsel pausiert nur, Rückkehr setzt
   **dieselbe** Engine fort (Zeit läuft), „Zurück“ schließt die TS-Verbindung nach 0,0–0,1 s und baut den VLC-Player ab.
6. **Tests nicht aufgeweicht** — `XCTExpectFailure` in `Tests/B07` 9 → 0. Die Assertions aus den entfernten Blöcken stehen
   unverändert (AK-15a/b, AK-15d/e, AK-16 ×2, AK-17) oder strenger da: AK-15c zusätzlich „altes Fenster schließt“, EC-07 jetzt
   `isPaused == (rate == 0)` statt nur bei Rate 0, AK-09 (Sheet und Player) prüft den genauen deutschen Text statt „bild-in-bild
   oder picture“ und zusätzlich das Verschwinden des Hinweises. Die fünf Umbenennungen beschreiben das neue Verhalten.
7. **Regressionen durch die Controller-Abgabe in `stop()`** — B06-Suiten grün (35 Tests, u. a. AK-28/28b Verlassen, EC-13
   Fenster schließen, R `testBUG02_MitBildInBildLaeuftWeiterBisBildInBildEndet`); B07 `testEC04_EC05_AbbruchWaehrendPiP_…
   ErneutVersuchen`, `testAngriff3_PiPUmschaltenInSchnellerFolge_…`, `testAK03_AK04_…` (Knopf öffnet und schließt) bestanden.
8. **Sicherheit** — neue Texte fest („Bild-in-Bild gibt es nur mit HLS …“), kein neuer `print`/`NSLog`/`os_log`/`Logger` in den
   geänderten Dateien; `B07DatenschutzTests testAK23_…`: `app=0 pip/avkit=0`, der eine Netzwerktreffer stammt aus CFNetwork im
   Test-Host (bekannt als BF-43).

**Funde**

Keine belegten Funde gegen die B07-Reparatur.

**Hinweise**

- Im Lauf mit parallelem Fremd-Host blieb bei V AK-15a nach `stopPictureInPicture()` an der übernommenen Engine das
  **Systemfenster** 40 s lang sichtbar (Wiedergabe stand: Rate 0, 0 Segmente; `fensterNachStopp=1`), danach wurden vier Tests
  übersprungen („Test-Host wurde nicht aktiv“). Einzeln wiederholt 3 von 3 grün, ebenso R `testBUG01_BeendenOhnePlayer_…`
  3 von 3. **Nicht belegbar wegen Parallelbetrieb**; in QA 2 ohne fremden Host erneut beobachten.
- iOS/iPadOS-Teile (BUG-05-Knopf, iPad-Anteile von BUG-01/03/04) hat das Review nur gebaut, nicht im Simulator ausgeführt; Beleg
  bleibt die iPad-Sonde des Builds.
- Offen und dokumentiert: OF-05 bis OF-09 (u. a. verwaistes Bild-in-Bild neben Multiview, nach Tabwechsel neben neuem Sender).

**Urteil B07: in Ordnung.** Nie zwei Streams, Ende des verwaisten Bild-in-Bild beim nächsten Sender, Restore-Delegate,
Pausenzustand und „Zurück“ aus der Senderliste sind ausgeführt belegt; die B06-Regressionstests sind grün.

**Aufgeräumt:** siehe B08-Bericht, Abschnitt „Review 2026-09-29“ (gemeinsamer Worktree, Helfer und Mock beendet, Worktree
entfernt).
