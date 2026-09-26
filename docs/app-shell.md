# Mika+Player — App-Shell

Stand: 2026-09-15 · rekonstruiert aus `Sources/App/`, den Views und `Sources/Resources/Info.plist`

> Beschreibt das Grundgerüst, wie es heute läuft. Keine Planung.

## Szenen

| Szene | Plattform | Inhalt | Eigenschaften |
|---|---|---|---|
| `WindowGroup` | beide | `ContentView` | `.modelContainer` (gemeinsam), macOS: `.windowResizability(.contentSize)`, `MultiviewSession` per `.environment` |
| `Window("Multiview", id: "multiview")` | nur macOS | `MultiviewScreen` | eigenes Einzelfenster, Standardgröße 1280 × 720, `.contentMinSize`, **dieselbe** `MultiviewSession`-Instanz wie das Hauptfenster |

`MultiviewSession` und `SparkleUpdater` werden auf App-Ebene als `@State` erzeugt (nur macOS) und
leben so lange wie die App. Als `WindowGroup` erlaubt das Hauptfenster auf macOS mehrere Instanzen
(Standardverhalten, nicht eigens konfiguriert); alle teilen sich dieselbe Multiview-Session.

## Navigation

```
ContentView (TabView, tint playerAccent)
├── Tab „Playlists"  (list.and.film)
│   └── NavigationStack
│       └── PlaylistsView ──sheet──▶ ImportPlaylistView (eigener NavigationStack)
│           └── push Playlist ▶ ChannelListView
│               └── push Channel ▶ PlayerView
└── Tab „Favoriten"  (star.fill)
    └── NavigationStack
        └── FavoritesView
            └── push Channel ▶ PlayerView

macOS zusätzlich:
ChannelRowView ⊞ ──openWindow("multiview")──▶ MultiviewScreen (eigenes Fenster)
```

- Navigation ist wertbasiert (`NavigationLink(value:)` + `.navigationDestination(for:)`):
  `Playlist.self` in `PlaylistsView`, `Channel.self` in `ChannelListView` **und** in `FavoritesView`.
- Jeder Tab hat seinen eigenen Stack; ein Tabwechsel behält die Tiefe des anderen Tabs.
- Der Player liegt **im Stack des Tabs**, nicht als Vollbild-Cover. Vollbild wird „in place" gelöst
  (siehe *Player-Chrome*), weil die VLC-Engine nur eine einzige Drawable-View hat.
- Es gibt keine Einstellungen, kein Onboarding, keinen Info-Screen und keine Deep Links.

## Kopfzeilen

| Ansicht | iOS | macOS |
|---|---|---|
| Playlists, Favoriten | Navigationsleiste **ausgeblendet**, stattdessen `PlayerHeader` im Scrollinhalt („MIKA+PLAYER · …" + großer Titel; bei Playlists „+"-Button rechts) | `navigationTitle` in der Fenstertitelleiste, zusätzlich `PlayerHeader` im Inhalt |
| Senderliste | Navigationsleiste sichtbar, Titel `.inline`, Suchfeld über `.searchable`; `PlayerHeader` mit Senderanzahl im Inhalt | Suchfeld in der Fenster-Toolbar, `PlayerHeader` im Inhalt |
| Gruppen-Filter | Chip-Leiste als `safeAreaInset(edge: .top)` auf `.bar`-Material, nur wenn mehr als eine Gruppe existiert | gleich |
| Player | Titel = Sendername, `.inline`; im Vollbild leer | Fenstertitel = Sendername; im Vollbild leer |
| Import-Sheet | Titel „Playlist importieren", „Abbrechen" als `cancellationAction` | gleich, Mindestgröße 420 × 360 |
| Multiview | — | Titel „Multiview", segmentierter Layout-Picker (Fokus/Raster) mittig in der Toolbar, deaktiviert bei weniger als zwei Streams |

## Tab-Leiste

iOS: `.toolbarBackground(.visible, for: .tabBar)`, im Player-Vollbild ausgeblendet.
macOS: System-Darstellung des `TabView` im Fenster; keine eigene Anpassung im Code.

## Menüleiste (macOS)

| Menü | Eintrag | Quelle |
|---|---|---|
| App-Menü, nach „Über …" | „Nach Updates suchen …" — deaktiviert, solange `canCheckForUpdates` falsch ist | `CommandGroup(after: .appInfo)` |
| alle übrigen | System-Standard | — |

Kein Tastenkürzel für das Multiview-Fenster, kein eigener Menüeintrag für Import, Aktualisieren
oder Favoriten. Tastatursteuerung gibt es nur im Player (siehe unten).

## Player-Chrome

| Element | Verhalten |
|---|---|
| Hintergrund | Schwarz, in beiden Modi |
| Steuerung oben rechts | Bild-in-Bild (nur wenn die Engine es unterstützt), Vollbild umschalten |
| Steuerung unten links | Play/Pause, Stumm |
| Sichtbarkeit | nur im Zustand `.playing`; Tap/Klick schaltet um, blendet nach 3,5 s aus; jede Aktion blendet kurz ein. macOS-Vollbild: zusätzlich sichtbar, solange der Zeiger in den oberen 90 pt ist |
| HUD | mittig, 0,9 s: Play/Pause, Stumm, Lautstärke mit Balken und Prozent |
| Laden | weißer Spinner mittig |
| Fehler | `ContentUnavailableView` mit Meldung und „Erneut versuchen" |
| Vollbild iOS | blendet Navigationsleiste, Tab-Leiste, Statusleiste und System-Overlays aus; **iPhone** wechselt per `requestGeometryUpdate` nach Querformat rechts, beim Verlassen zurück nach Hochformat |
| Vollbild macOS | schaltet das **native Fenster-Vollbild** des Schlüsselfensters; Fenster-Toolbar im Vollbild nur bei Hover am oberen Rand |
| Tastatur | Leertaste Play/Pause · ↑/↓ und +/−/= Lautstärke ±5 % · M Stumm · F Vollbild · P Bild-in-Bild · Esc verlässt Vollbild. Fokus wird beim Erscheinen und nach jedem Vollbildwechsel gesetzt |
| Verlassen | pausiert die Wiedergabe — außer Bild-in-Bild ist aktiv; setzt die iPhone-Orientierung zurück |

## Multiview-Fenster (macOS)

Schwarzer Hintergrund. Leer: `ContentUnavailableView` mit Hinweis auf den ⊞-Button. Fokus-Layout:
großer Stream füllt das Fenster, übrige als 240 × 135-Kacheln oben rechts. Raster: 1 Spalte bei
einem Stream, sonst 2. Klick auf eine Kachel macht sie zum Ton-Stream. **Schließen des Fensters
leert die Session** und gibt alle Engines frei — im Fokus-Layout. Im Raster-Layout stürzt die App dabei ab
(„Index out of range", belegt bei der Rückerfassung von B08, dort FB-01). Natives Vollbild über die Fensterknöpfe.

## Fehler und Ladezustände

| Wo | Laden | Fehler |
|---|---|---|
| Playlist-Übersicht (Aktualisieren) | Spinner in der betroffenen Karte | `.alert("Fehler")` |
| Import-Sheet | Formularzeile „Importiere…", Buttons deaktiviert | `.alert("Fehler")` im Sheet; Sheet bleibt offen |
| Senderliste | keiner (synchron aus der DB) | — |
| Player, Multiview-Kachel | Spinner | Fehleransicht über dem Video |

Nach erfolgreichem Import schließt das Sheet von selbst. Eine globale Fehler- oder Toast-Schicht
gibt es nicht.

## Systemintegration (`Info.plist`)

| Schlüssel | Wert | Wirkung |
|---|---|---|
| `CFBundleDisplayName` / `CFBundleName` | „Mika+Player" | Anzeigename; Bundle-/Produktname bleibt `MikaPlusPlayer` |
| `UISupportedInterfaceOrientations` | iPhone: Hochformat, Querformat links/rechts · iPad: alle vier | — |
| `UILaunchScreen` | leer | volle Auflösung ohne Letterbox |
| `UIBackgroundModes` | `audio` | Wiedergabe im Hintergrund/bei Sperre (iOS) |
| `CFBundleDocumentTypes` | M3U Playlist (`public.m3u-playlist`, **`public.text`**), Rang `Default` | App wird als Öffner angeboten — **ein Handler für geöffnete Dateien fehlt im Code** |
| `NSAppTransportSecurity` | `NSAllowsArbitraryLoads = true` | HTTP überall erlaubt |
| `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` | Feed auf `raw.githubusercontent.com/daumedia/…`, EdDSA-Schlüssel, automatisch an | Sparkle (macOS) |

## Auffälligkeiten

| # | Auffälligkeit | Fundstelle |
|---|---|---|
| AS-01 | Dokumenttyp registriert (sogar für `public.text`), aber kein `onOpenURL`/Dokument-Handler — die App bietet sich für beliebige Textdateien als Öffner an und importiert nichts | `Info.plist:68-82` |
| AS-02 | Mehrere Hauptfenster teilen eine Multiview-Session; das Multiview-Fenster leert beim Schließen die Session für alle | `MikaPlusPlayerApp.swift:20-29`, `MultiviewScreen.swift:26` |
| AS-03 | macOS-Vollbild schaltet `NSApp.keyWindow ?? mainWindow` — bei mehreren Fenstern nicht zwingend das Fenster des Players | `PlayerView.swift:376` |
| AS-04 | iPhone-Vollbild erzwingt immer Querformat **rechts** und beim Verlassen Hochformat, unabhängig von der vorherigen Ausrichtung | `PlayerView.swift:370-373` |
| AS-05 | Kein Menüeintrag und kein Tastenkürzel für Import; Multiview ohne eigenes Tastenkürzel, erreichbar über den ⊞-Button und über das System-Menü „Window › Multiview" (korrigiert nach der Rückerfassung von B08) | `MikaPlusPlayerApp.swift:34-41` |
