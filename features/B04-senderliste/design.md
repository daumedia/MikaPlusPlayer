# B04 · Senderliste — Systemdesign

Status: `rekonstruiert` · Stand: 2026-09-16 · Rekonstruktion aus dem Code (sdd-erfassen) · Stack-Profil: `swiftui-ios` + `swiftui-macos`

> **Gelesener Code-Stand: `main` @ `c01f1cf`, ohne Reparaturen.** Die parallel laufende Reparatur
> von B01 ist nicht berücksichtigt. `ChannelListView.swift`, `ChannelRowView.swift` und
> `PlayerTheme.swift` waren beim Abschluss unverändert; `Models/Channel.swift` ändert die Reparatur
> (Xtream-Stream-Adressen ohne Zugangsdaten), was hier nur die Anmerkungen zu mitgeladenen
> Zugangsdaten betrifft.

**Kein Code in diesem Dokument.** Beschrieben ist der Aufbau, wie er steht, nicht, wie er sein
sollte. Fragwürdiges ist markiert und verweist auf den *Fehlbestand* in `spec.md`. Messwerte und
Messumgebung stehen in `spec.md` (AK-32 bis AK-34).

## Überblick

Die Senderliste ist eine SwiftUI-Ansicht, die im Navigationsstapel des Playlists-Tabs liegt. Sie
hält Suchtext, gewählte Gruppe und die Liste der Gruppennamen als eigenen Zustand. Die eigentliche
Trefferliste ist eine Unteransicht mit einer `@Query`, die bei jeder Änderung von Suchtext oder
Gruppe mit neuem Filter neu erzeugt wird. SwiftData übersetzt den Filter in eine SQL-Abfrage auf
`ZCHANNEL`, mit Sortierung in SQLite, aber ohne Index. Die Gruppennamen berechnet die Ansicht
einmal beim Öffnen: Sie lädt dafür alle Sender der Playlist und dedupliziert im Speicher. Jede
Karte lädt ihr Logo mit `AsyncImage` direkt von der Adresse aus der Playlist, über die
Standard-`URLSession` der App samt Plattencache. Alles läuft auf dem Main-Thread.

## Szenen und Einstiege

SwiftUI, keine Routen. Plattform in Klammern.

| Einstieg | Zweck | Zugang |
|---|---|---|
| Tab „Playlists" → `PlaylistsView` → Karte einer Playlist (`NavigationLink(value:)`) → `.navigationDestination(for: Playlist.self)` | öffnet `ChannelListView(playlist:)` im selben `NavigationStack` (beide) | jeder Nutzer des Geräts |
| `ChannelListView` → Karte eines Senders → `.navigationDestination(for: Channel.self)` | öffnet `PlayerView` (B06) (beide) | ebenso |

Kein Deep Link, kein Menüeintrag, kein Tastenkürzel für Suche oder Gruppen (AS-05). Mehrere
Hauptfenster (macOS) haben je eigene Stapel und eigenen Zustand.

## Komponentenstruktur

```
PlaylistsView                                      (B03) navigationDestination(for: Playlist) → ChannelListView
└── ChannelListView                                @State searchText, selectedGroup, groups
    ├── ScrollView (vertikal, Indikatoren aus, Hintergrund playerBackground)
    │   └── VStack (Abstand 22, oben 8, unten 32)
    │       ├── PlayerHeader                       „MIKA+PLAYER · <playlist.channelCount> SENDER" + playlist.name
    │       └── ChannelResultsList                 privat; bei jeder Zustandsänderung neu initialisiert
    │           │  init(playlistID, searchText, group) → @Query(filter:sort:)
    │           ├── [leer, Suchtext leer]          eigener Leerzustand: tv.slash 44 pt, „Keine Sender", „Diese Playlist enthält keine Sender."  ⚠ FB-03
    │           ├── [leer, Suchtext gesetzt]       ContentUnavailableView.search(text:) — Systemtext, englisch (OF-03)
    │           └── LazyVStack (Abstand 10, Rand 20)
    │               └── ForEach(channels)
    │                   └── NavigationLink(value: channel), Stil .plain
    │                       └── ChannelRowView(channel:).playerCard()
    │                           ├── logo           AsyncImage(url: logoURL), 48 × 48, Radius 8, Fläche secondary 10 %
    │                           │   ├── .success   Bild resizable, scaledToFit, Innenabstand 4
    │                           │   ├── .failure   Platzhalter SF Symbol „tv", title3, secondary
    │                           │   └── .empty     ProgressView  ⚠ FB-04 (bleibt ohne URL und bei Verbindungsfehlern)
    │                           ├── Name           headline, eine Zeile
    │                           ├── PlayerBadge    Gruppe, wenn group != nil und nicht leer (ungekürzt)
    │                           ├── [macOS] ⊞      B08
    │                           └── ☆              B05
    ├── .safeAreaInset(edge: .top)                 groupFilterBar, nur wenn groups.count > 1
    │   └── ScrollView (horizontal) auf .bar
    │       └── HStack (Abstand 8, Rand 20/10)
    │           ├── GroupChip „Alle"               gewählt, wenn selectedGroup == nil
    │           └── GroupChip je Gruppe            Tipp: gleiche Gruppe → nil, sonst setzen
    ├── .navigationTitle(playlist.name)            iOS: .inline
    ├── .navigationDestination(for: Channel.self) → PlayerView (B06)
    ├── .searchable(text: $searchText, prompt: „Sender suchen")   Standardplatz: iOS Navigationsleiste, macOS Toolbar
    └── .task(id: playlist.id) { loadGroups() }    läuft beim Erscheinen; ID ändert sich beim Aktualisieren nicht ⚠ FB-02

GroupChip (privat)                                 Kapsel; gewählt: playerAccent + Weiß, sonst secondary 16 % + primary;
                                                   subheadline medium, eine Zeile, Innenabstand 14/7; kein Auswahl-Trait ⚠ FB-11
```

### Ablauf beim Tippen

```
Tastendruck im Suchfeld
  → searchText ändert sich (@State)
  → ChannelListView.body neu → neue ChannelResultsList(playlistID, searchText, selectedGroup)
  → neue @Query → SwiftData-Fetch auf dem Main-Thread, ohne Verzögerung, ohne Limit      ⚠ FB-10
      SQL: SELECT <alle Spalten> FROM ZCHANNEL
           WHERE ZPLAYLISTID = ? [AND NSCoreDataStringSearch(ZNAME, ?, 417, 1)] [AND ZGROUP = ?]
           ORDER BY ZNAME COLLATE NSCollateLocaleSensitive
      Plan: SCAN ZCHANNEL, USE TEMP B-TREE FOR ORDER BY                                    ⚠ FB-08
  → alle Treffer als Channel-Objekte → LazyVStack baut die sichtbaren Karten
  → sichtbare Karten starten AsyncImage-Ladevorgänge; weggefallene Karten brechen ihre ab
```

### Ablauf beim Öffnen

```
push ChannelListView
  → body: PlayerHeader + ChannelResultsList("" , nil) → Fetch aller Sender der Playlist (17.000 Objekte)
  → .task(id: playlist.id) → loadGroups()
      FetchDescriptor(playlistID == id), propertiesToFetch = [group]   → SQL liest trotzdem alle Spalten ⚠ FB-09
      group?.trimmingCharacters(in: .whitespaces), leer verwerfen, Set, sorted() (Zeichencode)
      → groups
  → groups.count > 1 → Chip-Leiste
```

### Beteiligte Typen

| Typ | Datei | Rolle in B04 |
|---|---|---|
| `ChannelListView` | `Views/ChannelListView.swift:7-81` | Seite, Zustand (`searchText`, `selectedGroup`, `groups`), Suchfeld, Chip-Leiste, `loadGroups()` |
| `ChannelResultsList` | `Views/ChannelListView.swift:84-134` (privat) | dynamische `@Query`, Leerzustände, `LazyVStack` der Karten |
| `GroupChip` | `Views/ChannelListView.swift:137-157` (privat) | Filter-Chip |
| `ChannelRowView` | `Views/ChannelRowView.swift` | Karteninhalt: Logo, Name, Badge; Stern (B05) und ⊞ (B08) |
| `PlayerHeader`, `PlayerBadge`, `.playerCard()` | `Views/Theme/PlayerTheme.swift:60-138` | gemeinsame Mika+-Komponenten |
| `Channel`, `Playlist` | `Models/` | Datenquelle, nur gelesen |
| `AsyncImage`, `URLSession.shared`, `URLCache.shared` | System | Logo-Abruf und -Cache |

## Datenmodell

Aus `docs/datenmodell.md`, beschränkt auf das, was B04 liest. B04 **schreibt nichts** in die
Datenbank (der Stern in der Karte gehört zu B05). Keine neuen Felder, keine Schemaänderung, keine
Migration.

### Entität `Playlist` (Tabelle `ZPLAYLIST`) — gelesen

| Feld | Typ | Wofür in B04 |
|---|---|---|
| `id` | `UUID` | Filterwert für `Channel.playlistID`; Schlüssel von `.task(id:)` |
| `name` | `String` | Titel und Kopfzeile |
| `channelCount` | `Int` | Zahl in der Kopfzeile, unabhängig vom Filter (OF-05) |

### Entität `Channel` (Tabelle `ZCHANNEL`) — gelesen

| Feld | Typ | Wofür in B04 |
|---|---|---|
| `playlistID` | `UUID?` (`ZPLAYLISTID`, BLOB) | ⚠ Filter auf die Playlist, **ohne Index** (FB-08) |
| `name` | `String` (`ZNAME`) | Anzeige, Suche (`localizedStandardContains`), Sortierung (`.localized`) |
| `group` | `String?` (`ZGROUP`) | Badge, Chips (gekürzt), Filter (ungekürzt) ⚠ FB-01 |
| `logoURL` | `URL?` (`ZLOGOURL`) | Logo-Abruf |
| `id` | `UUID` | Identität in `ForEach` (die eigene `id` erfüllt `Identifiable`) |
| `streamURL`, `tvgID`, `isFavorite`, `playlist` | — | nicht angezeigt, aber von beiden Abfragen mitgeladen (bei Xtream samt Zugangsdaten im Pfad) |

Beziehungen: eine `Playlist` hat viele `Channel` (`cascade`). B04 nutzt die Beziehung nicht.

**Indizes:** nur `ZCHANNEL_ZPLAYLIST_INDEX` auf `ZPLAYLIST`. Kein Index auf `ZPLAYLISTID`, `ZNAME`,
`ZGROUP` (DM-05). `#Index` wäre erst ab iOS 18 / macOS 15 verfügbar.

### Abfragen

| Abfrage | Auslöser | SQL (gekürzt) | Plan |
|---|---|---|---|
| Trefferliste | Öffnen, jede Änderung von Suchtext oder Gruppe | `SELECT <alle> FROM ZCHANNEL WHERE ZPLAYLISTID = ? [AND NSCoreDataStringSearch(ZNAME, ?, 417, 1)] [AND ZGROUP = ?] ORDER BY ZNAME COLLATE NSCollateLocaleSensitive` | `SCAN`, `USE TEMP B-TREE FOR ORDER BY` |
| Gruppenliste | `.task(id: playlist.id)` beim Erscheinen | `SELECT <alle> FROM ZCHANNEL WHERE ZPLAYLISTID = ?` — `propertiesToFetch` wirkungslos | `SCAN` |
| Vergleich (nicht benutzt) | — | `… WHERE ZPLAYLIST = ?` | `SEARCH … USING INDEX ZCHANNEL_ZPLAYLIST_INDEX` |

`NSCoreDataStringSearch` ist eine Core-Data-eigene SQLite-Funktion; sie ist in der Datenbank
unempfindlich gegen Groß-/Klein, Akzente und Zeichenbreite. Die Swift-Methode
`localizedStandardContains` im Speicher ist dagegen **nicht** breitenunempfindlich („ＡＲＤ"); die
App wertet aber nur in der Datenbank aus.

### Außerhalb des Schemas gespeichert

| Ort | Inhalt | Entsteht durch |
|---|---|---|
| `Cache.db` (+ `fsCachedData/` für große Antworten), macOS `~/Library/Caches/<Bundle-ID>/`, iOS `Library/Caches` | ⚠ Logo-Adressen, Antwortkopfzeilen und -inhalte, auch `no-store`, 404, HTML (FB-07) | `AsyncImage` über `URLSession.shared` / `URLCache.shared` (512 KB Speicher, 20 MB Platte) |

### Nicht persistiert

Suchtext, gewählte Gruppe, Gruppenliste, Scrollposition, geladene Bilder im Arbeitsspeicher. Alles
geht beim Verlassen der Liste verloren (AK-16).

## Zugriffsregeln

Die App hat keine Konten und keine Rollen.

| Wer | Darf lesen | Darf schreiben | Erzwungen durch |
|---|---|---|---|
| Nutzer der App | alle Sender aller Playlists; B04 zeigt nur die der geöffneten | nichts in B04 | fachlicher Filter `playlistID` in der Abfrage, sonst nichts |
| andere Prozesse desselben macOS-Benutzers | ⚠ `default.store` und `Cache.db` samt Logo-Verlauf | dieselben Dateien | nichts: App-Sandbox aus (B01 FB-09) |
| andere Apps unter iOS | nichts | nichts | iOS-App-Sandbox |
| Logo-Hosts und Weiterleitungsziele | ⚠ IP, User-Agent (App, Build, OS), Sprache, welche Sender sichtbar sind | — | nichts (FB-06) |
| Mitleser im Netz | ⚠ Logo-Adressen und -Inhalte bei `http://` | — | nichts: `NSAllowsArbitraryLoads` (`Info.plist:39-40`) |

## Missbrauchsschutz und Grenzen

| Stelle | Grenze | Verhalten bei Überschreitung | Wo konfiguriert |
|---|---|---|---|
| Anzahl gleichzeitiger Logo-Anfragen | nur die sichtbaren Karten (bei 700 pt Höhe 6–7) | beim Wegscrollen und Verlassen abgebrochen | `LazyVStack` + `AsyncImage` (System) |
| Größe und Abmessung eines Logos | **keine** | wird vollständig geladen und dekodiert, 640 MB gemessen (FB-05) | — |
| Dauer eines Logo-Abrufs | 60 s ohne Daten | Abbruch, Ladeindikator bleibt (FB-04); tröpfelnde Hosts unbegrenzt (FB-05) | `URLSession`-Standard |
| Weiterleitungen | Systemgrenze (21 Anfragen gemessen) | Abbruch, Ladeindikator bleibt | `URLSession`-Standard |
| Plattencache | 20 MB | System räumt ältere Einträge | `URLCache.shared`-Standard |
| Suchtext | **keine** Längengrenze | 10.000 Zeichen: 10 ms, kein Treffer | — |
| Abfragen je Tastendruck | **keine** Entprellung, keine Trefferobergrenze | Oberfläche blockiert je Zeichen 43–143 ms, Eingaben stauen sich (FB-10) | — |

## Externe Dienste

| Dienst | Wofür | Was geht hin | Was wird vorher entfernt |
|---|---|---|---|
| Host aus `Channel.logoURL` (`tvg-logo` bzw. `stream_icon`), beliebig | Senderlogo | ⚠ GET auf die Logo-Adresse; IP; `User-Agent: Mika+Player/<Build> CFNetwork/… Darwin/…`; `Accept-Language` der Systemsprache; `Accept: */*`; `Accept-Encoding: gzip, deflate`; zeitlich: welche Sender gerade sichtbar sind | nichts; keine Cookies, kein Referer |
| Ziel einer Weiterleitung des Logo-Hosts | wie oben | wie oben | nichts |
| lokale Datei bei `file://`-Logo-Adresse | Senderlogo | — (kein Netz) | — (OF-06) |

Kein KI-Dienst, keine Analyse, kein Fehler-Tracking, kein Server von daumedia. Der Suchtext geht
an niemanden.

## Erkennbare Entscheidungen

| # | Entscheidung | Alternative | Warum so |
|---|---|---|---|
| 1 | Trefferliste als Unteransicht mit dynamischer `@Query`, bei jeder Eingabe neu gebaut | alle Sender einmal laden und im Speicher filtern | CLAUDE.md, README, Kommentar `ChannelListView.swift:4-6`: DB-gestützt, damit 17.000 Sender flüssig bleiben |
| 2 | ⚠ Filter über die Kopie `playlistID` | Filter über die Beziehung `playlist` (hätte den FK-Index genutzt) | Kommentar `Channel.swift:19-21`: „ohne optionales Relationship-Keypath-Traversal", „schnell, robust". Dass dadurch der einzige Index ungenutzt bleibt, wurde offenbar nicht bedacht (FB-08) |
| 3 | ⚠ Gruppenliste einmal je Öffnen über `.task(id: playlist.id)`, im Speicher dedupliziert | Gruppen beim Import als eigene Liste an der Playlist speichern; `.task(id:)` an einen Refresh-Zeitpunkt koppeln | Kommentar `ChannelListView.swift:69`: „einmalig (statt pro Render zu scannen)". Folgen FB-02, FB-09 |
| 4 | Chips gekürzt, Filter ungekürzt | beides gekürzt, oder Gruppen beim Import normalisieren | Grund nicht erkennbar; vermutlich übersehen (FB-01) |
| 5 | Sortierung `.localized` (wie `localizedCompare`) | `.localizedStandard` mit Zahlensortierung; Reihenfolge des Anbieters | Grund nicht erkennbar (OF-01) |
| 6 | Chip-Sortierung `sorted()` nach Zeichencode | lokalisierte Sortierung wie bei den Sendern | Grund nicht erkennbar (OF-02) |
| 7 | Suche mit `localizedStandardContains` | `contains` (exakt) oder Präfixsuche mit Index | gängige SwiftUI-Wahl für eine tolerante Suche; läuft in SQL |
| 8 | Keine Entprellung der Suche | Suche nach kurzer Pause oder im Hintergrund | Grund nicht erkennbar (FB-10) |
| 9 | ⚠ Logos per `AsyncImage` ohne eigene Session | eigener Loader mit Größen-/Zeitgrenze, eigenem Cache, Abschaltschalter, nur HTTPS | README: „Logos via `AsyncImage`" — einfachste Lösung; Grenzen und Datenabfluss nicht berücksichtigt (FB-04 bis FB-07) |
| 10 | Chip-Leiste als `safeAreaInset(edge: .top)` auf `.bar`, nur bei > 1 Gruppe | Leiste im Scrollinhalt; immer anzeigen | bleibt beim Scrollen stehen; eine einzelne Gruppe filtert nichts |
| 11 | Kopfzeile aus `channelCount` | Trefferzahl anzeigen | CLAUDE.md: Zählen ohne Faulten der Beziehung; dass die Zahl beim Filtern nicht mitläuft, ist Folge (OF-05) |
| 12 | Zwei Leerzustands-Muster (eigen und `ContentUnavailableView.search`) | ein gemeinsames Muster | Grund nicht erkennbar (DS-05); das Systemmuster bringt englischen Text mit (OF-03) |
| 13 | Suchfeld am Standardplatz von `.searchable` | eigenes Suchfeld im Inhalt | Systemverhalten je Plattform |

## Abdeckung der Akzeptanzkriterien

Umgedreht: Was erfüllt das Kriterium heute? Fundstellen beziehen sich auf `Sources/` @ `c01f1cf`.

| AK | Erfüllt durch | Anmerkung |
|---|---|---|
| AK-01 | `Views/PlaylistsView.swift:30-31, 67-69`; `Views/ChannelListView.swift:15-44` (Header `:18-21`, Titel `:35-38`, Suchfeld `:42`); `Views/Theme/PlayerTheme.swift:83-115` | macOS-Toolbar über `.searchable` |
| AK-02 | `Views/ChannelListView.swift:19` (`playlist.channelCount`) | OF-05 |
| AK-03 | `Views/ChannelRowView.swift:14-32, 35-57`; `Views/Theme/PlayerTheme.swift:60-79, 118-138` | Badge-Bedingung `:22` prüft nur `isEmpty` (EC-01) |
| AK-04 | `Views/ChannelListView.swift:39-41, 111-114` | Stern/⊞ als eigene `.plain`-Buttons in der Karte |
| AK-05 | `Views/ChannelListView.swift:109-116` (`LazyVStack`); `Views/ChannelRowView.swift:36` (`AsyncImage` startet beim Erscheinen) | Systemverhalten |
| AK-06 | `Views/ChannelListView.swift:11, 23-27, 42, 88-97` (nur `ch.name`, nur `playlistID`) | keine Entprellung |
| AK-07 | `Views/ChannelListView.swift:94` → SQL `NSCoreDataStringSearch(…, 417, 1)` | Verhalten der Core-Data-Funktion; Breitenunempfindlichkeit nur in SQL |
| AK-08 | wie AK-07; kein Trimmen von `searchText` | — |
| AK-09 | `Views/ChannelListView.swift:97` (`SortDescriptor(\.name, comparator: .localized)`) → `COLLATE NSCollateLocaleSensitive` | OF-01 |
| AK-10 | `Views/ChannelListView.swift:34, 48-67` (Bedingung `:50`) | — |
| AK-11 | `Views/ChannelListView.swift:77-79` (`.whitespaces` ohne Zeilenumbrüche, `Set`) | — |
| AK-12 | `Views/ChannelListView.swift:79` (`sorted()`) | OF-02 |
| AK-13 | `Views/ChannelListView.swift:53-59, 137-157` | FB-11 |
| AK-14 | `Views/ChannelListView.swift:77` gegen `:95` | ⚠ FB-01 |
| AK-15 | wie AK-14, Leerzustand `:101-104, 121-133` | ⚠ FB-01, FB-03 |
| AK-16 | `Views/ChannelListView.swift:11-13` (`@State` je Ansichtsinstanz), `:43` | — |
| AK-17 | `Views/ChannelListView.swift:43` (`task(id: playlist.id)`) gegen `:85` (`@Query` beobachtet den Kontext); B03 `PlaylistImporter.refresh` | ⚠ FB-02 |
| AK-18 | `Views/ChannelListView.swift:101-104, 121-133`; Leiste entfällt über `:50` | DS-05 |
| AK-19 | `Views/ChannelListView.swift:101-104` (nur `searchText.isEmpty` geprüft) | ⚠ FB-03 |
| AK-20 | `Views/ChannelListView.swift:105-106` (`ContentUnavailableView.search`) | Bundle ohne `.lproj`/String-Kataloge, Entwicklungssprache `$(DEVELOPMENT_LANGUAGE)` = `en`, daher Systemtext englisch (OF-03) |
| AK-21 | `Views/ChannelRowView.swift:36-47, 53-57` | — |
| AK-22 | `Views/ChannelRowView.swift:42-43` (`.empty` → `ProgressView`) | ⚠ FB-04 |
| AK-23 | `AsyncImage`-Aufgabe endet mit dem Verschwinden der Karte; `URLSession`-Standard-Timeout 60 s | Systemverhalten |
| AK-24 | `Views/ChannelRowView.swift:36` (keine Grenze) | ⚠ FB-05 |
| AK-25 | `Views/ChannelRowView.swift:36`; `Resources/Info.plist:39-40` | ⚠ FB-06 |
| AK-26 | `URLSession.shared`-Standardkopfzeilen; `CFBundleName` „Mika+Player", Build aus `CURRENT_PROJECT_VERSION` | ⚠ FB-06 |
| AK-27 | AK-05 + AK-21 zusammen | ⚠ FB-06 |
| AK-28 | `URLCache.shared` (kein eigener Cache, kein Leeren im Code) | ⚠ FB-07 |
| AK-29 | Fehlen jedes Logging-, Speicher- oder Netzwerkaufrufs mit `searchText` in `Sources/` | — |
| AK-30 | `Views/ChannelRowView.swift:14-32` zeigt nur Logo, Name, Gruppe | Stream-Adressen werden dennoch geladen (AK-33) |
| AK-31 | `Views/ChannelListView.swift:88-97` → SwiftData → SQL | CLAUDE.md „Filter/Sortierung in der DB" |
| AK-32 | `Views/ChannelListView.swift:73, 93`; `Models/Channel.swift:19-22`; SQLite-Schema | ⚠ FB-08 |
| AK-33 | `Views/ChannelListView.swift:70-80` | ⚠ FB-09 |
| AK-34 | `Views/ChannelListView.swift:23-27, 42, 85, 88-97`, alles auf dem Main-Actor | ⚠ FB-10 |

### Code ohne AK-Zuordnung

- **`ChannelRowView.favoriteButton`** (`ChannelRowView.swift:59-69`) und **`multiviewButton`**
  (`:71-86`) sowie `@Environment(\.modelContext)` (`:7`) und `MultiviewSession`/`openWindow`
  (`:8-11`): gehören zu B05 bzw. B08.
- **`@unknown default: placeholder`** (`ChannelRowView.swift:44-45`): Schutzfall für künftige
  `AsyncImage`-Phasen, heute unerreichbar.
- **`.scrollIndicators(.hidden)`** (`ChannelListView.swift:32`): Die Liste hat keinen sichtbaren
  Rollbalken, auch nicht bei 17.000 Sendern. Beobachtbar, aber ohne eigenes Kriterium; bei der QA
  als Bedienbarkeitsfrage mitprüfen.
- **`.navigationDestination(for: Channel.self)`** ist zusätzlich in `FavoritesView` deklariert
  (B05); beide liegen in getrennten Stapeln und stören sich nicht.

### Bestehende Tests

Keine. Suche, Sortierung, Gruppen, Leerzustände, Logo-Verhalten und Leistung sind ungetestet. Die
Sonde, mit der die Kriterien belegt wurden, lief nur in einer Kopie und ist wieder entfernt; die
QA muss eigene Tests anlegen.
