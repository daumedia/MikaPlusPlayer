import Foundation
import SwiftData

/// Welche neuen Sender beim Aktualisieren Favorit werden (B03 · BUG-02, B05 · BUG-01).
///
/// Der Schlüssel (`Channel.favoriteKey`: tvg-ID bzw. Name in Kleinbuchstaben) entscheidet, **ob** ein neuer Sender
/// einen Favoriten übernehmen darf. Je Schlüssel werden aber höchstens so viele Sender Favorit, wie es vorher
/// Favoriten mit diesem Schlüssel gab. Welcher der Kandidaten den Stern bekommt, entscheidet in dieser Reihenfolge:
/// dieselbe Stream-Adresse, derselbe Name, sonst der erste Kandidat in der Reihenfolge des Anbieters.
enum FavoriteCarryOver {
    struct Previous: Sendable, Equatable {
        let key: String
        let streamURL: URL
        let name: String
    }

    static func flags(previous: [Previous], new channels: [ParsedChannel]) -> [Bool] {
        var flags = Array(repeating: false, count: channels.count)
        guard !previous.isEmpty else { return flags }
        let wanted = Dictionary(grouping: previous, by: \.key)
        var candidates: [String: [Int]] = [:]
        for (index, channel) in channels.enumerated() {
            let key = Channel.favoriteKey(name: channel.name, tvgID: channel.tvgID)
            if wanted[key] != nil { candidates[key, default: []].append(index) }
        }
        for (key, favorites) in wanted {
            guard var open = candidates[key], !open.isEmpty else { continue }
            var unmatched: [Previous] = []
            for favorite in favorites {
                if let hit = open.firstIndex(where: { channels[$0].streamURL == favorite.streamURL }) {
                    flags[open.remove(at: hit)] = true
                } else {
                    unmatched.append(favorite)
                }
            }
            var rest = 0
            for favorite in unmatched {
                if let hit = open.firstIndex(where: { channels[$0].name == favorite.name }) {
                    flags[open.remove(at: hit)] = true
                } else {
                    rest += 1
                }
            }
            for _ in 0..<rest where !open.isEmpty {
                flags[open.removeFirst()] = true
            }
        }
        return flags
    }
}

/// Einziger Schreibweg für Playlists und Sender, abseits des Main-Actors (B02 · BUG-04, B03 · BUG-01).
///
/// Anlegen, Ersetzen und Löschen laufen nacheinander über diesen Actor, jeder Vorgang in einem eigenen
/// `ModelContext`. Die Beziehung wird blockweise bzw. auf einmal gesetzt (`append(contentsOf:)`, `channels = []`),
/// nie je Sender – das wäre quadratisch (17.000 Sender: fast 5 Minuten).
///
/// Die Ansicht (Kontext des Main-Actors) sieht die Änderungen, sobald `PlaylistImporter` die Playlist dort neu
/// abruft; Sender, die eine Ansicht über eine Abfrage erhalten hat, bleiben dabei lesbar.
actor PlaylistStore {
    static let shared = PlaylistStore()

    /// Anzahl Sender je Speichervorgang beim Anlegen.
    static let batchSize = 5_000

    struct Draft: Sendable {
        var id: UUID
        var name: String
        var sourceURL: URL?
        var lastRefreshed: Date?
        var isXtream = false
        var xtreamOutput: String?
    }

    /// Schlüsselbund-Änderung, die nur gelten darf, wenn die Playlist beim Ersetzen noch existiert (B03 · BUG-08).
    enum CredentialUpdate: Sendable {
        case xtream(XtreamSecret)
        case m3u(M3USecret)

        func apply(_ store: XtreamCredentialStore, for id: UUID) throws {
            switch self {
            case .xtream(let secret): try store.save(secret, for: id)
            case .m3u(let secret): try store.saveM3U(secret, for: id)
            }
        }
    }

    enum ReplaceOutcome: Sendable, Equatable {
        case replaced(channelCount: Int)
        /// Die Playlist wurde inzwischen gelöscht (oder wird gerade gelöscht) – nichts geändert.
        case playlistGone
    }

    /// Playlists, deren Löschen läuft. Ein Ersetzen, das danach an die Reihe kommt, ändert nichts mehr.
    private var deleting: Set<UUID> = []

    // MARK: - Anlegen

    /// Legt Playlist und Sender an. Scheitert ein Block oder wird die aufrufende Aufgabe abgebrochen, wird die
    /// Playlist samt bereits gespeicherter Sender wieder entfernt.
    func create(_ draft: Draft, channels: [ParsedChannel], in container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let playlist = Playlist(id: draft.id, name: draft.name, sourceURL: draft.sourceURL,
                                lastRefreshed: draft.lastRefreshed, isXtream: draft.isXtream,
                                xtreamOutput: draft.xtreamOutput)
        context.insert(playlist)
        do {
            var start = channels.startIndex
            while start < channels.endIndex {
                try Task.checkCancellation()
                let end = min(start + Self.batchSize, channels.endIndex)
                var batch: [Channel] = []
                batch.reserveCapacity(end - start)
                for item in channels[start..<end] {
                    let channel = Self.makeChannel(item, playlistID: draft.id, isFavorite: false)
                    context.insert(channel)
                    batch.append(channel)
                }
                playlist.channels.append(contentsOf: batch)
                playlist.channelCount = end - channels.startIndex
                try context.save()
                start = end
            }
        } catch {
            context.rollback()
            let cleanup = ModelContext(container)
            cleanup.autosaveEnabled = false
            if let leftover = try? Self.find(draft.id, nil, in: cleanup) {
                Self.detachAndDeleteChannels(of: leftover, in: cleanup)
                cleanup.delete(leftover)
                try? cleanup.save()
            }
            throw error
        }
    }

    // MARK: - Ersetzen (Aktualisieren)

    /// Ersetzt alle Sender in **einem** Speichervorgang: Scheitert er, bleibt die alte Liste vollständig erhalten
    /// (B03 AK-18, B05 · BUG-11). Favoriten gehen nach `FavoriteCarryOver` auf die neuen Sender über.
    func replaceChannels(of id: UUID, persistentID: PersistentIdentifier?, with channels: [ParsedChannel],
                         refreshedAt: Date, newSourceURL: URL?, credentialUpdate: CredentialUpdate?,
                         credentialStore: XtreamCredentialStore, in container: ModelContainer) throws -> ReplaceOutcome {
        guard !deleting.contains(id) else { return .playlistGone }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        guard let playlist = try Self.find(id, persistentID, in: context) else { return .playlistGone }
        try credentialUpdate?.apply(credentialStore, for: id)

        let old = playlist.channels
        let previous = old.filter(\.isFavorite).map {
            FavoriteCarryOver.Previous(key: $0.favoriteKey, streamURL: $0.streamURL, name: $0.name)
        }
        let flags = FavoriteCarryOver.flags(previous: previous, new: channels)
        playlist.channels = []
        for channel in old { context.delete(channel) }
        var fresh: [Channel] = []
        fresh.reserveCapacity(channels.count)
        for (index, item) in channels.enumerated() {
            let channel = Self.makeChannel(item, playlistID: id, isFavorite: flags[index])
            context.insert(channel)
            fresh.append(channel)
        }
        playlist.channels.append(contentsOf: fresh)
        playlist.channelCount = fresh.count
        playlist.lastRefreshed = refreshedAt
        if let newSourceURL { playlist.sourceURL = newSourceURL }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw PlaylistStoreError.saveFailed
        }
        return .replaced(channelCount: fresh.count)
    }

    // MARK: - Löschen

    func beginDelete(_ ids: Set<UUID>) { deleting.formUnion(ids) }
    func endDelete(_ ids: Set<UUID>) { deleting.subtract(ids) }

    /// Schwerer Teil des Löschens: entfernt alle Sender der Playlist (und setzt `channelCount` auf 0) in einem
    /// Speichervorgang. Die Zeile der Playlist selbst entfernt danach der Kontext der Ansicht, damit deren
    /// Abfragen sofort stimmen. - Returns: false, wenn es die Playlist nicht (mehr) gibt.
    @discardableResult
    func removeChannels(of id: UUID, persistentID: PersistentIdentifier?, in container: ModelContainer) throws -> Bool {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        guard let playlist = try Self.find(id, persistentID, in: context) else { return false }
        Self.detachAndDeleteChannels(of: playlist, in: context)
        playlist.channelCount = 0
        do {
            try context.save()
        } catch {
            context.rollback()
            throw PlaylistStoreError.saveFailed
        }
        return true
    }

    /// Entfernt die Sender **aller** Playlists („Alle Daten entfernen", B03 · BUG-09).
    func removeAllChannels(in container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        for playlist in try context.fetch(FetchDescriptor<Playlist>()) {
            Self.detachAndDeleteChannels(of: playlist, in: context)
            playlist.channelCount = 0
        }
        // Sender ohne Playlist (nur bei beschädigten Beständen denkbar)
        for orphan in try context.fetch(FetchDescriptor<Channel>()) { context.delete(orphan) }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw PlaylistStoreError.saveFailed
        }
    }

    /// Verdichtet die Datenbankdatei nach dem Löschen, damit gelöschte Namen und Adressen nicht in freien Seiten
    /// oder im Write-Ahead-Log stehen bleiben (B03 · BUG-07). Ohne Wirkung bei einer Datenbank im Speicher.
    func compact(_ container: ModelContainer) {
        guard let url = Self.storeURL(of: container) else { return }
        AppPersistence.compactStore(at: url)
    }

    static func storeURL(of container: ModelContainer) -> URL? {
        guard let configuration = container.configurations.first, !configuration.isStoredInMemoryOnly else { return nil }
        let url = configuration.url
        return url.path == "/dev/null" ? nil : url
    }

    // MARK: - Hilfen

    private static func makeChannel(_ item: ParsedChannel, playlistID: UUID, isFavorite: Bool) -> Channel {
        Channel(name: item.name, streamURL: item.streamURL, logoURL: item.logoURL, group: item.group,
                tvgID: item.tvgID, isFavorite: isFavorite, playlistID: playlistID)
    }

    /// Löst die Beziehung auf einmal und löscht dann die Sender – ohne quadratische Pflege der Gegenseite.
    private static func detachAndDeleteChannels(of playlist: Playlist, in context: ModelContext) {
        let old = playlist.channels
        playlist.channels = []
        for channel in old { context.delete(channel) }
    }

    /// Playlist über ihre `id`; bei (nur per Manipulation möglichen) Dubletten über die `persistentModelID`.
    private static func find(_ id: UUID, _ persistentID: PersistentIdentifier?, in context: ModelContext) throws -> Playlist? {
        let matches = try context.fetch(FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == id }))
        guard matches.count > 1 else { return matches.first }
        guard let persistentID else { return nil }
        return matches.first { $0.persistentModelID == persistentID }
    }
}

enum PlaylistStoreError: LocalizedError, Equatable {
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Die Playlist konnte nicht gespeichert werden. Die bisherige Senderliste bleibt erhalten. "
                + "Bitte freien Speicherplatz prüfen und erneut versuchen."
        }
    }
}
