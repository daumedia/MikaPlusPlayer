# B05 · Favoriten — Systemdesign

Status: `rekonstruiert` · Stand: `c01f1cf` + Reparatur B01 (2026-09-16) · Rekonstruktion aus dem Code (sdd-erfassen) · Stack-Profil: `swiftui-ios` + `swiftui-macos`

> **Gelesener Code-Stand: `c01f1cf` + Reparatur B01 (2026-09-16).** `FavoritesView.swift`,
> `ChannelRowView.swift`, `ContentView.swift` und die Favoriten-Logik in `PlaylistImporter` sind
> gegenüber `c01f1cf` unverändert. Durch die B01-Reparatur geändert haben sich nur Randbedingungen:
> Speicherort der Datenbank, Anlage von Xtream-Playlists im Hintergrund-Kontext, Zugangsdaten im
> Schlüsselbund, `PlaylistImporter.delete`. Zeilenangaben beziehen sich auf diesen Stand.

**Kein Code in diesem Dokument.** Beschrieben ist der Aufbau, wie er steht, nicht, wie er sein
sollte. Fragwürdiges ist markiert und verweist auf den *Fehlbestand* in `spec.md`. Messwerte und
Belege: `qa-erfassung/sonde-protokoll.txt`.

## Überblick

Ein Favorit ist kein eigener Datensatz, sondern ein Wahr/Falsch-Merkmal am Sender. Der Stern in der
Senderkarte kehrt das Merkmal um und speichert sofort; ein Fehler beim Speichern wird verworfen. Der
Tab „Favoriten" ist eine Datenbankabfrage über **alle** Sender aller Playlists mit gesetztem Merkmal,
nach Namen sortiert, und zeigt dieselben Karten wie die Senderliste. Weil das Aktualisieren einer
Playlist alle ihre Sender löscht und neu anlegt, merkt es sich vorher eine Menge von Schlüsseln der
markierten Sender (`tvg-id`, sonst kleingeschriebener Name) und setzt das Merkmal bei jedem neuen
Sender mit passendem Schlüssel. Löschen einer Playlist nimmt ihre Sender samt Merkmal mit.

## Szenen und Einstiege

SwiftUI, keine Routen. Plattform in Klammern.

| Einstieg | Zweck | Zugang |
|---|---|---|
| Stern in jeder Senderkarte (`ChannelRowView`), in `ChannelListView` (B04) und im Tab | markieren, entmarkieren (beide) | jeder Nutzer des Geräts |
| Tab „Favoriten" in `ContentView`, eigener `NavigationStack` | alle Favoriten sehen, Player öffnen (beide) | ebenso |
| Kontextmenü „Aktualisieren" / „Löschen" in `PlaylistsView` (B03) | führt Favoriten über bzw. entfernt sie | ebenso |

Kein Menüeintrag, kein Tastenkürzel, keine Einstellung, kein Deep Link.

## Komponentenstruktur

```
ContentView (TabView, tint playerAccent)
├── Tab „Playlists"  → PlaylistsView → ChannelListView (B04)
│                                      └── ChannelResultsList → ForEach → NavigationLink(value: Channel)
│                                                                            └── ChannelRowView ─┐
└── Tab „Favoriten" (star.fill)                                                                  │
    └── NavigationStack                                                                          │
        └── FavoritesView                                                                        │
            ├── @Query  filter: isFavorite == true, sort: \Channel.name   ⚠ Zeichencode (OF-01)  │
            ├── ScrollView › LazyVStack                                                          │
            │   ├── PlayerHeader  „MIKA+PLAYER · FAVORITEN" / „Favoriten"                        │
            │   ├── [leer]  emptyState: star 44 pt, „Keine Favoriten", Hinweistext                │
            │   └── [sonst] LazyVStack › ForEach(favorites)                                      │
            │                └── NavigationLink(value: Channel), .buttonStyle(.plain)            │
            │                     └── ChannelRowView .playerCard() ◄─────────────────────────────┘
            ├── .navigationTitle „Favoriten"; iOS: Navigationsleiste ausgeblendet
            └── .navigationDestination(Channel) → PlayerView (B06)

ChannelRowView (@Bindable channel, @Environment modelContext)
├── logo            AsyncImage(channel.logoURL)   ⚠ lädt Logos der sichtbaren Favoriten (FB-03)
├── Name, Gruppe-Badge
├── [macOS] multiviewButton  ⊞ (B08), .help „Zu Multiview hinzufügen"
└── favoriteButton  Button, .plain
    ├── Aktion: channel.isFavorite.toggle(); try? modelContext.save()   ⚠ Fehler verworfen (FB-02)
    └── Bild: star / star.fill, secondary / playerAccent, .title3
        ⚠ keine Beschriftung, kein Wert: VoiceOver nur Aktion „Favourite" (FB-04, OF-06)
```

### Ablauf beim Umschalten

1. Klick auf den Stern → Aktion des inneren Buttons; der umgebende `NavigationLink` löst **nicht**
   aus (ausgeführt, macOS).
2. `isFavorite` wird am Objekt im Haupt-Kontext umgekehrt, danach `save()` synchron auf dem
   Main-Actor. Gelingt es, steht der Wert im selben Moment in der Datei.
3. Scheitert es, verwirft `try?` den Fehler. Das Objekt bleibt geändert (`hasChanges`), die Oberfläche
   zeigt den neuen Zustand, Abfragen liefern ihn mit (ausstehende Änderungen zählen). Das nächste
   erfolgreiche `save()` irgendwo im Haupt-Kontext schreibt ihn mit; ein Neustart vorher verliert ihn.
4. Jede `@Query` auf `Channel` im selben Container aktualisiert sich: Senderliste (B04) und Tab.

### Ablauf beim Aktualisieren (Favoriten-Anteil)

`PlaylistImporter.refresh(_:)`, `Services/PlaylistImporter.swift:220-265`, auf dem Main-Actor:

1. Nur für Playlists mit `sourceURL` (sonst sofortige Rückkehr, `:221`).
2. Neue Senderliste holen: Xtream über Schlüsselbund und `XtreamClient` (`:226-245`), M3U über
   `fetchText` und Parser (`:246-249`). Leer → Fehler (`:241`, `:250`). **Jeder Fehler bis hierher lässt
   Sender und Favoriten unangetastet.**
3. Schlüssel merken (`:253`): alle Sender der Playlist über die Beziehung laden, die markierten filtern,
   `favoriteKey` in eine **Menge** schreiben. ⚠ Welcher Sender markiert war, geht verloren (FB-01).
4. Alte Sender löschen (`:256-259`), neue über `attach` anlegen (`:262`, `:284-305`); `:299` setzt
   `isFavorite`, wenn der Schlüssel des neuen Senders in der Menge ist.
5. `lastRefreshed`, `save()` (`:263-264`).

Schritte 3 bis 5 laufen ohne `await` am Stück; ein Klick kann nicht dazwischen fallen (EC-04).

### Ablauf beim Löschen

`PlaylistsView.delete` (`Views/PlaylistsView.swift:104-107`) ruft ohne Rückfrage
`PlaylistImporter.delete` (`Services/PlaylistImporter.swift:270-278`): Playlist löschen, Cascade auf
alle Sender, speichern, bei Xtream den Schlüsselbund-Eintrag entfernen. Ein Fehler wird dort mit
`try?` verworfen (B03). Der Tab aktualisiert sich über seine `@Query`.

### Beteiligte Typen

| Typ | Datei | Rolle in B05 |
|---|---|---|
| `ContentView` | `App/ContentView.swift:15-20` | Tab „Favoriten" mit eigenem Stapel |
| `FavoritesView` | `Views/FavoritesView.swift` | Abfrage, Kopf, Leerzustand, Liste, Navigationsziel |
| `ChannelRowView` | `Views/ChannelRowView.swift:59-69` | Stern: Umschalten, Speichern, Darstellung; mit B04 und B08 geteilt |
| `Channel` | `Models/Channel.swift:14-17, 47-52` | `isFavorite`, `tvgID`, abgeleiteter `favoriteKey` |
| `PlaylistImporter` | `Services/PlaylistImporter.swift:220-265, 270-278, 284-305` | Favoriten über das Aktualisieren führen; Löschen |
| `M3UParser`, `XtreamClient` | `Services/M3UParser.swift:83, 113`; `Services/XtreamClient.swift:106, 112` | liefern Name und `tvg-id`, aus denen der Schlüssel entsteht |
| `AppPersistence` | `Services/AppPersistence.swift:16-17, 42-65` | Speicherort der Datenbank; Backup bewusst nicht ausgeschlossen |

## Datenmodell

Aus `docs/datenmodell.md`, beschränkt auf das, was B05 liest und schreibt. B05 führt **keine** eigenen
Felder oder Entitäten ein; es gibt keine Schemaänderung und keine Migration. Die Übernahme alter
Datenbanken und die Umstellung der Zugangsdaten durch die B01-Reparatur behalten `isFavorite` (in B01
getestet).

### Entität `Channel` (Tabelle `ZCHANNEL`) — B05-relevante Felder

| Feld | Typ | Pflicht | Bedeutung in B05 |
|---|---|---|---|
| `isFavorite` | `Bool` (`ZISFAVORITE INTEGER`) | ja | das Favoriten-Merkmal. Beim Import immer `false`; der Stern kehrt es um; `attach` setzt es beim Aktualisieren |
| `tvgID` | `String?` (`ZTVGID`) | nein | M3U `tvg-id`, Xtream `epg_channel_id`; leer → `nil`, aber Leerzeichen bleiben. Einzige Verwendung: Schlüssel |
| `name` | `String` (`ZNAME`) | ja | Anzeige, Sortierung im Tab, Rückfall-Schlüssel. M3U am Rand getrimmt, Xtream nicht, Xtream auch leer |
| `playlist` / `playlistID` | `Playlist?` / `UUID?` | nein | Cascade beim Löschen; der Tab nutzt beides nicht |
| `Z_PK` (intern) | `INTEGER PRIMARY KEY` | — | zweites Sortierkriterium im Tab: Reihenfolge der Anlage bei gleichem Namen (AK-09) |

Abgeleitet, nicht gespeichert: `favoriteKey` = `"id:" + tvgID`, wenn `tvgID` nicht leer, sonst
`"name:" + name.lowercased()`. ⚠ nicht eindeutig (FB-01, DM-06).

Beziehungen: `Playlist` 1 : n `Channel`, `cascade`. Favoriten gehören damit fest zu genau einer
Playlist; einen playlist-übergreifenden Favoriten (z. B. „Das Erste, egal von welchem Anbieter") gibt
es nicht.

### Abfragen

| Wo | SQL laut Core Data | Plan | Gemessen |
|---|---|---|---|
| `FavoritesView` `@Query` | `SELECT … FROM ZCHANNEL t0 WHERE t0.ZISFAVORITE = ? ORDER BY t0.ZNAME, t0.Z_PK` | `SCAN t0`, `USE TEMP B-TREE FOR ORDER BY` | 1,0–1,9 ms bei 17.000 / 50; 2,0–3,4 ms bei 34.000 / 100 |
| `refresh` Schritt 3 | Laden der Beziehung `playlist.channels` mit allen Spalten | nicht ausgewertet | 1.079 ms kalt bei 17.000, 10 ms warm (DM-07) |

Die Sortierung `sort: \Channel.name` ohne Vergleichsangabe ergibt ein `ORDER BY` **ohne Kollation**,
also Zeichencode. Die Senderliste (B04) sortiert mit `NSCollateLocaleSensitive`. Ein
`SortDescriptor(\.name)` mit Standard-Vergleich würde `NSCollateFinderlike` ergeben (in der Sonde
verglichen).

### Indizes

Auf `ZISFAVORITE` und `ZNAME` liegt kein Index (DM-05); `#Index` gäbe es erst ab iOS 18 / macOS 15.
Bei den gemessenen Größen unerheblich (AK-29).

### Außerhalb des Schemas gespeichert

| Ort | Inhalt mit B05-Bezug | Entsteht durch |
|---|---|---|
| `MikaPlusPlayer.store-wal` | Seiten mit Namen gelöschter Sender bis zum Checkpoint; nach dem Beenden leer | SQLite im WAL-Modus, `secure_delete = FAST` (AK-28) |
| `Cache.db` (`~/Library/Caches/<Bundle-ID>/`, iOS `Library/Caches`) | Logo-Adressen und -Bilder der im Tab angezeigten Favoriten | `AsyncImage` über `URLCache.shared` (B04 FB-07) |
| Backups des Nutzers | die ganze Datenbank | kein Backup-Ausschluss, bewusst (AK-23) |

### Nicht persistiert

Die Schlüsselmenge beim Aktualisieren (lokal in `refresh`), die ausstehende Änderung nach einem
gescheiterten Speichern (nur im Kontext, bis zum nächsten erfolgreichen `save()` oder Beenden).

## Zugriffsregeln

Die App hat keine Konten und keine Rollen. Zugriff regelt allein das Betriebssystem.

| Wer | Darf lesen | Darf schreiben | Erzwungen durch |
|---|---|---|---|
| Nutzer der App | alle Favoriten aller Playlists | markieren, entmarkieren; mit der Playlist löschen | nichts, Einzelnutzer |
| andere Programme desselben macOS-Benutzers | `MikaPlusPlayer.store` samt Favoriten | dieselbe Datei | **nichts** außer Dateirechten des Benutzers: Sandbox aus (`MikaPlusPlayer.entitlements:7-8`), bewusst (CLAUDE.md) |
| andere Benutzer desselben Macs | nichts | nichts | `~/Library` mit `rwx------` |
| andere Apps unter iOS | nichts | nichts | App-Sandbox des Systems |
| Backup (Time Machine, iCloud-/Geräte-Backup) | die Datenbank | — | kein Ausschluss, begründet in `AppPersistence.swift:16-17` |
| Logo-Hosts aus den Playlists | ⚠ welche Sender Favoriten sind, über die Anfragen beim Öffnen des Tabs | — | nichts (FB-03) |

## Missbrauchsschutz und Grenzen

| Stelle | Limit | Verhalten bei Überschreitung | Wo konfiguriert |
|---|---|---|---|
| Stern | keins; jeder Klick schaltet und speichert | Doppelklick schaltet zweimal | `ChannelRowView.swift:60-62` |
| Anzahl Favoriten | keins | Tab lädt alle Favoriten als Objekte (EC-09) | — |
| Wiederholte Schlüssel in der Anbieterliste | keins | ⚠ Vervielfachung der Favoriten beim Aktualisieren (FB-01) | `Channel.swift:49-52`, `PlaylistImporter.swift:253, 299` |
| Logo-Anfragen des Tabs | nur sichtbare Karten (`LazyVStack`), Abbruch beim Wegscrollen (B04 AK-23) | — | `FavoritesView.swift:16, 22` |

## Externe Dienste

| Dienst | Wofür | Was geht hin | Was wird vorher entfernt |
|---|---|---|---|
| Logo-Hosts aus den Playlists (beliebig) | Logos der Favoriten im Tab | ⚠ IP, User-Agent mit App-Build und Systemversion, `Accept-Language`, Abfolge der angefragten Logos = die sichtbaren Favoriten | nichts (FB-03) |
| Anbieter (M3U-Quelle, Xtream-Panel) | nur beim Aktualisieren (B03) | wie B01/B02; nichts Favoriten-spezifisches | — |

Kein Sync, kein Server von daumedia, kein Analyse- oder Fehlerdienst.

## Erkennbare Entscheidungen

| # | Entscheidung | Alternative | Warum so |
|---|---|---|---|
| 1 | Favorit als `Bool` am Sender | eigene Entität `Favorite` mit Schlüssel und Playlist-Bezug, unabhängig vom Senderobjekt | Grund nicht erkennbar; einfachste Form. Folge: Favoriten leben und sterben mit dem Senderobjekt, daher die Schlüssel-Brücke beim Aktualisieren |
| 2 | Tab filtert über das skalare `isFavorite` | `#Predicate` über die Beziehung | Kommentar `FavoritesView.swift:4-6` und CLAUDE.md: „zuverlässiger als ein #Predicate über optionale Relationship-Keypaths" |
| 3 | Aktualisieren löscht alle Sender und legt sie neu an, Favoriten über `favoriteKey` | Sender abgleichen und nur Änderungen übernehmen; Favoriten am stabilen Objekt lassen | Grund nicht erkennbar; der Kommentar `PlaylistImporter.swift:218-219` beschreibt nur das Wie |
| 4 | Schlüssel `tvg-id`, sonst Name klein | nur `tvg-id`; `tvg-id` + Name; Stream-Adresse bzw. `stream_id`; Normalisierung von Schreibweisen | README („über `tvg-id`/Name"), Kommentar `Channel.swift:14-15, 47-48`: `tvg-id` ist beim Anbieter am stabilsten, der Name deckt Listen ohne `tvg-id` ab. Warum `tvg-id` nicht ebenfalls klein geschrieben wird, ist nicht erkennbar |
| 5 | ⚠ Menge von Schlüsseln statt Zuordnung je Sender | Mehrfachvorkommen zählen, nur so viele Treffer markieren wie vorher; bei Mehrdeutigkeit zusätzlich Name oder Adresse vergleichen | Grund nicht erkennbar (FB-01) |
| 6 | ⚠ `try?` beim Speichern des Sterns | Fehler anzeigen und Merkmal zurücksetzen | Grund nicht erkennbar (FB-02) |
| 7 | ⚠ `sort: \Channel.name` ohne Vergleichsangabe | `SortDescriptor(\.name, comparator: .localized)` wie in der Senderliste | Grund nicht erkennbar; vermutlich nicht bedacht, dass ohne Angabe binär sortiert wird (OF-01) |
| 8 | Dieselbe `ChannelRowView` in Liste und Tab | eigene, kompaktere Favoriten-Karte mit Playlist-Angabe | Wiederverwendung; Stern und ⊞ wirken so überall gleich. Folge: keine Playlist-Angabe (OF-02), Logos laden auch im Tab (FB-03) |
| 9 | Karte als `NavigationLink` mit eingebetteten Buttons | Stern und ⊞ außerhalb des Links; eigene Accessibility-Beschriftung und -Werte | Grund nicht erkennbar; die Zusammenfassung zu einem Element ist Standardverhalten von SwiftUI (FB-04) |
| 10 | Datenbank nicht vom Backup ausgeschlossen | Ausschluss oder getrennte Ablage der Favoriten | Kommentar `AppPersistence.swift:16-17` (B01-Reparatur): Nutzer sollen beim Wiederherstellen ihre Playlists behalten |
| 11 | Kein Index auf `isFavorite` | `#Index` (ab iOS 18/macOS 15) bzw. Core-Data-Fetch-Index | Deployment-Target iOS 17 / macOS 14; gemessen ohne Folgen |

## Abdeckung der Akzeptanzkriterien

Umgedreht: Was erfüllt das Kriterium heute? Fundstellen beziehen sich auf `Sources/`.

| AK | Erfüllt durch | Anmerkung |
|---|---|---|
| AK-01 | `Views/ChannelRowView.swift:26-30, 59-69`; `Views/Theme/PlayerTheme.swift:26` (Akzent) | kein `.help` am Stern |
| AK-02 | `Views/ChannelRowView.swift:60-62` | synchrones `save()` im Haupt-Kontext |
| AK-03 | `Views/ChannelRowView.swift:68` (`.plain`), `Views/ChannelListView.swift:111-114`, `Views/FavoritesView.swift:24-27` | Verhalten von SwiftUI bei eingebettetem Button; iOS nicht ausgeführt |
| AK-04 | `@Query` in `FavoritesView.swift:8-12` und `ChannelListView.swift:85`; ein Container für alle Fenster (`App/MikaPlusPlayerApp.swift:7-19, 35, 56`) | |
| AK-05 | Fehlen von Accessibility-Angaben in `ChannelRowView.swift:59-69`; Zusammenfassung durch `NavigationLink` | ⚠ FB-04, OF-06 |
| AK-06 | `App/ContentView.swift:15-20`; `Views/FavoritesView.swift:17, 38-41` | |
| AK-07 | `Views/FavoritesView.swift:19-20, 47-61` | Muster dreifach dupliziert (DS-05) |
| AK-08 | `Views/FavoritesView.swift:22-31, 42-44` | |
| AK-09 | `Views/FavoritesView.swift:10` (nur Name) → `ORDER BY ZNAME, Z_PK`; Karte ohne Playlist-Angabe | ⚠ OF-02 |
| AK-10 | `Views/FavoritesView.swift:10` | ⚠ OF-01 |
| AK-11 | `Models/Channel.swift:49-52`; `Services/PlaylistImporter.swift:253, 299` | |
| AK-12 | wie AK-11; Stream-Adresse ist nicht Teil des Schlüssels | |
| AK-13 | `Models/Channel.swift:51` (`lowercased()`, Swift-Stringvergleich mit kanonischer Äquivalenz); `Services/M3UParser.swift:83` (Trim) | |
| AK-14 | `Services/PlaylistImporter.swift:253-262` (nur die aktuelle Liste zählt) | ⚠ OF-03 |
| AK-15 | `Models/Channel.swift:49-52`; `Services/PlaylistImporter.swift:253, 299`; `Services/M3UParser.swift:113`; `Services/XtreamClient.swift:106, 112` | ⚠ FB-01 |
| AK-16 | `Services/PlaylistImporter.swift:253` (nur `playlist.channels`), `:289-301` (nur neue Sender dieser Playlist) | |
| AK-17 | `Services/PlaylistImporter.swift:221-250` (alle Fehler vor dem Löschen) | |
| AK-18 | `Services/PlaylistImporter.swift:221`; Menü in `Views/PlaylistsView.swift:40-46` | |
| AK-19 | `@Query` in `FavoritesView.swift:8-12`; `PlayerView` hält das Objekt (DM-10) | Player-Verhalten → B03/B06 |
| AK-20 | `Models/Playlist.swift:29-30` (Cascade); `Services/PlaylistImporter.swift:270-278`; `Views/PlaylistsView.swift:47-52, 104-107` | ⚠ OF-04; Rückfrage → B03 |
| AK-21 | Fehlen entsprechender Funktionen in `Sources/` | OF-05 |
| AK-22 | `Services/AppPersistence.swift:42-50, 61-65`; `App/MikaPlusPlayerApp.swift:7-19` | |
| AK-23 | `Services/AppPersistence.swift:16-17` (kein `isExcludedFromBackup`) | bewusst |
| AK-24 | `Resources/MikaPlusPlayer.entitlements:7-8` | bewusst (CLAUDE.md) |
| AK-25 | `Views/FavoritesView.swift:22-28`; `Views/ChannelRowView.swift:36`; `Resources/Info.plist:39-40` | ⚠ FB-03 |
| AK-26 | Fehlen jedes Logging-Aufrufs in `Sources/` | |
| AK-27 | `Views/ChannelRowView.swift:62` (`try?`); Haupt-Kontext mit `autosaveEnabled` | ⚠ FB-02 |
| AK-28 | SQLite-Standard des Systems (WAL, `secure_delete = FAST`); keine eigene Bereinigung | |
| AK-29 | `Views/FavoritesView.swift:8-12` | kein Index (DM-05) |
| AK-30 | `Services/PlaylistImporter.swift:253` | DM-07, B03 |

### Code ohne AK-Zuordnung

- **`PlaylistImporter.importFromURL/importFromFile` rufen `attach(…, preservedFavorites: [])`**
  (`PlaylistImporter.swift:65, 211`), der Xtream-Import legt Sender mit `isFavorite = false` im
  Hintergrund-Kontext an (`:155-162`). Die leere Menge ist toter Parameter-Gebrauch; kein Import
  übernimmt Favoriten (AK-20, EC-11).
- **Kommentar `Channel.swift:14-15`** („zusammen mit dem Namen") beschreibt den Schlüssel als
  Kombination; tatsächlich ist der Name nur Rückfall, wenn die `tvg-id` fehlt.
- **CLAUDE.md** beschreibt den Schlüssel als „`tvgID ?? name`"; Kleinschreibung und die Behandlung einer
  leeren `tvg-id` fehlen dort.
- **`.navigationDestination(for: Channel.self)`** steht in `FavoritesView` und `ChannelListView`
  getrennt; der Tab braucht seine eigene, weil er einen eigenen Stapel hat. Kein toter Code, nur
  Doppelung.

### Bestehende Tests

Keine B05-eigenen Tests. Berührt wird das Merkmal von Tests der B01-Reparatur (nur macOS-Target):

| Test | Prüft | Deckt |
|---|---|---|
| `B01ReparaturTests.testBUG01_AktualisierenLiestSchluesselbundUndBehaeltFavoriten` | ein markierter Xtream-Sender (mit `epg_channel_id`) bleibt nach dem Aktualisieren Favorit | AK-11, AK-12 teilweise; Mock mit eindeutigen Schlüsseln, deshalb ohne AK-15 |
| `B01ReparaturTests.testBUG01_MigrationVorhandenerDatenbankOhneDatenverlust` | Umstellung der Zugangsdaten behält Favoriten | EC-06 |
| `B01LangsamTests.testBUG01_MigrationMit17000Sendern` | 17 Favoriten überstehen die Umstellung von 17.000 Sendern | EC-06 |

Ohne Test: der Stern und sein Speichern, der Tab, die Sortierung, Dubletten beim Aktualisieren,
Verlust bei Umbenennung oder Wegfall, Löschen, Speicherfehler, Logo-Anfragen des Tabs.
