import Foundation
import SwiftData

/// „Alle Daten entfernen" (B03 · BUG-09): der eine Weg, alles zu löschen, was die App außerhalb ihres Bundles ablegt.
///
/// Entfernt alle Playlists samt Sendern und Favoriten (über denselben Weg wie das Löschen einer Playlist, Datei
/// danach verdichtet), alle Schlüsselbund-Einträge des App-Dienstes, den HTTP-Plattencache, die Cookies des
/// Import-Loaders, beiseitegelegte Datenbanken (B09) und die Einstellungen der App. Laufende Wiedergaben enden vorher.
@MainActor
enum AppDataReset {
    struct Targets {
        var credentialStore: XtreamCredentialStore = .standard
        var httpCache: URLCache = .shared
        var loader: PlaylistHTTPLoader = .shared
        var store: PlaylistStore = .shared
        /// Ordner `Beiseitegelegt` neben der Datenbank; `nil` bei einer Datenbank im Speicher.
        var setAsideFolder: URL?
        /// Einstellungen, die entfernt werden (App: die Domäne der Bundle-ID). `nil` lässt sie stehen.
        var defaults: (suite: UserDefaults, domain: String)?

        /// Ziele der laufenden App. Im Test-Host bleiben Einstellungen unangetastet (sie gehören der echten App).
        static func app(container: ModelContainer) -> Targets {
            var targets = Targets()
            // Im Test-Host gehört `URLCache.shared` der echten App – dort nichts leeren.
            if AppEnvironment.isRunningTests { targets.httpCache = URLCache(memoryCapacity: 0, diskCapacity: 0) }
            targets.setAsideFolder = PlaylistStore.storeURL(of: container)?
                .deletingLastPathComponent().appendingPathComponent(AppPersistence.setAsideFolderName, isDirectory: true)
            if !AppEnvironment.isRunningTests, let bundleID = Bundle.main.bundleIdentifier {
                targets.defaults = (.standard, bundleID)
            }
            return targets
        }
    }

    static let confirmationTitle = "Alle Daten entfernen?"
    static let confirmationMessage = "Alle Playlists, Favoriten und gespeicherten Zugangsdaten sowie zwischengespeicherte "
        + "Daten und Einstellungen der App werden von diesem Gerät entfernt. Das lässt sich nicht rückgängig machen."

    static func eraseAll(context: ModelContext, targets: Targets) async throws {
        let ids = Set(try context.fetch(FetchDescriptor<Playlist>()).map(\.id))
        PlaylistEvents.postWillDelete(ids)
        defer { PlaylistEvents.finishDeleting(ids) }
        await targets.store.beginDelete(ids)
        do {
            try await targets.store.removeAllChannels(in: context.container)
            for playlist in try context.fetch(FetchDescriptor<Playlist>()) { context.delete(playlist) }
            try context.save()
        } catch {
            context.rollback()
            await targets.store.endDelete(ids)
            throw error
        }
        await targets.store.endDelete(ids)
        await targets.store.compact(context.container)

        try targets.credentialStore.deleteAll()
        targets.httpCache.removeAllCachedResponses()
        targets.loader.removeAllCookies()
        if let folder = targets.setAsideFolder, FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        if let defaults = targets.defaults {
            defaults.suite.removePersistentDomain(forName: defaults.domain)
        }
    }
}
