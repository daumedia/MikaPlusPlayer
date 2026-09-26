import Foundation

/// Meldet Ansichten, die Sender einer Playlist halten, dass diese Playlist gleich gelöscht wird (B03 · BUG-05).
///
/// Player, Multiview und Senderliste beenden daraufhin Wiedergabe und Verbindungen (bei Xtream mit Zugangsdaten
/// im Pfad) und zeigen, dass die Playlist weg ist – bevor ihre Sender aus der Datenbank verschwinden.
enum PlaylistEvents {
    static let willDelete = Notification.Name("lu.daumedia.MikaPlusPlayer.playlistWillDelete")
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

    static func finishDeleting(_ ids: Set<UUID>) {
        lock.withLock { pending.subtract(ids) }
    }

    static func isBeingDeleted(_ id: UUID) -> Bool {
        lock.withLock { pending.contains(id) }
    }

    /// Die IDs aus einer `willDelete`-Mitteilung.
    static func ids(in notification: Notification) -> Set<UUID> {
        notification.userInfo?[idsKey] as? Set<UUID> ?? []
    }
}
