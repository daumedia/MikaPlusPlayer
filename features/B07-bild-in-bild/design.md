# B07 · Bild-in-Bild — Systemdesign

Status: `rekonstruiert` · Stand: 2026-09-15 · Rekonstruktion aus dem Code (sdd-erfassen) · Stack-Profil: `swiftui-ios` + `swiftui-macos`

**Kein Code in diesem Dokument.** Beschrieben ist der Aufbau, wie er auf `main` @ `c01f1cf` steht,
nicht, wie er sein sollte. Fragwürdiges ist markiert und verweist auf den *Fehlbestand* in `spec.md`.

## Überblick

Bild-in-Bild ist eine optionale Fähigkeit im Protokoll `PlaybackEngine`. Alle Engines erben
wirkungslose Standardwerte („nicht unterstützt"); nur die AVKit-Engine überschreibt sie.

Für Bild-in-Bild hat die AVKit-Engine ihre Videofläche von SwiftUI-`VideoPlayer` auf einen eigenen
`AVPlayerLayer` umgestellt. Diesen Layer bettet `PlayerLayerView` in SwiftUI ein, und an ihm hängt
ein `AVPictureInPictureController`. Der Controller entsteht beim ersten Einbetten; ein kleiner
Delegate meldet Start und Ende an die Engine zurück.

Die `PlayerView` zeigt den Knopf, wenn die Engine Unterstützung meldet, belegt die Taste P und
schaltet auf iOS den automatischen Start beim App-Wechsel ein. Beim Verlassen pausiert sie nicht,
solange Bild-in-Bild aktiv ist. Die Engine lebt aber nur so lange wie der Zustand der Ansicht; daraus
folgt das unterschiedliche Verhalten beim Verlassen (FB-03).

## Szenen und Einstiege

SwiftUI, keine Routen. Plattform in Klammern.

| Einstieg | Zweck | Zugang |
|---|---|---|
| `PlayerView` (aus Senderliste B04 oder Favoriten B05), Knopf oben rechts | Bild-in-Bild ein/aus (beide) | jeder Nutzer des Geräts |
| `PlayerView`, Taste P bei Tastaturfokus | ebenso (macOS; iPad mit Tastatur) | ebenso |
| App-Wechsel bei laufendem Stream | automatischer Start (nur iOS/iPadOS) | ebenso |
| Knöpfe im schwebenden Fenster | Schließen, Pause, Springen, Zurück zur App — **Systemoberfläche**, nicht von der App gebaut | ebenso |

Kein Menüeintrag, kein Kontextmenü, keine Einstellung.

## Komponentenstruktur

```
PlayerView                                        (B06) @State engine: (any PlaybackEngine)?
├── engine.makePlayerView()                       AVKit: PlayerLayerView(playerLayer) + setupPiPIfNeeded
│                                                 VLC:   VLCPlayerSurface, keine PiP-Fähigkeit
├── controlsOverlay                               nur wenn controlsVisible UND state == .playing
│   └── HStack oben rechts
│       ├── [supportsPictureInPicture] Button     controlIcon(pip.enter | pip.exit), .help("Bild-in-Bild")
│       │                                         Aktion togglePiP()
│       └── Vollbild-Button                       (B06)
├── .onKeyPress  "p"/"P" → togglePiP() → .handled
├── .onAppear    startIfNeeded(): Factory → load → setAutomaticPictureInPicture(true)
└── .onDisappear falls !isPictureInPictureActive → engine.pause()
                 (bei aktivem PiP: nichts; die @State-Engine wird mit der Ansicht freigegeben
                  → iOS sofort, macOS verzögert bis zur nächsten Navigation, FB-03)

togglePiP()  = engine.togglePictureInPicture() + flashControls()   (3,5 s Steuerung sichtbar)

AVKitPlaybackEngine  (@MainActor @Observable)
├── player: AVPlayer                              privat
├── playerLayer: AVPlayerLayer                    gehört der Engine, player daran gebunden
├── pipController: AVPictureInPictureController?  lazy, einmalig, erst in makePlayerView()/start
├── pipDelegate: PiPDelegate?                     starke Referenz hält den Delegate am Leben
├── automaticPiP: Bool                            gemerkter Wunsch, falls Controller noch fehlt
├── isPictureInPictureActive                      beobachtbar, nur vom Delegate gesetzt
├── supportsPictureInPicture                      = AVPictureInPictureController.isPictureInPictureSupported()
│                                                   (Gerätefähigkeit, NICHT isPictureInPicturePossible)
├── startPictureInPicture()                       setup; nur wenn isPictureInPicturePossible → start
├── stopPictureInPicture()                        pipController?.stop
├── setAutomaticPictureInPicture(_:)              iOS: canStartPictureInPictureAutomaticallyFromInline
└── load(_:)                                      iOS: AVAudioSession .playback / .moviePlayback aktivieren

PiPDelegate (NSObject, AVPictureInPictureControllerDelegate)
├── weak engine
├── didStart   → isPictureInPictureActive = true
├── didStop    → false
└── failedToStart → false                         keine Meldung (AK-18)
    — kein willStart/willStop, kein restoreUserInterfaceForPictureInPictureStop (FB-03)

PlayerLayerView (UIViewRepresentable / NSViewRepresentable)
└── PlayerLayerHostView                           fügt den Engine-Layer als Sublayer ein,
                                                  hält den Frame ohne implizite Animation synchron

PlaybackEngine (Protokoll)  → Extension mit No-Op-Standards:
    supports = false · active = false · start/stop = nichts · toggle = active ? stop : start ·
    setAutomatic = nichts                         → VLCPlaybackEngine erbt alles davon
```

### Zustandsverlauf

```
            Knopf / P / App-Wechsel (iOS, laufend)
 inaktiv ────────────────────────────────────────▶ aktiv (schwebendes Fenster)
    ▲                                                 │
    │  Knopf / P / Schließen im Fenster / 2. PiP      │
    └─────────────────────────────────────────────────┘
                                                      │ „Zurück" im Player
                                                      ├─ iOS:   Engine frei → Fenster weg, Wiedergabe endet (AK-14)
                                                      └─ macOS: Engine lebt → Fenster spielt weiter, nicht steuerbar;
                                                                nächste Navigation → Engine frei → Fenster weg (AK-15)
 Start nicht möglich (lädt, Fehler, Gerät ohne PiP, VLC) → bleibt inaktiv, keine Meldung (AK-06–AK-09)
```

### Beteiligte Typen

| Typ | Datei | Rolle in B07 |
|---|---|---|
| `PlaybackEngine` (Protokoll + Extension) | `Services/PlaybackEngine.swift:61-94` | PiP-Schnittstelle und No-Op-Standards |
| `PlaybackEngineFactory`, `StreamType` | `Services/PlaybackEngine.swift:13-19, 99-108` | entscheidet über die Endung, ob AVKit (PiP) oder VLC (kein PiP) |
| `AVKitPlaybackEngine` | `Services/AVKitPlaybackEngine.swift:11-149` | Layer, Controller, Auto-PiP, Audio-Session |
| `PiPDelegate` | `Services/AVKitPlaybackEngine.swift:153-172` | Rückmeldung Start/Ende/Fehlschlag |
| `PlayerLayerView`, `PlayerLayerHostView` | `Services/PlayerLayerView.swift` | Einbettung des Layers (iOS `:17-50`, macOS `:56-96`) |
| `PlayerView` | `Views/PlayerView.swift` | Knopf `:114-121`, Taste `:312-313`, `togglePiP` `:337-340`, `onDisappear` `:79-88`, `startIfNeeded` `:398-408` |
| `VLCPlaybackEngine` | `Services/VLCPlaybackEngine.swift` | implementiert nichts davon, erbt „nicht unterstützt" |
| `MultiviewSession`, `MultiviewTile` | `Services/MultiviewSession.swift:53-64`, `Views/MultiviewTile.swift:17` | rufen `setAutomaticPictureInPicture` nie auf; `makePlayerView()` legt trotzdem je AVKit-Kachel einen Controller an |

## Datenmodell

B07 führt **keine** Felder, keine Entität und keine Schemaänderung ein. Eine Migration ist nicht
nötig. Nichts wird in SwiftData, `UserDefaults` oder Dateien geschrieben (AK-24).

### Außerhalb des Schemas

| Ort | Inhalt | Entsteht durch |
|---|---|---|
| `Info.plist:62-66` | `UIBackgroundModes = [audio]` | Voraussetzung für Hintergrundwiedergabe und PiP auf iOS |
| `AVAudioSession` (iOS, flüchtig) | Kategorie `.playback`, Modus `.moviePlayback`, aktiv | `AVKitPlaybackEngine.load` → `activateAudioSession` (`:105-111`), bei jedem Laden, Fehler ignoriert (`try?`) |
| Systemzustand Bild-in-Bild (flüchtig) | schwebendes Fenster, gebunden an den `AVPlayerLayer` | `AVPictureInPictureController`; hält nichts über das Fenster hinaus |

### Nicht persistiert

`isPictureInPictureActive`, `automaticPiP`, Controller und Delegate. Nach einem Neustart ist
Bild-in-Bild aus.

## Zugriffsregeln

Keine Daten, keine Konten, keine Rollen. Es geht nur um Sichtbarkeit und Steuerbarkeit.

| Wer | Sieht | Steuert | Erzwungen durch |
|---|---|---|---|
| Nutzer der App | Bild im Player bzw. im schwebenden Fenster | Knopf, P, Systemknöpfe im Fenster | App bzw. System |
| Nutzer nach „Zurück" auf dem Mac | ⚠ weiterlaufendes Fenster | nur noch die Systemknöpfe im Fenster; aus der App nichts (FB-03) | — |
| Umstehende, Bildschirmfreigabe, Bildschirmaufnahme, Bildschirmfotos | ⚠ das schwebende Fenster über allen Apps, auf iOS nach jedem App-Wechsel automatisch (OF-01) | nichts | System; die App setzt keinen Schutz |
| Sperrbildschirm | nicht geprüft; die App liefert keine „Jetzt läuft"-Daten (AK-22) | — | System |
| Andere Apps | nichts aus B07 | nichts | Betriebssystem |

## Missbrauchsschutz

| Stelle | Limit | Verhalten bei Überschreitung | Wo konfiguriert |
|---|---|---|---|
| Gleichzeitige Bild-in-Bild-Fenster | eins (System) | der neue Start beendet und pausiert den alten (AK-17) | Betriebssystem |
| Parallele Streams nach „Zurück" auf dem Mac | **keins** | zweite Verbindung zum Anbieter, bis die alte Engine freigegeben wird (FB-03) | — |
| Hintergrundwiedergabe (iOS) | **keins**, keine Zeitgrenze | Stream läuft weiter, auch unsichtbar (AK-21) | `Info.plist:62-66`, `.playback`-Session |
| Start-Versuche | keins nötig | ein unmöglicher Start ist wirkungslos | `AVKitPlaybackEngine.swift:72` |

## Externe Dienste

| Dienst | Wofür | Was geht hin | Was wird vorher entfernt |
|---|---|---|---|
| System-Bild-in-Bild (lokal; macOS-Systemprozess „Bild-in-Bild", auf iOS die Systemoberfläche) | Anzeige des schwebenden Fensters | der Videolayer; keine Metadaten, kein Titel | — |
| IPTV-Anbieter | in B07 keine neuen Abrufe; die Wiedergabe aus B06 läuft im Fenster bzw. Hintergrund weiter | wie B06; nach „Zurück" auf dem Mac ggf. zwei Verbindungen (FB-03) | — |

Kein KI-Dienst, keine Analyse, kein Fehler-Tracking, kein Server von daumedia.

## Plattformunterschiede

| Verhalten | macOS | iPadOS | iPhone |
|---|---|---|---|
| Unterstützung gemeldet | ja (ausgeführt) | ja (Simulator, ausgeführt) | Simulator iOS 26.5/27.0: **nein**; Gerät nicht geprüft |
| Knopf und Taste P | ja | ja (Taste mit Hardware-Tastatur) | nur wenn unterstützt |
| Automatischer Start beim App-Wechsel | nein (`#if os(iOS)`) | ja | ja, wenn unterstützt |
| „Zurück" bei aktivem Bild-in-Bild | Fenster spielt weiter, nicht steuerbar | Fenster verschwindet sofort | wie iPadOS (gelesen) |
| Audio-Session | keine (macOS kennt keine) | `.playback` / `.moviePlayback` | ebenso |

## Erkennbare Entscheidungen

| # | Entscheidung | Alternative | Warum so |
|---|---|---|---|
| 1 | PiP als optionale Protokollerweiterung mit No-Op-Standards | eigenes Protokoll `PictureInPictureCapable` und Typprüfung in der View | Commit `54550b2`: „VLCKit unangetastet"; die View bleibt engine-unabhängig |
| 2 | Eigener `AVPlayerLayer` statt SwiftUI-`VideoPlayer` oder `AVPlayerViewController` | `AVPlayerViewController` mit eingebautem PiP, Wiederherstellung und „Jetzt läuft" | Kommentar `PlayerLayerView.swift:6-9`: der Controller braucht einen Layer. Warum nicht `AVPlayerViewController` (bringt eigene Steuerung, die mit dem eigenen Chrome kollidieren würde), ist nicht ausdrücklich begründet |
| 3 | Separater `PiPDelegate` als `NSObject` | Engine selbst als `NSObject` | Kommentar `AVKitPlaybackEngine.swift:151-152`: `@Observable`-Engine soll kein `NSObject` sein |
| 4 | Controller lazy beim ersten Einbetten, Auto-PiP-Wunsch gemerkt | Controller im `init` | Kommentar `:25-27`: der Controller entsteht erst mit `makePlayerView` |
| 5 | Auto-PiP immer an im Einzel-Player, aus im Multiview | Einstellung für den Nutzer | Kommentar `PlaybackEngine.swift:77-79`: konkurrierende Auto-Starts aus mehreren Kacheln vermeiden. Eine Einstellung ist nicht vorgesehen (OF-01) |
| 6 | ⚠ Schutzabfrage in `onDisappear` statt eigener Lebensdauer der PiP-Wiedergabe | Engine bei aktivem PiP außerhalb der Ansicht halten (z. B. App-weite Sitzung wie beim Multiview) oder PiP beim Verlassen bewusst beenden | Kommentar `PlayerView.swift:83-84` nennt nur den App-Wechsel. Dass die Ansicht beim Zurücknavigieren samt Engine freigegeben wird, wurde offenbar nicht bedacht (FB-03, OF-04) |
| 7 | ⚠ Kein `restoreUserInterfaceForPictureInPictureStop` | Delegate, der den Player wieder öffnet | Grund nicht erkennbar; solange der Player offen ist, genügt das Standardverhalten des Systems (EC-08) |
| 8 | Audio-Session bei jedem `load` aktivieren, Fehler verschlucken | einmal beim App-Start, Fehler anzeigen | Kommentar `:103-104`: PiP und Hintergrund-Audio setzen eine aktive `.playback`-Session voraus. Warum bei jedem Laden und ohne Fehlerbehandlung, nicht erkennbar |
| 9 | ⚠ `isPaused` von der App geführt, nicht aus dem Player abgeleitet | Rate/`timeControlStatus` beobachten | Grund nicht erkennbar; stammt aus B06 (`PlaybackEngine.swift:38`: „Getrennt nachgehalten"), wurde für PiP nicht angepasst (FB-04) |
| 10 | Kein PiP für VLC | PiP über `AVSampleBufferDisplayLayer` mit VLC-Frames | Commit: „PiP nur für AVKit-Streams (HLS/mp4), nicht für rohe .ts" — technische Grenze, kein Aufwand dafür vorgesehen |
| 11 | Knopf nach Gerätefähigkeit (`isPictureInPictureSupported`), nicht nach aktueller Möglichkeit (`isPictureInPicturePossible`) | Knopf erst zeigen bzw. aktivieren, wenn der Start möglich ist | Grund nicht erkennbar; praktisch mild, weil der Knopf nur bei `.playing` erscheint |

## Abdeckung der Akzeptanzkriterien

Umgedreht: Was erfüllt das Kriterium heute? Fundstellen beziehen sich auf `Sources/`.

| AK | Erfüllt durch | Anmerkung |
|---|---|---|
| AK-01 | `PlayerView.swift:114-121, 154-160`; `AVKitPlaybackEngine.swift:66-68` | VoiceOver-Label kommt vom SF-Symbol, keine eigene `accessibilityLabel` (OF-03) |
| AK-02 | `PlayerView.swift:110, 237-243, 266-279` | Chrome aus B06 |
| AK-03 | `AVKitPlaybackEngine.swift:70-74, 88-99, 160-162`; `PlayerLayerView.swift`; Symbolwechsel `PlayerView.swift:116-117` | Platzhaltertext und Fenster vom System |
| AK-04 | `PlaybackEngine.swift:90-92`; `AVKitPlaybackEngine.swift:76-78, 164-166` | |
| AK-05 | `PlayerView.swift:57, 307-313, 337-340, 349-352` | `.lowercased()` macht P und p gleich |
| AK-06 | `AVKitPlaybackEngine.swift:72` (`isPictureInPicturePossible`-Wache, kein Merken) | |
| AK-07 | ebenso; `PlayerView.swift:100-101` | |
| AK-08 | `AVKitPlaybackEngine.swift:66-68, 89-91` | |
| AK-09 | `PlaybackEngine.swift:13-19, 85-94, 101-104`; `VLCPlaybackEngine.swift` ohne PiP | ⚠ FB-02 |
| AK-10 | `PlayerView.swift:403-404`; `AVKitPlaybackEngine.swift:80-85, 94-96, 105-111`; `Info.plist:62-66` | `#if os(iOS)` |
| AK-11 | Systemverhalten; die App beendet PiP bei Rückkehr nicht (kein `scenePhase`-Handler) | |
| AK-12 | `MultiviewSession.swift:53-64` (kein `setAutomaticPictureInPicture`), `MultiviewTile.swift` ohne Knopf, `MultiviewScreen.swift` ohne `onKeyPress` | |
| AK-13 | `PlayerView.swift:79-88` | B06 |
| AK-14 | `PlayerView.swift:17, 83-87`; `AVKitPlaybackEngine.swift:154` (weak) | ⚠ FB-03 |
| AK-15 | ebenso; Freigabe der `@State`-Engine auf macOS verzögert (beobachtet, Ursache in SwiftUI) | ⚠ FB-03 |
| AK-16 | `AVKitPlaybackEngine.swift:13, 45-47`; `PlayerView.swift:142, 323-328` | ⚠ FB-04 |
| AK-17 | ebenso; Systemverhalten „ein PiP-Fenster" | ⚠ FB-04 |
| AK-18 | `AVKitPlaybackEngine.swift:168-171` | OF-02 |
| AK-19 | kein `externalMetadata`, kein Titel am `AVPlayerItem` (`AVKitPlaybackEngine.swift:38`) | |
| AK-20 | Systemverhalten; kein Schutz der App | OF-01 |
| AK-21 | `Info.plist:62-66`; `AVKitPlaybackEngine.swift:105-111` | Hintergrund selbst gehört zu B06 |
| AK-22 | Fehlen von `MediaPlayer`/`MPNowPlayingInfoCenter` in `Sources/` | Systemverhalten nicht geprüft |
| AK-23 | Fehlen jedes Logging-Aufrufs in `Sources/` | nicht am Produktivbuild ausgeführt |
| AK-24 | kein Schreibzugriff im PiP-Code | |

### Code ohne AK-Zuordnung

- **PiP-Controller in Multiview-Kacheln** (`MultiviewTile.swift:17` → `AVKitPlaybackEngine.makePlayerView`
  → `setupPictureInPictureIfNeeded`): Für jede AVKit-Kachel entsteht ein Controller samt Delegate, der
  nie benutzt wird. Harmlos, aber toter Aufwand (EC-11).
- **Doku-Kommentar `stopPictureInPicture`** (`PlaybackEngine.swift:73`: „holt die Wiedergabe zurück
  in die App"): Nach „Zurück" auf dem Mac blieb der Aufruf wirkungslos (AK-15).
- **Kommentar `MultiviewSession.swift:8`** nennt das Fokus-Layout „(PiP)". Gemeint ist die
  Anordnung der Kacheln, nicht System-Bild-in-Bild.

### Bestehende Tests

`Tests/PlaybackEngineTests.swift`, 2 von 6 Tests betreffen B07, nur macOS-Target. Beide liefen am
2026-09-15 in der Scratchpad-Kopie grün.

| Test | Prüft | Deckt |
|---|---|---|
| `testPictureInPictureInactiveInitially` | frische Engine meldet „nicht aktiv" | Ruhezustand, kein AK direkt |
| `testTogglePictureInPictureIsSafeWithoutOnscreenLayer` | Umschalten ohne Layer im Fenster stürzt nicht ab und bleibt inaktiv | AK-06 teilweise |

Ohne Test: jeder tatsächliche Start und jedes Ende, der Delegate, Auto-PiP, der Knopf, die Taste,
das Verhalten beim Verlassen, VLC ohne PiP, alles auf iOS. Die Sonde (`qa-erfassung/sonde.patch`,
`B07ProbeTests`) zeigt, dass Start, Ende und zwei konkurrierende Engines auf macOS per XCTest mit
Fenster und lokalem HLS-Server prüfbar sind.
