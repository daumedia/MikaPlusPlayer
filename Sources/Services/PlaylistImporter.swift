import Foundation
import SwiftData

enum ImportError: LocalizedError {
    case invalidURL
    case emptyPlaylist
    case fileAccessDenied
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Die angegebene URL ist ungültig."
        case .emptyPlaylist: return "Die Playlist enthält keine gültigen Sender."
        case .fileAccessDenied: return "Auf die ausgewählte Datei kann nicht zugegriffen werden."
        case .network(let msg): return "Netzwerkfehler: \(msg)"
        }
    }
}

/// Lädt, parst und persistiert Playlists. Hält den `ModelContext` und läuft
/// auf dem MainActor, da SwiftData-Objekte hier erzeugt/verändert werden.
@MainActor
@Observable
final class PlaylistImporter {
    private let modelContext: ModelContext
    private let parser = M3UParser()
    private let credentialStore: XtreamCredentialStore
    private let xtreamLimits: XtreamClient.Limits
    private let loginThrottle: XtreamLoginThrottle

    /// True, während ein Import/Refresh läuft (für UI-Spinner).
    var isWorking = false

    init(
        modelContext: ModelContext,
        credentialStore: XtreamCredentialStore = .standard,
        xtreamLimits: XtreamClient.Limits = .standard,
        loginThrottle: XtreamLoginThrottle = .shared
    ) {
        self.modelContext = modelContext
        self.credentialStore = credentialStore
        self.xtreamLimits = xtreamLimits
        self.loginThrottle = loginThrottle
    }

    // MARK: - Import

    /// Importiert eine Playlist von einer Remote-URL.
    @discardableResult
    func importFromURL(_ urlString: String, name: String) async throws -> Playlist {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil else {
            throw ImportError.invalidURL
        }
        isWorking = true
        defer { isWorking = false }

        let text = try await fetchText(from: url)
        let parsed = parser.parse(text)
        guard !parsed.isEmpty else { throw ImportError.emptyPlaylist }

        let displayName = name.isEmpty ? (url.host ?? "Playlist") : name
        let playlist = Playlist(name: displayName, sourceURL: url, lastRefreshed: Date())
        modelContext.insert(playlist)
        attach(parsed, to: playlist, preservedFavorites: [])
        try modelContext.save()
        return playlist
    }

    /// Importiert eine Playlist über die Xtream-Codes-API (player_api.php).
    ///
    /// - Zugangsdaten gehen in den Schlüsselbund, Datenbank und Stream-Adressen bleiben ohne
    ///   Geheimnis (B01 · BUG-01).
    /// - Die Sender werden in einem eigenen `ModelContext` abseits des Main-Actors in Blöcken
    ///   gespeichert (B01 · BUG-12).
    /// - Wird die aufrufende Aufgabe vor dem Speichern abgebrochen, entsteht nichts (B01 · BUG-11).
    @discardableResult
    func importFromXtream(
        _ credentials: XtreamCredentials,
        output: XtreamOutput,
        name: String
    ) async throws -> Playlist {
        isWorking = true
        defer { isWorking = false }

        let client = XtreamClient(credentials: credentials, limits: xtreamLimits, throttle: loginThrottle)
        let parsed = try await client.fetchLiveChannels(output: output)
        guard !parsed.isEmpty else { throw ImportError.emptyPlaylist }
        try Task.checkCancellation()

        guard let secret = credentials.secret(), let sourceURL = credentials.storedSourceURL() else {
            throw XtreamClient.XtreamError.invalidHost
        }
        let displayName = name.isEmpty ? (credentials.baseURL()?.host ?? "Xtream") : name
        let playlistID = UUID()

        try credentialStore.save(secret, for: playlistID)
        do {
            try await Self.persistXtreamPlaylist(
                in: modelContext.container, id: playlistID, name: displayName,
                sourceURL: sourceURL, output: output, channels: parsed
            )
        } catch {
            try? credentialStore.delete(for: playlistID)
            throw error
        }

        // Im Kontext der Ansicht abholen. Das Speichern hier stößt auch die @Query-Ansichten an.
        var descriptor = FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == playlistID })
        descriptor.fetchLimit = 1
        guard let playlist = try modelContext.fetch(descriptor).first else { throw ImportError.emptyPlaylist }
        playlist.lastRefreshed = Date()
        try modelContext.save()
        return playlist
    }

    /// Anzahl Sender je Speichervorgang beim Xtream-Import.
    nonisolated static let xtreamBatchSize = 5_000

    /// Legt Playlist und Sender in einem eigenen Hintergrund-Kontext an (B01 · BUG-12).
    ///
    /// Die Beziehung wird blockweise über `channels.append(contentsOf:)` gesetzt, nicht je Sender:
    /// `Channel(playlist:)` bzw. `playlist.channels.append(_:)` je Objekt wächst quadratisch
    /// (17 000 Sender: 285 s). `channelCount` und `playlistID` stimmen nach jedem Block.
    /// Scheitert ein Block oder wird die aufrufende Aufgabe abgebrochen (BUG-11), wird die Playlist
    /// samt bereits gespeicherter Sender wieder entfernt.
    nonisolated private static func persistXtreamPlaylist(
        in container: ModelContainer,
        id: UUID,
        name: String,
        sourceURL: URL,
        output: XtreamOutput,
        channels parsed: [ParsedChannel]
    ) async throws {
        let worker = Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let playlist = Playlist(
                id: id,
                name: name,
                sourceURL: sourceURL,
                lastRefreshed: Date(),
                isXtream: true,
                xtreamOutput: output.rawValue
            )
            context.insert(playlist)
            do {
                var start = parsed.startIndex
                while start < parsed.endIndex {
                    try Task.checkCancellation()
                    let end = min(start + xtreamBatchSize, parsed.endIndex)
                    var batch: [Channel] = []
                    batch.reserveCapacity(end - start)
                    for item in parsed[start..<end] {
                        let channel = Channel(
                            name: item.name,
                            streamURL: item.streamURL,
                            logoURL: item.logoURL,
                            group: item.group,
                            tvgID: item.tvgID,
                            playlistID: id
                        )
                        context.insert(channel)
                        batch.append(channel)
                    }
                    playlist.channels.append(contentsOf: batch)
                    playlist.channelCount = end - parsed.startIndex
                    try context.save()
                    start = end
                }
            } catch {
                context.rollback()
                let saved = try? context.fetch(FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == id }))
                for leftover in saved ?? [] { context.delete(leftover) }
                try? context.save()
                throw error
            }
        }
        // Die abgelöste Aufgabe erbt den Abbruch nicht – ausdrücklich weiterreichen.
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Importiert eine Playlist aus einer lokalen Datei (.m3u/.m3u8).
    /// Erwartet eine über `fileImporter` erhaltene, ggf. security-scoped URL.
    @discardableResult
    func importFromFile(_ fileURL: URL, name: String? = nil) async throws -> Playlist {
        isWorking = true
        defer { isWorking = false }

        let needsScope = fileURL.startAccessingSecurityScopedResource()
        defer { if needsScope { fileURL.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ImportError.fileAccessDenied
        }
        let text = decodeText(data)
        let parsed = parser.parse(text)
        guard !parsed.isEmpty else { throw ImportError.emptyPlaylist }

        let displayName = name ?? fileURL.deletingPathExtension().lastPathComponent
        // Lokale Datei: sourceURL bleibt nil -> nicht refreshbar.
        let playlist = Playlist(name: displayName)
        modelContext.insert(playlist)
        attach(parsed, to: playlist, preservedFavorites: [])
        try modelContext.save()
        return playlist
    }

    // MARK: - Refresh

    /// Lädt eine Remote-Playlist neu. Favoriten werden über `favoriteKey`
    /// (tvg-id bzw. Name) erhalten. Unterstützt M3U-URL- und Xtream-Playlists.
    func refresh(_ playlist: Playlist) async throws {
        guard let url = playlist.sourceURL else { return }
        isWorking = true
        defer { isWorking = false }

        let parsed: [ParsedChannel]
        if playlist.isXtream {
            // B01 · BUG-01: Zugangsdaten aus dem Schlüsselbund. Altbestand mit Zugangsdaten in der
            // Adresse (Umstellung beim Start nicht gelungen) wird hier nachträglich umgestellt.
            let legacy = XtreamCredentials(legacyPlayerAPIURL: url)
            let credentials: XtreamCredentials
            if let legacy {
                credentials = legacy
            } else if let secret = try credentialStore.load(for: playlist.id) {
                credentials = XtreamCredentials(secret: secret)
            } else {
                throw StreamURLResolver.ResolveError.missingCredentials
            }
            let output = XtreamOutput(rawValue: playlist.xtreamOutput ?? "") ?? .hls
            parsed = try await XtreamClient(credentials: credentials, limits: xtreamLimits, throttle: loginThrottle)
                .fetchLiveChannels(output: output)
            guard !parsed.isEmpty else { throw ImportError.emptyPlaylist }
            if let legacy, let secret = legacy.secret() {
                try credentialStore.save(secret, for: playlist.id)
                playlist.sourceURL = legacy.storedSourceURL()
            }
        } else {
            let text = try await fetchText(from: url)
            parsed = parser.parse(text)
        }
        guard !parsed.isEmpty else { throw ImportError.emptyPlaylist }

        // Alte Favoriten-Schlüssel merken …
        let preserved = Set(playlist.channels.filter(\.isFavorite).map(\.favoriteKey))

        // … alte Channels entfernen (cascade kümmert sich beim Delete) …
        for old in playlist.channels {
            modelContext.delete(old)
        }
        playlist.channels.removeAll()

        // … und neu aufbauen, Favoriten dabei wiederherstellen.
        attach(parsed, to: playlist, preservedFavorites: preserved)
        playlist.lastRefreshed = Date()
        try modelContext.save()
    }

    // MARK: - Löschen

    /// Löscht eine Playlist samt Sendern und – bei Xtream – ihre Zugangsdaten im Schlüsselbund.
    func delete(_ playlist: Playlist) throws {
        let id = playlist.id
        let isXtream = playlist.isXtream
        modelContext.delete(playlist)
        try modelContext.save()
        if isXtream {
            try credentialStore.delete(for: id)
        }
    }

    // MARK: - Helpers

    /// Erzeugt Channel-Objekte und hängt sie an die Playlist. Setzt `isFavorite`
    /// für Channels, deren Schlüssel in `preservedFavorites` enthalten ist.
    private func attach(
        _ parsed: [ParsedChannel],
        to playlist: Playlist,
        preservedFavorites: Set<String>
    ) {
        for p in parsed {
            let channel = Channel(
                name: p.name,
                streamURL: p.streamURL,
                logoURL: p.logoURL,
                group: p.group,
                tvgID: p.tvgID,
                playlist: playlist,
                playlistID: playlist.id
            )
            channel.isFavorite = preservedFavorites.contains(channel.favoriteKey)
            modelContext.insert(channel)
            playlist.channels.append(channel)
        }
        // channels wurde gerade in-memory befüllt -> count ist hier günstig.
        playlist.channelCount = playlist.channels.count
    }

    private func fetchText(from url: URL) async throws -> String {
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ImportError.network("HTTP \(http.statusCode)")
            }
            return decodeText(data)
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.network(error.localizedDescription)
        }
    }

    /// Dekodiert Playlist-Bytes; UTF-8 mit Latin-1-Fallback.
    private func decodeText(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }
}
