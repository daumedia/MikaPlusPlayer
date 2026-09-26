import Foundation
import SwiftData

/// Der **einzige** Ort, an dem aus einem `Channel` eine abspielbare Adresse wird (B01 · BUG-01, B02 · BUG-01).
///
/// Xtream-Sender und M3U-Sender aus Adressen mit Zugangsdaten speichern ihre Adresse ohne Geheimnis. Wiedergabe
/// (B06), Bild-in-Bild (B07) und Multiview (B08) laden deshalb nie `channel.streamURL` direkt, sondern fragen hier:
/// Benutzername und Passwort kommen erst beim Abspielen aus dem Schlüsselbund dazu.
///
/// Die Playlist wird bei jedem Aufruf in der Datenbank nachgeschlagen: Ein Sender, den eine Ansicht über ein
/// Aktualisieren hinweg hält, spielt so weiter mit gültigen Zugangsdaten; ist seine Playlist gelöscht (oder wird sie
/// gerade gelöscht), gibt es eine klare Meldung statt eines Abrufs ohne Zugangsdaten (B03 · BUG-05).
enum StreamURLResolver {
    enum ResolveError: LocalizedError, Equatable {
        case missingCredentials
        case missingPlaylistCredentials
        case invalidAddress
        case playlistDeleted

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "Die Zugangsdaten dieser Xtream-Playlist fehlen auf diesem Gerät. Bitte die Playlist löschen und neu importieren."
            case .missingPlaylistCredentials:
                return "Die Zugangsdaten dieser Playlist fehlen auf diesem Gerät. Bitte die Playlist löschen und neu importieren."
            case .invalidAddress:
                return "Die Stream-Adresse ist ungültig."
            case .playlistDeleted:
                return "Die Playlist dieses Senders wurde gelöscht."
            }
        }
    }

    static func playableURL(for channel: Channel, store: XtreamCredentialStore = .standard) throws -> URL {
        let stored = channel.streamURL
        guard let playlist = try currentPlaylist(of: channel) else { return stored }
        guard !PlaylistEvents.isBeingDeleted(playlist.id) else { throw ResolveError.playlistDeleted }
        if playlist.isXtream {
            // Altbestand, dessen Umstellung beim Start nicht gelang: Die Adresse trägt die Zugangsdaten noch selbst.
            if let source = playlist.sourceURL, XtreamCredentials(legacyPlayerAPIURL: source) != nil {
                return stored
            }
            guard let secret = try store.load(for: playlist.id) else { throw ResolveError.missingCredentials }
            guard let url = XtreamStreamAddress.playable(stored: stored, secret: secret) else {
                throw ResolveError.invalidAddress
            }
            return url
        }
        guard M3UCredentials.needsSecret(stored) else { return stored }
        guard let secret = try store.loadM3U(for: playlist.id) else { throw ResolveError.missingPlaylistCredentials }
        guard let url = M3UCredentials.restore(stored, secret: secret) else { throw ResolveError.invalidAddress }
        return url
    }

    /// Die Playlist des Senders, wie sie jetzt in der Datenbank steht; wirft `playlistDeleted`, wenn es sie nicht mehr gibt.
    /// Maßgeblich ist die Beziehung (ein Sender bekommt nie die Zugangsdaten einer anderen Playlist, auch nicht über eine
    /// manipulierte `playlistID`); geprüft wird über die `persistentModelID`, ohne Attribute einer gelöschten Playlist zu
    /// lesen. `nil` nur für Sender ohne Datenbank (Vorschau, Tests) bzw. ohne Beziehung (wie bisher ohne Zugangsdaten).
    private static func currentPlaylist(of channel: Channel) throws -> Playlist? {
        guard let context = channel.modelContext else { return channel.playlist }
        if let related = channel.playlist {
            let id = related.persistentModelID
            var descriptor = FetchDescriptor<Playlist>(predicate: #Predicate { $0.persistentModelID == id })
            descriptor.fetchLimit = 1
            guard related.modelContext != nil, let current = try? context.fetch(descriptor).first else {
                throw ResolveError.playlistDeleted
            }
            return current
        }
        if let playlistID = channel.playlistID,
           (try? context.fetchCount(FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == playlistID }))) == 0 {
            throw ResolveError.playlistDeleted
        }
        return nil
    }
}
