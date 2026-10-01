import Foundation
import SwiftData

/// Ein einzelner Sender / Stream-Eintrag innerhalb einer Playlist.
@Model
final class Channel {
    var id: UUID
    var name: String
    /// Bei Xtream-Sendern ohne Zugangsdaten. Zum Abspielen immer `StreamURLResolver` benutzen.
    var streamURL: URL
    var logoURL: URL?
    /// `group-title` aus dem #EXTINF-Tag, z. B. "Sport", "News".
    var group: String?
    /// `tvg-id` aus dem #EXTINF-Tag. Wird (zusammen mit dem Namen) genutzt, um
    /// Favoriten über einen Refresh hinweg wiederzuerkennen.
    var tvgID: String?
    var isFavorite: Bool

    var playlist: Playlist?
    /// Denormalisierte ID der Playlist (Kopie von `playlist.id`). Ohne Index in der Datenbank: Die Senderliste filtert
    /// deshalb über die Beziehung `playlist`, deren Spalte indiziert ist (B04 · BUG-12, `ChannelListQuery`). Benutzt wird
    /// die Kopie weiter z. B. beim Festhalten von Stern-Änderungen (`FavoriteEdits`).
    var playlistID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        streamURL: URL,
        logoURL: URL? = nil,
        group: String? = nil,
        tvgID: String? = nil,
        isFavorite: Bool = false,
        playlist: Playlist? = nil,
        playlistID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.logoURL = logoURL
        self.group = group
        self.tvgID = tvgID
        self.isFavorite = isFavorite
        self.playlist = playlist
        self.playlistID = playlistID
    }

    /// Schlüssel, über den ein Channel beim Refresh wiedererkannt wird:
    /// bevorzugt die `tvg-id`, sonst der (kleingeschriebene) Name.
    /// Der Schlüssel entscheidet nur, **ob** ein neuer Sender Favorit werden darf; wie viele und welche,
    /// entscheidet `FavoriteCarryOver` (B03 · BUG-02).
    var favoriteKey: String { Self.favoriteKey(name: name, tvgID: tvgID) }

    static func favoriteKey(name: String, tvgID: String?) -> String {
        if let tvgID, !tvgID.isEmpty { return "id:\(tvgID)" }
        return "name:\(name.lowercased())"
    }
}
