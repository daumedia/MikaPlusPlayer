#if os(macOS)
import AppKit
import CryptoKit
import Foundation
import Security
import SwiftData
import XCTest
@testable import MikaPlusPlayer

/// B09 · Auto-Update — QA Durchlauf 2 (2026-09-16), nachgeführt im Bau Durchlauf 2 (2026-10-02).
///
/// Nachprüfung der Reparatur (BUG-13, BUG-18, EC-01/OF-10) und Belege für neue Befunde (BUG-19 bis BUG-23).
/// Tests, die einen offenen Befund belegen, formulieren das erwartete Verhalten und stehen in `XCTExpectFailure`
/// (noch: BUG-20 = B01 BF-46, nicht im Auftrag). BUG-19, -21, -22, -23 sind seit dem Bau vom 2026-10-02 feste Prüfungen.
///
/// Nichts davon berührt die Datenbank des Nutzers, den echten Schlüsselbund-Dienst der App, das echte Repository
/// oder das Netz: Temp-Ordner, eigener Schlüsselbund-Dienst je Test, kopierte Skripte, Wegwerf-Schlüssel.
@MainActor
final class B09QA2Tests: XCTestCase {
    private var tempDirs: [URL] = []
    private var credentialStores: [XtreamCredentialStore] = []

    override func tearDown() async throws {
        for store in credentialStores { try? store.deleteAll() }
        credentialStores.removeAll()
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs.removeAll()
        try await super.tearDown()
    }

    private func tempDir(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("b09-qa2-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    // MARK: - EC-07 / BUG-13 · zweiter Start nach dem Beiseitelegen

    /// Erster Start mit kaputter Datei: beiseitegelegt + Hinweis. Zweiter Start: öffnet die neue Datei, **kein** Hinweis mehr.
    /// Ist die neue Datei beim dritten Start wieder kaputt (gleicher Zeitstempel), entsteht ein zweiter Ordner – nichts wird
    /// überschrieben.
    func testEC07_BUG13_ZweiterStartOhneHinweisUndNichtsWirdUeberschrieben() throws {
        let dir = try tempDir("zweiterstart")
        let storeURL = dir.appendingPathComponent(AppPersistence.storeFileName)
        let erstesKaputt = Data(String(repeating: "erste kaputte Datei ", count: 300).utf8)
        try erstesKaputt.write(to: storeURL)
        let now = Date(timeIntervalSince1970: 1_900_000_000)

        let (_, erster) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema, now: now)
        guard case .recovered(let ersterOrt, _) = erster else { return XCTFail("erwartet .recovered, erhalten \(erster)") }
        XCTAssertNotNil(erster.notice, "erster Start zeigt den Hinweis")

        let (zweiterContainer, zweiter) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema, now: now)
        print("B09QA2|EC-07|zweiterStart|\(zweiter)|notice=\(zweiter.notice == nil ? "nil" : "gesetzt")")
        XCTAssertEqual(zweiter, .opened)
        XCTAssertNil(zweiter.notice, "zweiter Start ohne Hinweis")
        XCTAssertEqual(try zweiterContainer.mainContext.fetchCount(FetchDescriptor<Playlist>()), 0)

        // dritter Start: neue Datei ebenfalls kaputt, gleicher Zeitstempel
        let zweitesKaputt = Data(String(repeating: "zweite kaputte Datei ", count: 300).utf8)
        for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: storeURL.path + suffix) }
        try zweitesKaputt.write(to: storeURL)
        let (_, dritter) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema, now: now)
        guard case .recovered(let dritterOrt, _) = dritter else { return XCTFail("erwartet .recovered, erhalten \(dritter)") }
        print("B09QA2|EC-07|ordner|\(ersterOrt.deletingLastPathComponent().lastPathComponent)|\(dritterOrt.deletingLastPathComponent().lastPathComponent)")
        XCTAssertNotEqual(ersterOrt, dritterOrt)
        XCTAssertEqual(try Data(contentsOf: ersterOrt), erstesKaputt, "erste beiseitegelegte Datei unverändert")
        XCTAssertEqual(try Data(contentsOf: dritterOrt), zweitesKaputt, "zweite beiseitegelegte Datei unverändert")
        let ordner = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent(AppPersistence.setAsideFolderName).path)
        XCTAssertEqual(ordner.count, 2, "zwei Zeitstempel-Ordner: \(ordner)")
    }

    // MARK: - EC-07 / BUG-20 · Schlüsselbund-Einträge der beiseitegelegten Playlists

    /// Nach dem Beiseitelegen gibt es in der App keine Playlist mehr, über die die Zugangsdaten gelöscht werden könnten.
    /// Der Eintrag im Schlüsselbund bleibt; ein erneuter Import legt einen zweiten an.
    func testEC07_BUG20_ZugangsdatenBeiseitegelegterPlaylistsBleibenOhneLoeschweg() throws {
        let store = XtreamCredentialStore(service: "lu.daumedia.MikaPlusPlayer.xtream.tests.qa2.\(UUID().uuidString)")
        credentialStores.append(store)
        let secret = XtreamSecret(host: "http://127.0.0.1:9", username: "qa-user", password: "qa-pass-123")

        let dir = try tempDir("schluesselbund")
        let storeURL = dir.appendingPathComponent(AppPersistence.storeFileName)
        let alteID = UUID()
        do {
            let container = try AppPersistence.diskContainer(at: storeURL, schema: AppSchema.schema)
            let context = ModelContext(container)
            context.insert(Playlist(id: alteID, name: "QA Xtream", sourceURL: URL(string: "http://127.0.0.1:9/player_api.php"),
                                    isXtream: true, xtreamOutput: "ts"))
            try context.save()
            try store.save(secret, for: alteID)
        }
        // Datei unlesbar machen (Kopf überschreiben), wie nach einem Schreibfehler
        let handle = try FileHandle(forWritingTo: storeURL)
        try handle.write(contentsOf: Data(repeating: 0x5A, count: 100))
        try handle.close()

        let (container, outcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
        guard case .recovered = outcome else { return XCTFail("erwartet .recovered, erhalten \(outcome)") }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 0, "neue Datenbank leer")
        // Durchlauf 2 (OF-08, 2026-10-02): Der Hinweis nennt die Zugangsdaten im Schlüsselbund und den Löschweg.
        // Der verwaiste Eintrag selbst bleibt (BUG-20 = B01 BF-46, nicht im Auftrag) → XCTExpectFailure unten.
        XCTAssertTrue(outcome.notice?.message.contains("Schlüsselbund") ?? false, "Hinweis nennt die Zugangsdaten im Schlüsselbund")
        XCTAssertTrue(outcome.notice?.message.contains("„Alle Daten entfernen …“") ?? false, "Hinweis nennt den Löschweg")

        // Nutzer importiert dieselben Zugangsdaten neu → neue Playlist-ID, zweiter Eintrag
        try store.save(secret, for: UUID())
        let eintraege = try keychainAccounts(service: store.service)
        print("B09QA2|BUG-20|eintraege=\(eintraege.count)|alterEintragVorhanden=\((try? store.load(for: alteID)) != nil)")
        XCTAssertEqual(eintraege.count, 2)

        XCTExpectFailure("BUG-20 offen: Zugangsdaten der beiseitegelegten Playlists bleiben ohne Löschweg im Schlüsselbund") {
            XCTAssertFalse((try? store.load(for: alteID)) != nil, "verwaister Schlüsselbund-Eintrag ohne Playlist in der App")
        }
    }

    private func keychainAccounts(service: String) throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        XCTAssertEqual(status, errSecSuccess)
        return ((result as? [[String: Any]]) ?? []).compactMap { $0[kSecAttrAccount as String] as? String }
    }

    // MARK: - AK-01 / EC-01 / BUG-21 · Menü und Updater im Test-Host

    static let updateTitles = ["Nach Updates suchen …", "Automatisch nach Updates suchen", "Updates automatisch installieren"]

    private func updateMenuItem() async throws -> (appMenu: NSMenu, index: Int, item: NSMenuItem)? {
        let frist = Date().addingTimeInterval(10)
        while Date() < frist {
            if let appMenu = NSApp.mainMenu?.items.first?.submenu {
                appMenu.update()
                if let index = appMenu.items.firstIndex(where: { $0.title == "Nach Updates suchen …" }) {
                    return (appMenu, index, appMenu.items[index])
                }
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }

    /// AK-01 / AK-31 · Die drei Update-Einträge stehen direkt unter „Über …“ (deutsch, OF-01; englisch angenommen, falls
    /// das System die App-Sprache nicht übernimmt). Im Test-Host läuft Sparkle nicht (BF-49): alle drei inaktiv.
    /// Aktiv sind sie im Debug- und Release-Build (Selbsttest im Build-Bericht).
    func testAK01_AK31_UpdateEintraegeDirektUnterUeberImTestHostInaktiv() async throws {
        guard let (appMenu, index, _) = try await updateMenuItem() else {
            return XCTFail("Menüeintrag nicht gefunden: \(NSApp.mainMenu?.items.first?.submenu?.items.map(\.title) ?? [])")
        }
        let titel = appMenu.items.map { $0.isSeparatorItem ? "—" : $0.title }
        print("B09QA2|AK-01|appMenu=\(titel)|index=\(index)|enabled=\(appMenu.items.map(\.isEnabled))|state=\(appMenu.items.map(\.state.rawValue))")
        XCTAssertEqual(index, 1, "zweite Position")
        XCTAssertTrue(appMenu.items[0].title.hasPrefix("Über") || appMenu.items[0].title.hasPrefix("About"), "darüber steht „Über …“")
        XCTAssertEqual(Array(titel.dropFirst().prefix(3)), Self.updateTitles, "drei Update-Einträge in dieser Reihenfolge")
        for item in appMenu.items[1...3] {
            XCTAssertFalse(item.isEnabled, "„\(item.title)“ im Test-Host inaktiv")
        }
    }

    /// EC-01 / OF-10 / BF-49 / BF-119 · Der Test-Host trägt die eigene Debug-Bundle-ID (Einstellungsdomäne getrennt von
    /// der installierten App) und startet Sparkle nicht: `canCheckForUpdates` wird erst in `SPUUpdater.startUpdater` wahr
    /// (Sparkle 2.9.3 `SPUUpdater.m:168`), der Menüeintrag bleibt deshalb inaktiv. Vorher (QA 2, BUG-21) schrieb der
    /// Test-Host in `~/Library/Preferences/lu.daumedia.MikaPlusPlayer.plist` und fragte den echten Feed ab.
    func testEC01_BUG21_TestHostStartetSparkleNichtUndHatEigeneBundleID() async throws {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "lu.daumedia.MikaPlusPlayer.debug", "Test-Host mit eigener Bundle-ID")
        XCTAssertEqual(UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["ApplePersistenceIgnoreState"] as? String,
                       "YES", "Test-Host ignoriert gespeicherten Fensterzustand")
        XCTAssertEqual(ProcessInfo.processInfo.environment["MIKA_TEST_HOST"], "1", "Umgebungsmarke der Testaktion")
        XCTAssertEqual(Bundle(identifier: "org.sparkle-project.Sparkle")?.isLoaded, true, "Sparkle im Test-Host geladen")
        let item = try await updateMenuItem()?.item
        let updaterGestartet = item?.isEnabled ?? false
        print("B09QA2|EC-01|bundleID=\(Bundle.main.bundleIdentifier ?? "-")|updaterGestartet=\(updaterGestartet)|SUFeedURL=\(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") ?? "-")")
        XCTAssertNotNil(item, "Menüeintrag vorhanden")
        XCTAssertFalse(updaterGestartet, "Sparkle-Updater im Test-Host gestartet")
    }

    // MARK: - BUG-19 · Gegenprüfung blockiert Releases, sobald generate_appcast alte Einträge kürzt

    func testBUG19_FeedPruefungBlockiertReleaseNachKuerzungDurchGenerateAppcast() throws {
        let tools = try sparkleTools()
        let key = Curve25519.Signing.PrivateKey()
        let repo = try makeCheckRepo(build: "5", marketing: "1.4", publicKey: key.publicKey.rawRepresentation.base64EncodedString())

        // versionierter Feed wie nach zwei weiteren Releases: Einträge 2 (v1.1), 3 und 4, alle macOS 14.0
        let original = try String(contentsOf: B09ReleaseConfigTests.repoRoot().appendingPathComponent("appcast.xml"), encoding: .utf8)
        let zusatz = ["4": "1.3", "3": "1.2"].sorted { $0.key > $1.key }.map { build, short in
            """
                    <item>
                        <title>\(short)</title>
                        <pubDate>Wed, 16 Sep 2026 12:00:00 +0200</pubDate>
                        <sparkle:version>\(build)</sparkle:version>
                        <sparkle:shortVersionString>\(short)</sparkle:shortVersionString>
                        <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
                        <enclosure url="https://github.com/daumedia/MikaPlusPlayer/releases/download/v\(short)/MikaPlusPlayer-v\(short).dmg" length="1000" type="application/octet-stream" sparkle:edSignature="QUFBQQ=="/>
                    </item>

            """
        }.joined()
        let base = original.replacingOccurrences(of: "<item>", with: zusatz.trimmingCharacters(in: .whitespaces) + "        <item>",
                                                 options: [], range: original.range(of: "<item>"))
        let baseURL = repo.appendingPathComponent("appcast.xml")
        try base.write(to: baseURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(Self.feedVersions(base), [2, 3, 4])

        let dmg = try makeDMG(build: "5", marketing: "1.4", publicKey: key.publicKey.rawRepresentation.base64EncodedString())
        let stage = try tempDir("stage")
        try FileManager.default.copyItem(at: baseURL, to: stage.appendingPathComponent("appcast.xml"))
        try FileManager.default.copyItem(at: dmg, to: stage.appendingPathComponent(dmg.lastPathComponent))
        let keyFile = try tempDir("key").appendingPathComponent("test.key")
        try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: keyFile)

        // genau die Aufrufe aus scripts/release.sh (Durchlauf 2, BF-47: mit --maximum-versions 0)
        let release = try String(contentsOf: B09ReleaseConfigTests.repoRoot().appendingPathComponent("scripts/release.sh"), encoding: .utf8)
        XCTAssertTrue(release.contains(#""$GEN" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} --maximum-versions 0 \"#), "release.sh ruft generate_appcast wie hier auf")
        let gen = try shell(tools.appendingPathComponent("generate_appcast").path,
                            ["--ed-key-file", keyFile.path, "--maximum-versions", "0", "--download-url-prefix",
                             "https://github.com/daumedia/MikaPlusPlayer/releases/download/v1.4/", stage.path], in: stage)
        XCTAssertEqual(gen.status, 0, gen.output)
        _ = try shell(tools.appendingPathComponent("sign_update").path, ["--ed-key-file", keyFile.path, stage.appendingPathComponent("appcast.xml").path], in: stage)
        let neu = try String(contentsOf: stage.appendingPathComponent("appcast.xml"), encoding: .utf8)
        print("B09QA2|BUG-19|generate_appcast|\(gen.output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").last ?? "")|versionen=\(Self.feedVersions(neu))")
        XCTAssertTrue(gen.output.contains("removed 0 old updates"), "mit --maximum-versions 0 bleibt jeder Eintrag: \(gen.output)")
        XCTAssertEqual(Self.feedVersions(neu), [2, 3, 4, 5])

        let check = try shell("/bin/bash", [repo.appendingPathComponent("scripts/b09_release_check.sh").path, "feed"], in: repo,
                              environment: scriptEnvironment(["FEED": stage.appendingPathComponent("appcast.xml").path,
                                                              "BASE_FEED": baseURL.path, "DMG": dmg.path]))
        print("B09QA2|BUG-19|feed-check|exit=\(check.status)|\(check.output.components(separatedBy: "\n").filter { $0.contains("BEFUND") }.joined(separator: " / "))")
        // Durchlauf 2 (BF-47): behoben — der korrekt signierte Feed mit Build 5 wird angenommen.
        XCTAssertEqual(check.status, 0, "korrekter Feed (Build 5, signiert, gültig) wird als Befund abgewiesen\n\(check.output)")
    }

    // MARK: - BUG-22 / BUG-23 · Eingaben, die die Gegenprüfung vor dem Build durchlässt

    func testBUG22_VorBuildLaesstLeereAnzeigeversionDurch() throws {
        let repo = try makeCheckRepo(build: "3", marketing: "", publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString(), git: true)
        let result = try shell("/bin/bash", [repo.appendingPathComponent("scripts/b09_release_check.sh").path, "vor-build"], in: repo, environment: scriptEnvironment(["PROBEMODUS": "1"]))
        print("B09QA2|BUG-22|vor-build|exit=\(result.status)|\(result.output.components(separatedBy: "\n").filter { $0.contains("MARKETING") || $0.contains("Tag v") }.joined(separator: " / "))")
        // Durchlauf 2 (BF-50): behoben.
        XCTAssertEqual(result.status, 1, "leere Anzeigeversion muss ein Befund sein")
        XCTAssertTrue(result.output.contains("[BEFUND] MARKETING_VERSION ist leer oder keine Versionsnummer: „“"), result.output)
        XCTAssertEqual(result.output.components(separatedBy: "[BEFUND]").count - 1, 1, "genau dieser Befund\n\(result.output)")
    }

    func testBUG23_VorBuildPrueftDownloadAdressenBestehenderEintraegeNicht() throws {
        let repo = try makeCheckRepo(build: "3", marketing: "1.2", publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString(), git: false)
        let feed = try String(contentsOf: repo.appendingPathComponent("appcast.xml"), encoding: .utf8)
            .replacingOccurrences(of: "https://github.com/daumedia/MikaPlusPlayer/releases/download/v1.1/", with: "https://angreifer.example/download/")
        try feed.write(to: repo.appendingPathComponent("appcast.xml"), atomically: true, encoding: .utf8)
        try gitCommit(repo)
        let result = try shell("/bin/bash", [repo.appendingPathComponent("scripts/b09_release_check.sh").path, "vor-build"], in: repo, environment: scriptEnvironment(["PROBEMODUS": "1"]))
        print("B09QA2|BUG-23|vor-build|exit=\(result.status)|befunde=\(result.output.components(separatedBy: "\n").filter { $0.contains("BEFUND") })")
        // Durchlauf 2 (BF-48): behoben.
        XCTAssertEqual(result.status, 1, "fremder Download-Host im versionierten Feed muss ein Befund sein")
        XCTAssertTrue(result.output.contains("[BEFUND] versionierte appcast.xml: Download-Adresse außerhalb von https://github.com/daumedia/MikaPlusPlayer/releases/download/: https://angreifer.example/download/"), result.output)
        XCTAssertEqual(result.output.components(separatedBy: "[BEFUND]").count - 1, 1, "genau dieser Befund\n\(result.output)")
    }

    // MARK: - Hilfen (Attrappen)

    static func feedVersions(_ feed: String) -> [Int] {
        let regex = try! NSRegularExpression(pattern: "<sparkle:version>(\\d+)</sparkle:version>")
        return regex.matches(in: feed, range: NSRange(feed.startIndex..., in: feed))
            .compactMap { Range($0.range(at: 1), in: feed).flatMap { Int(feed[$0]) } }.sorted()
    }

    private func makeCheckRepo(build: String, marketing: String, publicKey: String, git: Bool = false) throws -> URL {
        let source = try B09ReleaseConfigTests.repoRoot()
        let repo = try tempDir("repo")
        let fm = FileManager.default
        for dir in ["scripts", "Sources/Resources"] {
            try fm.createDirectory(at: repo.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        for file in ["scripts/b09_release_check.sh", "scripts/b09_ed25519.swift", "appcast.xml"] {
            try fm.copyItem(at: source.appendingPathComponent(file), to: repo.appendingPathComponent(file))
        }
        var yml = try String(contentsOf: source.appendingPathComponent("project.yml"), encoding: .utf8)
        yml = yml.replacingOccurrences(of: #"(?m)^(\s*MARKETING_VERSION:).*$"#, with: "$1 \"\(marketing)\"", options: .regularExpression)
        yml = yml.replacingOccurrences(of: #"(?m)^(\s*CURRENT_PROJECT_VERSION:).*$"#, with: "$1 \"\(build)\"", options: .regularExpression)
        try yml.write(to: repo.appendingPathComponent("project.yml"), atomically: true, encoding: .utf8)
        let infoData = try Data(contentsOf: source.appendingPathComponent("Sources/Resources/Info.plist"))
        var info = try XCTUnwrap(PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any])
        info["SUPublicEDKey"] = publicKey
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: repo.appendingPathComponent("Sources/Resources/Info.plist"))
        try "build/\ndist/\n".write(to: repo.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        if git {
            try shell("/usr/bin/git", ["init", "-q"], in: repo)
            try gitCommit(repo)
        }
        return repo
    }

    private func gitCommit(_ repo: URL) throws {
        if !FileManager.default.fileExists(atPath: repo.appendingPathComponent(".git").path) {
            try shell("/usr/bin/git", ["init", "-q"], in: repo)
        }
        let g = ["-c", "user.name=QA", "-c", "user.email=qa@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"]
        try shell("/usr/bin/git", g + ["add", "-A"], in: repo)
        try shell("/usr/bin/git", g + ["commit", "-q", "-m", "QA"], in: repo)
    }

    /// Minimal-App (`/usr/bin/true`) mit macOS 14.0 als Mindestversion, ad hoc mit Runtime signiert, im DMG.
    private func makeDMG(build: String, marketing: String, publicKey: String) throws -> URL {
        let stage = try tempDir("dmgstage")
        let app = stage.appendingPathComponent("MikaPlusPlayer.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: app.appendingPathComponent("Contents/MacOS/MikaPlusPlayer"))
        let info: [String: Any] = [
            "CFBundleExecutable": "MikaPlusPlayer", "CFBundleIdentifier": "lu.daumedia.MikaPlusPlayer.qa2attrappe",
            "CFBundleName": "Mika+Player", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": marketing,
            "CFBundleVersion": build, "LSMinimumSystemVersion": "14.0", "SUPublicEDKey": publicKey
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try shell("/usr/bin/codesign", ["--force", "--sign", "-", "--options", "runtime", app.path], in: stage)
        let out = try tempDir("dmg").appendingPathComponent("MikaPlusPlayer-v\(marketing).dmg")
        try shell("/usr/bin/hdiutil", ["create", "-volname", "Mika+Player", "-srcfolder", stage.path, "-ov", "-format", "UDZO", out.path], in: stage)
        return out
    }

    private func sparkleTools() throws -> URL {
        let build = try B09ReleaseConfigTests.repoRoot().appendingPathComponent("build")
        for dd in ((try? FileManager.default.contentsOfDirectory(atPath: build.path)) ?? []).sorted() {
            let bin = build.appendingPathComponent(dd).appendingPathComponent("SourcePackages/artifacts/sparkle/Sparkle/bin")
            if FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent("generate_appcast").path),
               FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent("sign_update").path) {
                return bin
            }
        }
        throw XCTSkip("generate_appcast/sign_update nicht unter build/*/SourcePackages/artifacts gefunden")
    }

    private func scriptEnvironment(_ extra: [String: String]) throws -> [String: String] {
        let home = try tempDir("home")
        var environment = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("XCTest") && !$0.key.hasPrefix("DYLD_") && !$0.key.hasPrefix("__XPC_DYLD_")
        }
        environment["HOME"] = home.path
        environment["CFFIXED_USER_HOME"] = home.path
        environment["LANG"] = "de_DE.UTF-8"
        for (key, value) in extra { environment[key] = value }
        return environment
    }

    @discardableResult
    private func shell(_ tool: String, _ args: [String], in dir: URL, environment: [String: String]? = nil) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.currentDirectoryURL = dir
        if let environment { process.environment = environment }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
#endif
