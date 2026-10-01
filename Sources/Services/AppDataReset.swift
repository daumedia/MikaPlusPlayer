import Foundation
import SwiftData

/// „Alle Daten entfernen" (B03 · BUG-09): der eine Weg, alles zu löschen, was die App außerhalb ihres Bundles ablegt.
///
/// Entfernt alle Playlists samt Sendern und Favoriten (über denselben Weg wie das Löschen einer Playlist, Datei
/// danach verdichtet), alle Schlüsselbund-Einträge des App-Dienstes, den HTTP-Plattencache, die zwischengespeicherten
/// Senderlogos (B04 · BUG-07), die Cookies des
/// Import-Loaders und der App (`HTTPCookieStorage.shared`, dort legten M3U-Abrufe bis Version 1.1 Cookies ab – Review
/// R-11), beiseitegelegte Datenbanken (B09, auch wenn die Sitzung wegen eines B09-Rückfalls im Speicher läuft – Review
/// R-04) und die Einstellungen der App. Laufende Wiedergaben enden vorher.
@MainActor
enum AppDataReset {
    struct Targets {
        var credentialStore: XtreamCredentialStore = .standard
        var httpCache: URLCache = .shared
        var loader: PlaylistHTTPLoader = .shared
        var store: PlaylistStore = .shared
        /// Zwischengespeicherte Senderlogos (nur Arbeitsspeicher, B04 · BUG-07).
        var logoLoader: ChannelLogoLoader = .shared
        /// Gemeinsamer Cookie-Speicher der App (Review R-11; App: `HTTPCookieStorage.shared`). `nil` lässt ihn stehen.
        var sharedCookies: HTTPCookieStorage?
        /// Ordner `Beiseitegelegt` neben der Datenbank; `nil`, wenn es keinen gibt.
        var setAsideFolder: URL?
        /// Einstellungen, die entfernt werden (App: die Domäne der Bundle-ID). `nil` lässt sie stehen.
        var defaults: (suite: UserDefaults, domain: String)?

        /// Ziele der laufenden App. Im Test-Host bleiben Einstellungen, Plattencache und Cookie-Speicher der App
        /// unangetastet (sie gehören der echten App).
        static func app(container: ModelContainer) -> Targets {
            var targets = Targets()
            if AppEnvironment.isRunningTests {
                targets.httpCache = URLCache(memoryCapacity: 0, diskCapacity: 0)
            } else {
                targets.sharedCookies = .shared
            }
            let appStore = AppEnvironment.isRunningTests ? nil : AppPersistence.appStoreURL()
            targets.setAsideFolder = setAsideFolder(container: container, appStoreURL: appStore)
            if !AppEnvironment.isRunningTests, let bundleID = Bundle.main.bundleIdentifier {
                targets.defaults = (.standard, bundleID)
            }
            return targets
        }

        /// Ordner `Beiseitegelegt` neben der Datenbankdatei. Läuft die Sitzung im Speicher (B09-Rückfall
        /// `inMemoryFallback`), liegt die beiseitegelegte Datei trotzdem am Speicherort der App (Review R-04).
        static func setAsideFolder(container: ModelContainer, appStoreURL: URL?) -> URL? {
            guard let storeURL = PlaylistStore.storeURL(of: container) ?? appStoreURL else { return nil }
            return storeURL.deletingLastPathComponent()
                .appendingPathComponent(AppPersistence.setAsideFolderName, isDirectory: true)
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
        targets.logoLoader.removeAll()
        targets.loader.removeAllCookies()
        if let cookies = targets.sharedCookies {
            for cookie in cookies.cookies ?? [] { cookies.deleteCookie(cookie) }
        }
        if let folder = targets.setAsideFolder, FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        if let defaults = targets.defaults {
            defaults.suite.removePersistentDomain(forName: defaults.domain)
        }
    }
}
