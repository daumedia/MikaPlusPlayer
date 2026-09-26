# B06 · Wiedergabe — Systemdesign

Status: `rekonstruiert` · Stand: `c01f1cf` + Reparatur B01 (2026-09-16) · Rekonstruktion aus dem Code (sdd-erfassen), erstellt 2026-09-16 · Stack-Profil: `swiftui-ios` + `swiftui-macos`

**Kein Code in diesem Dokument.** Beschrieben ist der Aufbau auf dem Stand `c01f1cf` einschließlich der noch nicht
committeten Reparatur von B01, nicht, wie er sein sollte. Fundstellen beziehen sich auf `Sources/` dieses Stands;
`PlayerView.swift` ist im Arbeitsbaum identisch mit der eingefrorenen Kopie. Fragwürdiges ist markiert und verweist
auf den *Fehlbestand* in `spec.md`.

## Überblick

Die Wiedergabe besteht aus einer Ansicht und zwei austauschbaren Engines hinter einem Protokoll. Die
`PlayerView` wird aus der Senderliste (B04) oder den Favoriten (B05) in den Navigationsstapel des Tabs gelegt.
Beim Erscheinen fragt sie den `StreamURLResolver` nach der abspielbaren Adresse; bei Xtream fügt er Benutzername
und Passwort aus dem Schlüsselbund ein (B01). Die `PlaybackEngineFactory` wählt dann anhand der Dateiendung
die AVKit-Engine (HLS, alles Übrige) oder die VLC-Engine (rohes MPEG-TS) und startet sie.

Die Engines übersetzen ihre eigenen Zustände in das gemeinsame `PlaybackState` (`idle`, `loading`, `playing`,
`failed`), dazu die getrennt gehaltenen Werte `isPaused`, `isMuted` und `volume`. Nach diesem Zustand richtet sich
die Ansicht: Ladekreis, Fehleransicht oder Video mit Steuerung und HUD. Tastatur, Klick bzw. Tipp und die Knöpfe
rufen dieselben kleinen Aktionen. Vollbild wird „in place" gelöst: Die Ansicht blendet die Leisten aus und schaltet
unter macOS zusätzlich das native Fenster-Vollbild, unter iOS auf dem iPhone die Ausrichtung. Beim Verschwinden
pausiert die Ansicht nur. Wie lange Engine und Verbindung danach leben, bestimmt SwiftUI über den Zustand der
Ansicht (FB-02).

## Szenen und Einstiege

SwiftUI, keine Routen. Plattform in Klammern.

| Einstieg | Zweck | Zugang |
|---|---|---|
| `ChannelListView` → Senderkarte → `.navigationDestination(for: Channel.self)` (`ChannelListView.swift:39-41`) | Player öffnen (beide) | jeder Nutzer des Geräts, keine Anmeldung an der App |
| `FavoritesView` → Senderkarte (`FavoritesView.swift:42-44`) | ebenso (beide) | ebenso |
| „Zurück" der Navigationsleiste bzw. Fenster-Symbolleiste, Tabwechsel | Player verlassen (beide) | ebenso |
| Tastatur bei Fokus auf dem Player | Steuerung (macOS; iOS nur mit Hardware-Tastatur) | ebenso |
| Grüner Fensterknopf, Menü „Enter Full Screen", ⌃⌘F | natives Vollbild **am Player vorbei** (macOS, AK-24) | ebenso |

Kein Deep Link, kein eigener Menüeintrag, kein Tastenkürzel außerhalb des Players (AS-05). Multiview (B08) nutzt
dieselben Engines, aber nicht die `PlayerView`.

## Komponentenstruktur

```
PlayerView(channel: Channel)                         Views/PlayerView.swift
│  @State engine: (any PlaybackEngine)?              lebt so lange wie der Zustand der Ansicht (FB-02)
│  @State resolveError: String?                      Meldung des Resolvers
│  @State isFullscreen, showControls, topHover (macOS), hud: HUDKind?, autoHideTask, hudTask
│  @FocusState keyboardFocused
│
├── ZStack
│   ├── Color.black
│   ├── [engine != nil]
│   │   ├── engine.makePlayerView()                  AVKit: PlayerLayerView(AVPlayerLayer) · VLC: VLCPlayerSurface(NSView/UIView)
│   │   ├── stateOverlay(state)                      .idle/.loading → ProgressView large weiß
│   │   │                                            .failed(msg)  → failureView(msg)
│   │   │                                            .playing      → nichts
│   │   ├── controlsOverlay                          nur wenn controlsVisible UND state == .playing
│   │   │   ├── oben rechts: [PiP → B07] · Vollbild-Knopf     Padding 12 bzw. 24 im Vollbild
│   │   │   └── unten links: Play/Pause · Stumm (controlIcon: weiß, Kreis schwarz 50 %)
│   │   └── hudOverlay                               0,9 s: playPause(isPaused) · mute(isMuted) · volume(0…1)
│   ├── [engine == nil, resolveError != nil] failureView(resolveError)
│   └── [sonst] ProgressView weiß
│
├── .onTapGesture → toggleControls()                 Steuerung an/aus, bei „an" Auto-Ausblenden neu
├── .focusable · .focusEffectDisabled · .focused($keyboardFocused) · .onKeyPress(handleKey)
├── macOS .onContinuousHover → topHover (y < 90 pt)  wirkt nur im Vollbild (controlsVisible, Symbolleiste)
├── .ignoresSafeArea(.all nur im Vollbild) · .navigationTitle(channel.name | "")
├── iOS  .toolbar(hidden) für navigationBar und tabBar · .statusBarHidden · .persistentSystemOverlays   (im Vollbild)
├── macOS .toolbar(macToolbarVisibility, for: .windowToolbar)                                          (im Vollbild nur bei Hover)
├── .onAppear    startIfNeeded() · scheduleAutoHide() · keyboardFocused = true
└── .onDisappear autoHide/HUD abbrechen · resetOrientation() · falls kein PiP aktiv: engine.pause()      (kein stop)

failureView(msg)                                     ContentUnavailableView „Wiedergabe fehlgeschlagen", Warndreieck
├── Text(msg)                                        ungefilterter Text der Engine bzw. des Resolvers (AK-06, AK-31)
├── [gespeicherte Adresse endet auf TS-Endung] „Hinweis: Rohe MPEG-TS-Streams (.ts) benötigen VLCKit – siehe README."  ⚠ FB-04
└── Button „Erneut versuchen" → retry()              .borderedProminent, Akzent; Hintergrund .ultraThinMaterial

startIfNeeded()
├── engine == nil: playableURL() → nil ⇒ resolveError gesetzt, Ende
│                  Factory.engine(for: url) → engine = … → load(url) → setAutomaticPictureInPicture(true) (B07)
└── engine != nil: engine.play()                     Rückkehr aus anderem Tab (AK-27)

retry()          playableURL() → nil ⇒ Fehler bleibt · engine vorhanden ⇒ engine.load(url) (dieselbe Engine) · sonst startIfNeeded()

handleKey(press)                                     Rückgabe .handled unterdrückt den macOS-Warnton
├── .space → togglePlay()        ├── .upArrow → changeVolume(+0,05)   ├── .downArrow → changeVolume(-0,05)
├── .escape → isFullscreen ? toggleFullscreen() : .ignored
└── characters.lowercased(): "m" toggleMute · "f" toggleFullscreen · "p" togglePiP (B07) · "+"/"=" +0,05 · "-" -0,05 · sonst .ignored

togglePlay()     engine.togglePlayPause() · flashControls() · HUD playPause(isPaused)
toggleMute()     engine.toggleMute() · flashControls() · HUD mute(isMuted)
changeVolume(d)  engine.setVolume(volume + d) · HUD volume   (kein flashControls)
flashControls()  showControls = true · scheduleAutoHide()
scheduleAutoHide() Task: 3,5 s schlafen → showControls = false   (gestartet schon in onAppear, AK-14)

toggleFullscreen()  isFullscreen.toggle() · applyFullscreenSideEffects · showControls = true · Auto-Ausblenden · keyboardFocused = true
applyFullscreenSideEffects(on)
├── iOS:   nur iPhone: activeWindowScene.requestGeometryUpdate(on ? .landscapeRight : .portrait)          ⚠ AK-25
└── macOS: window = NSApp.keyWindow ?? NSApp.mainWindow; window.toggleFullScreen, falls Zustand abweicht ⚠ FB-06
resetOrientation()  nur wenn isFullscreen: applyFullscreenSideEffects(false)    (aus onDisappear)
```

### Engines

```
PlaybackEngine (Protokoll, @MainActor, AnyObject, Observable)       Services/PlaybackEngine.swift:35-81
  state · isPaused · isMuted · volume · load · play · pause · togglePlayPause · toggleMute · setMuted · setVolume
  makePlayerView · PiP-Teil mit No-Op-Standard (B07)          — kein stop(), kein Freigeben

StreamType(url:)            pathExtension.lowercased(): m3u8|m3u → .hls · ts|mpegts|mts|m2ts → .transportStream · sonst .other
PlaybackEngineFactory       .transportStream → VLCPlaybackEngine (falls VLCKit kompiliert) sonst AVKit · .hls/.other → AVKit

AVKitPlaybackEngine (@Observable)                                   Services/AVKitPlaybackEngine.swift
├── player: AVPlayer (ein Player je Engine) · playerLayer: AVPlayerLayer (PlayerLayerView)
├── load(url): state = .loading · iOS AVAudioSession .playback/.moviePlayback aktiv · AVPlayerItem · play() · isPaused = false
├── observe(item): status .readyToPlay → .playing · .failed → .failed(item.error.localizedDescription) · .unknown → .loading
│                  AVPlayerItemFailedToPlayToEndTime → .failed(localizedDescription)
│                  nicht beobachtet: timeControlStatus, Rate, PlaybackStalled, Ende (DidPlayToEndTime)
├── play/pause: player.play()/pause() + isPaused
├── setVolume: clamp 0…1 → player.volume · > 0 hebt Stumm auf · setMuted → player.isMuted
└── deinit: nur Beobachter abbrechen

VLCPlaybackEngine (NSObject, @Observable, VLCMediaPlayerDelegate)   Services/VLCPlaybackEngine.swift (hinter canImport)
├── mediaPlayer: VLCMediaPlayer · drawableView: NSView/UIView (einzige Zeichenfläche)
├── load(url): state = .loading · VLCMedia(url) · play() · isPaused = false
├── pause(): nur wenn mediaPlayer.isPlaying → pause(); isPaused = true immer            ⚠ AK-29, EC-05
├── setVolume/setMuted → applyAudio(): audio.volume = Int(volume·100), audio.isMuted (ohne Audiokanal: später erneut)
├── Delegate mediaPlayerStateChanged → Task @MainActor → liest mediaPlayer.state **zum Ausführungszeitpunkt**
│     .playing/.buffering/.esAdded → .playing (+ applyAudio) · .opening → .loading
│     .error → .failed("VLC konnte den Stream nicht abspielen.") · .stopped/.ended → .idle · sonst (.paused) nichts   ⚠ FB-01
└── kein deinit, kein stop

StreamURLResolver.playableURL(for:store:)                           Services/StreamURLResolver.swift:24-35
├── keine Playlist oder nicht Xtream → channel.streamURL unverändert (M3U)
├── Xtream-Altbestand (sourceURL mit username/password) → channel.streamURL unverändert
├── Schlüsselbund leer → ResolveError.missingCredentials · Schlüsselbundfehler → KeychainError-Text
└── XtreamStreamAddress.playable(stored:secret:) → <host>/live/<user%>/<pass%>/<rest> · kein /live/ → .invalidAddress
```

### Zustandsabbildung (beobachtet)

| Situation | AVKit: Engine-Zustand → Ansicht | VLC: Rohzustände → Engine-Zustand → Ansicht |
|---|---|---|
| Stream spielt | `.playing` → Video, Steuerung | opening, buffering, playing, esAdded, buffering… → `.playing` → Video, Steuerung |
| HTTP 401/403/404, Port zu, DNS | `.failed(Systemtext)` → Fehleransicht | opening, buffering, **error, stopped** (selbe ms) → `.idle` → **Ladekreis ohne Ende** |
| HTML statt Medium | `.failed` → Fehleransicht | opening, buffering, playing, **paused** → `.loading` oder `.playing` → Ladekreis bzw. Schwarz |
| Verbindung angenommen, keine Daten | `.loading` → nach ≈ 40 s (HLS) / 120 s (MP4) `.failed` | buffering → `.playing` → Schwarz, Steuerung, unbegrenzt |
| Abbruch mitten im Stream | Live-HLS: `.playing` (Standbild) → nach ≈ 31 s `.failed` | **paused** → bleibt `.playing` → Standbild |
| VOD zu Ende | bleibt `.playing` (Rate 0) | ended → `.idle` → Ladekreis *(gelesen)* |
| Pause | Rate 0, `.playing`, `isPaused` | paused, `.playing`, `isPaused` |
| Pause vor Spielbeginn | wirkt | **wirkt nicht**, `isPaused = true`, VLC spielt danach |

### Beteiligte Typen

| Typ | Datei | Rolle in B06 |
|---|---|---|
| `PlayerView` | `Views/PlayerView.swift` | Ansicht, Zustand der Oberfläche, Tastatur, Vollbild, Fehleransicht, Start/Pause |
| `PlaybackEngine`, `PlaybackState`, `StreamType`, `PlaybackEngineFactory` | `Services/PlaybackEngine.swift` | Protokoll, gemeinsamer Zustand, Engine-Wahl |
| `AVKitPlaybackEngine` | `Services/AVKitPlaybackEngine.swift:1-149` | HLS/MP4 über `AVPlayer`; PiP-Teil → B07 |
| `PlayerLayerView`, `PlayerLayerHostView` | `Services/PlayerLayerView.swift` | bettet den `AVPlayerLayer` ein, hält den Frame synchron |
| `VLCPlaybackEngine`, `VLCPlayerSurface`, `VLCDrawableView` | `Services/VLCPlaybackEngine.swift` | rohes MPEG-TS über VLCKit (`VLCKitSPM` 3.6.0, libVLC 3.0.21) |
| `StreamURLResolver` | `Services/StreamURLResolver.swift` | abspielbare Adresse, Meldungen bei fehlenden Zugangsdaten (B01) |
| `XtreamStreamAddress`, `XtreamURLEncoding`, `XtreamCredentialStore` | `Services/XtreamCodes.swift:175-224`, `Services/XtreamCredentialStore.swift` | Adressbildung und Schlüsselbund (B01), hier nur gelesen |
| `ChannelListView`, `FavoritesView` | `Views/` | Einstiege (B04, B05) |

## Datenmodell

B06 führt **keine** Felder ein und schreibt nichts in die Datenbank. Keine Schemaänderung, keine Migration.

### Gelesen

| Entität | Feld | Wofür |
|---|---|---|
| `Channel` | `name` | Titel der Navigationsleiste bzw. des Fensters |
| `Channel` | `streamURL` | Grundlage der abspielbaren Adresse; Endung entscheidet über den README-Hinweis (FB-04) |
| `Channel` | `playlist` | Resolver: Xtream oder nicht |
| `Playlist` | `isXtream`, `sourceURL`, `id` | Resolver: Altbestand erkennen, Schlüsselbund-Eintrag finden |

### Außerhalb des Schemas

| Ort | Inhalt | Entsteht durch |
|---|---|---|
| Schlüsselbund, Dienst `lu.daumedia.MikaPlusPlayer.xtream`, Konto `Playlist.id` | Host, Benutzer, Passwort (nur gelesen) | B01 |
| `UserDefaults` der App, Schlüssel `VLCParams` | Startparameter von VLCKit (`--verbose=4`, `--vout=macosx`, `--extraintf=macosx_dialog_provider` …) | VLCKit beim ersten Erzeugen eines Players (belegt unter der Sonden-ID) |
| `~/Library/Preferences/<Bundle-ID>/vlcrc` (macOS) | Konfigurationsdatei von libVLC, 88 KB, Inhalt nicht untersucht | libVLC beim ersten Abspielen (belegt unter der Sonden-ID) |
| Arbeitsspeicher der Engine | abspielbare Adresse **mit** Zugangsdaten, Puffer | `load(url)`, so lange die Engine lebt (FB-02) |

### Nicht persistiert

Lautstärke, Stumm, Pause, Vollbild, Sichtbarkeit der Steuerung, HUD, zuletzt gesehener Sender. Jeder neue Player
beginnt bei 100 %, nicht stumm, nicht im Vollbild. Der HTTP-Cache bleibt leer (belegt).

## Zugriffsregeln

Die App hat keine Konten und keine Rollen. B06 hat keine gespeicherten Daten mit Zugriffsregeln.

| Wer | Darf lesen | Darf schreiben | Erzwungen durch |
|---|---|---|---|
| Nutzer der App | sieht Bild, Sendername, Fehlermeldung; nie Adresse oder Zugangsdaten (AK-31) | steuert Wiedergabe | Oberfläche |
| Zuschauer am Bildschirm | Bild und Sendername | — | nichts |
| andere Prozesse desselben Benutzers (macOS) | ⚠ Speicher der App samt Adresse mit Zugangsdaten, wenn sie Debug-Rechte haben (vgl. B09 BF-02) | — | Sandbox aus (`MikaPlusPlayer.entitlements:7-8`) |
| Inhalte des Streams (libVLC im Prozess der App) | ⚠ bei einer ausnutzbaren Lücke alles, was der Benutzer darf | ebenso | nichts: Sandbox und Library Validation aus (FB-03) |
| Mitleser im Netz | Adresse samt Zugangsdaten bei `http://` | — | Schema aus dem Host (B01), `NSAllowsArbitraryLoads` (`Info.plist:37-41`) |
| Anbieter | Zugangsdaten, IP-Adresse, Sender, User-Agent mit Systemversion und Sprache | — | protokollbedingt |

## Missbrauchsschutz

| Stelle | Limit | Verhalten bei Überschreitung | Wo konfiguriert |
|---|---|---|---|
| Warten auf erste Daten, AVKit HLS | ≈ 40 s (System) | „resource unavailable" | AVFoundation, nicht die App |
| Warten auf erste Daten, AVKit MP4 | ≈ 120 s (System) | „The operation could not be completed" | AVFoundation |
| Abbruch im Live-HLS | ≈ 31 s (System) | „The network connection was lost." | AVFoundation |
| Warten, Abbruch, HTTP-Fehler, VLC | **keins** | Ladekreis, Schwarz oder Standbild ohne Ende (FB-01) | — |
| „Erneut versuchen" | keins; eine neue Anfrage je Betätigung | — | `PlayerView.swift:225-227, 250-257` |
| Gleichzeitige Verbindungen zum Anbieter | keins; verlassene Engines halten Verbindungen (FB-02) | zweite Verbindung beim nächsten Sender | — |
| Hintergrund (iOS) | keins | AVKit spielt weiter (AK-30) | `Info.plist:63-66` |
| Inhalt des Streams | nur Dateiendung; keine Prüfung von Schema, Host, Größe | Übergabe an AVFoundation bzw. libVLC (FB-03) | `PlaybackEngine.swift:13-19, 99-108` |

## Externe Dienste

| Dienst | Wofür | Was geht hin | Was wird vorher entfernt |
|---|---|---|---|
| Host der Stream-Adresse (Xtream-Anbieter) | Stream | Pfad `/live/<Benutzer>/<Passwort>/<id>.<ext>`; bei HLS alle 2 s Playlist und jedes Segment mit derselben Pfadbasis; IP-Adresse; User-Agent `AppleCoreMedia/… (Macintosh; U; Intel Mac OS X 27_0; de_de)` bzw. `VLC/3.0.21 LibVLC/3.0.21`; VLC: `Range: bytes=0-` | nichts |
| Host einer M3U-Adresse (beliebig, auch lokales Netz, `file://`) | Stream | die Adresse unverändert, samt Benutzerinfo und Query-Token | nichts |
| Weitere Hosts aus HLS-Playlists (absolute Segment-Adressen) | Segmente | wie oben; bestimmt der Anbieter *(gelesen, AVFoundation-Standard)* | nichts |

Kein daumedia-Server, keine Analyse, kein Fehler-Tracking, keine Protokollierung durch die App (AK-33).

## Plattformunterschiede

| Thema | iOS | macOS |
|---|---|---|
| Vollbild | Leisten, Statusleiste, System-Overlays aus; iPhone: Querformat rechts erzwungen, zurück Hochformat | natives Fenster-Vollbild des Schlüsselfensters; Symbolleiste nur bei Hover |
| Hover am oberen Rand | — | blendet Steuerung und Symbolleiste im Vollbild ein |
| Tastatur | nur mit Hardware-Tastatur *(gelesen)* | Standard; unbelegte Tasten erzeugen den Warnton |
| Audio-Sitzung | AVKit aktiviert `.playback`; VLC keine | keine `AVAudioSession` |
| Hintergrund | `UIBackgroundModes audio`, AVKit spielt weiter | App läuft weiter wie jedes Fenster |
| Zeichenfläche VLC | `UIView` | `NSView` mit schwarzer Ebene |

## Erkennbare Entscheidungen

| # | Entscheidung | Alternative | Warum so |
|---|---|---|---|
| 1 | Protokoll `PlaybackEngine` + Factory; Views sprechen nur `any PlaybackEngine` | Player-Ansicht direkt mit AVKit bzw. VLCKit | Kommentar `PlaybackEngine.swift:30-34`, CLAUDE.md: neue Engine = Klasse + Eintrag in der Factory |
| 2 | Engine-Wahl nur nach Dateiendung, `.m3u` zählt als HLS | Inhaltstyp (HEAD-Anfrage, MIME) prüfen; bei Fehler auf die andere Engine ausweichen | CLAUDE.md, README, Website; Grund für `.m3u` nicht erkennbar (EC-02, OF-04) |
| 3 | VLCKit als SPM-Binärpaket eines Dritten, exakt 3.6.0 gepinnt, hinter `canImport` | offizielles VLCKit von VideoLAN (CocoaPods) oder regelmäßig aktualisieren | README: ein Paket für iOS und macOS, App baut auch ohne; Pin-Grund und fehlende Aktualisierung nicht erkennbar (FB-03) |
| 4 | Nur `isPaused` in der App, `PlaybackState` ohne `.paused` | Zustand aus Rate bzw. VLC-Zustand ableiten | Kommentar `PlaybackEngine.swift:38`: „bewusst kein .paused"; Folge EC-05, B07 FB-04 |
| 5 | ⚠ VLC-Zustand im Delegate später aus `mediaPlayer.state` lesen | Zustand aus der Benachrichtigung übernehmen; `.buffering` getrennt; Zeitgrenze | Kommentar `VLCPlaybackEngine.swift:81-82`: Delegate nicht garantiert auf dem MainActor. Dass dabei `error` verloren geht, wurde offenbar nicht bedacht (FB-01) |
| 6 | ⚠ Beim Verlassen nur `pause()`, kein `stop()`, Engine als `@State` | Engine beim Verschwinden stoppen und freigeben; `stop()` im Protokoll | Kommentar zu PiP `PlayerView.swift:87-88` (B07); `MultiviewSession.swift:69-70` kennt die Lücke (FB-02) |
| 7 | Vollbild „in place" statt eigener Vollbild-Ansicht | `fullScreenCover` bzw. eigenes Fenster | CLAUDE.md: VLC hat nur eine Zeichenfläche, keine zweite Player-Instanz |
| 8 | ⚠ macOS-Vollbild über `NSApp.keyWindow ?? mainWindow` und eigenes `isFullscreen` | Fenster der Ansicht ermitteln, Vollbild-Benachrichtigungen des Fensters beobachten | Grund nicht erkennbar (FB-06, AS-03) |
| 9 | ⚠ iPhone: fest `.landscapeRight`, zurück fest `.portrait` | `.landscape` anfordern, vorherige Ausrichtung merken | Grund nicht erkennbar (OF-03, AS-04) |
| 10 | Fehleransicht zeigt `localizedDescription` ungefiltert | eigene deutsche Meldungen je Fehlerart | Grund nicht erkennbar (OF-01) |
| 11 | ⚠ README-Hinweis nach Endung der gespeicherten Adresse | Hinweis nur, wenn VLCKit fehlt (Kompilierbedingung) | stammt aus der Zeit, als VLCKit optional war (README „Ohne VLCKit"); nicht nachgezogen (FB-04, DS-06) |
| 12 | Auto-Ausblenden ab `onAppear`, nicht ab Spielbeginn | Timer beim Übergang nach `.playing` starten | Grund nicht erkennbar; lokal kaum spürbar |
| 13 | Lautstärke > 0 hebt Stumm auf, auch bei „leiser" | nur bei „lauter" aufheben | Kommentar `PlaybackEngine.swift:55` (OF-02) |
| 14 | `.handled` für belegte Tasten, unbelegte gehen weiter (Warnton) | alle Tasten schlucken | Kommentar `PlayerView.swift:317`; Systemverhalten beibehalten |
| 15 | Resolver als einziger Ort der abspielbaren Adresse, Aufruf bei jedem Start und „Erneut versuchen" | Adresse beim Import speichern | Reparatur B01 BUG-01: keine Zugangsdaten in der Datenbank |
| 16 | AVKit-Engine besitzt `AVPlayerLayer` statt SwiftUI-`VideoPlayer` | `VideoPlayer` mit Systemsteuerung | für Bild-in-Bild (B07); README beschreibt noch `AVKit.VideoPlayer` |

## Abdeckung der Akzeptanzkriterien

Umgedreht: Was erfüllt das Kriterium heute? Fundstellen in `Sources/`, Stand siehe Kopfzeile.

| AK | Erfüllt durch | Anmerkung |
|---|---|---|
| AK-01 | `ChannelListView.swift:39-41`, `FavoritesView.swift:42-44`; `PlayerView.swift:41-55, 66-72, 78-82, 423-434`; `AVKitPlaybackEngine.swift:13-15, 35-43`; `VLCPlaybackEngine.swift:26-28, 40-46` | Startwerte 100 %, nicht stumm |
| AK-02 | `PlaybackEngine.swift:13-19, 97-118` | nur `pathExtension` |
| AK-03 | `StreamURLResolver.swift:24-35`; `XtreamCodes.swift:184-186, 209-214`; `PlayerView.swift:239-248, 426` | Engine-Wahl an der aufgelösten Adresse |
| AK-04 | `StreamURLResolver.swift:10-21, 30-33`; `PlayerView.swift:50-51, 239-257` | Resolver-Fehler vor jeder Engine |
| AK-05 | `AVKitPlaybackEngine.swift:35-43, 115-132`; `PlayerView.swift:97-109, 112-114` | Playlist-Takt bestimmt AVFoundation |
| AK-06 | `AVKitPlaybackEngine.swift:123-126, 135-142`; `PlayerView.swift:104-105, 214-232` | Zeiten und Texte vom System |
| AK-07 | AVFoundation (Wiederholung des Abrufs) | kein App-Code |
| AK-08 | `PlayerView.swift:225-227, 250-257`; `AVKitPlaybackEngine.swift:35-43` | ohne Drosselung |
| AK-09 | `PlaybackEngine.swift:16, 101-104`; `VLCPlaybackEngine.swift:40-46, 85-88` | `.buffering` gilt als spielend |
| AK-10 | `VLCPlaybackEngine.swift:80-99` (`.error` wird von `.stopped` überholt → `.idle`); `PlayerView.swift:100-103` | ⚠ FB-01 |
| AK-11 | `VLCPlaybackEngine.swift:85-88, 95-96` | ⚠ FB-01 |
| AK-12 | `VLCPlaybackEngine.swift:95-96` (`.paused` ignoriert) | ⚠ FB-01 |
| AK-13 | `PlayerView.swift:104-105, 114, 214-236` | ⚠ FB-04 |
| AK-14 | `PlayerView.swift:57, 81, 112-164, 262-268, 291-304, 309-310, 374-377` | Auto-Ausblenden ab `onAppear` |
| AK-15 | `PlayerView.swift:145-148, 172-175, 348-353`; `AVKitPlaybackEngine.swift:45-47`; `VLCPlaybackEngine.swift:48-50` | |
| AK-16 | `PlayerView.swift:149-152, 176-179, 355-360`; `AVKitPlaybackEngine.swift:55-57`; `VLCPlaybackEngine.swift:58-70` | |
| AK-17 | `PlayerView.swift:32, 180-212, 322-325, 339-342, 367-371`; `AVKitPlaybackEngine.swift:49-53`; `VLCPlaybackEngine.swift:52-56, 65-70` | ↓ hebt Stumm auf (OF-02) |
| AK-18 | `PlayerView.swift:58-61, 318-346` | Warnton durch AppKit bei `.ignored` |
| AK-19 | `PlayerView.swift:60, 81, 312` | Fokus bei `onAppear` und nach jedem Vollbildwechsel |
| AK-20 | `PlayerView.swift:337-338, 362-365`; `PlaybackEngine.swift:85-94` | P selbst → B07 |
| AK-21 | `PlayerView.swift:65-66, 76, 127-133, 155, 306-313, 326-327, 399-404, 408-411` | natives Vollbild |
| AK-22 | `PlayerView.swift:63, 262-288` | nicht bedient |
| AK-23 | `PlayerView.swift:399-404` | ⚠ FB-06 (AS-03) |
| AK-24 | `PlayerView.swift:20, 306-313, 399-404` (kein Abgleich mit dem Fenster) | ⚠ FB-06 |
| AK-25 | `PlayerView.swift:69-72, 393-398, 408-418` | ⚠ OF-03 (AS-04); `Info.plist:48-53` erlaubt beide Querformate |
| AK-26 | `PlayerView.swift:395` (`userInterfaceIdiom == .phone`) | nicht ausgeführt |
| AK-27 | `PlayerView.swift:83-92, 431-433` | TabView behält den Stapel |
| AK-28 | `PlayerView.swift:17, 83-92`; `PlaybackEngine.swift:35-81` (kein `stop`); `AVKitPlaybackEngine.swift:145-148` | ⚠ FB-02 |
| AK-29 | `VLCPlaybackEngine.swift:49` | ⚠ FB-02 |
| AK-30 | `Info.plist:63-66`; `AVKitPlaybackEngine.swift:105-111`; `VLCPlaybackEngine.swift` ohne Audio-Sitzung | OF-05; AVKit belegt in B07 |
| AK-31 | `StreamURLResolver.swift:14-21`; `XtreamCredentialStore.swift:36-43`; Systemtexte ohne Adresse; VLC ohne Text | nur für geprüfte Fehlerarten belegt |
| AK-32 | `StreamURLResolver.swift:30-34`; `XtreamCodes.swift:209-214`; AVFoundation/libVLC | Protokoll verlangt Zugangsdaten im Pfad |
| AK-33 | kein `print`/`Logger`/`os_log`/`NSLog` in B06-Dateien; System redigiert Adressen | Test-Host abweichend (EC-10) |
| AK-34 | keine Schreibzugriffe in `PlayerView`/Engines; `VLCParams` und `vlcrc` schreibt VLCKit/libVLC selbst | |
| AK-35 | `project.yml:17-19, 58-60, 75-77`; `VLCPlaybackEngine.swift:40-46`; `PlaybackEngine.swift:13-19`; `MikaPlusPlayer.entitlements:7-12` | ⚠ FB-03 |

### Code ohne AK-Zuordnung

- **`VLCPlaybackEngine`: Zweig `.error` → „VLC konnte den Stream nicht abspielen."** (`VLCPlaybackEngine.swift:91-92`):
  in keinem geprüften Fall erreicht (FB-01), praktisch toter Code.
- **`PlaybackEngineFactory`: AVKit-Rückfall ohne VLCKit** (`PlaybackEngine.swift:104, 112-118`): im Build immer
  VLC, weil `VLCKitSPM` an beiden Targets hängt. Verhalten nur aus EC-03 abgeleitet.
- **`PlayerLayerView` für iOS** (`PlayerLayerView.swift:14-51`): im iPhone-Simulator mitgelaufen, nicht eigens geprüft.
- **`AVKitPlaybackEngine.state = .loading` bei `.unknown`** (`AVKitPlaybackEngine.swift:127-130`): nur beim Start beobachtet.
- **README-Abschnitt „Wiedergabe mit `AVKit.VideoPlayer`"**: beschreibt eine Ansicht, die es nicht mehr gibt
  (Entscheidung 16).

### Bestehende Tests

`Tests/PlaybackEngineTests.swift`, 6 Tests, nur macOS-Target, nur `AVKitPlaybackEngine`, ohne Stream. Am
2026-09-16 in der Kopie grün.

| Test | Prüft | Deckt |
|---|---|---|
| `testSetVolumeClampsToUnitRange` | 0…1-Begrenzung | AK-17 teilweise |
| `testRaisingVolumeUnmutes` | Lautstärke > 0 hebt Stumm auf | AK-17 teilweise |
| `testToggleMuteFlips` | Stumm umschalten | AK-16 teilweise |
| `testTogglePlayPauseFlipsIsPaused` | `isPaused` umschalten | AK-15 teilweise |
| `testPictureInPictureInactiveInitially`, `testTogglePictureInPictureIsSafeWithoutOnscreenLayer` | Ruhezustand PiP | B07 |

Ohne Test: `StreamType`/Factory, die VLC-Engine insgesamt, alle Zustandsübergänge und Fehler, Resolver im Player,
Tastatur, HUD, Auto-Ausblenden, Vollbild, Verlassen und Freigabe. Die Sonde (`qa-erfassung/sonde.patch`,
`Tests/B06/B06EngineProbeTests.swift`) zeigt, wie sich Engine-Wahl, Zustände und Freigabe gegen einen lokalen
Mock prüfen lassen.
