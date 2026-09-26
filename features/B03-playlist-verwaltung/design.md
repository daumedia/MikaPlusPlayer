# B03 · Playlist-Verwaltung — Systemdesign

Status: `rekonstruiert` · Stand: 2026-09-16 · Rekonstruktion aus dem Code (sdd-erfassen) · Stack-Profil: `swiftui-ios` + `swiftui-macos`

> **Stand: `c01f1cf` + Reparatur B01 (2026-09-16).** Beschrieben ist der Aufbau der eingefrorenen
> Kopie nach der B01-Reparatur 1. Gegenüber `c01f1cf` geändert: `PlaylistsView.delete` ruft
> `PlaylistImporter.delete` (Schlüsselbund), `PlaylistImporter.refresh` liest Zugangsdaten aus dem
> Schlüsselbund, Speicherort und Xtream-Netzwerkschicht stammen aus B01. `attach` ist unverändert.

**Kein Code in diesem Dokument.** Beschrieben ist der Aufbau, wie er steht, nicht, wie er sein
sollte. Fragwürdiges ist markiert und verweist auf den *Fehlbestand* in `spec.md`. Messwerte und
Messumgebung stehen in `spec.md` (AK-37, AK-38).

## Überblick

Die Übersicht ist die Wurzel des Tabs „Playlists". Eine `@Query` liefert alle Playlists nach
Anlagezeitpunkt absteigend; jede erscheint als Karte mit Kontextmenü. „Aktualisieren" startet eine
ungebundene Aufgabe, die einen neuen `PlaylistImporter` auf dem Main-Actor erzeugt. Der Importer
holt die Senderliste neu (M3U über `URLSession.shared`, Xtream über den `XtreamClient` aus B01 mit
Zugangsdaten aus dem Schlüsselbund), merkt sich die Schlüssel der Favoriten, löscht alle Sender der
Playlist einzeln, legt die neuen einzeln mit Beziehung an und speichert. Alles nach dem Abruf läuft
auf dem Main-Thread und wächst quadratisch mit der Senderzahl. „Löschen" ruft ohne Rückfrage
`PlaylistImporter.delete`: Die Playlist wird im Kontext der Ansicht gelöscht (kaskadierend alle
Sender), gespeichert, danach der Schlüsselbund-Eintrag entfernt. Kein anderes Objekt der App wird
über Aktualisieren oder Löschen informiert.

## Szenen und Einstiege

SwiftUI, keine Routen. Plattform in Klammern.

| Einstieg | Zweck | Zugang |
|---|---|---|
| Tab „Playlists" (`ContentView`) → `NavigationStack` → `PlaylistsView` | Übersicht (beide) | jeder Nutzer des Geräts |
| Karte → Kontextmenü (Rechtsklick macOS, langes Drücken iOS) → „Aktualisieren" | Remote-Playlist neu laden (beide) | ebenso |
| Karte → Kontextmenü → „Löschen" | Playlist entfernen (beide) | ebenso |
| Karte antippen → `.navigationDestination(for: Playlist.self)` | Senderliste (B04) | ebenso |
| „+" bzw. „Playlist importieren" → `.sheet` | Import (B01, B02) | ebenso |

Kein Menüleisteneintrag, kein Tastenkürzel, keine Wischgeste, kein Bearbeiten-Modus (AS-05). Jedes
macOS-Hauptfenster hat eine eigene `PlaylistsView` mit eigenem Zustand; alle teilen denselben
`ModelContainer` und dessen Hauptkontext.

## Komponentenstruktur

```
ContentView → Tab „Playlists" → NavigationStack
└── PlaylistsView                                  @Environment modelContext · @Query(sort: createdAt, .reverse)
    │                                              @State showingImport, refreshingID: PersistentIdentifier?  ⚠ FB-03,
    │                                                     errorMessage: String?
    ├── ScrollView (Indikatoren aus, Hintergrund playerBackground)
    │   └── VStack (Abstand 22, oben 8, unten 32)
    │       ├── PlayerHeader „MIKA+PLAYER · PLAYLISTS" / „Playlists"
    │       │   └── Button „+" (.borderedProminent, .small, Akzent) → showingImport = true
    │       ├── [playlists leer] emptyState        list.and.film 44 pt, „Keine Playlists", Hinweistext (OF-04),
    │       │                                      Button „Playlist importieren" → showingImport = true
    │       └── [sonst] LazyVStack (Abstand 10, Rand 20)
    │           └── ForEach(playlists)
    │               └── NavigationLink(value: playlist), Stil .plain
    │                   ├── PlaylistRow(playlist, isRefreshing: refreshingID == playlist.persistentModelID)
    │                   │   ├── Symbol globe (isRemote) | doc     title3, Akzent, 32 pt breit
    │                   │   ├── Name                               headline, eine Zeile
    │                   │   ├── PlayerBadge „<channelCount> Sender"
    │                   │   └── ProgressView | chevron.right       je nach isRefreshing
    │                   └── .contextMenu
    │                       ├── [isRemote] Button „Aktualisieren" (arrow.clockwise)
    │                       │              → Task { await refresh(playlist) }   ungebunden, nie deaktiviert ⚠ FB-04
    │                       └── Button(role: .destructive) „Löschen" (trash)
    │                                      → delete(playlist)                    ohne Rückfrage (OF-01)
    ├── .navigationTitle „Playlists"; iOS: Navigationsleiste ausgeblendet
    ├── .navigationDestination(for: Playlist.self) → ChannelListView (B04)
    ├── .sheet(isPresented: showingImport) → ImportPlaylistView (B01/B02)
    └── .alert „Fehler" (isPresented: errorMessage != nil) · Button „OK" → errorMessage = nil
```

### Ablauf „Aktualisieren"

```
PlaylistsView.refresh(playlist)                         @MainActor
  refreshingID = playlist.persistentModelID  … defer nil          ⚠ FB-03 (ein Wert für alle)
  PlaylistImporter(modelContext:)                       neue Instanz, Schlüsselbund .standard, Grenzen .standard,
                                                        Anmeldebremse .shared
  └── refresh(playlist)                                 @MainActor, keine Sperre gegen Parallelaufrufe ⚠ FB-04
      ├── sourceURL == nil → return (lokale Datei, kein Fehler)
      ├── [isXtream]
      │   ├── XtreamCredentials(legacyPlayerAPIURL:) ≠ nil → Altbestand: diese Zugangsdaten
      │   ├── sonst credentialStore.load(playlist.id) → XtreamSecret | nil → ResolveError.missingCredentials
      │   ├── output = XtreamOutput(rawValue: xtreamOutput) ?? .hls                     (EC-01)
      │   ├── await XtreamClient(credentials, limits, throttle).fetchLiveChannels(output)   (B01: 3 Anfragen,
      │   │                                                     ephemeral ohne Cache, Grenzen, Bremse)
      │   ├── leer → ImportError.emptyPlaylist
      │   └── [Altbestand] credentialStore.save(secret, id); sourceURL = ohne Zugangsdaten   ⚠ FB-08 (auch wenn
      │                                                                                     inzwischen gelöscht)
      ├── [M3U] await fetchText(sourceURL)               URLSession.shared, schreibt Cache ⚠ FB-06 → M3UParser.parse
      ├── leer → ImportError.emptyPlaylist
      │   ── bis hier: bei jedem Fehler bleibt die alte Liste unverändert (AK-18 bis AK-21) ──
      ├── preserved = Set(favoriteKey der Favoriten)     lädt alle Sender (Beziehung)          ⚠ FB-02
      ├── for old in playlist.channels { delete(old) }; channels.removeAll()                    ⚠ FB-01
      ├── attach(parsed, to: playlist, preservedFavorites)                                     ⚠ FB-01
      │   └── je Eintrag: Channel(…, playlist:, playlistID:) · isFavorite = preserved ∋ favoriteKey ·
      │       insert · playlist.channels.append(channel)          (quadratisch)
      │       channelCount = channels.count
      ├── lastRefreshed = Date()
      └── modelContext.save()
  Fehler → errorMessage = localizedDescription → Alert
```

### Ablauf „Löschen"

```
PlaylistsView.delete(playlist)
  try? PlaylistImporter(modelContext:).delete(playlist)          Fehler still verworfen ⚠ FB-08
  └── delete(playlist)                                           @MainActor
      ├── id, isXtream merken
      ├── modelContext.delete(playlist)                          Kaskade: alle Channel (Main-Thread) ⚠ FB-01
      ├── modelContext.save()                                    wirft → Schlüsselbund bleibt
      └── [isXtream] credentialStore.delete(for: id)             errSecItemNotFound gilt als Erfolg
  nicht berührt: URLCache.shared ⚠ FB-06 · freie SQLite-Seiten ⚠ FB-07 · MultiviewSession, offene PlayerView
  und ChannelListView ⚠ FB-05
```

### Beteiligte Typen

| Typ | Datei | Rolle in B03 |
|---|---|---|
| `PlaylistsView` | `Views/PlaylistsView.swift:6-119` | Übersicht, Kontextmenü, Leerzustand, Alert, `refresh`/`delete`-Aufrufe, Ladezustand |
| `PlaylistRow` | `Views/PlaylistsView.swift:122-149` (privat) | Karteninhalt |
| `PlaylistImporter` | `Services/PlaylistImporter.swift:22-329` | `refresh` (`:220-265`), `delete` (`:270-278`), `attach` (`:284-305`), `fetchText` (`:307-321`); einziger Ort, der Sender anlegt und löscht |
| `ImportError` | `Services/PlaylistImporter.swift:4-18` | Meldungen „Die Playlist enthält keine gültigen Sender.", „Netzwerkfehler: …" |
| `XtreamClient`, `XtreamHTTPLoader`, `XtreamLoginThrottle` | `Services/` (B01) | Abruf beim Xtream-Aktualisieren, Grenzen, Bremse |
| `XtreamCredentialStore` | `Services/XtreamCredentialStore.swift` (B01) | `load` beim Aktualisieren, `save` bei Altbestand, `delete` beim Löschen |
| `XtreamCredentials`, `XtreamSecret` | `Services/XtreamCodes.swift` (B01) | Rekonstruktion aus Schlüsselbund oder Altadresse |
| `StreamURLResolver` | `Services/StreamURLResolver.swift` (B01) | `ResolveError.missingCredentials` als Meldung beim Aktualisieren; bildet für gehaltene Sender die Adresse (FB-05) |
| `M3UParser` | `Services/M3UParser.swift` (B02) | Parsen beim M3U-Aktualisieren |
| `Playlist`, `Channel` | `Models/` | Datenquelle und Ziel |
| `MultiviewSession`, `PlayerView`, `ChannelListView` | B08, B06, B04 | halten Objekte, die B03 löscht (FB-05) |

## Datenmodell

Aus `docs/datenmodell.md`, beschränkt auf das, was B03 liest und schreibt. Keine neuen Felder,
keine Schemaänderung, keine Migration.

### Entität `Playlist` (Tabelle `ZPLAYLIST`)

| Feld | Was B03 damit tut |
|---|---|
| `createdAt` | Sortierung der Übersicht, absteigend; beim Aktualisieren unverändert |
| `name` | angezeigt; nie geändert |
| `sourceURL` | `nil` → kein „Aktualisieren", Dokument-Symbol; sonst Abrufadresse. Bei Altbestand beim Aktualisieren auf die Form ohne Zugangsdaten umgeschrieben (AK-17) |
| `isXtream` | wählt den Abrufweg; beim Löschen: Schlüsselbund-Eintrag entfernen |
| `xtreamOutput` | Format beim Xtream-Aktualisieren; unbekannt → HLS (EC-01) |
| `lastRefreshed` | nach erfolgreichem Aktualisieren auf jetzt; **nirgends angezeigt** (OF-03) |
| `channelCount` | Badge; von `attach` auf die neue Anzahl gesetzt |
| `channels` | beim Aktualisieren vollständig geladen, geleert, neu befüllt; beim Löschen kaskadierend entfernt |
| `id` | Konto des Schlüsselbund-Eintrags; bleibt beim Aktualisieren gleich |

### Entität `Channel` (Tabelle `ZCHANNEL`)

B03 ändert keine Sender, es **ersetzt** sie: Beim Aktualisieren werden alle Zeilen gelöscht und neue
mit neuer `id` angelegt (`name`, `streamURL`, `logoURL`, `group`, `tvgID` aus der Quelle,
`playlist`, `playlistID` = Playlist-ID, `isFavorite` aus dem Favoriten-Abgleich). Beim Löschen
verschwinden alle Zeilen der Playlist.

Beziehungen: `Playlist.channels` 1 : n, Löschregel `cascade`, Inverse `Channel.playlist`.
Indizes: keine, die B03 nutzt (DM-05). Invariante `channelCount == channels.count` hält B03 ein
(AK-07, AK-23).

### Außerhalb des Schemas gespeichert

| Ort | Inhalt | B03 schreibt | B03 entfernt |
|---|---|---|---|
| `Application Support/<Bundle-ID>/MikaPlusPlayer.store` (+ `-wal`, `-shm`) | Playlists, Sender | beim Aktualisieren und Löschen | Zeilen ja; Bytes in freien Seiten nicht (`secure_delete` FAST, kein Verdichten) ⚠ FB-07 |
| Schlüsselbund, Dienst `lu.daumedia.MikaPlusPlayer.xtream`, Konto = `Playlist.id` | `XtreamSecret` (Host, Benutzer, Passwort) | nur bei Altbestand (AK-17) | beim Löschen einer Xtream-Playlist; nicht bei Fehlern, nicht nach dem Löschen der App ⚠ FB-08, FB-09 |
| `Cache.db`, macOS `~/Library/Caches/<Bundle-ID>/`, iOS `Library/Caches` | M3U-Abrufadresse samt Query und Antwortkörper | beim M3U-Aktualisieren (und Import, B02) | nie ⚠ FB-06 |

### Nicht persistiert

`refreshingID`, `errorMessage`, `showingImport` (je Ansichtsinstanz), die Menge der
Favoriten-Schlüssel während eines Aktualisierens, `PlaylistImporter.isWorking` (gesetzt, von keiner
Ansicht beobachtet).

## Zugriffsregeln

Die App hat keine Konten und keine Rollen.

| Wer | Darf lesen | Darf schreiben | Erzwungen durch |
|---|---|---|---|
| Nutzer der App | alle Playlists (Name, Senderzahl); Quelle, Zugangsdaten und Zeitpunkt nicht sichtbar | aktualisieren, löschen; nicht umbenennen oder ändern | nichts, Einzelnutzer |
| andere Prozesse desselben macOS-Benutzers | ⚠ Datenbank samt Resten gelöschter Sender, `Cache.db` samt M3U-Adressen | dieselben Dateien | nichts: App-Sandbox aus (B01) |
| andere Prozesse, Schlüsselbund (macOS) | nur nach Freigabe | — | Zugriffsliste des Eintrags (B01); nach Updates Abfrage des Anmeldepassworts (B01 OF-08) |
| andere Apps unter iOS | nichts | nichts | App-Sandbox |
| Anbieter (Host der Playlist) | Zugangsdaten, IP, Zeitpunkt jedes Aktualisierens | — | protokollbedingt; mehrfaches Auslösen ungebremst ⚠ FB-04 |

## Missbrauchsschutz und Grenzen

| Stelle | Grenze | Verhalten bei Überschreitung | Wo konfiguriert |
|---|---|---|---|
| Mehrfaches „Aktualisieren" derselben Playlist | **keine** | jeder Aufruf ein vollständiger Abruf und Ersetzen (AK-14) ⚠ FB-04 | — |
| Abgelehnte Xtream-Anmeldungen | 3 in Folge je Panel, dann 30 s, verdoppelnd bis 5 min | Meldung, keine Anfrage (AK-20) | `XtreamLoginThrottle.shared` (B01) |
| Xtream-Antwort | 64 MB, 100.000 Sender, 60 s Leerlauf, 180 s gesamt, Weiterleitungen nur im selben Panel | Meldung, alte Liste bleibt (AK-19) | `XtreamClient.Limits` (B01) |
| M3U-Antwort | **keine** eigene; `URLSession`-Standard (60 s Leerlauf), Weiterleitungen werden befolgt | — (B02) | — |
| Dauer des Ersetzens / Löschens auf dem Main-Thread | **keine**, quadratisch | Oberfläche eingefroren, 17.000 Sender ≈ 292 s bzw. 60–70 s ⚠ FB-01 | — |
| Rückfrage vor destruktiven Aktionen | **keine** | sofortiges Löschen (AK-22), sofortiges Ersetzen durch kürzere Liste (AK-11) | — |

## Externe Dienste

| Dienst | Wofür | Was geht hin | Was wird vorher entfernt |
|---|---|---|---|
| Host der M3U-Adresse (beliebig) und Ziele von Weiterleitungen | M3U-Aktualisieren | GET auf die gespeicherte Adresse samt Query (z. B. Token), IP, Standard-Kopfzeilen von `URLSession` | nichts |
| Xtream-Panel am gespeicherten Host, `/player_api.php` | Xtream-Aktualisieren | drei GET mit `username`/`password` als Query, über das beim Import gewählte Schema; IP | nichts (B01) |

Löschen spricht keinen Dienst an. Kein KI-Dienst, keine Analyse, kein Fehler-Tracking, kein Server
von daumedia.

## Erkennbare Entscheidungen

| # | Entscheidung | Alternative | Warum so |
|---|---|---|---|
| 1 | Aktualisieren ersetzt **alle** Sender statt abzugleichen | Abgleich über `stream_id`/Adresse: vorhandene behalten, neue anlegen, fehlende löschen | Kommentar `PlaylistImporter.swift:252-262` („alte Channels entfernen … neu aufbauen"); einfach. Folgen: neue IDs (AK-07), gehaltene Objekte ungültig (FB-05), volle Kosten auch ohne Änderung (EC-02) |
| 2 | ⚠ Favoriten-Erhalt über nicht eindeutigen `favoriteKey` | eindeutiger Schlüssel (Stream-ID + Playlist), oder Abgleich je Sender | README, CLAUDE.md, Website: Wiedererkennung über tvg-ID/Name; die Mehrdeutigkeit wurde offenbar nicht bedacht (FB-02) |
| 3 | ⚠ Ersetzen auf dem Main-Actor mit `attach` je Sender | blockweise im Hintergrund-Kontext wie der Xtream-Import seit B01 BUG-12 | `PlaylistImporter` ist als `@MainActor` angelegt („SwiftData-Objekte hier erzeugt/verändert", Kommentar `:20-21`). B01 hat nur den Import umgebaut (Build-Bericht, Abschnitt 2) (FB-01) |
| 4 | Fehler vor jeder Änderung prüfen, erst danach löschen und neu anlegen | Änderungen in Transaktion mit Rücksetzen | ergibt den Erhalt der alten Liste bei Netz- und Inhaltsfehlern (AK-18 bis AK-21); Fehler beim abschließenden Speichern sind nicht abgefangen (EC-03) |
| 5 | Ungebundene `Task` je Menüwahl, neue Importer-Instanz je Aufruf | ein Importer je Playlist mit Zustand „läuft", Menüeintrag deaktiviert | Grund nicht erkennbar; `isWorking` existiert, wird aber nicht beobachtet (FB-03, FB-04) |
| 6 | Ein `refreshingID` für die ganze Übersicht | Menge laufender IDs | Grund nicht erkennbar (FB-03) |
| 7 | Löschen ohne Rückfrage, ohne `UndoManager` | `confirmationDialog`; `modelContainer(…, isUndoEnabled: true)` | Grund nicht erkennbar (OF-01) |
| 8 | Erst Datenbank speichern, dann Schlüsselbund löschen; Fehler mit `try?` verworfen | umgekehrte Reihenfolge; Fehler anzeigen; Bereinigung verwaister Einträge beim Start | Reihenfolge ist sinnvoll (eine Playlist ohne Zugangsdaten wäre schlimmer als ein verwaister Eintrag); das Verwerfen ist nicht begründet (FB-08) |
| 9 | M3U-Abruf über `URLSession.shared` | eigene `ephemeral`-Sitzung wie `XtreamHTTPLoader` | Import und Aktualisieren teilen `fetchText`; B01 hat nur Xtream umgestellt (FB-06) |
| 10 | Lokale Datei nicht aktualisierbar | Security-Scoped Bookmark speichern und neu lesen | Kommentar `PlaylistImporter.swift:208`, PRD: gewollt (AK-16, OF-05) |
| 11 | Kontextmenü als einziger Weg | Toolbar-/Menüleisten-Aktionen, Wischgesten, Entf-Taste | Grund nicht erkennbar; hält die Übersicht schlicht (AS-05) |
| 12 | Fehler als Alert mit `localizedDescription` | eigene Meldungen je Fehlerart | wie B01 (OF-06 dort) |

## Abdeckung der Akzeptanzkriterien

Umgedreht: Was erfüllt das Kriterium heute? Fundstellen beziehen sich auf `Sources/` im Stand
`c01f1cf` + Reparatur B01.

| AK | Erfüllt durch | Anmerkung |
|---|---|---|
| AK-01 | `Views/PlaylistsView.swift:17-24, 63-66`; `Views/Theme/PlayerTheme.swift` (`PlayerHeader`) | |
| AK-02 | `Views/PlaylistsView.swift:26-27, 80-100, 70-72` | OF-04 |
| AK-03 | `Views/PlaylistsView.swift:8, 29-38, 122-149`; `Models/Playlist.swift:55` (`isRemote`) | |
| AK-04 | `Views/PlaylistsView.swift:31, 67-69` | B04 |
| AK-05 | `Views/PlaylistsView.swift:127-147` (nur Symbol, Name, Badge) | OF-03 |
| AK-06 | `Views/PlaylistsView.swift:39-52` | `role: .destructive` |
| AK-07 | `Services/PlaylistImporter.swift:220-224, 246-250, 253-264, 284-305, 307-321` | |
| AK-08 | `Services/PlaylistImporter.swift:226-241`; `XtreamClient.fetchLiveChannels`; `XtreamStreamAddress.stored` | B01 |
| AK-09 | `Services/PlaylistImporter.swift:253, 299`; `Models/Channel.swift:49-52` | |
| AK-10 | wie AK-09 | ⚠ FB-02 |
| AK-11 | `Services/PlaylistImporter.swift:250` (prüft nur „nicht leer"), `:253-262` | OF-02 |
| AK-12 | `Views/PlaylistsView.swift:34, 110-111, 140-146` | |
| AK-13 | `Views/PlaylistsView.swift:11, 110-111` | ⚠ FB-03 |
| AK-14 | `Views/PlaylistsView.swift:41-43`; `Services/PlaylistImporter.swift:220` | ⚠ FB-04 |
| AK-15 | `Services/PlaylistImporter.swift:220-265` (je Aufruf eigene Playlist, Main-Actor serialisiert den Teil nach dem Abruf) | |
| AK-16 | `Views/PlaylistsView.swift:40`; `Services/PlaylistImporter.swift:208-209, 221` | OF-05 |
| AK-17 | `Services/PlaylistImporter.swift:229-232, 242-245` | B01-Test `testBUG01_AltbestandBleibtSpielbarUndWirdBeimAktualisierenUmgestellt` |
| AK-18 | `Services/PlaylistImporter.swift:246-250, 307-321, 4-18`; `Views/PlaylistsView.swift:115-117, 73-77` | |
| AK-19 | `Services/PlaylistImporter.swift:239-241`; `XtreamClient.XtreamError` | B01 |
| AK-20 | `XtreamClient.fetchLiveChannels` + `XtreamLoginThrottle.shared` | B01 |
| AK-21 | `Services/PlaylistImporter.swift:233-237`; `StreamURLResolver.ResolveError` | OF-06 |
| AK-22 | `Views/PlaylistsView.swift:47-51, 104-107`; `App/MikaPlusPlayerApp.swift:35` (`.modelContainer` ohne Undo) | OF-01 |
| AK-23 | `Services/PlaylistImporter.swift:270-274`; `Models/Playlist.swift:29-30` (`cascade`) | |
| AK-24 | `Services/PlaylistImporter.swift:275-277`; `Services/XtreamCredentialStore.swift:75-78` | |
| AK-25 | `Services/PlaylistImporter.swift:190-214` (nur Inhalt übernommen), `:270-278` | |
| AK-26 | `Services/PlaylistImporter.swift:253-264` auf gelöschter Playlist: SwiftData legt keine Zeilen an | Verhalten von SwiftData, nicht vom Code abgesichert |
| AK-27 | `Views/ChannelListView.swift:9, 18-21, 35, 43` (hält `Playlist`), `@Query` leert die Liste | ⚠ FB-05 |
| AK-28 | `Services/MultiviewSession.swift:37-41`; `Views/PlayerView.swift:13, 17, 239-257`; `Services/StreamURLResolver.swift:25-30` | ⚠ FB-05 |
| AK-29 | `Services/PlaylistImporter.swift:259` (`removeAll` trennt die Beziehung); `Services/StreamURLResolver.swift:25` | ⚠ FB-05 |
| AK-30 | `ImportError`, `XtreamClient.XtreamError`, `StreamURLResolver.ResolveError`, `XtreamCredentialStore.KeychainError` (Texte ohne Adresse) | |
| AK-31 | Fehlen jedes Logging-Aufrufs in `Sources/` | SwiftData-Systemzeilen ohne Nutzdaten |
| AK-32 | `XtreamHTTPLoader` (B01, `ephemeral`, `urlCache = nil`) | |
| AK-33 | `Services/PlaylistImporter.swift:307-321` (`URLSession.shared`) | ⚠ FB-06 |
| AK-34 | `Services/PlaylistImporter.swift:270-278` ohne Verdichten; SQLite `secure_delete` = FAST | ⚠ FB-07 |
| AK-35 | `Services/PlaylistImporter.swift:242-245` | ⚠ FB-08 |
| AK-36 | kein Code; `AppPersistence.swift:61-65`, `XtreamCredentialStore.swift:26-30` | ⚠ FB-09 |
| AK-37 | `Services/PlaylistImporter.swift:253-264, 284-305` | ⚠ FB-01 |
| AK-38 | `Services/PlaylistImporter.swift:273-274` | ⚠ FB-01 |

### Code ohne AK-Zuordnung

- **`PlaylistImporter.isWorking`** (`PlaylistImporter.swift:31-32, 222-223`): wird beim Aktualisieren
  gesetzt, aber von keiner Ansicht beobachtet, weil jeder Aufruf eine eigene Instanz erzeugt. Der
  Ladezustand der Karte kommt aus `refreshingID` (FB-03).
- **`guard let url = playlist.sourceURL else { return }`** (`PlaylistImporter.swift:221`): über die
  Oberfläche unerreichbar, weil lokale Dateien kein „Aktualisieren" haben (AK-16).
- **Zweite Leerprüfung** (`PlaylistImporter.swift:250`) für Xtream doppelt zur Prüfung in `:241`.
- **Kommentar `Playlist.swift:22`** nennt Formatwerte `"m3u8"/"ts"`, die nie geschrieben werden (DM-11,
  EC-01).

### Bestehende Tests

Kein eigener Test für B03. Berührt wird B03 von B01-Tests:

| Test | Prüft | Deckt |
|---|---|---|
| `B01ReparaturTests.testBUG01_AktualisierenLiestSchluesselbundUndBehaeltFavoriten` | Xtream-Aktualisieren mit Zugangsdaten aus dem Schlüsselbund, ein Favorit bleibt, Benutzerinfo bleibt | AK-08, AK-09 teilweise |
| `B01ReparaturTests.testBUG01_AltbestandBleibtSpielbarUndWirdBeimAktualisierenUmgestellt` | Umstellung beim Aktualisieren | AK-17 |
| `B01ReparaturTests.testBUG01_ResolverM3UUnveraendertXtreamMitSchluesselbund` | Aktualisieren ohne Schlüsselbund-Eintrag wirft `missingCredentials` | AK-21 |
| `B01SicherheitTests.testAK24_KlartextInDatenbankUndRestNachLoeschen` | Löschen entfernt Schlüsselbund-Eintrag und Zeilen; Passwort nach Schließen in keiner Datei | AK-23, AK-24 |

Ohne Test: Übersicht und Kontextmenü, M3U-Aktualisieren, Favoriten-Dubletten, Fehlerfälle mit Erhalt
der alten Liste, Ladeindikator, Parallelität, gehaltene Objekte, Cache und freie Seiten nach dem
Löschen, Leistung. Die Sonde, mit der die Kriterien belegt wurden, lief nur in einer Kopie und ist
wieder entfernt; ihr Code liegt als `qa-erfassung/sonde.patch` bei.
