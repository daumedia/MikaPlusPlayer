# B06 · Wiedergabe — Build-Bericht

Durchlauf 1 · 2026-09-27 · Eingang: Fehlerauftrag (`qa-report.md` QA 1, BUG-01 bis BUG-09 ohne BUG-05) · Branch `sdd/reparaturen`
auf dem Stand von `main` (`47a90c3`), nicht committet

## 1 · Umgesetzt

Die VLC-Engine meldet ihre Fehler: 401/403/404, nicht erreichbarer oder unbekannter Host, HTML statt Video, Abbruch und Hänger enden
in der Fehleransicht mit einer deutschen Meldung ohne Adresse, mit Zeitgrenzen analog zur AVKit-Engine (40 s bis zum ersten Bild,
30 s ohne neues Bild). „Läuft“ heißt erst, wenn VLC ein Bild dekodiert bzw. zeigt. Verlassen beendet die Wiedergabe: „Zurück“ und
am Mac das Schließen des Fensters stoppen die Engine und schließen die Verbindung (AVKit: Element frei, VLC: stoppen und Player
abbauen); ein Tabwechsel pausiert wie bisher nur. Mit aktivem Bild-in-Bild läuft die Wiedergabe im schwebenden Fenster weiter, bis
Bild-in-Bild endet, und endet dann ebenfalls – über eine neue app-weite Stelle (`DetachedPlayback`), auf der die B07-Reparatur
aufbauen kann. VLC-Player werden nur noch einzeln und gestoppt abgebaut, neue entstehen erst danach; das schließt die Lage aus, in
der libVLC in QA 1 hing, auch für Multiview. Der Vollbildzustand ist an das Fenster des Players gebunden. Der README-Hinweis erscheint
nur noch ohne VLCKit, der Ladekreis ist weiß, der Sendername unter iOS im hellen Erscheinungsbild lesbar. Die Bezugsquelle von VLCKit
(BUG-03) ließ sich unter den gesetzten Bedingungen nicht umstellen.

| BUG | Grad | Ergebnis | Wo | Nachweis |
|---|---|---|---|---|
| BUG-01 | hoch | behoben | `VLCPlaybackEngine` (Zustand im Delegate, Wächter, Fristen, `Failure`) | Z `testAK10_…ZeigenMeldung`, `testAK11_…MeldenSich` (auch langsam: 40,0 s, 30,4 s), `testAK12_EC04_…`, `testAK35_…`; P `testAK10_AK11_…MitMeldung`; R `testBUG01_…` (3); iOS-Sonde |
| BUG-02 | hoch | behoben | `PlayerView.leavePlayer`, `DetachedPlayback` (neu), `VLCPlaybackEngine.pause/stop`, `MultiviewSession.remove/clear` | R `testBUG02_…NullWeitereAnfragen` (4 × 0 Anfragen nach „Zurück“, höchstens 1 Strom), `testBUG02_MitBildInBild…`; P `testAK28_…`, `testAK28b_…`, `testAK29_…`; S `testEC05_…`; iOS-Sonde iPhone + iPad |
| BUG-03 | hoch | **nicht behoben** | — (`project.yml` unverändert) | Bedingung (b) nicht erfüllbar, siehe 2; eingebettete Version am Bundle belegt |
| BUG-04 | mittel | behoben | `PlayerView.showsMissingVLCKitHint` | P `testAK13_…`, `testAK10_AK11_…` |
| BUG-05 | niedrig | nicht Teil des Auftrags | Website (B10 Teil 2) | — |
| BUG-06 | mittel | behoben | `PlayerView` (`PlayerWindowReader`, `PlayerHostWindow`, Vollbild-Benachrichtigungen) | P `testAK23_…PlayerFenster`, `testAK24_…PlayerFolgtFenster`; R `testBUG06_…` |
| BUG-07 | mittel | behoben (Ursache ausgeschlossen; Hänger war schon in QA 1 nicht reproduzierbar) | `VLCPlayerLifecycle`, `VLCPlayerBox` (neu, in `VLCPlaybackEngine.swift`), `MultiviewSession` | R `testBUG07_…` (Multiview 3 × 4 schließen + sofort 4 neue); `B06DeadlockTests` 12 × 4 und 8 × 6 |
| BUG-08 | mittel | eingebaut, **nicht nachgewiesen** | `PlayerView` (iOS: `defaultFocus`, erneuter Fokus nach dem Übergang und beim Tipp) | keine Tastatur-Automatisierung für den Simulator, siehe 2 |
| BUG-09 | niedrig | behoben | `PlayerView.loadingIndicator`; iOS-Leiste `toolbarBackground`/`toolbarColorScheme` | R `testBUG09_…` (0,589 / 0,618 statt 0,275); iOS-Sonde (Bilder) |

Tests: 11 `XCTExpectFailure`-Blöcke in `Tests/B06` entfernt und auf das behobene Verhalten gestellt (BUG-01: 4, BUG-02: 4, BUG-04: 1,
BUG-06: 2), betroffene Tests umbenannt. Neu: `Tests/B06/B06ReparaturTests.swift` mit 8 Tests. In B08 zwei Tests, die das alte
VLC-Verhalten festschrieben, angepasst (siehe 4). Ergebnis des Gesamtlaufs siehe *Verifikation*.

## 2 · Offene Kriterien und nicht behobene BUGs

- **BUG-03 · libVLC 3.0.21** — nicht behoben, weil Bedingung (b) nicht erfüllbar ist. (a) ist erfüllt: VideoLAN bietet VLCKit 3.7.3
  (libVLC 3.0.23-2, Commit `79128878`) an. Aber nur als CocoaPods-Archiv `download.videolan.org/pub/cocoapods/prod/VLCKit-3.7.3-319ed2c0-79128878.tar.xz`
  bzw. `MobileVLCKit-…tar.xz` (Podspecs im Tag 3.7.3 unter `Packaging/podspecs/`). Kein Tag 3.7.x hat ein `Package.swift`
  (code.videolan.org und GitHub-Spiegel, per API/`raw` geprüft), ein `.zip` gibt es nicht. SwiftPM nimmt das Archiv nicht an –
  ausgeführt mit einem Probe-Paket im Scratchpad: `error: 'spm-probe': unsupported extension for binary target 'VLCKit'; valid
  extensions are: 'artifactbundleindex', 'zip'`. Das einzige offizielle SwiftPM-Paket (`videolan/vlckit`, Zweig `master`,
  `VLCKit-4.0-20260831-1526.zip`) ist VLCKit 4 als Vorabversion mit anderer API, also keine andere Bezugsquelle *derselben*
  Bibliothek. (c) und (d) wurden deshalb nicht mehr geprüft; `project.yml` ist unverändert. Eingebettet bleibt, am gebauten
  Bundle gelesen: macOS `3.0.21-49-g608e9fb467`, iOS `3.0.21-49-gd1840ca85f` (siehe *Verifikation*). Entscheidungen → `spec.md`
  OF-06 (Bezugsquelle: CocoaPods/Carthage, eigenes Neupacken, Einchecken, Warten, VLCKit 4) und OF-07 (Eingrenzung von
  `file://` und Zielen, Produktverhalten).
- **BUG-08 · iPad-Tastatur** — eingebaut, nicht nachgewiesen. Die Reproduktion braucht Hardware-Tastenereignisse im iPad-Simulator;
  die Umgebung hat dafür keine Automatisierung (kein AXe/idb, XcodeBuildMCP ohne UI-Werkzeuge). Die iPad-Sonde lief (Wiedergabe,
  Verlassen, Tabwechsel), Tasten wurden nicht gesendet. Prüfung in QA 2.
- **BUG-07 · libVLC-Hänger** — die Ursache (mehrere nicht gestoppte Player werden gleichzeitig abgebaut, während ein neuer entsteht)
  ist ausgeschlossen und belegt. Der Hänger selbst war schon in QA 1 nicht mehr reproduzierbar; „behoben“ heißt hier nicht, dass ein
  zuvor reproduzierbarer Fehler verschwunden ist. Hängt libVLC trotzdem im Abbau, bleibt der Hauptthread frei: neue VLC-Sender
  warten dann und melden nach 40 s „Der Sender antwortet nicht.“ (die App friert nicht ein, AVKit-Sender spielen weiter).
- **BUG-05** — gehört zur Website-Reparatur (B10 Teil 2).
- **Nicht aus dem Auftrag, festgestellt:**
  - `Tests/B06/B06NachtragTests.swift` (laut QA 1 fünf Tests: FB-05, FB-02 beim Senderwechsel, AK-34, FB-06 beim Tabwechsel,
    BUG-07 im Stapel) liegt **nicht im Repository**. Die Fälle FB-06 beim Tabwechsel und FB-02 beim Senderwechsel decken jetzt
    `testBUG06_…` und `testBUG02_…` ab; AK-34 und FB-05 haben keinen Test.
  - Nach „Zurück“ von HLS hält AVFoundation eine leere Keep-alive-Verbindung ≈ 29 s offen (keine Anfrage, keine Daten), wie B08 H-1;
    aus der App nicht steuerbar.
  - Ein Tabwechsel hält Engine und Verbindung pausiert (AK-27, unverändert): AVKit lädt Live-HLS weiter, VLC hält die Verbindung →
    `spec.md` OF-10.
  - Die Fehleransicht ist unter iOS im hellen Erscheinungsbild kontrastarm (Sonde, Bild `BUILD-IOS-iphone-02-…`) → OF-13; die
    Multiview-Kachel hat weiter den grauen Ladekreis → OF-12 (B08).
  - Die UI-Tests mit Fenster-Aktivierung (B06 AK-21–24, B07) werden übersprungen, wenn der Test-Host nicht aktiv werden kann. Während
    dieses Builds lief parallel ein zweiter Test-Host aus dem Review-Worktree `/private/tmp/claude-501/nacharbeit-b0203`; fremde
    Tastenereignisse (`keyDown`+`keyUp`, die Tests senden nur `keyDown`) erreichten zweimal den Test-Host und lösten den Beep-Wächter
    aus: in der Baseline B06 `testAK23_…` (dort sendet der Test gar keine Taste) und im Teillauf B07 `testAK16_…`. Im Gesamtlauf
    bestanden beide.
  - AK-22 (Hover im Vollbild) bleibt übersprungen (synthetische Mausbewegung erreicht `onContinuousHover` nicht), wie in QA 1.
  - Bild-in-Bild unter iOS nach „Zurück“ (B07 BUG-02) wurde nicht geprüft: Die Engine wird jetzt gehalten, bis Bild-in-Bild endet;
    ob iOS das schwebende Fenster dann weiterlaufen lässt, bleibt für die B07-Reparatur.

## 3 · Getroffene Annahmen

Alle ohne Rückfrage (Zielmodus), zur Bestätigung durch den Nutzer.

1. **Verlassen erkennen:** Der Player gilt als verlassen, wenn er aus dem Navigationsstapel fällt (`@Environment(\.isPresented)`
   wird falsch bzw. ist beim Verschwinden falsch) oder sein Fenster schließt (macOS). Verschwindet er, während er im Stapel bleibt
   (Tabwechsel), wird nur pausiert (AK-27). Belegt auf macOS (Tests) und iOS (Sonde iPhone und iPad).
2. **Fenster schließen = Verlassen** (EC-13, macOS) → OF-11.
3. **Bild-in-Bild beim Verlassen:** Die Engine läuft weiter, bis `isPictureInPictureActive` falsch wird (Fenster geschlossen,
   „Zurück zur App“, System), dann `stop()`. Kein Wiederherstellen des Players, keine Beendigung beim nächsten Sender – das ist B07.
4. **Fristen und Meldungen** (OF-08): 40 s bis zum ersten Bild, 30 s ohne neues Bild bei laufender, nicht pausierter Wiedergabe;
   vier deutsche Meldungen (siehe qa-report BUG-01). Die AVKit-Texte bleiben englisch (OF-01).
5. **„Läuft“** = VLC hat Video- oder Audioblöcke dekodiert oder Bilder angezeigt (`VLCMedia.statistics`). Dekodierte Blöcke
   zählen, damit eine gerade verdeckte Zeichenfläche (Multiview-Kachel) nicht als Hänger gilt. Lokal ≈ 0,3 s nach dem Öffnen statt
   0,05 s (vorher galt schon „buffering“).
6. **Ende eines Datenstroms:** ohne vorheriges Bild → „kein abspielbares Video“; mit Bild → „Verbindung unterbrochen“; Ausnahme ist
   das Ende einer suchbaren Datei (Position ≥ 90 %): Standbild wie das MP4-Ende bei AVKit (EC-04, VOD nicht im Scope).
7. **Pause während des Ladens** (OF-09) bricht bei VLC das Laden ab (Verbindung zu, Zustand `idle`), „Abspielen“ lädt neu.
8. **Je Laden ein frischer VLC-Player**, auch bei „Erneut versuchen“; nach einem Fehler wird der Player abgebaut. Ein neuer Player
   entsteht erst, wenn kein Abbau läuft (bei vier gleichzeitig entfernten Kacheln gemessen: alle vier neuen spielen nach 1,1–1,4 s).
9. **Abbau:** `stop()` (in VLCKit asynchron), höchstens 5 s auf „stopped“ warten, letzte Referenz auf der Queue
   `lu.daumedia.MikaPlusPlayer.vlc-release` abgeben, höchstens 5 s warten, bis der Player frei ist. Eine VLC-Engine, die ohne `stop()`
   freigegeben wird, gibt ihren Player aus `deinit` in denselben Weg.
10. **Vollbild am Mac:** Der Player übernimmt beim Erscheinen den Vollbild-Zustand seines Fensters. Öffnet man ihn in einem schon
    per grünem Knopf vollbildigen Fenster, zeigt er die Vollbild-Darstellung, und „Zurück“ verlässt das Fenster-Vollbild (AK-21).
11. **Ladekreis:** System-`ProgressView` im dunklen Farbschema mit `brightness(1)` – weiß mit der (halbtransparenten) Deckkraft des
    Systemkreises, kein eigener Kreis (die Bedienungshilfe meldet weiter „busy“, worauf mehrere Tests aufbauen).
12. **iOS-Navigationsleiste im Player** schwarz mit hellem Titel, in beiden Erscheinungsbildern.
13. **README-Hinweis** nur in Builds ohne VLCKit, dann weiterhin nach Endung der gespeicherten Adresse.
14. **Test-Stellschraube:** `VLCPlaybackEngine.limitsForNewEngines` (statisch, Standard `.standard`) – nur Tests setzen kürzere Fristen,
    `B06TestCase.tearDown` setzt zurück. Zähler in `VLCPlayerLifecycle` (`completedTeardowns`, `deferredCreations`,
    `maxConcurrentTeardowns`) dienen als Beleg.
15. **Nachweise:** Neue Bilder und Protokolle heißen `BUILD-…` unter `features/B06-wiedergabe/qa/`; die Bilder aus QA 1, die die
    Testläufe überschrieben, sind zurückgesetzt.

## 4 · Systemweite Änderungen

| Datei / Stelle | Feature | Änderung |
|---|---|---|
| `Sources/Services/VLCPlaybackEngine.swift` | B06, **B08** | Zustandslogik neu (Delegate liest synchron, Wächter, Fristen, `Failure`), Player je Laden und erst bei Bedarf erzeugt, `pause()` beim Laden bricht ab, `stop()` gibt den Player ab, `deinit` gibt ab; neue Typen `VLCPlayerLifecycle`, `VLCPlayerBox`. Wirkt auf jede VLC-Kachel im Multiview: Kacheln zeigen jetzt VLC-Fehler (B08 BUG-07, VLC-Teil) und die vom Anbieterlimit abgelehnten Kacheln eine Meldung (B08 BUG-06, Teil „ohne Meldung“); ein Hänger zeigt 40 s die Ladeanzeige statt „spielt“ |
| `Sources/Services/DetachedPlayback.swift` (neu) | B06, **B07** | app-weite Übernahme einer Wiedergabe, deren Player mit aktivem Bild-in-Bild verlassen wird; `stop()` beim Ende von Bild-in-Bild; `stopAll()` |
| `Sources/Views/PlayerView.swift` | B06, **B07** | Verlassen (`isPresented`, Fenster schließen) → `leavePlayer()`; Tabwechsel pausiert; Vollbild am eigenen Fenster; Ladekreis; iOS-Leiste; iPad-Fokus; README-Hinweis. Für B07: Verlassen mit Bild-in-Bild hält die Engine jetzt fest (vorher nur `@State`/schwache Referenz) |
| `Sources/Services/MultiviewSession.swift` | **B08** | `remove(_:)` und `clear()` rufen `stop()` statt `pause()` (Kommentar zur fehlenden Stopp-Methode angepasst) |
| `PlaybackEngine`-Protokoll, `AVKitPlaybackEngine` | alle | **unverändert**; genutzt wird das `stop()` aus der B03-Reparatur (`replaceCurrentItem(with: nil)`) |
| `project.yml`, Paketquelle `tylerjonesio/vlckit-spm` 3.6.0 | alle | **unverändert** (BUG-03 nicht umgestellt) |
| `Info.plist`, Entitlements | alle | unverändert |
| `Tests/B06/*` | Tests | 11 `XCTExpectFailure` entfernt, Assertions auf das Behobene gestellt, Tests umbenannt; `B06Support`: Route `/stall/<s>/tslive/…` (Strom verstummt, Verbindung bleibt), Rücksetzen der VLC-Fristen im `tearDown`; `B06DeadlockTests`: Variante `B06_DEADLOCK_STOP=1` ruft jetzt `stop()` der Engine (Weg wie Verlassen/Multiview); neu `B06ReparaturTests` (8) |
| `Tests/B08/B08SessionTests.swift` | **B08** | `testAK25_AK26_FehlerJeKachel`: wartet bis die TS-Kachel spielt (≈ 0,3 s statt sofort); VLC-Teil von BUG-07 jetzt als erfüllt geprüft (404, Port zu, Abbruch melden sich, Hänger lädt), `XCTExpectFailure` nur noch für den HLS-Teil. `testAK31_…` umbenannt in `…DreiKachelnMeldenAblehnung`: die drei abgelehnten Kacheln melden sich, `XCTExpectFailure` („ohne Meldung“) entfernt – BUG-06 bleibt für die Rücksicht auf das Limit (`testAK30_…`, unverändert) |
| `Tests/B08/B08OberflaecheTests.swift` | **B08** | `testAK25_AK26_AK32_…`: 404-TS-Kachel zeigt die Meldung statt der Ladeanzeige; beim Anbieterlimit drei Meldungen statt drei Ladeanzeigen |
| `Tests/B08/B08Support.swift` | Tests | `B08Engine.isVLC` erkennt die Engine am Typ (nach einem Fehler hat sie keinen Player mehr; vorher hieß sie im Protokoll „AVKit“) |
| `docs/app-shell.md` | Doku | **nicht geändert, jetzt veraltet:** Player-Chrome „Verlassen: pausiert die Wiedergabe“ (jetzt: beendet, außer Bild-in-Bild), „Vollbild macOS … des Schlüsselfensters“ (jetzt: des Player-Fensters; AS-03 erledigt) |
| `docs/design-system.md` | Doku | nicht geändert; „Laden (Video): weiß“ stimmt jetzt; DS-06 (README-Hinweis) erledigt |
| `CLAUDE.md` | Doku | nicht geändert; der Architekturteil nennt `VLCPlayerLifecycle` und `DetachedPlayback` noch nicht (Vorschlag für den Orchestrator) |
| `features/B06-wiedergabe/spec.md` | Doku | nur *Offene Fragen*: OF-06 bis OF-13 |

Nicht angefasst: `features/index.md`, `features/befunde.md`, `appcast.xml`, `web/`, Schlüsselbund, die echte Datenbank.
Vor diesem Build lag bereits `build/dd` (3,5 GB, nicht aus diesem Build) im Projekt – unverändert gelassen.

## Verifikation

Stand 2026-09-27, letzte Läufe nach allen Änderungen. Ausgaben gefiltert; Protokolle vollständig nur im Scratchpad der Session.

**Baseline vor der Reparatur** (`main` `47a90c3`, unveränderter Code) — B06-Tests
`-only-testing:` `B06EngineZustandTests`, `B06SteuerungTests`, `B06PlayerViewTests`:

```
Executed 32 tests, with 3 tests skipped and 2 failures (0 unexpected) in 396.682 (396.706) seconds
** TEST FAILED **
B06PlayerViewTests.swift:57: error: -[… testAK23_ZweiFensterVollbildTrifftSchluesselfenster] : XCTAssertEqual failed: ("["SYSTEMBEEP-UNTERDRUECKT NSWindow keyDown:"]") is not equal to ("[]")
B06PlayerViewTests.swift:557: error: -[… testAK24_GruenerKnopfVerstimmtPlayer] : XCTAssertNotNil failed - erst das zweite F verlässt das Vollbild
```

Reproduziert: 10 der 11 `XCTExpectFailure`-Belege griffen (Z AK-10 6 ×, AK-11 2 ×, AK-12; P AK-10/11 2 ×, AK-13, AK-23 2 ×,
AK-24 2 ×, AK-28 2 ×, AK-29 2 ×; S EC-05 2 ×). Nicht gegriffen hat der nicht strikte Beleg `testAK28b_…`: im Test-Host-Stapel war
die Engine in diesem Lauf schon nach 5 s frei (QA 1: „Lebensdauer schwankt“); nach der Reparatur ist er strikt und die Verbindung
nach 0,1 s zu. Warnungen: 0 in `Sources/`, 21 Stellen in `Tests/` (Deprecations, Sendable), `appintentsmetadataprocessor`.

**1 · Projekt erzeugen** — `xcodegen generate` → exit 0.

**2 · macOS-Gesamtlauf** — `xcodebuild test -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -derivedDataPath build/dd-test -collect-test-diagnostics never`

```
Test Suite 'B06DeadlockTests' passed       Executed 1 test, with 1 test skipped and 0 failures (0 unexpected)
Test Suite 'B06EngineWahlTests' passed     Executed 5 tests, with 0 failures (0 unexpected)
Test Suite 'B06EngineZustandTests' passed  Executed 10 tests, with 2 tests skipped and 0 failures (0 unexpected)
Test Suite 'B06ErkundungTests' passed      Executed 1 test, with 1 test skipped and 0 failures (0 unexpected)
Test Suite 'B06PlayerViewTests' passed     Executed 17 tests, with 0 failures (0 unexpected)
Test Suite 'B06ReparaturTests' passed      Executed 8 tests, with 0 failures (0 unexpected)
Test Suite 'B06SteuerungTests' passed      Executed 5 tests, with 0 failures (0 unexpected)
Test Suite 'B07VerlassenTests' passed      Executed 6 tests, with 0 failures (0 unexpected)
Test Suite 'B07SystemfensterTests' passed  Executed 7 tests, with 5 tests skipped and 0 failures (0 unexpected)
Test Suite 'B08OberflaecheTests' passed    Executed 14 tests, with 1 test skipped and 0 failures (0 unexpected)
Test Suite 'B08SessionTests' passed        Executed 18 tests, with 0 failures (0 unexpected)
Test Suite 'All tests' passed
	 Executed 476 tests, with 27 tests skipped and 0 failures (0 unexpected) in 3008.994 (3009.259) seconds
** TEST SUCCEEDED **
```

B06: 0 erwartete Fehlschläge (QA 1: 11 Blöcke). Gesamt 78 erwartete Fehlschläge in 57 Tests – offene Befunde anderer Features,
darunter B08 `testAK25_AK26_FehlerJeKachel` nur noch mit dem HLS-Teil von BUG-07. Übersprungen (27): die mit Umgebungsvariablen
geschützten Tests (`B06_LANGSAM`, `B06_DEADLOCK`, `B06_ERKUNDUNG`, B08-Absturz- und Neustarttests u. a.), B07-Systemfenster-Tests
ohne aktiven Test-Host bzw. Bild-in-Bild und B06 AK-22 wie in QA 1.

**3 · Saubere Builds und Warnungen** — `xcodebuild clean build-for-testing … -derivedDataPath build/dd-test` und
`xcodebuild clean build -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd-ios`

```
** CLEAN SUCCEEDED **
** TEST BUILD SUCCEEDED **        macOS: 0 Warnungen in Sources/, Test-Warnungen dieselben 21 Stellen wie in der Baseline, keine neue
** CLEAN SUCCEEDED **
** BUILD SUCCEEDED **             iOS: nur „appintentsmetadataprocessor … Metadata extraction skipped, no AppIntents.framework dependency found“
```

Zwei Warnungen, die zwischendurch neu entstanden, sind beseitigt (`weak var released` in `VLCPlaybackEngine.swift`,
`CGWindowListCreateImage` in `B06ReparaturTests.swift`).

**4 · Lange Läufe mit Standardfristen** (`TEST_RUNNER_B06_LANGSAM=1`)

```
B06QA|AK-10|401-ts|nach 60s|zustand=failed(Der Sender konnte nicht geöffnet werden. …)|zeiten=["loading": 0.0, "failed": 0.05…]|anfragen=4   (ebenso 403, 404, Port zu, DNS, Xtream-404)
B06QA|AK-11|haenger-ts|nach 60s|zustand=failed(Der Sender antwortet nicht.)|zeiten=["loading": 0.0, "failed": 39.9996…]|frist=40s
B06QA|AK-11|html-ts|nach 60s|zustand=failed(Der Sender liefert kein abspielbares Video.)|zeiten=["loading": 0.0, "failed": 0.051…]
B06QA|AK-11|verzoegert30-ts|nach 60s|zustand=playing|zeiten=["loading": 0.0, "playing": 30.377…]
B06QA|BUG-01|Hänger ab 4 s|frist=30s|playingNach=0.3s|meldungNach=34.2s|text=Die Verbindung zum Sender wurde unterbrochen.|verbindung=zu(client-closed)
** TEST SUCCEEDED ** (je Lauf)
```

**5 · BUG-07 unter Last** (`TEST_RUNNER_B06_DEADLOCK=1`, Wachhund; je einzeln – der Wachhund aus QA 1 läuft nach dem Test weiter
und beendete in einem gemeinsamen Lauf mit anderen Tests nach 60 s den Prozess: Fehlalarm, Sample verworfen)

```
BUG-07|Start: 12 Runden mit je 4 VLC-Engines …|stop=true|fenster=false
BUG-07|alle 12 Runden ohne Hänger durchgelaufen …|abbauten=48|zurückgestellteErzeugungen=0|höchstensGleichzeitig=1
BUG-07|Start: 8 Runden mit je 6 VLC-Engines …|stop=false|fenster=true
BUG-07|alle 8 Runden ohne Hänger durchgelaufen …|abbauten=48|zurückgestellteErzeugungen=0|höchstensGleichzeitig=1
BUG-07|Durchgang 1..3 (Multiview schließen + sofort vier neue)|clear+add in 0.0s|alle vier spielen nach 1.1–1.4s|abbauten +4|zurückgestellte Erzeugungen +4|höchstens gleichzeitige Abbauten=1|alte Verbindungen offen=0
```

**6 · Mock-Protokoll BUG-02 (macOS, `testBUG02_…`)**

```
BUG-02|QA TS 1|anfragenBisZurück=1|anfragen 1–6 s nach Zurück=0|offeneStröme=0
BUG-02|QA HLS|anfragenBisZurück=5|anfragen 1–6 s nach Zurück=0|offeneStröme=0
BUG-02|QA TS 2|anfragenBisZurück=1|anfragen 1–6 s nach Zurück=0|offeneStröme=0
BUG-02|QA TS 1 erneut|anfragenBisZurück=2|anfragen 1–6 s nach Zurück=0|offeneStröme=0
BUG-02|höchstens gleichzeitig offene Ströme=1|verbindungen=["1:client-closed", "3:client-closed", "4:client-closed"]
```

**7 · iOS zur Laufzeit** — Sonde in einer Kopie im Scratchpad (nur dort eine Einstiegsdatei, aktiv mit `B06_PROBE=1`), eigene
Simulatoren „B06-Build iPhone 17“ und „B06-Build iPad Air 11“ (iOS 27.0, hell), Python-Mock 127.0.0.1, Medien ohne Tonspur.
Protokoll `qa/BUILD-IOS-sonde-protokoll.txt`, Bilder `qa/BUILD-IOS-…`:

```
iPhone  ios1 (TS):  Anfragen ab 1 s nach Zurück=0 | Verbindung zu nach 0.03 s
iPhone  ioshls:     Anfragen ab 1 s nach Zurück=0 | (leere Keep-alive-Verbindung von AVFoundation bis 29 s)
iPhone  ios2 (TS):  Tabwechsel: 0 neue Anfragen, Verbindung bleibt (dieselbe Engine) | nach Zurück zu nach 0.01 s
iPad    ios1/ios2:  Verbindung zu nach 0.39/0.13 s (Wiederholung 0.02/0.02 s), HLS 0 Anfragen, Tabwechsel ohne neuen Aufbau
beide   höchstens gleichzeitig offene TS-Ströme=1
```

Tastatur am iPad (BUG-08) nicht ausgeführt, siehe 2.

**8 · BUG-03-Belege**

```
$ strings -a …/Debug/MikaPlusPlayer.app/Contents/Frameworks/VLCKit.framework/Versions/A/VLCKit | grep -E '^3\.0\.'
3.0.21   3.0.21 Vetinari   3.0.21-49-g608e9fb467
$ strings -a …/Debug-iphonesimulator/MikaPlusPlayer.app/Frameworks/MobileVLCKit.framework/MobileVLCKit | grep -E '^3\.0\.'
3.0.21   3.0.21 Vetinari   3.0.21-49-gd1840ca85f
$ git ls-remote --tags https://code.videolan.org/videolan/VLCKit.git   → 3.7.0 … 3.7.3 (kein Package.swift in 3.7.3: HTTP 404)
$ curl …/pub/cocoapods/prod/   → VLCKit-3.7.3-319ed2c0-79128878.tar.xz, MobileVLCKit-3.7.3-319ed2c0-79128878.tar.xz (kein .zip)
$ swift package dump-package   (Probe-Paket mit binaryTarget auf das .tar.xz)
error: 'spm-probe': unsupported extension for binary target 'VLCKit'; valid extensions are: 'artifactbundleindex', 'zip'
```

**Aufräumen:** eigene Simulatoren gelöscht (`xcrun simctl delete`), Kopie samt Sonden-DerivedData (3,0 GB), Probe-Paket, gelesene
VLCKit-Quelltexte und Testmedien im Scratchpad gelöscht, Mock beendet, keine eigenen Prozesse mehr. `build/dd-release` wurde nicht
angelegt (kein Release-Lauf nötig, da BUG-03 nicht umgestellt). Von den Testläufen überschriebene Nachweise anderer Features
(B02, B03, B04, B07, B08) und die QA-1-Bilder von B06 sind mit `git checkout` zurückgesetzt; neu sind nur `qa/BUILD-…`.
Verbleibend: `build/dd-test`, `build/dd-ios` (erlaubt), `build/dd` (lag schon vorher). Datenbank und Schlüsselbund des Nutzers
wurden weder gelesen noch beschrieben (Test-Host im Speicher, Schlüsselbund nur mit Test-Dienstnamen), alles ohne Ton.

## Review 2026-09-28

Unabhängiges Review des Stands im Commit-Objekt `3aaf142` (Elter `47a90c3`), begonnen am 2026-09-27, nach Verlust des
ersten Worktrees (`/private/tmp` geleert) am 2026-09-28 in einem neuen, getrennten Worktree wiederholt. Geprüft wurde nur der
B06-Stand (nicht die inzwischen im Arbeitsbaum liegende B07-Reparatur). Alle Streams von 127.0.0.1, Medien ohne Tonspur, selbst
erzeugte Engines stumm, keine Systembeeps. Zusätzliche Prüftests (`B06ReviewTests`, R1–R8) lagen nur im Review-Worktree und
sind mit ihm gelöscht. Parallel liefen Test-Hosts zweier anderer Agenten (B07-Reparatur, B02/B03-Nacharbeit); Tests, die
Fensteraktivierung oder Bild-in-Bild-Systemfenster brauchen, wurden deshalb einzeln wiederholt, als keine fremden Bild-in-Bild-Fenster offen waren.

**Urteil: in Ordnung** – keine blockierenden und keine wichtigen Funde. BUG-01, -02, -04, -06, -07 und -09 sind behoben und
nachgewiesen, BUG-03, -05 und -08 sind nachvollziehbar offen. Vier Funde der Schwere „gering“ und drei Hinweise für die
nachfolgenden Schritte.

### Belege je Prüfpunkt

**1 · Reproduktionen aus dem qa-report**

| BUG | Ergebnis | Beleg (Mock-Protokoll) |
|---|---|---|
| BUG-01 | greift nicht mehr | Standardfristen (`B06_LANGSAM=1`): 401/403/404/Port zu/DNS/Xtream-404 → „Der Sender konnte nicht geöffnet werden …“ nach 0,07 s, 60 s stabil, 4 Anfragen je Öffnen; Hänger → „antwortet nicht“ nach 40,2 s; HTML → nach 0,05 s; verzögerter Start (30 s) spielt nach 30,4 s; Hänger mitten im Stream → „Verbindung unterbrochen“ nach 34,2 s, Verbindung zu. Client-seitig per `lsof` (R6c): die TCP-Verbindung verschwindet mit der Meldung (3,4 s), nach „Erneut versuchen“ genau eine Verbindung, spielt nach 0,3 s. |
| BUG-02 | greift nicht mehr | R1, zehnmal Öffnen/„Zurück“ ohne Pause dazwischen (TS und HLS gemischt, Verweildauer 0,1–2 s, viermal während des Ladens): höchstens 1 gleichzeitige TS-Verbindung, 0 Anfragen ab 1 s nach jedem „Zurück“, 0 offene TS-Verbindungen, 0 lebende VLC-Player, 0 `AVPlayer` mit Element, Abbau-Warteschlange leer. Bild-in-Bild (echtes Systemfenster, B07-Helfer): nach „Zurück“ spielt das Fenster weiter; „Schließen“ bzw. „Zurück zur App“ im Systemfenster → Rate 0, **0 Segmente in 20 s bzw. 40 s** (vor der Reparatur liefen 20 Segmente in 40 s unsichtbar weiter). |
| BUG-06 | greift nicht mehr | `testAK23_…PlayerFenster`, `testAK24_…PlayerFolgtFenster`, `testBUG06_…` grün (A geht ins Vollbild, B nicht; grüner Knopf: Symbol „Vollbild verlassen“, 24,5 pt; erstes F verlässt; Tabwechsel im Vollbild: Titel und Symbol richtig). |
| BUG-07 | Ursache ausgeschlossen, wie gemeldet | R3: fünfmal vier VLC-Kacheln schließen und sofort vier neue: alle `libvlc_media_player_destroy` (per Swizzle an `.cxx_destruct` gemessen) laufen nacheinander auf `lu.daumedia.MikaPlusPlayer.vlc-release` (0,02–0,05 s je Player), die vier neuen `VLCMediaPlayer.init` beginnen erst nach dem letzten Abbau, **0 Überschneidungen** Erzeugen/Abbau (auch in R1: 6/6, R2: 11/11). B08 `testBF101_…` (`B08_HAENGER=1`, 16 Runden echtes Multiview-Fenster, Schließen bzw. 4 × X, sofort 4 neue): kein Hänger, alle Player frei und Verbindungen zu nach 0,6–0,7 s. |
| BUG-04, BUG-09 | greifen nicht mehr | `testAK13_…`, `testAK10_AK11_…`, `testBUG09_…` grün. |

**2 · Tests nicht aufgeweicht.** Die 11 entfernten `XCTExpectFailure` (Z: AK-10, AK-11, AK-12; S: EC-05; P: AK-10/11, AK-13,
AK-23, AK-24, AK-28, AK-28b, AK-29) sind alle durch strikte Assertions auf das behobene Verhalten ersetzt; `testAK28b` war vorher
nicht strikt und ist jetzt strikt (Verbindung < 3 s zu). Die B08-Anpassungen sind strenger als vorher: `testAK25_AK26_FehlerJeKachel`
fordert jetzt drei VLC-Meldungen und „lädt“ beim Hänger (`XCTExpectFailure` nur noch für den HLS-Teil), `testAK31_…` fordert
`.failed` mit Meldung für alle drei abgelehnten Kacheln, `B08Engine.isVLC` erkennt am Typ (nötig, weil eine VLC-Engine nach einem
Fehler keinen Player mehr hat). Kein neues Skip in bestehenden Tests (neu nur `XCTSkip` bei nicht aktivierbarem Test-Host im neuen
`testBUG06_…`, wie in den bestehenden Fenstertests). Verkürzt: `testAK10_…` beobachtet im Standardlauf 8 s statt 15 s, prüft dafür
„Meldung < 3 s, nie läuft, keine offene Verbindung“; mit `B06_LANGSAM=1` 60 s (ausgeführt, stabil). `testAK11_…` nutzt im
Standardlauf 5-s-Fristen, die 40-s-Frist nur mit `B06_LANGSAM=1` (ausgeführt: 40,2 s).

**3 · Regressionen.** Multiview (vier VLC-Kacheln in Fenstern, Fokus 1→2→3→0, ein X, Schließen, sofort neu): genau eine Kachel mit
Ton, vier neue spielen nach 0,57 s, alte Verbindungen zu (R2); `B08SessionTests` + `B08OberflaecheTests` 32 Tests grün, 1 übersprungen
wie im Build. Bild-in-Bild: siehe BUG-02; `B07VerlassenTests` (6) und `B07KnopfTests` (11) einzeln grün. Tabwechsel: `testAK27_…`
grün (dieselbe Engine, 1 Anfrage); Tabwechsel während VLC lädt (R6b): Laden abgebrochen, 0 Verbindungen im anderen Tab, zurück spielt
nach 0,3 s, höchstens 1 Verbindung. Wiederholen nach Fehler: siehe BUG-01 (R6c) und `testBUG01_ErneutVersuchen…`. Pause und sofort
Weiter (R4, Abstand 0–400 ms) und Doppeldruck der Leertaste im Player (R5, 30–200 ms): nie eine falsche Fehlermeldung; VLC meldet
„paused“ 2–15 ms nach `pause()`. Verkleinertes bzw. ausgeblendetes Fenster mit 3-s-Hängerfrist (R8): 8 s lang weiter „läuft“, kein
falscher Hänger. iOS: `xcodebuild build … 'generic/platform=iOS Simulator'` → `** BUILD SUCCEEDED **` ohne Warnung; zur Laufzeit
unter iOS nicht erneut geprüft (Sonde des Builds liegt vor).

**4 · Nebenläufigkeit.** Hauptthread-Latenz (Ping alle 5 ms von einem Hintergrund-Thread): „Zurück“ bei spielendem TS 0,000 s
synchron, höchstens 22–34 ms Latenz, Verbindung zu nach 0,04–0,09 s; `MultiviewSession.remove`/`clear` 0,000 s synchron, höchstens
76–79 ms; zehn schnelle Wechsel höchstens 0,11–0,14 s (Navigation eingeschlossen). Deadlock-Lage „Abbau während Erzeugen“: in keinem
Lauf aufgetreten (siehe BUG-07); Restrisiko siehe H-1.

**5 · Sicherheit.** Keine neue Protokollausgabe (`git diff … -- Sources/`: kein `print`/`NSLog`/`os_log`/`Logger`); die vier
VLC-Meldungen sind feste deutsche Sätze ohne Adresse, Host, Benutzer oder Passwort (`testBUG01_Fristen…`, AK-31-Prüfungen in
`testAK10_…`, `testAK10_AK11_…`). Die Fehleransicht enthielt in keinem Lauf `127.0.0.1`, Pfad oder Zugangsdaten.

**6 · BUG-03 (nur gelesen).** Die Begründung trifft zu: `download.videolan.org/pub/cocoapods/prod/` führt VLCKit/MobileVLCKit/TVVLCKit
3.7.0–3.7.3 nur als `.tar.xz`; `Package.swift` fehlt in den Tags 3.7.0 und 3.7.3 und im Zweig `3.0` (HTTP 404), `master` ist VLCKit 4.0
(`cocoapods/unstable/VLCKit-4.0-20260831-1526.zip`); SwiftPM lehnt das Archiv ab (eigene Probe: `unsupported extension for binary
target 'VLCKit'; valid extensions are: 'artifactbundleindex', 'zip'`); libVLC-Commit `79128878` = Tag `3.0.23-2` (3.7.1–3.7.3), `f9020c4d`
= `3.0.22` (3.7.0). Ergänzung siehe R-04.

### Funde

| Nr. | Art | Ort | Beleg | Schwere |
|---|---|---|---|---|
| R-01 | unvollständige Behebung (BUG-02, „die Ansicht gibt die Engine frei“) | `PlayerView` im `NavigationStack` (Halter nicht ermittelt; SwiftUI-Hierarchie des Fensters) | Die Engine des **ersten** im Fenster geöffneten Senders bleibt nach „Zurück“ als Objekt erhalten, alle späteren werden frei. R1: nach 10 Wechseln 1 lebende VLC-Engine `rv1-0.ts` (`idle`, `isPaused`, kein Player, `reloadOnPlay=false`, `session=2` = über `leavePlayer`/`stop()` beendet), unverändert nach 6 s, 21 s und nach einem Tabwechsel; R1b (4 Wechsel) ebenso `rv1b-0.ts`, nach Schließen des Fensters frei. Keine Verbindung, keine Anfrage, kein libVLC-Player – nur das Objekt samt Zeichenfläche. Entspricht der QA-1-Beobachtung „erste TS-Engine lebte bis zum Beenden der App“, jetzt ohne Verbindung. | gering |
| R-02 | sonstiges (Produktverhalten, nur als Annahme 10 dokumentiert) | `PlayerView.attach(to:)`, `leaveFullscreenOnDisappear()` | R7: App-Fenster **vor** dem Öffnen des Senders per grünem Knopf im Vollbild → Player übernimmt Vollbild, nach „Zurück“ verlässt das Fenster das Vollbild (`im Player vollbild=true`, `nach „Zurück“ vollbild=false`); vorher blieb es im Vollbild. Wer die App im Vollbild bedient, fällt bei jedem „Zurück“ bzw. Tabwechsel heraus. Spürbare Folge → gehört als offene Frage in `spec.md` (fehlt unter OF-06–OF-13). | gering |
| R-03 | sonstiges (Folge für B07-Testbelege) | `Tests/B07/B07SystemfensterTests.swift:200` (`orphan`) | Mit dem B07-Helfer ausgeführt (im Build übersprungen, daher im Gesamtlauf unsichtbar): `testAK15d_…` und `testAK15e_…` scheitern mit „Expected failure 'BUG-01 …' but none recorded“, weil `DetachedPlayback` die verwaiste Wiedergabe nach „Schließen“/„Zurück zur App“ jetzt beendet (Rate 0, 0 Segmente). Die B07-Reparatur muss diese Belege auf das neue Verhalten stellen. Unverändert (B07-Umfang): `stopPictureInPicture()` an der verwaisten Engine wirkt nicht, mit dem nächsten Sender laufen zwei Streams 42 s bzw. 60 s (`testAK15a/b`). | gering |
| R-04 | sonstiges (Entscheidungsgrundlage BUG-03 unvollständig) | `spec.md` OF-06, Build-Bericht 2 | Es gibt ein drittes SwiftPM-Paket mit **MobileVLCKit 3.7.3** (libVLC 3.0.23): `github.com/MobileVLCKit-SPM/MobileVLCKit-SPM`, Tags 3.7.1–3.7.3, `binaryTarget` `MobileVLCKit-3.7.3.xcframework.zip`, laut README aus den VideoLAN-CocoaPods-Archiven umgepackt – nur iOS. Für macOS fand sich keins (geprüft: `tylerjonesio/vlckit-spm` bis 3.6.0, `rsalesas/VLCKit` 3.6.x nur iOS/tvOS, `rursache/VLCKitSPM`, `virtualox/vlckit-spm`, `gluttony/vlckit-spm`, `MobileVLCKit-SPM/VLCKit-SPM` je 4.0-Vorab, `omaralbeik/VLC` 3.6.0). Das Ergebnis „für die App nicht umstellbar“ bleibt; OF-06 sollte die Option (iOS über ein Dritt-Paket, wie heute `tylerjonesio` auch eines ist) nennen. | gering |

### Hinweise (kein Fund)

- **H-1 · Restrisiko im geordneten Abbau.** `VLCPlayerLifecycle.tearDown` wartet, bis die schwache Referenz `nil` ist; das ist sie,
  sobald die Freigabe *beginnt*. VLCKit 3.6 hält den Player je Ereignis fest und gibt ihn auf seiner eigenen Queue
  `handler.releaseQueue` frei (`VLCEventsHandler.m`, `handleEvent:`); genau dort lief der Abbau im QA-1-Sample. Hält VLCKit die letzte
  Referenz, liefe `libvlc_media_player_destroy` außerhalb der seriellen Queue, und der nächste Player könnte gleichzeitig entstehen.
  Gemessen in keinem Fall (37 von 37 Abbauten auf `vlc-release`, 0 Überschneidungen); für QA 2 im Blick behalten.
- **H-2 · `DetachedPlayback` und Löschen.** Die übernommene Bild-in-Bild-Engine reagiert nicht auf `PlaylistEvents.willDelete`
  (gelesen; Player und Multiview tun es). Verhalten wie vor der Reparatur, für B07/B03.
- **H-3 · Gesamtlauf unter Parallelbetrieb.** Ein Gesamtlauf am 2026-09-27 (abgebrochen durch das Sitzungsende nach B08) war in
  B06 vollständig grün (47 Tests, 5 übersprungen wie im Build); rot waren B01 `testBUG03_…`, B03 `testAK14_…`, B07 `testAK05/06/07`,
  B07 `testAK10_Mac_…`, B07 `testAK15a_…` – in allen B07-Fällen standen fremde Bild-in-Bild-Fenster im Protokoll. Einzeln wiederholt:
  alle grün (B07 `testAK15a` mit aufgezeichnetem erwarteten Fehlschlag), die übrigen Suiten (B06 47, B08 32, B09 + Basistests 49) grün;
  B06 `testAK01_AK14_…` war einmal rot, als der Test-Host den Fokus verlor, und mit Aktivierungshelfer 3 × grün. Ein sauberer
  Gesamtlauf ohne fremde Test-Hosts war nicht möglich; von B06 geänderte Dateien berühren B01/B03/B09 nicht.

### Ausgeführt (gefiltert)

```
B06 (7 Suiten)            Executed 47 tests, with 4 tests skipped and 1 failure (AK-01/AK-14 Fokusverlust; einzeln 3 × passed)
B06 langsam (3)           testAK10_… passed (61.4 s) · testAK11_… passed (61.0 s) · testBUG01_Haenger… passed (35.8 s)
B06ReviewTests R1–R8      R1 failed (1 lebende Engine, R-01) · R2–R5, R7, R8 passed · R6 failed (Mock liest während /delay/ nicht;
                          client-seitig per lsof R6c passed)
B08 Session+Oberfläche    Executed 32 tests, with 1 test skipped and 0 failures · ** TEST EXECUTE SUCCEEDED **
B08 testBF101 (16 Runden) passed (60.4 s)
B07 Verlassen+Systemfenster (Helfer)  Executed 13 tests, 1 skipped, 1 failure (1 unexpected: testAK15d, R-03)
B07 Knopf + testAK15e     Executed 12 tests, 1 failure (1 unexpected: testAK15e, R-03); B07KnopfTests 11/11 passed
B09 + Basistests          Executed 49 tests, with 0 failures · ** TEST EXECUTE SUCCEEDED **
iOS                       ** BUILD SUCCEEDED ** (0 Warnungen)
```

Aufgeräumt: Review-Worktree samt DerivedData entfernt, eigene Helfer (Bild-in-Bild-Brücke, Aktivierungshelfer) beendet, Probe-Paket
und Protokolle gelöscht; keine Simulatoren angelegt. Datenbank, Schlüsselbund und Nachweise des Arbeitsbaums nicht berührt (Nachweise
der Testläufe landeten nur im Review-Worktree bzw. in dessen Protokollordner).
