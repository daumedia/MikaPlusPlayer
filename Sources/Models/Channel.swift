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

    /// Steuerzeichen werden dabei wie beim Import ignoriert (B05 · BUG-09): So ergibt ein vor der Bereinigung
    /// gespeicherter Sender denselben Schlüssel wie die bereinigte neue Liste.
    static func favoriteKey(name: String, tvgID: String?) -> String {
        if let tvgID {
            let id = removingControlCharacters(tvgID)
            if !id.isEmpty { return "id:\(id)" }
        }
        return "name:\(removingControlCharacters(name).lowercased())"
    }

    /// Entfernt Steuerzeichen (U+0000–U+001F und U+007F) außer Leerraum (Tabulator, Zeilenumbrüche), B05 · BUG-09.
    /// Die Datenbankdatei speichert Text nur bis zu einem NUL-Zeichen; ein Name oder eine `tvg-id` mit NUL ergäbe nach
    /// dem nächsten Laden einen anderen Favoriten-Schlüssel. Leerraum bleibt, weil er sichtbar ist und die Senderliste
    /// einen Zeilenumbruch in Gruppen als eigene Gruppe führt (B04 AK-11). Die Steuerzeichen U+0080–U+009F bleiben: Sie
    /// entstehen beim Latin-1-Rückfall des M3U-Imports aus Umlauten und Sonderzeichen (B02 EC-07/EC-08, dort OF-06) und
    /// werden unverändert gespeichert. Ohne Steuerzeichen kommt der Text unverändert zurück.
    static func removingControlCharacters(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isRemovedControl) else { return text }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter { !isRemovedControl($0) })
        return String(scalars)
    }

    private static func isRemovedControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D: return false
        case 0x00...0x1F, 0x7F: return true
        default: return false
        }
    }
}
