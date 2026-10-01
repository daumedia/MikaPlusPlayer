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

    /// Stand der Übernahme nach einem Ersetzen: welche alten Sender beim Lesen Favorit waren, die neue Liste in
    /// Anbieterreihenfolge mit den IDs der angelegten Sender und die daraus gesetzten Sterne. Grundlage, um Sterne
    /// nachzuziehen, die während des Ersetzens in der Ansicht gesetzt oder entfernt wurden (Review R-01).
    struct State: Sendable {
        struct ReadFavorite: Sendable {
            let channelID: UUID
            let previous: Previous
        }

        /// Favoriten der alten Liste, so wie `replaceChannels` sie gelesen hat
        let read: [ReadFavorite]
        let channels: [ParsedChannel]
        let newIDs: [UUID]
        /// Sterne der neuen Sender, wie sie in der Datenbank stehen (nach jedem Nachziehen aktualisiert)
        var flags: [Bool]

        /// Favoriten der alten Liste, als wären `edits` vor dem Lesen gespeichert worden.
        func previous(applying edits: [FavoriteEdit]) -> [Previous] {
            var final: [UUID: Bool] = [:]
            for edit in edits { final[edit.channelID] = edit.isFavorite }
            var result: [Previous] = []
            var known = Set<UUID>()
            for favorite in read {
                known.insert(favorite.channelID)
                if final[favorite.channelID] != false { result.append(favorite.previous) }
            }
            var added = Set<UUID>()
            for edit in edits where final[edit.channelID] == true && !known.contains(edit.channelID) {
                if added.insert(edit.channelID).inserted { result.append(edit.previous) }
            }
            return result
        }
    }
}

extension ParsedChannel {
    /// Name, Gruppe und `tvg-id` ohne Steuerzeichen (`Channel.removingControlCharacters`), B05 · BUG-09: Die
    /// Datenbankdatei kürzte einen Text mit NUL-Zeichen, der Favoriten-Schlüssel passte danach nicht mehr zur Liste
    /// des Anbieters. Gilt für M3U und Xtream gleich, weil beide Wege über `PlaylistStore` speichern. Eine Gruppe oder
    /// `tvg-id`, die dadurch leer wird, entfällt.
    var withoutControlCharacters: ParsedChannel {
        var copy = self
        copy.name = Channel.removingControlCharacters(name)
        copy.group = group.flatMap(Self.cleaned)
        copy.tvgID = tvgID.flatMap(Self.cleaned)
        return copy
    }

    private static func cleaned(_ value: String) -> String? {
        let result = Channel.removingControlCharacters(value)
        return result.isEmpty && !value.isEmpty ? nil : result
    }
}

/// Eine Stern-Änderung in der Ansicht: der Sender (wie beim Lesen erkannt) und sein Stern **danach**.
struct FavoriteEdit: Sendable, Equatable {
    let channelID: UUID
    let previous: FavoriteCarryOver.Previous
    var isFavorite: Bool
}

/// Stern setzen und entfernen – der eine Weg dafür (`ChannelRowView`), Review R-01.
///
/// Während eine Playlist aktualisiert wird, liest `PlaylistStore.replaceChannels` die Favoriten der alten Sender und
/// ersetzt danach alle Sender in einem Speichervorgang. Ein Stern, den die Ansicht in dieser Zeit an einem alten Sender
/// speichert, stünde sonst nur an einem Sender, den das Ersetzen löscht. Deshalb wird jede Änderung an Sendern einer
/// Playlist, die gerade aktualisiert wird, zusätzlich hier festgehalten; `PlaylistImporter.refresh` zieht sie nach dem
/// Ersetzen auf die neuen Sender nach (`PlaylistStore.reconcileFavorites`), bevor die Ansicht die neuen Sender zeigt.
/// Der Stern bleibt dabei die ganze Zeit bedienbar, und das Aktualisieren läuft weiter im Hintergrund.
@MainActor
enum FavoriteEdits {
    private static var journals: [UUID: [FavoriteEdit]] = [:]

    /// Schaltet den Stern um, speichert sofort und hält die Änderung fest, falls die Playlist des Senders gerade
    /// aktualisiert wird.
    ///
    /// Scheitert das Speichern (z. B. Datenträger voll), wird die Änderung verworfen (B05 · BUG-02): Der Kontext wird
    /// zurückgerollt – sonst schriebe ein späteres Speichern den Stern unbemerkt mit –, der Stern zeigt wieder den
    /// gespeicherten Zustand, und das Festgehaltene steht wie vor dem Klick, damit das Aktualisieren den verworfenen
    /// Stern nicht auf die neuen Sender nachzieht. Der Aufrufer meldet den Fehler.
    /// - Throws: `PlaylistStoreError.starNotSaved`
    static func toggle(_ channel: Channel, in context: ModelContext) throws {
        try toggle(channel, in: context, save: { try $0.save() })
    }

    /// Wie `toggle(_:in:)`, mit austauschbarem Speichern (Tests: Speicherfehler ohne vollen Datenträger).
    static func toggle(_ channel: Channel, in context: ModelContext, save: (ModelContext) throws -> Void) throws {
        let before = channel.isFavorite
        let journalBefore = channel.playlistID.flatMap { journals[$0] }
        channel.isFavorite.toggle()
        record(channel)
        do {
            try save(context)
        } catch {
            context.rollback()
            if channel.isFavorite != before { channel.isFavorite = before }
            if let playlistID = channel.playlistID, journals[playlistID] != nil { journals[playlistID] = journalBefore }
            throw PlaylistStoreError.starNotSaved
        }
    }

    static func record(_ channel: Channel) {
        guard let playlistID = channel.playlistID, journals[playlistID] != nil else { return }
        let edit = FavoriteEdit(
            channelID: channel.id,
            previous: FavoriteCarryOver.Previous(key: channel.favoriteKey, streamURL: channel.streamURL, name: channel.name),
            isFavorite: channel.isFavorite)
        if let index = journals[playlistID]?.firstIndex(where: { $0.channelID == edit.channelID }) {
            journals[playlistID]?[index].isFavorite = edit.isFavorite
        } else {
            journals[playlistID]?.append(edit)
        }
    }

    static func begin(_ playlistID: UUID) { journals[playlistID] = [] }

    /// Die seit dem letzten Aufruf festgehaltenen Änderungen; das Festhalten läuft weiter.
    static func take(_ playlistID: UUID) -> [FavoriteEdit] {
        guard let edits = journals[playlistID] else { return [] }
        journals[playlistID] = []
        return edits
    }

    static func end(_ playlistID: UUID) { journals[playlistID] = nil }

    /// Fasst Änderungen zusammen: je Sender zählt der letzte Stand, die Reihenfolge der ersten Änderung bleibt.
    static func merge(_ earlier: [FavoriteEdit], _ later: [FavoriteEdit]) -> [FavoriteEdit] {
        var result = earlier
        for edit in later {
            if let index = result.firstIndex(where: { $0.channelID == edit.channelID }) {
                result[index].isFavorite = edit.isFavorite
            } else {
                result.append(edit)
            }
        }
        return result
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

    enum ReplaceOutcome: Sendable {
        /// Ersetzt; `carryOver` dient dem Nachziehen von Sternen aus der Laufzeit (`reconcileFavorites`).
        case replaced(channelCount: Int, carryOver: FavoriteCarryOver.State)
        /// Die Playlist wurde inzwischen gelöscht (oder wird gerade gelöscht) – nichts geändert.
        case playlistGone
    }

    /// Playlists, deren Löschen läuft. Ein Ersetzen, das danach an die Reihe kommt, ändert nichts mehr.
    private var deleting: Set<UUID> = []

    /// Nur für Tests: läuft auf diesem Actor direkt nach dem gespeicherten Ersetzen, bevor `replaceChannels`
    /// zurückkehrt (Review R-01: Sterne im Moment zwischen Ersetzen und Abholen durch die Ansicht).
    private var afterReplaceSaved: (@Sendable () -> Void)?
    func setAfterReplaceSavedForTesting(_ hook: (@Sendable () -> Void)?) { afterReplaceSaved = hook }

    // MARK: - Anlegen

    /// `channelCount` einer Playlist, deren Anlegen noch läuft oder gescheitert ist (Review R-02). Kein gültiger Wert
    /// einer fertigen Playlist.
    static let unfinishedChannelCount = -1

    /// Legt Playlist und Sender in Blöcken an. Bis zum letzten Block trägt die Playlist `unfinishedChannelCount`: Die
    /// Übersicht blendet sie aus, und nur der letzte Block setzt die Senderzahl. Scheitert ein Block oder wird die
    /// aufrufende Aufgabe abgebrochen, wird die Playlist samt bereits gespeicherter Sender sofort wieder entfernt. Gelingt
    /// auch das nicht (z. B. Datenträger voll), bleibt sie unsichtbar und `removeUnfinished` entfernt sie beim nächsten
    /// Anlegen bzw. beim nächsten Start (Review R-02). Name, Gruppe und `tvg-id` werden ohne Steuerzeichen gespeichert
    /// (B05 · BUG-09, `ParsedChannel.withoutControlCharacters`).
    /// - Throws: `CancellationError` beim Abbruch, sonst `PlaylistStoreError.createFailed`.
    func create(_ draft: Draft, channels: [ParsedChannel], in container: ModelContainer) throws {
        let channels = channels.map(\.withoutControlCharacters)
        _ = try? removeUnfinished(in: container)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let playlist = Playlist(id: draft.id, name: draft.name, sourceURL: draft.sourceURL,
                                lastRefreshed: draft.lastRefreshed, isXtream: draft.isXtream,
                                xtreamOutput: draft.xtreamOutput, channelCount: Self.unfinishedChannelCount)
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
                if end == channels.endIndex { playlist.channelCount = channels.count }
                try context.save()
                start = end
            }
            if channels.isEmpty {
                playlist.channelCount = 0
                try context.save()
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
            if error is CancellationError { throw error }
            throw PlaylistStoreError.createFailed
        }
    }

    /// Entfernt Playlists, deren Anlegen nicht fertig geworden ist (`unfinishedChannelCount`), samt ihrer Sender.
    /// Läuft vor jedem Anlegen und beim Start; Anlegen läuft nur über diesen Actor und ohne Unterbrechung, also ist
    /// eine solche Playlist hier nie eine, die gerade entsteht.
    /// - Returns: Anzahl entfernter Playlists.
    @discardableResult
    func removeUnfinished(in container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let marker = Self.unfinishedChannelCount
        let leftovers = try context.fetch(FetchDescriptor<Playlist>(predicate: #Predicate { $0.channelCount == marker }))
        guard !leftovers.isEmpty else { return 0 }
        for playlist in leftovers {
            Self.detachAndDeleteChannels(of: playlist, in: context)
            context.delete(playlist)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw PlaylistStoreError.saveFailed
        }
        return leftovers.count
    }

    // MARK: - Ersetzen (Aktualisieren)

    /// Ersetzt alle Sender in **einem** Speichervorgang: Scheitert er, bleibt die alte Liste vollständig erhalten
    /// (B03 AK-18, B05 · BUG-11). Favoriten gehen nach `FavoriteCarryOver` auf die neuen Sender über. Die neue Liste wird
    /// wie beim Anlegen ohne Steuerzeichen übernommen – vor der Übernahme, damit die Schlüssel zu den gespeicherten passen
    /// (B05 · BUG-09).
    func replaceChannels(of id: UUID, persistentID: PersistentIdentifier?, with channels: [ParsedChannel],
                         refreshedAt: Date, newSourceURL: URL?, credentialUpdate: CredentialUpdate?,
                         credentialStore: XtreamCredentialStore, in container: ModelContainer) throws -> ReplaceOutcome {
        let channels = channels.map(\.withoutControlCharacters)
        guard !deleting.contains(id) else { return .playlistGone }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        guard let playlist = try Self.find(id, persistentID, in: context) else { return .playlistGone }
        try credentialUpdate?.apply(credentialStore, for: id)

        let old = playlist.channels
        let read = old.filter(\.isFavorite).map {
            FavoriteCarryOver.State.ReadFavorite(
                channelID: $0.id,
                previous: FavoriteCarryOver.Previous(key: $0.favoriteKey, streamURL: $0.streamURL, name: $0.name))
        }
        let flags = FavoriteCarryOver.flags(previous: read.map(\.previous), new: channels)
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
        let state = FavoriteCarryOver.State(read: read, channels: channels, newIDs: fresh.map(\.id), flags: flags)
        afterReplaceSaved?()
        return .replaced(channelCount: fresh.count, carryOver: state)
    }

    /// Zieht Stern-Änderungen nach, die die Ansicht während des Ersetzens an alten Sendern gespeichert hat (Review R-01):
    /// Die Übernahme wird so berechnet, als wären `edits` vor dem Lesen gespeichert worden, und nur die Sterne, die sich
    /// dadurch ändern, werden an den neuen Sendern gesetzt bzw. entfernt. `edits` enthält alle Änderungen seit Beginn
    /// des Aktualisierens (je Sender der letzte Stand); Änderungen, die das Lesen schon gesehen hat, ändern nichts.
    /// - Returns: der neue Stand für einen weiteren Aufruf.
    func reconcileFavorites(of id: UUID, state: FavoriteCarryOver.State, edits: [FavoriteEdit],
                            in container: ModelContainer) throws -> FavoriteCarryOver.State {
        guard !deleting.contains(id) else { return state }
        let target = FavoriteCarryOver.flags(previous: state.previous(applying: edits), new: state.channels)
        var changes: [UUID: Bool] = [:]
        for index in target.indices where target[index] != state.flags[index] {
            changes[state.newIDs[index]] = target[index]
        }
        var next = state
        next.flags = target
        guard !changes.isEmpty else { return next }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let ids = Array(changes.keys)
        let channels = try context.fetch(FetchDescriptor<Channel>(predicate: #Predicate {
            $0.playlistID == id && ids.contains($0.id)
        }))
        for channel in channels {
            if let value = changes[channel.id] { channel.isFavorite = value }
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw PlaylistStoreError.favoritesNotSaved
        }
        return next
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

    // MARK: - Start

    /// Wartung beim Start (Review R-10): unfertige Playlists entfernen (R-02), dann Zugangsdaten umstellen und
    /// verdichten (B01/B02 · BUG-01, R-08) – auf diesem Actor, also abseits des Main-Threads und nie gleichzeitig mit
    /// Anlegen, Aktualisieren oder Löschen.
    func launchMaintenance(container: ModelContainer, storeURL: URL, credentials: XtreamCredentialStore,
                           defaults: UserDefaults?) -> AppPersistence.CredentialMigrationResult {
        _ = try? removeUnfinished(in: container)
        return AppPersistence.migrateCredentials(container: container, storeURL: storeURL, store: credentials,
                                                 defaults: defaults)
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

    /// Einziger Ort, an dem Sender entstehen (Anlegen und Aktualisieren, alle Importwege). Erwartet eine bereinigte
    /// Liste (`ParsedChannel.withoutControlCharacters`).
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

extension Playlist {
    /// Anlegen läuft noch oder ist gescheitert (`PlaylistStore.unfinishedChannelCount`); die Übersicht blendet sie aus.
    var isUnfinished: Bool { channelCount == PlaylistStore.unfinishedChannelCount }
}

enum PlaylistStoreError: LocalizedError, Equatable {
    case saveFailed
    /// Anlegen gescheitert; sichtbar bleibt nichts, ein Rest in der Datei wird spätestens beim nächsten Anlegen bzw.
    /// Start entfernt (Review R-02).
    case createFailed
    /// Die neue Senderliste ist gespeichert, Stern-Änderungen aus der Laufzeit nicht (Review R-01).
    case favoritesNotSaved
    /// Ein Stern ließ sich nicht speichern und ist zurückgesetzt (B05 · BUG-02).
    case starNotSaved

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Die Playlist konnte nicht gespeichert werden. Die bisherige Senderliste bleibt erhalten. "
                + "Bitte freien Speicherplatz prüfen und erneut versuchen."
        case .createFailed:
            return "Die Playlist konnte nicht gespeichert werden. Bitte freien Speicherplatz prüfen und erneut versuchen."
        case .favoritesNotSaved:
            return "Die Playlist wurde aktualisiert, aber Sterne, die während des Aktualisierens gesetzt oder entfernt "
                + "wurden, konnten nicht gespeichert werden. Bitte die Favoriten dieser Playlist prüfen."
        case .starNotSaved:
            return "Der Stern konnte nicht gespeichert werden und ist zurückgesetzt. "
                + "Bitte freien Speicherplatz prüfen und erneut versuchen."
        }
    }
}
