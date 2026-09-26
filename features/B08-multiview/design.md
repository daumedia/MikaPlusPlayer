# B08 · Multiview — Systemdesign

Status: `rekonstruiert` · Stand: `c01f1cf` + Reparatur B01 (2026-09-16) · Rekonstruktion aus dem Code (sdd-erfassen), erstellt 2026-09-16 · Stack-Profil: `swiftui-macos` (XcodeGen-Target `MikaPlusPlayer-macOS`)

**Kein Code in diesem Dokument.** Beschrieben ist der Aufbau, wie er in der eingefrorenen Kopie
(`c01f1cf` + Reparatur B01) steht, nicht, wie er sein sollte. Fragwürdiges ist markiert und verweist auf den
*Fehlbestand* in `spec.md`. Zeilenangaben beziehen sich auf diesen Stand unter `Sources/`.

## Überblick

Multiview gibt es nur auf macOS; alle beteiligten Typen stehen hinter `#if os(macOS)`. Die App erzeugt beim
Start **eine** `MultiviewSession` als `@State` und reicht sie per Environment an jedes Hauptfenster und an
das einzelne Fenster „Multiview". Der ⊞-Button in jeder Senderkarte ruft `session.add(channel)` und öffnet
das Fenster. `add` bildet die abspielbare Adresse über den `StreamURLResolver` (bei Xtream mit Zugangsdaten
aus dem Schlüsselbund), lässt die `PlaybackEngineFactory` eine Engine wählen (VLC für `.ts`, sonst AVKit),
startet sie sofort und legt einen `Slot` aus Sender und Engine an. Die Session setzt den Ton-Fokus: Nur die
Engine an `focusedIndex` ist nicht stumm. `MultiviewScreen` zeichnet die Slots als Fokus-Layout oder Raster,
jede Kachel ist ein `MultiviewTile` mit der Plattform-Ansicht der Engine. Entfernen und Schließen pausieren
die Engines und werfen die Slots weg; erst das Freigeben der Engine beendet die Verbindung. Gespeichert wird
nichts.

## Szenen und Einstiege

SwiftUI, keine Routen.

| Einstieg | Zweck | Zugang |
|---|---|---|
| ⊞-Button in `ChannelRowView` (Senderliste B04, Favoriten-Tab B05) | Sender hinzufügen, Fenster öffnen bzw. nach vorn holen | jeder Nutzer des Geräts; abgeblendet bei vier Streams (⚠ Klick geht an die Karte, FB-03) |
| Menü „Window › Multiview" | Fenster öffnen, ggf. leer | automatisch von SwiftUI für die `Window`-Szene angelegt (widerspricht `docs/app-shell.md` AS-05) |
| `Window("Multiview", id: "multiview")` | das einzige Multiview-Fenster, 1280 × 720 pt Standardgröße, Größe durch Inhalt nach unten begrenzt | `MikaPlusPlayerApp.swift:52-58` |

Kein Tastenkürzel, kein Deep Link, kein iOS-Gegenstück.

## Komponentenstruktur

```
MikaPlusPlayerApp                                   App/MikaPlusPlayerApp.swift
├── @State multiview = MultiviewSession()           :25, lebt so lange wie die App
├── WindowGroup (mehrere Hauptfenster möglich)      :29-46
│   └── ContentView .environment(multiview)         :32
│       └── … ChannelListView / FavoritesView
│           └── NavigationLink(value: channel)      ChannelListView.swift:111-113, FavoritesView.swift:24-26
│               └── ChannelRowView                  Views/ChannelRowView.swift
│                   └── multiviewButton             :73-85  Symbol rectangle.split.2x2, .title3
│                       Aktion: multiview.add(channel); openWindow(id: "multiview")
│                       .disabled(!canAddMore) ⚠ FB-03 · Tooltip „Zu Multiview hinzufügen" / „Multiview voll (max. 4)"
└── Window("Multiview", id: "multiview")            :52-58, .modelContainer, .windowResizability(.contentMinSize)
    └── MultiviewScreen .environment(multiview)     Views/MultiviewScreen.swift
        ├── ZStack: Color.black
        │   ├── [leer]  ContentUnavailableView       :97-103  „Kein Stream im Multiview" + Hinweis
        │   └── [sonst] content nach session.layout  :30-35
        │       ├── focusLayout                     :39-65
        │       │   ├── MultiviewTile(slots[focusedIndex], isFocused: true, onFocus: {})   ⚠ ohne .id je Slot (FB-02)
        │       │   └── .overlay(.topTrailing) VStack(spacing 8), padding 16                 ⚠ verdeckt das X (FB-04)
        │       │       └── je nicht fokussiertem Slot: MultiviewTile 240 × 135, cardRadius 12, Schatten 8
        │       └── gridLayout                      :69-93   ⚠ Absturz bei sinkender Zeilenzahl (FB-01)
        │           count / columns (1 bei ≤ 1, sonst 2) / rows einmal berechnet
        │           └── Grid(4, 4) › ForEach(0..<rows, id: \.self) › GridRow › ForEach(0..<columns)
        │               └── index < count ? MultiviewTile(session.slots[index]) (:79) : Color.clear
        ├── .navigationTitle("Multiview")           :21
        ├── .toolbar(.principal) layoutPicker       :105-117  segmentiert „Fokus | Raster", .disabled(slots.count < 2)
        └── .onDisappear { session.clear() }        :26  Schließen des Fensters leert die Session für alle Fenster

MultiviewTile                                       Views/MultiviewTile.swift
├── ZStack
│   ├── Color.black
│   ├── slot.engine.makePlayerView()                :17  .allowsHitTesting(isFocused)
│   ├── stateOverlay                                :34-50  .loading/.idle → ProgressView · .failed → „Wiedergabe fehlgeschlagen" + Text · .playing → nichts
│   └── chrome                                      :53-75  PlayerBadge(Lautsprecher-Symbol, Sendername, tinted: isFocused) · X-Button „Stream entfernen"
├── .overlay: 2 pt Rahmen playerAccent, wenn fokussiert   :24-27
└── .onTapGesture { if !isFocused { onFocus() } }  :28-29
```

### Beteiligte Typen

| Typ | Datei | Rolle in B08 |
|---|---|---|
| `MultiviewLayout` | `Services/MultiviewSession.swift:7-21` | `focus` („Fokus"), `grid` („Raster") |
| `MultiviewSession` | `Services/MultiviewSession.swift:30-102` | `@MainActor @Observable`; `slots`, `focusedIndex`, `layout`; `add`, `remove`, `setFocus`, `clear`, `enforceAudioFocus` |
| `MultiviewSession.Slot` | `:37-41` | `id` (neue `UUID` je Hinzufügen), `channel` (das `Channel`-Objekt selbst), `engine` |
| `MultiviewScreen` | `Views/MultiviewScreen.swift` | Fenster-Inhalt, Layouts, Umschalter, Leerzustand, Leeren beim Verschwinden |
| `MultiviewTile` | `Views/MultiviewTile.swift` | eine Kachel |
| `ChannelRowView.multiviewButton` | `Views/ChannelRowView.swift:73-85` | Einstieg |
| `StreamURLResolver` | `Services/StreamURLResolver.swift:24-35` | abspielbare Adresse; wirft bei fehlenden Zugangsdaten, `add` verschluckt das (`try?`) |
| `PlaybackEngineFactory`, `AVKitPlaybackEngine`, `VLCPlaybackEngine` | `Services/PlaybackEngine.swift:97-119`, `AVKitPlaybackEngine.swift`, `VLCPlaybackEngine.swift` | Engines (B06); `setMuted(_:)` eigens für den Ton-Fokus eingeführt (`PlaybackEngine.swift:52-54`) |
| `VLCPlayerSurface` | `Services/VLCPlaybackEngine.swift:121-129` | bettet die **eine** Zeichenfläche der VLC-Engine ein; `updateNSView` leer ⚠ FB-02 |
| `PlayerLayerView` | `Services/PlayerLayerView.swift:56-66` | bettet den `AVPlayerLayer` ein und hängt ihn bei jeder Aktualisierung neu an |

### Abläufe

```
⊞ angeklickt                                        ChannelRowView :74-77
  ├── MultiviewSession.add(channel)                 :54-67
  │   ├── guard slots.count < 4                     sonst nichts (Button ist dann ohnehin deaktiviert)
  │   ├── guard let url = try? StreamURLResolver.playableURL(for:)   sonst nichts, ohne Meldung (AK-07)
  │   ├── engine = PlaybackEngineFactory.engine(for: url)            .ts/.mpegts/.mts/.m2ts → VLC, sonst AVKit
  │   ├── engine.load(url)                          Wiedergabe startet sofort, eine Verbindung je Slot
  │   ├── engine.setMuted(!isFirst)
  │   ├── slots.append(Slot(channel, engine))
  │   └── enforceAudioFocus()                       nur slots[focusedIndex] nicht stumm
  └── openWindow(id: "multiview")                   immer, auch wenn nichts hinzugefügt wurde

Klick auf nicht fokussierte Kachel → setFocus(index) :83-87 → focusedIndex = index → enforceAudioFocus()
X „Stream entfernen" → remove(slot.id)             :71-80
  ├── engine.pause()                                VLC pausiert nur, wenn isPlaying (VLCPlaybackEngine :49)
  ├── slots.remove(at:) → letzte Referenz auf die Engine fällt → Engine frei → Verbindung zu
  ├── index < focusedIndex → focusedIndex − 1      Fokus folgt demselben Stream
  ├── focusedIndex = min(focusedIndex, count − 1)   entfernter Fokus → Nachfolger bzw. Vorgänger
  └── enforceAudioFocus()
Fenster schließen → onDisappear → clear()           :90-94  pause alle, removeAll, focusedIndex = 0; layout bleibt
```

## Datenmodell

B08 hat **kein persistentes Datenmodell**, keine Schemaänderung und schreibt nichts in die Datenbank, den
Schlüsselbund oder eigene Einstellungen. Eine Migration ist nicht nötig.

### Laufzeitzustand `MultiviewSession` (flüchtig, `@Observable`)

| Feld | Typ | Pflicht | Bedeutung |
|---|---|---|---|
| `maxSlots` | `static Int` | — | `4` |
| `slots` | `[Slot]` | ja | Reihenfolge des Hinzufügens; `private(set)` |
| `focusedIndex` | `Int` | ja | Index des Streams mit Ton und, im Fokus-Layout, des großen Bildes; `0` bei leerer Session |
| `layout` | `MultiviewLayout` | ja | `.focus` beim App-Start; `clear()` setzt es **nicht** zurück |
| `Slot.id` | `UUID` | ja | Identität der Kachel, unabhängig vom Sender; derselbe Sender zweimal ergibt zwei IDs |
| `Slot.channel` | `Channel` (SwiftData-Objekt) | ja | gelesen werden nur `name` (Etikett) und beim Hinzufügen `streamURL`, `playlist` (Resolver) |
| `Slot.engine` | `any PlaybackEngine` | ja | besitzt die Verbindung; einzige starke Referenz außerhalb der Ansichten |

Gelesen, nicht geschrieben: `Channel.name`, `Channel.streamURL`, `Channel.playlist` (`isXtream`, `id`,
`sourceURL`), der Schlüsselbund-Eintrag der Playlist (über `XtreamCredentialStore.load`).

⚠ Der Slot hält das `Channel`-Objekt und eine bereits geladene Adresse. Löschen und Aktualisieren in B03
ersetzen oder entfernen diese Objekte, ohne die Session zu benachrichtigen (DM-10, FB-05). Beobachtet: Nach
dem Löschen hat das Objekt keinen `modelContext` mehr, `isDeleted` bleibt `false`, `name` ist lesbar.

Außerhalb der App speichert macOS Größe und Lage des Fensters „Multiview" (Fenster-Autosave der Szene).

## Zugriffsregeln

Keine Konten, keine Rollen. B08 hat keine eigenen Daten mit Zugriffsregeln.

| Wer | Darf lesen | Darf schreiben | Erzwungen durch |
|---|---|---|---|
| Nutzer der App, jedes Hauptfenster | die gemeinsame Session: Belegung, Fokus, Layout | hinzufügen, fokussieren, entfernen, leeren | nichts, Einzelnutzer; eine Instanz auf App-Ebene |
| Betrachter des Bildschirms | welche Sender gleichzeitig laufen | — | nichts |
| IPTV-Anbieter | je Kachel eine Verbindung, bei Xtream mit Benutzername und Passwort im Pfad | — | protokollbedingt; ⚠ nach dem Löschen der Playlist weiter (FB-05) |
| Mitleser im Netz | Stream-Adressen samt Zugangsdaten bei `http://` | — | Transport gehört zu B01 |

## Missbrauchsschutz

| Stelle | Limit | Verhalten bei Überschreitung | Wo konfiguriert |
|---|---|---|---|
| Streams im Multiview | 4 | ⊞ abgeblendet, `add` tut nichts; ⚠ Klick auf den abgeblendeten Button öffnet den Player (FB-03) | `MultiviewSession.swift:34, 49, 55`; `ChannelRowView.swift:80-84` |
| Verbindungen je Anbieterkonto | **keins** | jede Kachel eine eigene Verbindung, auch für denselben Sender; über dem Anbieterlimit endlose Ladeanzeige ohne Meldung (FB-06) | — |
| Verbindungsversuche je Kachel | nur durch VLC: vier Versuche kurz hintereinander, dann Stillstand | keine Wiederholung, kein „Erneut versuchen" | VLCKit-Standard |
| Laufzeit | **keins** | läuft minimiert und ohne Hauptfenster weiter, bis X, Schließen oder App-Ende | — |
| Mehrere Multiview-Fenster | 1 | `Window`-Szene, ein weiteres Öffnen holt das vorhandene nach vorn | `MikaPlusPlayerApp.swift:52` |

## Externe Dienste

| Dienst | Wofür | Was geht hin | Was wird vorher entfernt |
|---|---|---|---|
| Stream-Host des Senders (Xtream-Anbieter oder beliebiger Host aus der M3U) | je Kachel ein Stream, MPEG-TS dauerhaft offen bzw. HLS-Playlist alle ~2 s und Segmente | IP-Adresse, abgerufener Sender; bei Xtream Benutzername und Passwort im Pfad `/live/<benutzer>/<passwort>/<id>.<endung>`; Standard-Kopfzeilen von AVFoundation bzw. VLC (nicht mitgeschnitten) | nichts |

Kein KI-Dienst, keine Analyse, kein Fehler-Tracking, kein Server von daumedia.

## Erkennbare Entscheidungen

| # | Entscheidung | Alternative | Warum so |
|---|---|---|---|
| 1 | Eigenes `Window` statt Ansicht im Hauptfenster | Multiview als Tab oder Navigationsziel | Kommentar `MultiviewScreen.swift:7-8` und `MikaPlusPlayerApp.swift:48-50`: natives Fenster-Vollbild „out of the box"; VLC hat nur eine Zeichenfläche (CLAUDE.md), ein eigenes Fenster vermeidet Konflikte mit dem Player |
| 2 | Eine Session auf App-Ebene für alle Fenster | Session je Hauptfenster | Kommentar `MultiviewSession.swift:26-29`: der ⊞-Button soll dieselbe Instanz wie das Fenster erreichen. Folge: Schließen leert für alle (AS-02) |
| 3 | Höchstens vier Streams | frei wählbar | Kommentar `:33` „2×2-Raster"; Website und Release-Notes nennen vier |
| 4 | Ton nur beim fokussierten Stream, erzwungen nach jeder Änderung über `setMuted` | `toggleMute` je Klick; Lautstärke je Kachel | Kommentar `PlaybackEngine.swift:52-54`: `toggleMute` „könnte aus dem Tritt geraten" |
| 5 | Engine je Slot sofort beim Hinzufügen starten | erst starten, wenn das Fenster sichtbar ist | Grund nicht erkennbar; Folge: Wiedergabe läuft schon, während sich das Fenster öffnet |
| 6 | Stoppen über `pause()` und Freigabe der Referenz | eigenes `stop()`/`deinit` in den Engines | Kommentar `MultiviewSession.swift:69-70` nennt das Fehlen von `stop`/`deinit` ausdrücklich. Die Verbindung endet nur, weil die Engine freigegeben wird (EC-04) |
| 7 | Schließen des Fensters leert die Session (`onDisappear`) | Session bleibt, Fenster öffnet mit alter Belegung | Kommentar `MultiviewScreen.swift:25`: „sonst läuft Audio weiter" |
| 8 | Raster über festen Zeilen-/Spaltenindex und Array-Zugriff im `ForEach` | `ForEach(session.slots)` mit Slot-Identität, `LazyVGrid` | Grund nicht erkennbar; ⚠ Ursache von FB-01 |
| 9 | Große Kachel im Fokus-Layout ohne Slot-Identität, VLC-Oberfläche ohne `updateNSView` | `.id(slot.id)`; Zeichenfläche in `updateNSView` neu einhängen wie bei AVKit | Grund nicht erkennbar; ⚠ Ursache von FB-02 |
| 10 | Nicht fokussierte Videoflächen nehmen keine Klicks an (`allowsHitTesting(isFocused)`) | eigene Klickfläche über dem Video | Kommentar `MultiviewTile.swift:18-19`: damit der Fokus-Tap zuverlässig greift |
| 11 | Kleine Kacheln als Overlay oben rechts über der großen | Seitenleiste neben dem großen Bild | Kommentar `MultiviewSession.swift:8`, `MultiviewScreen.swift:6`: „wie bei Reacts". ⚠ verdeckt das X (FB-04) |
| 12 | Kein Bild-in-Bild im Multiview | Auto-PiP je Kachel | Kommentar `PlaybackEngine.swift:78-79`: konkurrierende Auto-Starts vermeiden |
| 13 | Fehlende Zugangsdaten still ignorieren, Fenster trotzdem öffnen | Meldung, Button deaktivieren | B01-Reparatur, Annahme 16 im Build-Bericht, offen als B01 OF-11 |
| 14 | Keine Tastatursteuerung, keine Fokus-fähige Ansicht | `.focusable` + `.onKeyPress` wie im Player | Grund nicht erkennbar (OF-04) |

## Abdeckung der Akzeptanzkriterien

Umgedreht: Was erfüllt das Kriterium heute? Fundstellen beziehen sich auf `Sources/`.

| AK | Erfüllt durch | Anmerkung |
|---|---|---|
| AK-01 | `ChannelRowView.swift:27-29, 73-85`; `MikaPlusPlayerApp.swift:32, 52-58`; `MultiviewSession.add` | Button in der Karte, die als Ganzes `NavigationLink` ist |
| AK-02 | `MikaPlusPlayerApp.swift:57-58` (`.defaultSize(1280, 720)`), Fenster-Autosave von SwiftUI/AppKit | Autosave ist Systemverhalten |
| AK-03 | `MultiviewSession.swift:59-66, 97-101` | |
| AK-04 | `MultiviewSession.swift:34, 49, 55`; `ChannelRowView.swift:80, 83-84`; Observation aktualisiert alle Fenster | |
| AK-05 | `ChannelRowView.swift:83` (`.disabled`) innerhalb `ChannelListView.swift:111-113` / `FavoritesView.swift:24-26` | ⚠ FB-03 |
| AK-06 | `MultiviewSession.add` ohne Dublettenprüfung; `Slot.id = UUID()` | ⚠ OF-01 |
| AK-07 | `MultiviewSession.swift:57` (`try?` → `return`); `ChannelRowView.swift:76` (`openWindow` unbedingt) | ⚠ OF-02 |
| AK-08 | `MultiviewScreen.swift:15-16, 97-103` | |
| AK-09 | `Window`-Szene `MikaPlusPlayerApp.swift:52`; Menüeintrag erzeugt SwiftUI | widerspricht AS-05 |
| AK-10 | `MultiviewScreen.swift:39-65`; `MultiviewTile.swift:24-27, 53-75`; `PlayerTheme.cardRadius` | |
| AK-11 | `MultiviewScreen.swift:69-93` | |
| AK-12 | `MultiviewScreen.swift:22-24, 105-117`; `MultiviewSession.swift:46, 90-94` (`clear` lässt `layout` stehen) | |
| AK-13 | `MultiviewScreen.swift:116` (`.disabled(slots.count < 2)`) zusammen mit `:69-93` | ⚠ FB-01 |
| AK-14 | `MultiviewTile.swift:20, 28-29`; `MultiviewScreen.swift:44, 54, 83`; `MultiviewSession.setFocus` `:83-87` | Raster gelesen |
| AK-15 | `MultiviewScreen.swift:40-46`; `VLCPlaybackEngine.swift:121-129`; Gegenprobe `PlayerLayerView.swift:63-65` | ⚠ FB-02 |
| AK-16 | `MultiviewScreen.swift:41-46, 47-64`; `MultiviewTile.swift:55-71` | ⚠ FB-04 |
| AK-17 | `MultiviewSession.swift:71-80, 83-87, 97-101` | |
| AK-18 | Ton-Fokus nur in `MultiviewSession`; `PlayerView` hat eine eigene Engine ohne Bezug zur Session | ⚠ OF-05 |
| AK-19 | `MultiviewTile.swift:62-70` → `MultiviewSession.remove` `:71-80`; Freigabe der Engine | |
| AK-20 | `MultiviewScreen.swift:26` → `MultiviewSession.clear` `:90-94` | nur Fokus-Layout, sonst AK-23 |
| AK-21 | `MikaPlusPlayerApp.swift:25, 32, 54` (eine Instanz, zwei Szenen) | AS-02 |
| AK-22 | kein Code, der bei Minimieren oder Schließen der Hauptfenster eingreift | |
| AK-23 | `MultiviewScreen.swift:69-93, 79`; Auslöser `:26`, `MultiviewTile.swift:62-70` | ⚠ FB-01 |
| AK-24 | `MikaPlusPlayerApp.swift:25` (`@State`), keine Persistenz | |
| AK-25 | `MultiviewTile.swift:40-46`; Meldungstext aus `AVKitPlaybackEngine.swift:121-141` | keine Wiederholen-Aktion |
| AK-26 | `MultiviewTile.swift:35-39, 47-48`; Zustandsabbildung `VLCPlaybackEngine.swift:84-96` | ⚠ Ursache B06 FB-01 |
| AK-27 | `MultiviewSession.swift:37-41, 54-67`; `PlaylistImporter.delete` `:270-278` ohne Benachrichtigung | ⚠ FB-05 |
| AK-28 | wie AK-27; `PlaylistImporter.refresh` `:220-266` | ⚠ FB-05 |
| AK-29 | keine `.focusable`/`.onKeyPress` in `MultiviewScreen`/`MultiviewTile`; AppKit-Standard `noResponderFor:` | OF-04 |
| AK-30 | `MultiviewSession.add` (Engine je Slot); `StreamURLResolver.swift:30-34`; `XtreamStreamAddress.playable` | ⚠ FB-06 |
| AK-31 | wie AK-30; `XtreamClient.swift:165-171` (nur `auth` dekodiert); `MultiviewTile.swift:35-39` | ⚠ FB-06 |
| AK-32 | `MultiviewTile.swift:40-46, 56-60` (Name und Engine-Meldung, keine Adresse) | |
| AK-33 | Fehlen jedes Logging-Aufrufs in `Sources/` | mit Vorbehalt (B01 H-2) |
| AK-34 | `MultiviewSession` ohne Persistenz; kein `UserDefaults`-Zugriff | Fenster-Autosave ist Systemverhalten |

### Code ohne AK-Zuordnung

- **`MultiviewSession.isEmpty`** wird nur von `MultiviewScreen.swift:15` benutzt; unauffällig, mit AK-08 gedeckt.
- **`onFocus: {}` der großen Kachel** (`MultiviewScreen.swift:44`): wirkungslos, weil `MultiviewTile` den
  Fokus-Tap für die fokussierte Kachel ohnehin nicht auslöst.
- **Kommentar `MultiviewSession.swift:61-62`** („bei VLC greift er, sobald der Audiokanal nach `.playing`
  existiert"): In VLCKit 3.6.0 ist der Audiokanal schon vorher da; der Wert greift sofort (EC-03). Der erneute
  Aufruf im Delegate schadet nicht.
- **Kommentar `MultiviewScreen.swift:25`** („sonst läuft Audio weiter"): Schon `pause()` allein würde die
  Verbindung nicht beenden (EC-04); tatsächlich beendet sie die Freigabe der Engine.
- **PiP-Controller in HLS-Kacheln** (`AVKitPlaybackEngine.makePlayerView` → `setupPictureInPictureIfNeeded`):
  wird angelegt, nie benutzt (B07 EC-11).

### Bestehende Tests

Keine. Weder `MultiviewSession` noch die Ansichten haben einen Test im Repository. Die Sonde (XCTest T01–T08,
App-Läufe S1–S15) ist nicht eingecheckt; ihr Code liegt als `qa-erfassung/sonde.patch` vor.

### Befunde für andere Dokumente

- `docs/app-shell.md` AS-05 („Multiview nur über den ⊞-Button erreichbar") trifft nicht zu: „Window ›
  Multiview" öffnet das Fenster ebenfalls (AK-09).
- `docs/app-shell.md` *Multiview-Fenster*: „Schließen des Fensters leert die Session und pausiert alle
  Engines" gilt nur im Fokus-Layout; im Raster stürzt die App dabei ab (FB-01).
- `docs/datenmodell.md` DM-10: „Das Verhalten in diesem Fall ist nicht untersucht" ist für das Multiview jetzt
  belegt: kein Absturz, Weiterlaufen mit Zugangsdaten (AK-27, AK-28).
