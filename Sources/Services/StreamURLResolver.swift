import Foundation

/// Der **einzige** Ort, an dem aus einem `Channel` eine abspielbare Adresse wird (B01 · BUG-01).
///
/// Xtream-Sender speichern ihre Adresse ohne Zugangsdaten. Wiedergabe (B06), Bild-in-Bild (B07)
/// und Multiview (B08) laden deshalb nie `channel.streamURL` direkt, sondern fragen hier:
/// Benutzername und Passwort kommen erst beim Abspielen aus dem Schlüsselbund dazu.
/// M3U-Sender (B02) werden unverändert durchgereicht.
enum StreamURLResolver {
    enum ResolveError: LocalizedError, Equatable {
        case missingCredentials
        case invalidAddress

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "Die Zugangsdaten dieser Xtream-Playlist fehlen auf diesem Gerät. Bitte die Playlist löschen und neu importieren."
            case .invalidAddress:
                return "Die Stream-Adresse ist ungültig."
            }
        }
    }

    static func playableURL(for channel: Channel, store: XtreamCredentialStore = .standard) throws -> URL {
        guard let playlist = channel.playlist, playlist.isXtream else { return channel.streamURL }
        // Altbestand, dessen Umstellung beim Start nicht gelang: Die Adresse trägt die Zugangsdaten noch selbst.
        if let source = playlist.sourceURL, XtreamCredentials(legacyPlayerAPIURL: source) != nil {
            return channel.streamURL
        }
        guard let secret = try store.load(for: playlist.id) else { throw ResolveError.missingCredentials }
        guard let url = XtreamStreamAddress.playable(stored: channel.streamURL, secret: secret) else {
            throw ResolveError.invalidAddress
        }
        return url
    }
}
