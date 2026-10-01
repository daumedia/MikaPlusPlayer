import Foundation
import SwiftData

/// Abfragen der Senderliste (B04). Laufen in einem eigenen `ModelContext` abseits des Main-Actors
/// (`ChannelListView` ruft sie aus einer abgelösten Aufgabe auf), damit auch 17.000 Sender die Oberfläche nicht
/// blockieren (B04 · BUG-13, BUG-14).
///
/// - Gefiltert wird über die **Beziehung** `Channel.playlist`. Ihre Spalte `ZPLAYLIST` hat als einzige einen Index
///   (`ZCHANNEL_ZPLAYLIST_INDEX`, von Core Data angelegt); die Kopie `playlistID` hat keinen und wird dafür nicht mehr
///   benutzt (B04 · BUG-12). `#Index` für weitere Spalten gibt es erst ab iOS 18/macOS 15.
/// - Die Trefferliste besteht nur aus Kennungen (`fetchIdentifiers`); die Sender selbst holt jede Karte, sobald sie
///   sichtbar wird (`channel(_:in:)`).
/// - Ein Gruppen-Chip steht für alle gespeicherten Gruppenwerte, die ohne Leerzeichen und Tabulatoren am Rand so heißen
///   (B04 · BUG-01); der Filter fragt genau diese Werte ab.
enum ChannelListQuery {
    /// Gruppen einer Playlist, wie die Chip-Leiste sie zeigt.
    struct Groups: Equatable, Sendable {
        /// Chip-Titel: gekürzt, einmalig, nach Zeichencode sortiert (AK-11, AK-12; Sortierung wartet auf OF-02).
        var chips: [String] = []
        /// Je Chip die gespeicherten Gruppenwerte, die gekürzt so heißen (z. B. „Sport“, „ Sport“, „Sport “).
        var values: [String: [String]] = [:]
    }

    /// Der Chip-Titel zu einem gespeicherten Gruppenwert; `nil` für keine, leere oder nur aus Leerzeichen bestehende
    /// Gruppen. Ein Zeilenumbruch bleibt Teil des Namens (AK-11, EC-02).
    static func chipTitle(_ group: String?) -> String? {
        guard let trimmed = group?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Die Abfrage der Trefferliste: Sender der Playlist, optional Suche im Namen (AK-06 bis AK-08) und gewählte
    /// Gruppe (alle gespeicherten Werte des Chips), sortiert nach Namen (AK-09).
    ///
    /// Die Beziehung steht mit `!` im Prädikat: So entsteht `t0.ZPLAYLIST IS NOT NULL AND t0.ZPLAYLIST = ?`, und SQLite
    /// sucht über `ZCHANNEL_ZPLAYLIST_INDEX`. Die Schreibweise mit `?.` ergäbe `CASE … END = ?` und damit wieder einen
    /// `SCAN` über alle Sender aller Playlists. Ausgewertet wird das Prädikat nur in SQLite (`includePendingChanges`
    /// aus); Sender ohne Playlist fallen dort über `IS NOT NULL` heraus.
    static func descriptor(playlist: PersistentIdentifier, search: String, groupValues: [String]?) -> FetchDescriptor<Channel> {
        let predicate: Predicate<Channel>
        switch (search.isEmpty, groupValues) {
        case (true, nil):
            predicate = #Predicate { $0.playlist!.persistentModelID == playlist }
        case (false, nil):
            predicate = #Predicate { $0.playlist!.persistentModelID == playlist && $0.name.localizedStandardContains(search) }
        case (true, let values?):
            if values.count == 1, let value = values.first {
                predicate = #Predicate { $0.playlist!.persistentModelID == playlist && $0.group == value }
            } else {
                predicate = #Predicate {
                    $0.playlist!.persistentModelID == playlist && $0.group != nil && values.contains($0.group!)
                }
            }
        case (false, let values?):
            if values.count == 1, let value = values.first {
                predicate = #Predicate {
                    $0.playlist!.persistentModelID == playlist && $0.name.localizedStandardContains(search) && $0.group == value
                }
            } else {
                predicate = #Predicate {
                    $0.playlist!.persistentModelID == playlist && $0.name.localizedStandardContains(search)
                        && $0.group != nil && values.contains($0.group!)
                }
            }
        }
        var descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.name, comparator: .localized)])
        descriptor.includePendingChanges = false
        return descriptor
    }

    /// Kennungen der Treffer in Anzeigereihenfolge (eigener Kontext; nicht auf dem Main-Actor aufrufen).
    static func identifiers(in container: ModelContainer, playlist: PersistentIdentifier, search: String,
                            groupValues: [String]?) throws -> [PersistentIdentifier] {
        let context = ModelContext(container)
        return try context.fetchIdentifiers(descriptor(playlist: playlist, search: search, groupValues: groupValues))
    }

    /// Gruppen der Playlist (eigener Kontext; nicht auf dem Main-Actor aufrufen).
    static func groups(in container: ModelContainer, playlist: PersistentIdentifier) throws -> Groups {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Channel>(predicate: #Predicate { $0.playlist!.persistentModelID == playlist })
        // SwiftData liest trotzdem alle Spalten (belegt mit SQLDebug); deshalb läuft das hier im Hintergrund.
        descriptor.propertiesToFetch = [\.group]
        descriptor.includePendingChanges = false
        var values: [String: Set<String>] = [:]
        for channel in try context.fetch(descriptor) {
            guard let raw = channel.group, let title = chipTitle(raw) else { continue }
            values[title, default: []].insert(raw)
        }
        return Groups(chips: values.keys.sorted(), values: values.mapValues { $0.sorted() })
    }

    /// Der Sender zu einer Kennung im Kontext der Ansicht – `nil`, wenn es ihn nicht mehr gibt. Unbekannte Kennungen
    /// werden per Abfrage geholt, nie als leere Hülle angelegt (eine gelöschte Zeile ergibt so keinen Absturz).
    @MainActor
    static func channel(_ id: PersistentIdentifier, in context: ModelContext) -> Channel? {
        if let registered: Channel = context.registeredModel(for: id) {
            return registered.isDeleted ? nil : registered
        }
        var descriptor = FetchDescriptor<Channel>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
