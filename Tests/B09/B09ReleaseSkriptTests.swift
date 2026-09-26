#if os(macOS)
import CryptoKit
import Foundation
import XCTest

/// B09 · BUG-02/04/10/11 — die Gegenprüfungen (`scripts/b09_release_check.sh`) und `scripts/release.sh`,
/// ausgeführt in Attrappen-Repositories im Temp-Ordner.
///
/// Nichts davon berührt das echte Repository, den Schlüsselbund oder das Netz: Die Skripte werden kopiert, Build und
/// DMG sind Stubs, signiert wird mit einem im Test erzeugten Wegwerf-Schlüssel (`--ed-key-file`). `HOME` zeigt auf den
/// Temp-Ordner (Git-Konfiguration, Cache von generate_appcast).
final class B09ReleaseSkriptTests: XCTestCase {
    private var tempDirs: [URL] = []

    override func tearDown() {
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs.removeAll()
        super.tearDown()
    }

    // MARK: - vor-build

    func testBUG04_VorBuildBrichtAbWennBuildNummerNichtHoeher() throws {
        let repo = try makeRepo(build: "2", marketing: "1.2")
        let result = try run(repo, "vor-build")
        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("[BEFUND] CURRENT_PROJECT_VERSION=2 ist nicht größer als die höchste sparkle:version 2"), result.output)
    }

    func testBUG11_VorBuildBestehtMitNeuenVersionen() throws {
        let repo = try makeRepo(build: "3", marketing: "1.2")
        let result = try run(repo, "vor-build")
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertFalse(result.output.contains("[BEFUND]"), result.output)
        XCTAssertTrue(result.output.contains("[ offen] SURequireSignedFeed fehlt"), "offener Punkt BUG-08 wird genannt")

        let strict = try run(repo, "vor-build", env: ["STRENG": "1"])
        XCTAssertEqual(strict.status, 1, "STRENG=1 lässt offene Punkte abbrechen")
    }

    func testBUG11_VorBuildMeldetVeroeffentlichteVersionUndUnsauberenStand() throws {
        let repo = try makeRepo(build: "3", marketing: "1.1")
        try Data("lokale Änderung\n".utf8).write(to: repo.appendingPathComponent("unversioniert.txt"))
        let result = try run(repo, "vor-build")
        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("[BEFUND] MARKETING_VERSION=1.1 ist schon veröffentlicht"), result.output)
        XCTAssertTrue(result.output.contains("[BEFUND] Arbeitsverzeichnis nicht sauber"), result.output)
    }

    func testBUG10_VorBuildErkenntAltstandImVersioniertenFeed() throws {
        let repo = try makeRepo(build: "3", marketing: "1.2", appcast: Self.staleAppcast)
        let result = try run(repo, "vor-build")
        XCTAssertEqual(result.status, 1, result.output)
        for finding in ["appcast.xml enthält Mukaarts-URLs", "nie veröffentlichter 1.0-Eintrag", "Kanaltitel „MikaPlusPlayer“"] {
            XCTAssertTrue(result.output.contains("[BEFUND] \(finding)"), "\(finding)\n\(result.output)")
        }
    }

    // MARK: - nach-build

    func testBUG02_NachBuildErkenntGetTaskAllowUndFehlendeRuntime() throws {
        let repo = try makeRepo(build: "3", marketing: "1.2")
        let debugLike = try makeApp(build: "3", marketing: "1.2", runtime: false, getTaskAllow: true)
        let dmg = try makeDMG(app: debugLike, marketing: "1.2")
        let bad = try run(repo, "nach-build", env: ["APP": debugLike.path, "DMG": dmg.path])
        XCTAssertEqual(bad.status, 1, bad.output)
        XCTAssertTrue(bad.output.contains("[BEFUND] get-task-allow im Bundle"), bad.output)
        XCTAssertTrue(bad.output.contains("[BEFUND] Hardened Runtime nicht aktiv"), bad.output)

        let release = try makeApp(build: "3", marketing: "1.2", runtime: true, getTaskAllow: false)
        let releaseDMG = try makeDMG(app: release, marketing: "1.2")
        let good = try run(repo, "nach-build", env: ["APP": release.path, "DMG": releaseDMG.path])
        XCTAssertEqual(good.status, 0, good.output)
        XCTAssertTrue(good.output.contains("[  ok  ] kein get-task-allow"), good.output)
        XCTAssertTrue(good.output.contains("[  ok  ] Hardened Runtime aktiv"), good.output)
        XCTAssertTrue(good.output.contains("[  ok  ] App im DMG ist das geprüfte Bundle"), good.output)
        XCTAssertTrue(good.output.contains("[ offen] ad-hoc signiert"), "BUG-03 bleibt als offener Punkt sichtbar")

        // DMG mit einem anderen Bundle als dem geprüften
        let mismatch = try run(repo, "nach-build", env: ["APP": release.path, "DMG": dmg.path])
        XCTAssertEqual(mismatch.status, 1, mismatch.output)
        XCTAssertTrue(mismatch.output.contains("[BEFUND] App im DMG weicht vom geprüften Bundle ab"), mismatch.output)
    }

    // MARK: - release.sh vollständig (Attrappen für Build und DMG, echtes generate_appcast/sign_update)

    func testBUG10_ReleaseSchreibtVersioniertenFeedFort() throws {
        let tools = try sparkleTools()
        let repo = try makeRepo(build: "3", marketing: "1.2", releaseStubs: true)
        let appcastBefore = try Data(contentsOf: repo.appendingPathComponent("appcast.xml"))
        let distBefore = try Data(contentsOf: repo.appendingPathComponent("dist/appcast.xml"))

        let result = try runRelease(repo, tools: tools, keyFile: keyFile)
        XCTAssertEqual(result.status, 0, result.output)
        let feed = try String(contentsOf: repo.appendingPathComponent("appcast.xml"), encoding: .utf8)
        print("B09BUILD|BUG-10|release.sh|exit=\(result.status)|mukaarts=\(feed.lowercased().contains("mukaarts"))|version1=\(feed.contains("<sparkle:version>1</sparkle:version>"))|titel=\(feed.contains("<title>Mika+Player</title>"))|signiert=\(feed.contains("<!-- sparkle-signatures:"))")
        XCTAssertTrue(feed.contains("<title>Mika+Player</title>"), "Titel aus der versionierten appcast.xml bleibt")
        XCTAssertFalse(feed.lowercased().contains("mukaarts"), "keine Mukaarts-URLs aus dist/appcast.xml")
        XCTAssertFalse(feed.contains("<sparkle:version>1</sparkle:version>"), "kein 1.0-Eintrag aus dist/appcast.xml")
        XCTAssertTrue(feed.contains("<sparkle:version>2</sparkle:version>"), "veröffentlichter Eintrag 1.1 bleibt")
        XCTAssertTrue(feed.contains("<sparkle:version>3</sparkle:version>"), "neuer Eintrag")
        XCTAssertTrue(feed.contains("releases/download/v1.2/MikaPlusPlayer-v1.2.dmg"))
        XCTAssertTrue(feed.contains("<!-- sparkle-signatures:"), "Feed ist signiert (Vorbereitung BUG-08)")
        XCTAssertNotEqual(try Data(contentsOf: repo.appendingPathComponent("appcast.xml")), appcastBefore)
        XCTAssertEqual(try Data(contentsOf: repo.appendingPathComponent("dist/appcast.xml")), distBefore, "dist/appcast.xml unberührt")
        XCTAssertTrue(result.output.contains("[  ok  ] EdDSA-Signatur des DMG gültig gegen SUPublicEDKey"), result.output)
        XCTAssertTrue(result.output.contains("[  ok  ] Feed-Signatur gültig gegen SUPublicEDKey"), result.output)
    }

    /// Falscher Schlüssel: generate_appcast warnt nur und schreibt einen Eintrag ohne Signatur. Die Gegenprüfung
    /// bricht ab, bevor appcast.xml geändert wird.
    func testBUG11_ReleaseBrichtBeiFalschemSchluesselAbOhneFeedZuAendern() throws {
        let tools = try sparkleTools()
        let repo = try makeRepo(build: "3", marketing: "1.2", releaseStubs: true)
        let appcastBefore = try Data(contentsOf: repo.appendingPathComponent("appcast.xml"))
        let foreignKey = try writeKeyFile(Curve25519.Signing.PrivateKey(), name: "fremd.key")

        let result = try runRelease(repo, tools: tools, keyFile: foreignKey)
        print("B09BUILD|BUG-11|falscherSchluessel|exit=\(result.status)")
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("[BEFUND]"), result.output)
        XCTAssertEqual(try Data(contentsOf: repo.appendingPathComponent("appcast.xml")), appcastBefore, "appcast.xml unverändert")
    }

    // MARK: - Attrappen

    private lazy var testKey = Curve25519.Signing.PrivateKey()
    private lazy var keyFile: URL = try! writeKeyFile(testKey, name: "test.key")
    private var publicKeyBase64: String { testKey.publicKey.rawRepresentation.base64EncodedString() }

    private func tempDir(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("b09-build-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    private func writeKeyFile(_ key: Curve25519.Signing.PrivateKey, name: String) throws -> URL {
        let dir = try tempDir("schluessel")
        let url = dir.appendingPathComponent(name)
        try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: url)
        return url
    }

    private static let staleAppcast = """
    <?xml version="1.0" standalone="yes"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
        <channel>
            <title>MikaPlusPlayer</title>
            <item>
                <title>1.1</title>
                <sparkle:version>2</sparkle:version>
                <sparkle:shortVersionString>1.1</sparkle:shortVersionString>
                <enclosure url="https://github.com/Mukaarts/MikaPlusPlayer/releases/download/v1.1/MikaPlusPlayer-v1.1.dmg" length="1" type="application/octet-stream" sparkle:edSignature="AA=="/>
            </item>
            <item>
                <title>1.0</title>
                <sparkle:version>1</sparkle:version>
                <sparkle:shortVersionString>1.0</sparkle:shortVersionString>
                <enclosure url="https://github.com/Mukaarts/MikaPlusPlayer/releases/download/v1.0/MikaPlusPlayer-v1.0.dmg" length="1" type="application/octet-stream" sparkle:edSignature="AA=="/>
            </item>
        </channel>
    </rss>
    """

    /// Kopie der echten Skripte, `project.yml`, `Info.plist` (mit Test-Schlüssel) und `appcast.xml`; Git-Stand sauber.
    private func makeRepo(build: String, marketing: String, appcast: String? = nil, releaseStubs: Bool = false) throws -> URL {
        let source = try B09ReleaseConfigTests.repoRoot()
        let repo = try tempDir("repo")
        let fm = FileManager.default
        for dir in ["scripts", "Sources/Resources", "dist"] {
            try fm.createDirectory(at: repo.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        for file in ["scripts/b09_release_check.sh", "scripts/b09_ed25519.swift", "scripts/release.sh"] {
            try fm.copyItem(at: source.appendingPathComponent(file), to: repo.appendingPathComponent(file))
        }
        var yml = try String(contentsOf: source.appendingPathComponent("project.yml"), encoding: .utf8)
        yml = yml.replacingOccurrences(of: #"(?m)^(\s*MARKETING_VERSION:).*$"#, with: "$1 \"\(marketing)\"", options: .regularExpression)
        yml = yml.replacingOccurrences(of: #"(?m)^(\s*CURRENT_PROJECT_VERSION:).*$"#, with: "$1 \"\(build)\"", options: .regularExpression)
        try yml.write(to: repo.appendingPathComponent("project.yml"), atomically: true, encoding: .utf8)

        let infoData = try Data(contentsOf: source.appendingPathComponent("Sources/Resources/Info.plist"))
        var info = try XCTUnwrap(PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any])
        info["SUPublicEDKey"] = publicKeyBase64
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: repo.appendingPathComponent("Sources/Resources/Info.plist"))

        if let appcast {
            try appcast.write(to: repo.appendingPathComponent("appcast.xml"), atomically: true, encoding: .utf8)
        } else {
            try fm.copyItem(at: source.appendingPathComponent("appcast.xml"), to: repo.appendingPathComponent("appcast.xml"))
        }
        // Altstand wie im echten dist/ (nicht versioniert)
        try Self.staleAppcast.write(to: repo.appendingPathComponent("dist/appcast.xml"), atomically: true, encoding: .utf8)
        try "build/\ndist/\n".write(to: repo.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

        if releaseStubs {
            let app = try makeApp(build: build, marketing: marketing, runtime: true, getTaskAllow: false)
            try """
            #!/bin/bash
            set -euo pipefail
            ROOT="$(cd "$(dirname "$0")/.." && pwd)"
            mkdir -p "$ROOT/build"; rm -rf "$ROOT/build/MikaPlusPlayer.app"; cp -R "\(app.path)" "$ROOT/build/MikaPlusPlayer.app"
            echo "==> [Attrappe] build/MikaPlusPlayer.app"
            """.write(to: repo.appendingPathComponent("scripts/build-macos.sh"), atomically: true, encoding: .utf8)
            try """
            #!/bin/bash
            set -euo pipefail
            ROOT="$(cd "$(dirname "$0")/.." && pwd)"
            VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/build/MikaPlusPlayer.app/Contents/Info.plist")
            STAGE=$(mktemp -d); cp -R "$ROOT/build/MikaPlusPlayer.app" "$STAGE/"
            rm -f "$ROOT/dist"/*.dmg
            hdiutil create -volname "Mika+Player" -srcfolder "$STAGE" -ov -format UDZO "$ROOT/dist/MikaPlusPlayer-v$VER.dmg" >/dev/null 2>&1
            rm -rf "$STAGE"; echo "==> [Attrappe] dist/MikaPlusPlayer-v$VER.dmg"
            """.write(to: repo.appendingPathComponent("scripts/make-dmg.sh"), atomically: true, encoding: .utf8)
        }

        let git = ["-c", "user.name=B09", "-c", "user.email=b09@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"]
        try shell("/usr/bin/git", ["init", "-q"], in: repo)
        try shell("/usr/bin/git", git + ["add", "-A"], in: repo)
        try shell("/usr/bin/git", git + ["commit", "-q", "-m", "Attrappe"], in: repo)
        return repo
    }

    /// Minimal-Bundle: `/usr/bin/true` als Programm, ad hoc signiert wie das Release.
    private func makeApp(build: String, marketing: String, runtime: Bool, getTaskAllow: Bool) throws -> URL {
        let base = try tempDir("app")
        let app = base.appendingPathComponent("MikaPlusPlayer.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appendingPathComponent("MikaPlusPlayer"))
        let info: [String: Any] = [
            "CFBundleExecutable": "MikaPlusPlayer",
            "CFBundleIdentifier": "lu.daumedia.MikaPlusPlayer.b09attrappe",
            "CFBundleName": "Mika+Player",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": marketing,
            "CFBundleVersion": build,
            "LSMinimumSystemVersion": "14.0",
            "SUFeedURL": "https://raw.githubusercontent.com/daumedia/MikaPlusPlayer/main/appcast.xml",
            "SUPublicEDKey": publicKeyBase64,
            "SUVerifyUpdateBeforeExtraction": true,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        var entitlements: [String: Any] = ["com.apple.security.cs.disable-library-validation": true]
        if getTaskAllow { entitlements["com.apple.security.get-task-allow"] = true }
        let entitlementsURL = base.appendingPathComponent("ents.plist")
        try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0).write(to: entitlementsURL)
        var args = ["--force", "--sign", "-", "--entitlements", entitlementsURL.path]
        if runtime { args += ["--options", "runtime"] }
        try shell("/usr/bin/codesign", args + [app.path], in: base)
        return app
    }

    private func makeDMG(app: URL, marketing: String) throws -> URL {
        let stage = try tempDir("dmgstage")
        try FileManager.default.copyItem(at: app, to: stage.appendingPathComponent("MikaPlusPlayer.app"))
        let out = try tempDir("dmg").appendingPathComponent("MikaPlusPlayer-v\(marketing).dmg")
        try shell("/usr/bin/hdiutil", ["create", "-volname", "Mika+Player", "-srcfolder", stage.path, "-ov", "-format", "UDZO", out.path], in: stage)
        return out
    }

    private func sparkleTools() throws -> URL {
        let root = try B09ReleaseConfigTests.repoRoot()
        let build = root.appendingPathComponent("build")
        let candidates = (try? FileManager.default.contentsOfDirectory(atPath: build.path)) ?? []
        for dd in candidates.sorted() {
            let bin = build.appendingPathComponent(dd).appendingPathComponent("SourcePackages/artifacts/sparkle/Sparkle/bin")
            if FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent("generate_appcast").path),
               FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent("sign_update").path) {
                return bin
            }
        }
        throw XCTSkip("generate_appcast/sign_update nicht unter build/*/SourcePackages/artifacts gefunden")
    }

    private func runRelease(_ repo: URL, tools: URL, keyFile: URL) throws -> (status: Int32, output: String) {
        try run(repo, script: "scripts/release.sh", args: [], env: [
            "GENERATE_APPCAST": tools.appendingPathComponent("generate_appcast").path,
            "SIGN_UPDATE": tools.appendingPathComponent("sign_update").path,
            "SPARKLE_ED_KEY_FILE": keyFile.path,
        ])
    }

    private func run(_ repo: URL, _ phase: String, env: [String: String] = [:]) throws -> (status: Int32, output: String) {
        try run(repo, script: "scripts/b09_release_check.sh", args: [phase], env: env)
    }

    private func run(_ repo: URL, script: String, args: [String], env: [String: String]) throws -> (status: Int32, output: String) {
        let home = try tempDir("home")
        var environment = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("XCTest") && !$0.key.hasPrefix("DYLD_") && !$0.key.hasPrefix("__XPC_DYLD_")
        }
        environment["HOME"] = home.path
        environment["CFFIXED_USER_HOME"] = home.path
        environment["LANG"] = "de_DE.UTF-8"
        for (key, value) in env { environment[key] = value }
        return try shell("/bin/bash", [repo.appendingPathComponent(script).path] + args, in: repo, environment: environment, check: false)
    }

    @discardableResult
    private func shell(_ tool: String, _ args: [String], in dir: URL, environment: [String: String]? = nil,
                       check: Bool = true) throws -> (status: Int32, output: String) {
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
        let output = String(decoding: data, as: UTF8.self)
        if check, process.terminationStatus != 0 {
            XCTFail("\(tool) \(args.joined(separator: " ")) → \(process.terminationStatus)\n\(output)")
        }
        return (process.terminationStatus, output)
    }
}
#endif
