# Mika+Player — Datenmodell

Stand: 2026-09-15 · rekonstruiert aus `Sources/Models/`, `Sources/Services/PlaylistImporter.swift`
und dem SQLite-Schema einer lokalen Store-Datei (nur Schema gelesen, keine Inhalte)

> Bestandsprojekt: Anders als im Greenfield-Fall stehen die **Felder hier sofort**, weil sie
> existieren. Beschrieben ist, was der Code tut. Was davon fragwürdig ist, steht unter *Fehlbestand*.

## Überblick

Zwei SwiftData-Entitäten, kein Backend, keine Nutzer, keine Rollen. Das Schema ist seit dem
ersten Commit (2026-06-19) unverändert.

```
Playlist 1──n Channel
   │             │
   │ cascade     └─ playlistID (UUID, denormalisierte Kopie von Playlist.id)
   └─ channelCount (Int, denormalisierte Anzahl)
```

| Entität | Bedeutung |
|---|---|
| `Playlist` | eine importierte Senderquelle: Xtream-Zugang, M3U-URL oder lokale Datei |
| `Channel` | ein einzelner Sender mit Stream-URL, zugehörig zu genau einer Playlist |

## `Playlist`

`Sources/Models/Playlist.swift` · Tabelle `ZPLAYLIST`

| Feld | Typ | Pflicht | Bedeutung und tatsächliche Befüllung |
|---|---|---|---|
| `id` | `UUID` | ja | eigene stabile ID, beim Anlegen `UUID()`. **Kein** `@Attribute(.unique)` |
| `name` | `String` | ja | Anzeigename. Leer eingegeben → Host der URL, sonst `"Playlist"` bzw. `"Xtream"`; bei Datei der Dateiname ohne Endung |
| `sourceURL` | `URL?` | nein | M3U-URL: die eingegebene URL **unverändert** (inkl. etwaiger Zugangsdaten in der Query). Xtream: `http://host[:port]/player_api.php?username=…&password=…` **im Klartext**. Lokale Datei: `nil` |
| `createdAt` | `Date` | ja | Anlagezeitpunkt, Sortierschlüssel der Übersicht (absteigend) |
| `lastRefreshed` | `Date?` | nein | beim Import aus URL/Xtream gesetzt, nach jedem erfolgreichen Refresh aktualisiert; bei Datei `nil`. Wird nirgends angezeigt |
| `isXtream` | `Bool` | ja | `true`, wenn über `player_api.php` befüllt. Steuert den Refresh-Zweig |
| `xtreamOutput` | `String?` | nein | Rohwert von `XtreamOutput`: `"hls"` oder `"mpegts"`. Beim Refresh unbekannt/`nil` → Fallback `hls`. Der Code-Kommentar nennt abweichend `"m3u8"/"ts"` |
| `channelCount` | `Int` | ja | denormalisierte Senderanzahl, siehe *Invarianten* |
| `channels` | `[Channel]` | — | Beziehung, `deleteRule: .cascade`, Inverse `Channel.playlist` |

Abgeleitet, nicht gespeichert: `isRemote` = `sourceURL != nil` (steuert Refresh-Menü und Symbol).

## `Channel`

`Sources/Models/Channel.swift` · Tabelle `ZCHANNEL`

| Feld | Typ | Pflicht | Bedeutung und tatsächliche Befüllung |
|---|---|---|---|
| `id` | `UUID` | ja | beim Anlegen `UUID()`. **Kein** `@Attribute(.unique)`. Wechselt bei jedem Refresh, weil alle Sender neu angelegt werden |
| `name` | `String` | ja | M3U: Text nach dem ersten Komma außerhalb von Anführungszeichen, leer → letzter URL-Pfadbestandteil. Xtream: `name` aus `get_live_streams` |
| `streamURL` | `URL` | ja | M3U: URL-Zeile unverändert. Xtream: `http://host/live/<user>/<pass>/<stream_id>.<m3u8\|ts>`, **Benutzername und Passwort im Klartext im Pfad**, per String-Interpolation ohne Prozentkodierung gebaut |
| `logoURL` | `URL?` | nein | `tvg-logo` bzw. `stream_icon`; beliebiger Host |
| `group` | `String?` | nein | `group-title`, ersatzweise `#EXTGRP`; bei Xtream Kategoriename über `category_id` |
| `tvgID` | `String?` | nein | `tvg-id` bzw. `epg_channel_id`; leer → `nil`. Einzige Verwendung: Favoriten-Schlüssel |
| `isFavorite` | `Bool` | ja | vom Stern-Button umgeschaltet, sofort gespeichert |
| `playlist` | `Playlist?` | nein | Inverse der Cascade-Beziehung |
| `playlistID` | `UUID?` | nein | denormalisierte Kopie von `playlist.id`, siehe *Invarianten* |

Abgeleitet, nicht gespeichert: `favoriteKey` = `"id:<tvgID>"`, sonst `"name:<name kleingeschrieben>"`.

## Beziehungen und Löschregeln

| Beziehung | Kardinalität | Löschregel | Ausgelöst durch |
|---|---|---|---|
| `Playlist.channels` ↔ `Channel.playlist` | 1 : n | `.cascade`: Playlist löschen löscht alle Sender | Kontextmenü „Löschen" in der Playlist-Übersicht, **ohne Rückfrage** |
| Refresh | — | alle Sender der Playlist werden einzeln gelöscht und neu angelegt | Kontextmenü „Aktualisieren" |

Mit einer Playlist verschwinden auch die Favoriten ihrer Sender und die darin gespeicherten
Zugangsdaten. Einen Papierkorb oder ein Rückgängig gibt es nicht.

## Invarianten (von Hand gepflegt)

Beide Denormalisierungen werden **ausschließlich** in `PlaylistImporter.attach(_:to:preservedFavorites:)`
geschrieben — dem einzigen Ort, an dem `Channel`-Objekte entstehen.

| Invariante | Gepflegt in | Nicht gepflegt bei |
|---|---|---|
| `Channel.playlistID == Channel.playlist?.id` | `attach` | — (Sender wechseln nie die Playlist) |
| `Playlist.channelCount == Playlist.channels.count` | `attach` (nach Import und Refresh) | es gibt keinen weiteren Schreibpfad, der Sender einzeln löscht |
| Favorit bleibt über Refresh erhalten | `refresh` merkt `favoriteKey` der Favoriten, `attach` setzt `isFavorite` für jeden neuen Sender mit gleichem Schlüssel | — |

`favoriteKey` ist **nicht eindeutig**: Sender ohne `tvg-id` mit gleichem Namen, oder mehrere Sender
mit derselben `tvg-id` (z. B. HD/SD-Varianten), werden nach einem Refresh **alle** zu Favoriten,
wenn vorher einer davon markiert war.

## Abfragen

| Wo | Filter | Sortierung |
|---|---|---|
| `PlaylistsView` | alle Playlists | `createdAt` absteigend |
| `ChannelListView` → `ChannelResultsList` | `playlistID == id` ∧ (Suche leer ∨ `name.localizedStandardContains`) ∧ (keine Gruppe ∨ `group == g`) | `name`, lokalisiert |
| `ChannelListView.loadGroups` | `playlistID == id`, nur Feld `group` | distinct und Sortierung **im Speicher** über alle Sender der Playlist |
| `FavoritesView` | `isFavorite == true` | `name` |
| `PlaylistImporter.refresh` | — | lädt `playlist.channels` vollständig, um Favoriten zu merken und Sender zu löschen |

## Indizes

Laut SQLite-Schema existiert genau ein Index: `ZCHANNEL_ZPLAYLIST_INDEX` auf dem Fremdschlüssel
`ZPLAYLIST` (von Core Data automatisch angelegt). Auf **`ZPLAYLISTID`, `ZISFAVORITE` und `ZNAME`**,
über die gefiltert und sortiert wird, liegt **kein** Index. `#Index` ist erst ab iOS 18/macOS 15
verfügbar; das Deployment-Target ist iOS 17/macOS 14.

## Persistenz, Speicherort, Migration

| Thema | Ist-Stand |
|---|---|
| Container | `ModelContainer(for: Schema([Playlist, Channel]), configurations: [ModelConfiguration(schema:, isStoredInMemoryOnly: false)])` in `MikaPlusPlayerApp`; ein Container für Haupt- und Multiview-Fenster |
| Dateiname | kein `name`, keine `url` gesetzt → SwiftData-Standard `default.store` im Application-Support-Verzeichnis |
| Speicherort iOS | App-Container (sandboxed) |
| Speicherort macOS | App-Sandbox ist **aus** → **`~/Library/Application Support/default.store`**, nicht nach Bundle-ID getrennt. Belegt am 2026-09-15: Der Testlauf (App als Test-Host) hat genau diese Datei angelegt; vorher existierte sie nicht. Zwei ältere, leere Stores liegen in Sandbox-Containern aus Entwicklungsläufen vom 2026-06-19 |
| Verschlüsselung | keine über den Standard hinaus (iOS: Data Protection des Systems; macOS: FileVault, falls aktiv) |
| Backup | kein Ausschluss gesetzt (`isExcludedFromBackup` fehlt) → die Datenbank samt Zugangsdaten landet in Time Machine bzw. im iCloud-/Geräte-Backup |
| Sync | keiner (kein CloudKit, keine iCloud-Entitlements) |
| Schema-Versionierung | **keine** — kein `VersionedSchema`, kein `SchemaMigrationPlan`. Es greift nur die automatische Lightweight-Migration |
| Fehler beim Öffnen | `fatalError("ModelContainer konnte nicht erstellt werden")` → Absturz beim Start, kein Wiederherstellungsweg |
| Zugriff | Einzelnutzer, lokal. Keine Zugriffsregeln im Modell. Unter macOS ohne Sandbox kann jeder Prozess des Benutzers die Datei lesen |

## Laufzeitzustand mit Modellbezug

Kein Teil des Schemas, aber relevant beim Löschen und Aktualisieren:

- `MultiviewSession.Slot` (macOS) hält ein **`Channel`-Objekt direkt**, nicht dessen ID, und lebt so
  lange wie die App.
- `PlayerView` hält ebenfalls das `Channel`-Objekt.
- Refresh und Löschen einer Playlist löschen diese Objekte, während sie im Multiview oder Player
  noch referenziert sein können. Das Verhalten in diesem Fall ist nicht untersucht — Prüfpunkt für
  B03 und B08.

## Keine Entität

| Klingt nach Tabelle | Ist tatsächlich |
|---|---|
| Xtream-Zugangsdaten | `XtreamCredentials` (Struct, nicht persistiert) — wird beim Refresh aus `Playlist.sourceURL` **zurückgelesen** |
| Kategorien / Gruppen | nur als String in `Channel.group`; Liste der Gruppen wird bei jedem Öffnen der Senderliste neu berechnet |
| Import-Ergebnis | `ParsedChannel` (DTO, bewusst kein `@Model`) |
| Multiview-Belegung, Layout, Fokus | `MultiviewSession` (flüchtig, `@Observable`) — geht beim Beenden verloren |
| Wiedergabezustand, Lautstärke, Stumm | in der jeweiligen Engine-Instanz, flüchtig. Lautstärke wird **nicht** gespeichert |
| Einstellungen | kein eigener `UserDefaults`-/`@AppStorage`-Zugriff im Code. **Sparkle** schreibt jedoch `SU*`-Schlüssel (u. a. `SULastCheckTime`) in `lu.daumedia.MikaPlusPlayer.plist` (macOS, belegt bei der Rückerfassung von B09) |

## Fehlbestand

Was fehlt oder fragwürdig ist. Kein Kriterium, sondern Befund — die Bewertung macht `sdd-qa`.

| # | Befund | Fundstelle | Betrifft |
|---|---|---|---|
| DM-01 | Xtream-Passwort liegt im **Klartext** in `Playlist.sourceURL` und in **jeder** `Channel.streamURL` (17.000 Sender = 17.000 Kopien); keine Keychain | `XtreamCodes.swift:85-95`, `XtreamClient.swift:46`, `PlaylistImporter.swift:76` | B01, B03 |
| DM-02 | Zugangsdaten sind nicht vom Backup ausgeschlossen | `MikaPlusPlayerApp.swift:7-15` | B01 |
| DM-03 | macOS ohne Sandbox + Standard-Storename: Datenbank liegt als `~/Library/Application Support/default.store` — **belegt** (Testlauf 2026-09-15). Jede andere nicht-sandboxed App mit SwiftData-/Core-Data-Standardkonfiguration nutzt dieselbe Datei; die Kollision selbst ist nicht nachgestellt. Außerdem verwendet der Test-Host dieselbe Datei wie die echte App | `MikaPlusPlayerApp.swift:9` | alle |
| DM-04 | Keine Schema-Versionierung und `fatalError` beim Öffnen: Eine nicht automatisch migrierbare Modelländerung lässt die App nach dem Update beim Start abstürzen, ohne Ausweg für den Nutzer | `MikaPlusPlayerApp.swift:10-14` | alle, B09 |
| DM-05 | Keine Indizes auf `playlistID`, `isFavorite`, `name` — die als „DB-gestützt" beschriebene Suche filtert ohne Index über alle Sender aller Playlists | SQLite-Schema | B04, B05 |
| DM-06 | `favoriteKey` nicht eindeutig: Refresh kann aus einem Favoriten mehrere machen | `Channel.swift:48-51`, `PlaylistImporter.swift:136,169` | B05 |
| DM-07 | Gruppenliste und Refresh laden alle Sender einer Playlist in den Speicher — bei 17.000 Sendern entgegen der Begründung der Denormalisierung | `ChannelListView.swift:70-80`, `PlaylistImporter.swift:136-142` | B03, B04 |
| DM-08 | Löschen einer Playlist ohne Rückfrage, ohne Rückgängig, samt Favoriten | `PlaylistsView.swift:47-52,104-107` | B03 |
| DM-09 | `id`-Felder ohne `@Attribute(.unique)` | `Playlist.swift:10`, `Channel.swift:7` | — |
| DM-10 | Multiview und Player halten `Channel`-Objekte, die durch Refresh/Löschen ungültig werden können | `MultiviewSession.swift:37-41` | B03, B08 |
| DM-11 | Code-Kommentar zu `xtreamOutput` nennt Werte (`"m3u8"/"ts"`), die nie geschrieben werden | `Playlist.swift:21` | — |
