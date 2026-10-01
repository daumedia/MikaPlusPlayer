import Foundation

/// Meldet Ansichten, die Sender einer Playlist halten, dass diese Playlist gleich gelöscht wird (B03 · BUG-05)
/// bzw. dass ihre Sender ersetzt wurden (B04 · BUG-02).
///
/// Player, Multiview und Senderliste beenden beim Löschen Wiedergabe und Verbindungen (bei Xtream mit Zugangsdaten
/// im Pfad) und zeigen, dass die Playlist weg ist – bevor ihre Sender aus der Datenbank verschwinden. Nach dem
/// Aktualisieren berechnen offene Senderlisten – in allen Fenstern – Gruppen-Chips und Trefferliste neu.
enum PlaylistEvents {
    static let willDelete = Notification.Name("lu.daumedia.MikaPlusPlayer.playlistWillDelete")
    /// Die Sender der Playlists wurden ersetzt (Aktualisieren) und sind im Kontext der Ansicht angekommen.
    static let didReplaceChannels = Notification.Name("lu.daumedia.MikaPlusPlayer.playlistDidReplaceChannels")
    /// `Set<UUID>` der betroffenen `Playlist.id`
    static let idsKey = "ids"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var pending: Set<UUID> = []

    /// Meldet das bevorstehende Löschen und merkt die Playlists, bis `finishDeleting` sie freigibt: Wer in dieser Zeit
    /// einen ihrer Sender öffnet (z. B. aus dem Favoriten-Tab), bekommt keine Wiedergabe mehr (`StreamURLResolver`).
    @MainActor
    static func postWillDelete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        lock.withLock { pending.formUnion(ids) }
        NotificationCenter.default.post(name: willDelete, object: nil, userInfo: [idsKey: ids])
    }

    /// Meldet ersetzte Sender (nach dem Abholen in den Kontext der Ansicht, `PlaylistImporter.refresh`).
    @MainActor
    static func postDidReplaceChannels(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        NotificationCenter.default.post(name: didReplaceChannels, object: nil, userInfo: [idsKey: ids])
    }

    static func finishDeleting(_ ids: Set<UUID>) {
        lock.withLock { pending.subtract(ids) }
    }

    static func isBeingDeleted(_ id: UUID) -> Bool {
        lock.withLock { pending.contains(id) }
    }

    /// Die IDs aus einer `willDelete`- bzw. `didReplaceChannels`-Mitteilung.
    static func ids(in notification: Notification) -> Set<UUID> {
        notification.userInfo?[idsKey] as? Set<UUID> ?? []
    }
}
