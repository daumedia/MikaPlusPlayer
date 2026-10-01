# B08 · Multiview — Build-Bericht

Durchlauf 1 · 2026-09-28 · Eingang: Fehlerauftrag (`qa-report.md` QA 1, BUG-01 bis BUG-10) · Branch `sdd/reparaturen`
auf dem Stand von `main` (`47a90c3`) plus den nicht committeten Reparaturen B02+B03 (mit Nacharbeit), B06 und B07, nicht
committet. Nur macOS (Multiview gibt es auf iOS nicht); iOS wird mitgebaut.

## Ausgangslauf

Erster Gesamtlauf auf dem **kombinierten Stand nach B02+B03, B06 und B07**, vor jeder Änderung dieses Builds – Bezug für
alle folgenden Reparaturen. Bildschirm nicht gesperrt (`CGSSessionScreenIsLocked` nicht gesetzt), Stand `47a90c3` +
Arbeitsbaum (40 geänderte, 2 neue Quelldateien laut `git diff --stat`), `xcodegen generate` → exit 0.

**macOS** — `xcodebuild test -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -derivedDataPath build/dd-test -collect-test-diagnostics never`
(20:59–22:00, ohne Aktivierungshelfer):

```
Test Suite 'B06PlayerViewTests' failed at 2026-09-28 21:41:26.206.
Test Suite 'MikaPlusPlayerTests.xctest' failed at 2026-09-28 22:00:17.969.
	 Executed 493 tests, with 30 tests skipped and 1 failure (0 unexpected) in 3627.194 (3627.475) seconds
** TEST FAILED **
Tests/B06/B06PlayerViewTests.swift:57: error: -[… B06PlayerViewTests testAK21_AK19_EC07_VollbildTastenUndZurueck] : XCTAssertEqual failed: ("["SYSTEMBEEP-UNTERDRUECKT NSWindow keyDown:"]") is not equal to ("[]") - kein unbehandeltes Tastenereignis
```

Alle übrigen 66 Suiten bestanden (462 Tests bestanden, 30 übersprungen, 63 erwartete Fehlschläge offener Befunde). Übersprungen
sind die mit Umgebungsvariablen geschützten Fälle (u. a. `B06_LANGSAM`, `B06_DEADLOCK`, B08-Absturz- und Neustarttests,
`B08_HAENGER`, `B08_TASTEN`), die B07-Systemfenster-Tests ohne Helfer und die Tests, deren Test-Host sich nicht aktivieren
ließ (B08 `testAK14_AK15_AK16_KlicksBeiAktiverApp`). B08 im Ausgangslauf: `B08SessionTests` 18 bestanden (5 erwartete
Fehlschläge: BUG-05 Aktualisieren, BUG-06, BUG-07 HLS, BUG-08, BUG-09), `B08OberflaecheTests` 13 bestanden, 1 übersprungen
(6 erwartete Fehlschläge: BUG-01, -02, -03, -04, -10), `B08NachtragTests` 2 bestanden, 2 übersprungen, `B08AbsturzTests`
8 übersprungen (opt-in), `B08HauptfensterTests` 1 bestanden. Warnungen: keine in `Sources/`; in `Tests/` 60 Stellen (49 verschiedene Meldungen)
in 18 Dateien (Veraltungshinweise, Sendable; 28 Meldungen in `B07Support.swift`), in `Tests/B08/` nur
`B08Support.swift:845` (`CGWindowListCreateImage` veraltet).

**Fehlschlag einzeln wiederholt:**

| Test | Ausgang im Gesamtlauf | Einzeln | Einordnung |
|---|---|---|---|
| B06 `testAK21_AK19_EC07_VollbildTastenUndZurueck` | rot: ein Tastenereignis erreichte unbehandelt das Ende der Responder-Kette (Beep-Wächter fing den Warnton ab) | 1. Wiederholung ohne Helfer: übersprungen (Test-Host nicht aktivierbar); 2. Wiederholung mit Aktivierungshelfer: **bestanden** (7,5 s) | hängt an Aktivierung und Tastaturfokus des Test-Hosts (wie B06-Bericht, Review H-3); B08-Dateien waren noch unverändert – kein Befund dieses Builds |

Mit dem Aktivierungshelfer (siehe *Verifikation*) lief auch B08 `testAK14_AK15_AK16_KlicksBeiAktiverApp` und bestand mit den
erwarteten Fehlschlägen BUG-02 (Schwarzanteil 1,00) und BUG-04 (3 Streams nach dem Klick aufs große X).

**iOS** — `xcodebuild build -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd-ios`

```
** BUILD SUCCEEDED **
appintentsmetadataprocessor … warning: Metadata extraction skipped, no AppIntents.framework dependency found
```

**Ergebnis:** Der kombinierte Stand ist grün bis auf **einen** Fehlschlag: B06 `testAK21_AK19_EC07_VollbildTastenUndZurueck`
(umgebungsbedingt, einzeln grün). Er tritt nach der Reparatur nicht mehr auf – in der Schlussverifikation bestand er im
Gesamtlauf (6,5 s, siehe *Verifikation*). Die Nachweise, die der Lauf überschrieb (127 getrackte Dateien in
`features/*/qa/`), sind per `git checkout` zurückgesetzt; zu den ungetrackten `BUILD-…`-Bildern von B06/B07 siehe
*Verifikation*, Aufräumen.

## 1 · Umgesetzt

Das Multiview stürzt nicht mehr ab: Raster und Fokus-Layout sind eine gemeinsame, an die Slots gebundene Anordnung
(`ForEach(session.slots)`, Identität `Slot.id`, eigene `Layout`-Implementierung `MultiviewArrangement`). Schließen des
Fensters und Entfernen per X gehen im Raster bei jeder Anzahl, auch im Release-Build; mit einem Stream im Raster führt der
Umschalter zurück zu „Fokus“. Weil jede Kachel dieselbe Ansicht bleibt und die VLC-Zeichenfläche zusätzlich in einem eigenen
Behälter eingehängt wird, zeigt das große Bild nach einem Fokuswechsel den angeklickten VLC-Stream, und im Raster zeigen die
nachrückenden Kacheln ihr eigenes Bild. Die kleinen Kacheln beginnen unterhalb der Leiste des großen Streams, dessen X ist
erreichbar. Ein Klick auf den abgeblendeten ⊞ bewirkt nichts mehr. Kacheln, die der Anbieter ablehnt, während ein anderer
Stream desselben Anbieters läuft, erklären das mögliche Verbindungslimit auf Deutsch. HLS-Kacheln, deren Segmente
ausbleiben, melden sich nach 30 s ohne Fortschritt, statt endlos ein Standbild zu zeigen. Das Fenster hat eine Mindestgröße,
in die alle Kacheln passen.

| BUG | Grad | Ergebnis | Wo | Nachweis |
|---|---|---|---|---|
| BUG-01 | kritisch | behoben (Debug und Release) | `MultiviewScreen` (`MultiviewArrangement`, Umschalter) | A `testAK23_…` 4 Fälle + 3 Gegenproben (jetzt im Gesamtlauf), R `testBUG01_…` (2), O `testAK11_AK12_AK13_…` |
| BUG-02 | hoch | behoben | `MultiviewScreen` (Identität je Slot), `VLCPlaybackEngine` (`VLCPlayerSurface`, neu `VLCSurfaceHostView`) | O `testAK14_AK15_…`, N `testAK14_AK15_AK16_…` (echter Klick), N `testCR_…`, R `testBUG02_…` |
| BUG-04 | hoch | behoben | `MultiviewArrangement`/`MultiviewMetrics` (kleine Kacheln 46 pt statt 16 pt vom oberen Rand), `MultiviewTile` (X fest 30 × 30 pt) | O `testAK16_…Erreichbar`, O `testAK10_…`, N (echter Klick), R `testBUG04_…` |
| BUG-07 | hoch | behoben: VLC-Teil durch B06 (im Ausgangslauf grün), HLS-Teil hier | `AVKitPlaybackEngine.limitStalls(to:)`, `MultiviewSession.add` | S `testAK25_AK26_…`, R `testBUG07_…` (Standardfrist 30 s) |
| BUG-03 | mittel | behoben | `ChannelRowView.multiviewButton` | O `testAK04_AK05_…KlickAufGrauBewirktNichts`, R `testBUG03_…` (Favoriten-Tab) |
| BUG-05 | mittel | Teil Löschen durch B02+B03 behoben (geprüft); Teil Aktualisieren **nicht behoben** | — (`PlaylistEvents` aus B03) | S `testAK27_…` grün; S `testAK28_…` behält `XCTExpectFailure` |
| BUG-06 | mittel | Teil Meldung behoben; Rücksicht auf das Limit **nicht behoben** | `MultiviewTile` (Hinweis), `MultiviewSession` (`Slot.provider`, `otherStreamIsPlaying`) | R `testBUG06_…`, O AK-31-Teil; S `testAK30_…` behält `XCTExpectFailure` |
| BUG-08 | niedrig | **nicht behoben** (wartet auf OF-01) | — | `XCTExpectFailure` bleibt |
| BUG-09 | niedrig | **nicht behoben** (wartet auf OF-02) | — | `XCTExpectFailure` bleibt |
| BUG-10 | niedrig | behoben | `MultiviewScreen.minimumContentSize` (640 × 483 pt) | O `testEC10_EC11_…`, R `testBUG10_…` |

Tests: 9 `XCTExpectFailure`-Blöcke in `Tests/B08` entfernt und auf das behobene Verhalten gestellt (O: BUG-01, -02, -03,
-04, -10; N: BUG-02 zweimal, BUG-04; S: BUG-07 HLS), dabei die „Ist“-Assertions, die den Fehler festschrieben, ersetzt;
fünf Tests umbenannt (Name beschrieb den Fehler). Die sieben Absturz- und Gegenprobefälle in `B08AbsturzTests` laufen jetzt
im Gesamtlauf (vorher nur mit `TEST_RUNNER_B08_ABSTURZ`); EC-15 (beendet die App absichtlich) bleibt opt-in. Neu:
`Tests/B08/B08ReparaturTests.swift` mit 8 Tests. Es bleiben 6 `XCTExpectFailure` (BUG-05 Aktualisieren, BUG-06 Limit,
BUG-08 zweimal, BUG-09 zweimal). Kürzel: S `B08SessionTests`, O `B08OberflaecheTests`, N `B08NachtragTests`,
A `B08AbsturzTests`, R `B08ReparaturTests`.

## 2 · Offene Kriterien und nicht behobene BUGs

- **BUG-05, Teil Aktualisieren** (AK-28) — nicht behoben: Ob laufende Kacheln beim Aktualisieren auf die neue Adresse
  umschalten, enden oder bleiben, ist Produktverhalten mit spürbarer Folge und in B03 OF-09 für Player und Multiview gemeinsam
  offen; die zweite Kachel desselben Senders hängt zusätzlich an OF-01 (spec OF-14). Belegt: `testAK28_…` hält weiter
  `/live/…/101.ts` und `/live/…/201.ts` offen (erwarteter Fehlschlag). Teil Löschen (AK-27) ist durch die B02+B03-Reparatur
  erledigt – im Ausgangslauf und danach grün.
- **BUG-06, Rücksicht auf das Anbieterlimit** (AK-30) — nicht behoben: `max_connections` auswerten, die Zahl der Kacheln
  begrenzen oder vorab warnen ist eine Produktentscheidung (spec OF-03, mit Stand vom 2026-09-28 ergänzt). Belegt:
  `testAK30_…` öffnet weiter vier Verbindungen bei `max_connections=1` (erwarteter Fehlschlag). Der Hinweis erscheint nur,
  wenn ein anderer Stream **desselben Anbieters** im Multiview läuft; belegt der Player im Hauptfenster die Verbindung, zeigt
  die Kachel nur die Meldung der Engine (die Kachel kennt den Player nicht).
- **BUG-08** (wartet auf OF-01) und **BUG-09** (wartet auf OF-02 = B01 OF-11) — Produktentscheidungen, nicht gebaut; ihre
  `XCTExpectFailure` bleiben und schlagen weiter erwartungsgemäß fehl.
- **Nicht aus dem Auftrag, festgestellt:**
  - Kacheln zeigen weiter den grauen System-Ladekreis (B06 OF-12) → spec OF-13, nicht geändert.
  - Der Player (B06) zeigt bei Live-HLS mit ausbleibenden Segmenten weiter endlos ein Standbild – die neue Frist gilt nur
    für Kacheln (spec OF-11).
  - Der ⊞ ist bei vollem Multiview für Bedienungshilfen nicht mehr „deaktiviert“ (spec OF-12).
  - UI-Tests, die einen aktiven Test-Host brauchen (N `testAK14_AK15_AK16_…`, B06 AK-21 u. a.), werden ohne Aktivierungshelfer
    übersprungen; im Ausgangslauf war das der Fall. In diesem Build liefen sie mit Helfer (siehe *Verifikation*).
  - `docs/app-shell.md` („Im Raster-Layout stürzt die App dabei ab …“, Multiview-Fenster ohne Mindestgröße) und
    `docs/design-system.md` (Kachelstapel „16“ pt, `.disabled` am Multiview-Button) sind **nicht geändert und jetzt veraltet**.
  - Die Rekonstruktion in `spec.md` (AK-05, AK-10, AK-12, AK-13, AK-15, AK-16, AK-23, AK-26) und `design.md` beschreibt
    weiter das Ist vor der Reparatur; Nachführen ist Sache von QA-Durchlauf 2.

## 3 · Getroffene Annahmen

Alle ohne Rückfrage (Zielmodus), zur Bestätigung durch den Nutzer; die mit spürbarer Folge stehen als offene Fragen in
`spec.md` (OF-08 bis OF-14).

1. **Eine Anordnung für beide Layouts** (BUG-01/02): Die Kacheln bleiben in beiden Layouts dieselben Ansichten; nur Lage,
   Größe, Beschnitt (runde Ecken bei kleinen Kacheln), Schatten und Zeichenreihenfolge (`zIndex`, kleine über der großen)
   wechseln – über gleichbleibende Modifier mit wechselnden Werten, damit SwiftUI die Kachel nicht neu anlegt. Die große
   Kachel bleibt unbeschnitten, ihre Videofläche reicht wie bisher unter die Titelleiste.
2. **Umschalter mit weniger als zwei Streams** (BUG-01, OF-09): aktiv, wenn „Raster“ gewählt ist; gesperrt wie bisher, wenn
   „Fokus“ gewählt ist. Das Layout bleibt beim Entfernen und Schließen erhalten (AK-12 unverändert).
3. **Lage der kleinen Kacheln** (BUG-04, OF-08): 46 pt vom oberen Inhaltsrand (8 + 30 + 8), 16 pt vom rechten Rand, 8 pt
   Abstand; das X jeder Kachel hat eine feste Größe von 30 × 30 pt (vorher Symbol + 6 pt Innenabstand, gemessen ebenfalls
   30 × 30).
4. **Mindestgröße** (BUG-10, OF-10): Inhalt 640 × 483 pt, berechnet aus den Maßen der kleinen Kacheln (46 + 3 × 135 +
   2 × 8 + 16); gilt auch für das leere Fenster. Testfenster, die `MultiviewScreen` kleiner einbetten (B03, B07), wachsen auf
   diese Höhe.
5. **⊞ bei vollem Multiview** (BUG-03, OF-12): abgeblendet (30 % Deckkraft, wie in AK-04 beschrieben), aber nicht
   deaktiviert; der Klick bewirkt nichts und öffnet auch das Fenster nicht. Der Tooltip bleibt.
6. **Hinweis auf das Verbindungslimit** (BUG-06): Text „Möglicherweise erlaubt dein Abo nicht so viele Streams gleichzeitig.“
   unter der Meldung einer gescheiterten Kachel, nur solange ein anderer Stream desselben Anbieters (Host und Port der
   abspielbaren Adresse, ohne Pfad und Zugangsdaten, nur im Arbeitsspeicher) spielt. HTTP 403 und 404 lassen sich bei VLC
   nicht unterscheiden (beide „kann nicht geöffnet werden“); deshalb „möglicherweise“.
7. **Frist für hängende AVKit-Kacheln** (BUG-07, OF-11): 30 s ohne Fortschritt der Wiedergabezeit, nur im Zustand „spielt“,
   nicht bei Pause oder am Dateiende; danach Meldung „Die Verbindung zum Sender wurde unterbrochen.“ (wie VLC), Element frei,
   kein Nachladen. Gesetzt von `MultiviewSession` für jede AVKit-Kachel (`MultiviewSession.stallLimitForNewTiles`, nur Tests
   setzen kürzere Werte); der Player behält das Verhalten von AVKit. Gemessen vor der Entscheidung: AVKit gab bei Segment-404
   in 120 s nie auf.
8. **VLC-Zeichenfläche** (BUG-02): Der Behälter `VLCSurfaceHostView` (nur macOS) führt je Zeichenfläche eine schwache Liste
   seiner Behälter; die jüngste Einbettung übernimmt die Fläche, beim Abbau geht sie an eine andere im Fenster. Unter iOS
   (keine Kacheln) ist `VLCPlayerSurface` unverändert.
9. **Tests**: Nachweisbilder dieses Builds heißen `BUILD-…` unter `features/B08-multiview/qa/`; die Bilder und Protokolle der
   QA, die die Testläufe überschrieben, sind zurückgesetzt. Die Absturzfälle laufen im Gesamtlauf; ein Rückfall beendet den
   Test-Host und fällt dadurch auf.

## 4 · Systemweite Änderungen

| Datei / Stelle | Feature | Änderung |
|---|---|---|
| `Sources/Services/VLCPlaybackEngine.swift` (macOS-Teil) | **B06**, B08 | `VLCPlayerSurface` gibt nicht mehr die Zeichenfläche selbst zurück, sondern einen Behälter `VLCSurfaceHostView` (neu), in den die Fläche mit Autoresizing eingehängt wird; `updateNSView` und `viewDidMoveToWindow` hängen sie wieder ein, `dismantleNSView` gibt sie weiter. **Wirkt auf den Player (B06)** bei jedem VLC-Sender; die B06-Suiten (Bild, Vollbild, Verlassen) liefen danach grün (siehe *Verifikation*). iOS-Teil unverändert |
| `Sources/Services/AVKitPlaybackEngine.swift` | **B06**, B07, B08 | neu `limitStalls(to:)` und `interruptedMessage`, Wächter in `load`/`stop`/`deinit`. Ohne Aufruf (Player, Bild-in-Bild) ohne Wirkung: kein Wächter-`Task`, keine neue Meldung |
| `Sources/Services/MultiviewSession.swift` | B08 | `Slot.provider`, `otherStreamIsPlaying(onProviderOf:)`, `stallLimitForNewTiles`; `add` setzt die Frist für AVKit-Kacheln (Typprüfung auf `AVKitPlaybackEngine` in der Session, nicht in einer View) |
| `Sources/Views/ChannelRowView.swift` | B04, B05, B08 | ⊞ ohne `.disabled`, Aktion prüft `canAddMore` – gilt in Senderliste und Favoriten-Tab |
| `Sources/Views/MultiviewScreen.swift`, `MultiviewTile.swift` | B08 | neue Typen `MultiviewArrangement` (`Layout`), `MultiviewMetrics`, `TileClip`; Mindestgröße; Hinweistext |
| Tests anderer Features | B03, B07 | unverändert; ihre Multiview-Testfenster (640 × 400 bzw. 900 × 520) unterliegen jetzt der Mindesthöhe |
| `Tests/B08/*` | Tests | 9 `XCTExpectFailure` entfernt, 5 Tests umbenannt, `B08AbsturzTests` im Gesamtlauf, neu `B08ReparaturTests` (8); `B08Support`, `B08UITestCase` unverändert |
| `docs/app-shell.md`, `docs/design-system.md` | Doku | **nicht geändert, jetzt veraltet** (Absturz im Raster, Mindestgröße, Kachelabstand 16 pt, `.disabled` am ⊞) |
| `CLAUDE.md` | Doku | nicht geändert; nennt `VLCSurfaceHostView` und die Kachelfrist nicht (Vorschlag für den Orchestrator) |
| `features/B08-multiview/spec.md` | Doku | nur *Offene Fragen*: OF-03 ergänzt, OF-08 bis OF-14 neu |
| `project.yml`, `Info.plist`, Entitlements, Abhängigkeiten | alle | **unverändert** |
| `Sources/App/MikaPlusPlayerApp.swift` | alle | von diesem Build **nicht** geändert (der Diff im Arbeitsbaum stammt aus B03/B09: Dokument-Handler, „Alle Daten entfernen …“, Start-Wartung); die Multiview-Szene mit `.windowResizability(.contentMinSize)` ist unverändert, die Mindestgröße kommt aus `MultiviewScreen` |

Nicht angefasst: `features/index.md`, `features/befunde.md`, `appcast.xml`, `web/`, Schlüsselbund, die echte Datenbank.

## Verifikation

Stand 2026-09-29, Schlussläufe nach allen Änderungen. Alle Streams von 127.0.0.1, Medien ohne Tonspur (`ffmpeg -an`), jede
Engine sofort auf Lautstärke 0, keine Tasten (AK-29, `B08_TASTEN`, nicht ausgeführt), kein Systembeep. UI-Tests, die einen
aktiven Test-Host brauchen, liefen mit einem Aktivierungshelfer außerhalb des Test-Hosts (setzt per Bedienungshilfen
`AXFrontmost` für die PID aus `TEST_RUNNER_B06_ACTIVATE_REQ` bzw. `TEST_RUNNER_B08_AKTIVIEREN`; danach beendet).

**0 · Vor der Reparatur reproduziert** (28.09., Stand des Ausgangslaufs, `test-without-building`, je Fall eigener Prozess)

```
TEST_RUNNER_B08_ABSTURZ=schliessen-raster-4  → Swift/ContiguousArrayBuffer.swift:695: Fatal error: Index out of range · ** TEST EXECUTE FAILED **
TEST_RUNNER_B08_ABSTURZ=schliessen-raster-1  → Fatal error: Index out of range · ** TEST EXECUTE FAILED **
TEST_RUNNER_B08_ABSTURZ=x-3auf2              → Fatal error: Index out of range · ** TEST EXECUTE FAILED **
TEST_RUNNER_B08_ABSTURZ=x-1auf0              → Fatal error: Index out of range · ** TEST EXECUTE FAILED **
Absturzbericht MikaPlusPlayer-2026-09-28-220252.ips: EXC_BREAKPOINT (SIGTRAP) · Array.subscript.getter
  ← closure … in MultiviewScreen.gridLayout.getter MultiviewScreen.swift:79 ← ForEachChild.updateValue()
N testAK14_AK15_AK16_KlicksBeiAktiverApp (mit Helfer): Expected failure BUG-04 ("3" ≠ "2") · Expected failure BUG-02 (Schwarzanteil 1,0)
B08ErkundungTemp (Messung, danach gelöscht): Live-HLS, Segmente ab 6 s 404 → 120 s lang state=playing,
  timeControlStatus=waiting(AVPlayerWaitingToMinimizeStallsReason), Wiedergabezeit steht bei 15,9 s, 57 × 404
```

BUG-03, BUG-10 und die übrigen Teile von BUG-02/-04 griffen im Ausgangslauf als erwartete Fehlschläge der QA-Tests.

**1 · Projekt erzeugen** — `xcodegen generate` → exit 0.

**2 · macOS-Gesamtlauf** — `xcodebuild test -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -derivedDataPath build/dd-test -collect-test-diagnostics never`
(29.09., 18:11–19:05, mit Aktivierungshelfer)

```
Test Suite 'B04LogoTests' failed at 2026-09-29 18:34:57.230.
Test Suite 'MikaPlusPlayerTests.xctest' failed at 2026-09-29 19:05:08.431.
	 Executed 501 tests, with 21 tests skipped and 1 failure (0 unexpected) in 3224.530 (3224.814) seconds
** TEST FAILED **
Tests/B04/B04LogoTests.swift:407: error: -[… B04LogoTests testEC07_WegscrollenUndZurueckscrollenWaehrendDesLadens] : XCTAssertGreaterThan failed: ("0") is not greater than ("400") - das Logo der obersten Karte ist nach dem Zurückscrollen da
Test Case '-[… B06PlayerViewTests testAK21_AK19_EC07_VollbildTastenUndZurueck]' passed (6.514 seconds).      ← Fehlschlag des Ausgangslaufs, jetzt grün
Test Suite 'B08AbsturzTests'     passed   7 bestanden, 1 übersprungen (EC-15, opt-in)
Test Suite 'B08HauptfensterTests' passed  1 bestanden
Test Suite 'B08NachtragTests'    passed   3 bestanden, 1 übersprungen (BF-101, opt-in) · erwartet: BUG-08, BUG-09
Test Suite 'B08NeustartTests'    passed   1 übersprungen (zwei Prozesse, opt-in)
Test Suite 'B08OberflaecheTests' passed  13 bestanden, 1 übersprungen (AK-29, opt-in) · 0 erwartete Fehlschläge (Ausgangslauf 6)
Test Suite 'B08ReparaturTests'   passed   8 bestanden
Test Suite 'B08SessionTests'     passed  18 bestanden · erwartet: BUG-05 Aktualisieren, BUG-06 Limit, BUG-08, BUG-09
```

**Fehlschlag einzeln wiederholt:**

| Test | Gesamtlauf | Einzeln | Einordnung |
|---|---|---|---|
| B04 `testEC07_WegscrollenUndZurueckscrollenWaehrendDesLadens` | rot: Logo der obersten Karte nach dem Zurückscrollen nicht gezeichnet (`logopunkte0=0`) | 2 × **bestanden** (`logopunkte0=6400`, je 29,9 s) | im Ausgangslauf grün; prüft das Nachladen eines `AsyncImage`-Logos, das dieser Build nicht berührt (in `ChannelRowView` nur der ⊞: `.disabled` entfernt, Aktion mit Prüfung). Zeitabhängig, kein Befund dieses Builds – für QA 2 im Blick behalten |

Gegenüber dem Ausgangslauf: 501 statt 493 Tests (+8 `B08ReparaturTests`), 21 statt 30 übersprungen (die sieben
Absturz-/Gegenprobefälle laufen jetzt mit, N `testAK14_AK15_AK16_…` und B06 AK-21 mit Helfer), erwartete Fehlschläge in B08
6 statt 14.

**3 · Release (`-O`), alle BUG-01-Wege** — `xcodebuild build-for-testing … -configuration Release -derivedDataPath build/dd-release ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES`,
dann `test-without-building` mit `-only-testing:` `B08AbsturzTests`, `B08ReparaturTests/testBUG01_…` (2), `…/testBUG02_…`,
`…/testBUG04_…`, `B08OberflaecheTests/testAK11_AK12_AK13_…`. Die drei Einstellungen nur, weil der Test-Runner sich mit der
ausgelieferten Release-Signatur (Hardened Runtime, ohne `get-task-allow`) nicht an den Test-Host hängen kann (28.09.
ausgeführt: „The test runner hung before establishing connection.“); Optimierung unverändert (`swiftc … -O`, Grenzprüfung
aktiv wie in QA 1).

```
** TEST BUILD SUCCEEDED **
AK-23|FALL … |Konfiguration Release   (7 ×)
	 Executed 13 tests, with 1 test skipped and 0 failures (0 unexpected) in 104.146 (104.162) seconds
** TEST EXECUTE SUCCEEDED **
TEST_RUNNER_B08_ABSTURZ=beenden-raster (EC-15, Release): Prozess endet über NSApp.terminate („Restarting after unexpected exit“, gewollt),
  Absturzberichte MikaPlusPlayer vorher 28, nachher 28
```

Alle vier Absturzfälle (Raster + Schließen mit 4 und mit 1, X 3 → 2, X 1 → 0), die drei Gegenproben, `clear()` im Raster mit
1–4 Streams und Entfernen von vorn/hinten/Mitte bis 0 bestehen in Release. `build/dd-release` (3,3 GB) ist danach gelöscht.

**4 · iOS** — `xcodebuild clean build -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd-ios`

```
** CLEAN SUCCEEDED **
** BUILD SUCCEEDED **
appintentsmetadataprocessor … warning: Metadata extraction skipped, no AppIntents.framework dependency found   ← wie Ausgangslauf
```

**5 · Warnungen** — `xcodebuild clean build-for-testing … -derivedDataPath build/dd-test` → `** CLEAN SUCCEEDED **`,
`** TEST BUILD SUCCEEDED **`: **0 Warnungen in `Sources/`**; in `Tests/` dieselben Dateien wie im Ausgangslauf, in
`Tests/B08/` nur `B08Support.swift:845` (`CGWindowListCreateImage` veraltet, schon im Ausgangslauf); `B08ReparaturTests`
ohne Warnung. Keine neue Warnung.

**6 · Zusätzliche Läufe gegen einen libVLC-Hänger** (29.09., wegen des abgebrochenen Laufs, siehe unten)

```
B06EngineZustandTests (einzeln)                            Executed 10 tests, 2 skipped, 0 failures · jeder tearDown „VLC-Player abgebaut nach 0.0–0.3s, noch offen=0“
TEST_RUNNER_B06_DEADLOCK=1 _STOP=1                         alle 12 Runden ohne Hänger … abbauten=48 | höchstensGleichzeitig=1
TEST_RUNNER_B06_DEADLOCK=1 _FENSTER=1 (VLC-Flächen in Fenstern)  alle 12 Runden ohne Hänger … abbauten=48 | höchstensGleichzeitig=1
TEST_RUNNER_B08_HAENGER=1 (echtes Multiview, 16 Runden)    alle 16 Runden ohne Hänger … alle frei + Verbindungen zu nach 0.6–0.7 s
```

**Abgebrochener erster Verifikationslauf (28.09., 22:31–23:35).** Der erste Gesamtlauf nach der Reparatur endete durch das
Herunterfahren des Rechners um 23:35 mitten in `B08ReparaturTests`. Bis dahin: 27 Fehlschläge. Ursache war ein einziger
libVLC-Abbau, der hing: Nach B06 `testAK09_…VLCSpieltAlleEndungen` waren 5 von 6 VLC-Playern nach 15,2 s nicht abgebaut
(`tearDown|… noch offen=5`); danach entstand in diesem Prozess kein VLC-Player mehr (`anfragen=0`), und alle folgenden
VLC-Tests (B06 EngineZustand 4, PlayerView 4, B07, B08) scheiterten in Folge. Dazu B01 `testBUG03_AlterHTTPCache…`
(`URLCache`-Zeitverhalten), einzeln grün. Dieselbe Stelle (Übergang AK-09 → AK-10) nennt der B06-Bericht aus QA 1 als Ort
des libVLC-Hängers (BF-101) und als Restrisiko (Review H-1). Im Schlusslauf und in den Läufen unter 6 trat der Hänger nicht
auf. **Nicht ausgeschlossen** ist, dass der neue Behälter der VLC-Zeichenfläche (`VLCSurfaceHostView`) die Wahrscheinlichkeit
verändert – belegt ist nur, dass er in 12 + 12 + 16 Runden und zwei vollständigen Läufen der betroffenen Suiten nicht auftrat.
Für QA 2: BF-101 im Gesamtlauf im Blick behalten.

**Aufräumen und Vorkommnisse**

- **Reguläre App-Instanz nach dem Neustart:** Beim Wiederanmelden am 29.09. um 17:06 hat macOS (Fenster wiederherstellen) den
  Test-Host des abgebrochenen Laufs (`build/dd-test/…/Debug/MikaPlusPlayer.app`) **regulär** neu gestartet, also ohne
  Test-Umgebung und mit dem echten Datenbankpfad des Nutzers. Er lief bis 18:06 und ist dann per `SIGTERM` beendet. Die
  Datenbank, der Cache und die Einstellungen des Nutzers wurden von mir weder gelesen noch geprüft; ob die Instanz dort beim
  Start etwas angelegt oder umgestellt hat (`AppPersistence`), ist offen – **Hinweis an den Orchestrator/Nutzer**.
- **Ungetrackte Nachweise von B06/B07:** Der abgebrochene Lauf vom 28.09. hat elf `BUILD-…`-Bilder von B06 und B07 mit
  gleichwertigen Aufnahmen derselben Tests neu geschrieben (B06: `BUILD-BUG-01-…` 2, `BUILD-BUG-04-…`, `BUILD-BUG-06-…` 2,
  `BUILD-BUG-09-…` 2; B07: `BUILD-BUG-01-…` 2, `BUILD-BUG-04-…` 2). Die Sicherung der Originale lag im Scratchpad unter
  `/private/tmp` und ging mit dem Neustart verloren; seit dem 29.09. sind diese Bilder vor jedem Lauf gesichert und danach
  wiederhergestellt. Die `BUILD-IOS-…`-Dateien sind unberührt.
- Getrackte Nachweise aller Features (zuletzt 123 Dateien in `features/*/qa/`), die die Läufe überschrieben, sind per
  `git checkout` zurückgesetzt; neue ungetrackte Dateien anderer Features entfernt. Eigene Nachweise: 13 × `BUILD-…` unter
  `features/B08-multiview/qa/` (aus dem Schlusslauf).
- Beendet: Aktivierungshelfer, alle Test-Hosts; keine Mock-Server- oder ffmpeg-Prozesse offen (die Mocks laufen im Test-Host).
  Keine Simulatoren angelegt, keine Datenträgerabbilder, keine Kopien oder Worktrees. `build/dd-release` gelöscht; es
  bleiben `build/dd-test`, `build/dd-ios` und `build/dd` (lag schon vor B06 im Projekt, unverändert).
- Temporäre Messdatei `Tests/B08/B08ErkundungTemp.swift` nach der Messung gelöscht; Aktivierungshelfer und Sicherungskopien
  gelöscht. Die ungefilterten Protokolle der Schlussläufe liegen außerhalb des Repositorys unter
  `~/.claude/projects/…/e8de96ed-…/b08work/logs/` (nur Textprotokolle, erfundene Zugangsdaten).
- Schlüsselbund nur mit Test-Dienstnamen (die Tests löschen ihre Einträge), die echte Datenbank nie gelesen.

## Review 2026-09-29

Unabhängiges Review der Reparatur. Geprüfter Stand: Commit-Objekt `bb7ccd5` (B06-Stand `3aaf142` + B07 + B02/B03-Nacharbeit
+ B08), eigener Worktree mit eigener DerivedData, danach entfernt. Gelesen: `git diff 3aaf142 bb7ccd5` für `MultiviewScreen`,
`MultiviewTile`, `MultiviewSession`, `ChannelRowView`, `VLCPlaybackEngine`, `AVKitPlaybackEngine`, `Tests/B08`; `qa-report.md` mit
den „Behoben“-Vermerken; dieser Bericht. Alle Streams von 127.0.0.1, Medien ohne Tonspur (ffprobe: 0 Audiostreams), Engines auf
Lautstärke 0, keine Tasten. Parallel lief zeitweise der Test-Host der B04-Reparatur; es gab keinen Gesamtlauf, nur gezielte
Suiten und eigene Prüftests (`ReviewB08Tests`, nur im Worktree). Die gefilterten Protokolle und die Prüftests liegen außerhalb
des Repositorys unter `~/.claude/projects/…/e8de96ed-…/review-b08-belege/`.

**Läufe (Debug, `test-without-building`):**

```
B08AbsturzTests, B08HauptfensterTests, B08NachtragTests, B08OberflaecheTests, B08ReparaturTests, B08SessionTests
  Executed 53 tests, with 3 tests skipped and 0 failures (0 unexpected) · ** TEST EXECUTE SUCCEEDED **
  übersprungen nur opt-in (EC-15, BF-101, AK-29); erwartete Fehlschläge 6 (BUG-05 Aktualisieren, BUG-06 Limit, BUG-08 ×2, BUG-09 ×2)
ReviewB08Tests RV01–RV08 (eigene): alle bestanden · B06PlayerViewTests + B06ReparaturTests + B06EngineZustandTests:
  Executed 35 tests, with 2 tests skipped (B06_LANGSAM) and 0 failures
B06DeadlockTests (B06_DEADLOCK=1, _FENSTER=1, _STOP=1, 20 Runden): „alle 20 Runden ohne Hänger … abbauten=80 | höchstensGleichzeitig=1“
iOS: xcodebuild build … 'generic/platform=iOS Simulator' → ** BUILD SUCCEEDED ** · macOS: 0 Warnungen in Sources/
```

**Belege zu den Prüfpunkten**

1. **Vier Absturzwege** — A `testAK23_…` 4 Fälle + 3 Gegenproben bestanden (Raster, roter Knopf echt, X per Mausereignis).
   Zusätzlich RV01 mit **laufenden** Streams (2 × VLC, 2 × AVKit): Raster + Schließen mit 4 → `slots=0`, VLC frei und TS zu nach
   0,1 s, 0 HLS-Anfragen danach; Raster + Schließen mit 1 → `slots=0`, Umschalter im Raster mit 1 Stream `aktiv=true`; X im Raster
   `[2, 1, 0]`, Fenster bleibt offen mit Leerzustand. R `testBUG01_…`: `clear()` im Raster mit 1–4, Entfernen vorn/hinten/Mitte je
   `[3, 2, 1, 0]`. Kein Absturz. Release (`-O`) hat das Review nicht erneut gebaut (Beleg nur aus dem Build, *Verifikation* 3).
2. **VLC-Bild nach Fokuswechsel** — N `testAK14_AK15_AK16_…` mit echtem Klick bei aktiver App: Schwarzanteil vorher/2 s/10 s
   `0,00/0,00/0,00`; O `testAK14_AK15_…`: VLC 1/5/10/15 s, nach Größenänderung, nach Raster↔Fokus je `0,00`. RV02: zwölf schnelle
   Fokus- und Layoutwechsel mit vier VLC-Kacheln → vier verschiedene Behälter, großes Bild `0,00` schwarz, die drei kleinen Flächen
   genau an ihren Kachelrechtecken, danach im Raster alle vier Zellen `0,00`.
3. **X des großen Streams** — O `testAK16_…`: X (1562, 795, 30 × 30) von der ersten kleinen Kachel (Oberkante 787) nicht verdeckt,
   ein Mausklick entfernt den großen Stream; N mit aktiver App ebenso; R `testBUG04_…` von 4 auf 1 nur über das große X.
4. **Abgeblendeter ⊞** — O AK-05: Titel bleibt „QA Voll“, 0 Anfragen für Kanal 5, kein neuer `AVPlayer`; R `testBUG03_…` im
   Favoriten-Tab ebenso.
5. **30-s-Meldung (Grenzwert)** — R `testBUG07_…`: Meldung 29,8 s nach dem Stillstand (Messraster 0,5 s), 0 Anfragen danach, die
   gesunde Kachel spielt. Eigener Mock mit einmal zurückgehaltenem Segment (RV04b, Abtastung 0,1 s): Stillstand **17,9 / 23,9 /
   26,9 s → keine Meldung, Wiedergabe läuft weiter**; Stillstand **30,05 s → Meldung bei 30,15 s**. Dauerhafter Segment-404 (RV04):
   Meldung bei 30,77 s Stillstand. Die Frist greift weder zu früh noch spürbar zu spät; der Player (B06) hat keine Frist
   (`stallLimit` einer neuen Engine `nil`).
6. **Tests nicht aufgeweicht** — `XCTExpectFailure` in `Tests/B08` 15 → 6 (9 entfernt: O BUG-01/-02/-03/-04/-10, N BUG-02 ×2 und
   BUG-04, S BUG-07). Die entfernten Blöcke sind durch die frühere Erwartung oder strengere Aussagen ersetzt (z. B. AK-05 zusätzlich
   `playerMuted == []`, AK-16 genaue Restliste und Ton, EC-10 Mindestgröße + Umschalter). Die sechs verbliebenen gehören zu nicht
   behobenen BUGs mit offener Entscheidung. Einschränkung siehe R-B08-2.
7. **Regressionen** — `VLCSurfaceHostView` im Einzel-Player: B06-Suiten grün (Bild, Vollbild, Tasten, Verlassen, Tabwechsel);
   RV06/RV08 in der echten `ContentView` mit VLC-Sender (Playlists-Stapel Tiefe 2 und Favoriten Tiefe 1): Tabwechsel pausiert nur
   (Verbindung bleibt), Rückkehr → dieselbe Engine spielt, Zeit läuft (4505 → 6105 ms), Bild `0,00` schwarz; „Zurück“ → TS zu nach
   0,0–0,1 s, VLC-Player abgebaut. **BF-101:** `testBF101_…` mit 20 Runden (Schließen / X×4, sofort neu) und RV05 mit 20 Runden
   (je Runde Fokus reihum, Raster↔Fokus, dann Schließen im Raster / X×4 / `clear()` im Raster, sofort vier neue) — kein Hänger,
   höchstens 4 VLC-Player gleichzeitig, alle frei und alle Verbindungen zu nach 0,2–0,7 s; B06-Deadlock-Test 20 Runden mit Fenstern.
8. **Sicherheit** — Die neuen Texte (`interruptedMessage`, `connectionLimitHint`) sind feste Zeichenketten; `Slot.provider` enthält
   nur Host:Port und wird nicht angezeigt. RV03 und R `testBUG06_…`: keine Beschriftung enthält `127.0.0.1`, Pfad, Benutzer oder
   Passwort. Im Diff der B07/B08-Dateien kein neuer `print`/`NSLog`/`os_log`/`Logger`.

**Funde**

| Nr. | Art | Ort | Beleg | Schwere |
|---|---|---|---|---|
| R-B08-1 | Verhalten/Text | `Views/MultiviewTile.swift` (`stateOverlay`, Fall `.failed`) mit `MultiviewSession.otherStreamIsPlaying` | RV03: HLS-Kachel lief, stockte (Segment-404) und meldet „Die Verbindung zum Sender wurde unterbrochen.“; darunter steht „Möglicherweise erlaubt dein Abo nicht so viele Streams gleichzeitig.“, weil eine andere Kachel desselben Hosts spielt. Der Hinweis hängt an **jedem** Fehlschlag (auch `.noResponse`, `.unplayable`, `.interrupted`), nicht nur an einer abgelehnten Verbindung; bei einer Unterbrechung nach laufender Wiedergabe führt er in die Irre | gering |
| R-B08-2 | Test | `B08OberflaecheTests.testAK11_AK12_AK13_…`, `B08ReparaturTests.testBUG01_EinStreamImRasterZurueckZuFokus` | Scheitert der Mausklick auf „Fokus“, lösen beide Tests die Aktion des Umschalters programmatisch aus (`sendAction`) und bestehen trotzdem – ein Rückfall des Klickwegs fiele nicht auf. Der reine Klick wirkt (RV07: `gewählt=1 aktiv=true` → Klick → `gewählt=0 aktiv=false`, Layout „Fokus“); kein Produktfehler | gering |

**Hinweise (keine Funde dieser Reparatur)**

- Zu OF-11: AVKit erholt sich bei Live-HLS nach einem Segmentausfall von ≈ 20 s nicht, obwohl der Anbieter wieder liefert (RV04:
  Segmente ab 30,1 s wieder `200`, Wiedergabezeit steht weiter); die Kachel meldet dann nach 30 s „unterbrochen“ und bietet
  keinen Neuversuch – der Nutzer muss sie entfernen und neu hinzufügen.
- Die Wachhund-Threads von `B08NachtragTests.testBF101_…` (und `B06DeadlockTests`) laufen nach dem Test weiter und beenden den
  Test-Host 60 s später, wenn im selben Prozess ein weiterer Test folgt (hier beobachtet: Exit 70 während eines anschließenden
  Tests, der allein wiederholt 20/20 Runden bestand). Opt-in-Läufe mit `B08_HAENGER=1` nur einzeln starten.
- `docs/app-shell.md` und `docs/design-system.md` sind veraltet (vom Build selbst gemeldet); Nachführen in QA 2.

**Urteil B08: in Ordnung.** Alle vier Absturzwege, das VLC-Bild, das große X, der abgeblendete ⊞ und die 30-s-Frist sind
ausgeführt belegt; kein blockierender oder wichtiger Fund. R-B08-1 und R-B08-2 können mit QA 2 bzw. einer Nacharbeit erledigt werden.

**Aufgeräumt:** Worktree `wt/review-b08` samt DerivedData (`build/dd-test`, `build/dd-ios` darin) mit `git worktree remove --force`
entfernt, `git worktree prune`; eigener HLS-Mock (Python, 127.0.0.1), Aktivierungs- und Systemfenster-Helfer beendet; keine
Simulatoren, keine Datenträgerabbilder; im Arbeitsbaum nur dieser Abschnitt (und der in B07) ergänzt, keine Nachweise geschrieben.
