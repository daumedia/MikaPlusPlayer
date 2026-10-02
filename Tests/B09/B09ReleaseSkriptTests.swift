#if os(macOS)
import CryptoKit
import Foundation
import XCTest

/// B09 · BUG-02/04/10/11, Durchlauf 2 (BF-03, BF-08, BF-09, BF-47, BF-48, BF-50, BF-51) — die Gegenprüfungen
/// (`scripts/b09_release_check.sh`) und `scripts/release.sh`, ausgeführt in Attrappen-Repositories im Temp-Ordner.
///
/// Nichts davon berührt das echte Repository, den Schlüsselbund oder das Netz: Die Skripte werden kopiert, Build und
/// DMG sind Stubs, Notarisieren und Heften sind Attrappen (Prüfnähte `NOTARYTOOL`, `STAPLER`), es läuft der Probemodus
/// ohne Developer ID; signiert wird mit einem im Test erzeugten Wegwerf-Schlüssel (`--ed-key-file`). `HOME` zeigt auf
/// den Temp-Ordner (Git-Konfiguration, Cache von generate_appcast).
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
        let result = try run(repo, "vor-build", env: ["PROBEMODUS": "1"])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertFalse(result.output.contains("[BEFUND]"), result.output)
        XCTAssertTrue(result.output.contains("[  ok  ] SURequireSignedFeed gesetzt"), "BF-08: Feed-Pflicht gesetzt\n\(result.output)")
        XCTAssertTrue(result.output.contains("[ skip ] Probemodus: kein Notar-Profil verlangt"), result.output)
    }

    /// BF-03 · Außerhalb des Probemodus verlangt vor-build ein benanntes, gültiges Notar-Profil.
    func testBF03_VorBuildVerlangtNotarProfil() throws {
        let repo = try makeRepo(build: "3", marketing: "1.2")
        let ohne = try run(repo, "vor-build")
        XCTAssertEqual(ohne.status, 1, ohne.output)
        XCTAssertTrue(ohne.output.contains("[BEFUND] NOTARY_PROFILE nicht gesetzt"), ohne.output)

        let tools = try notaryAttrappen()
        let fehlt = try run(repo, "vor-build", env: ["NOTARY_PROFILE": "B09Attrappe", "NOTARYTOOL": tools.notarytool,
                                                     "B09_NOTAR_HISTORY": "fehlt"])
        XCTAssertEqual(fehlt.status, 1, fehlt.output)
        XCTAssertTrue(fehlt.output.contains("[BEFUND] Notar-Profil „B09Attrappe“ fehlt im Schlüsselbund oder ist ungültig"), fehlt.output)

        let da = try run(repo, "vor-build", env: ["NOTARY_PROFILE": "B09Attrappe", "NOTARYTOOL": tools.notarytool])
        XCTAssertEqual(da.status, 0, da.output)
        XCTAssertTrue(da.output.contains("[  ok  ] Notar-Profil „B09Attrappe“ vorhanden und gültig"), da.output)
        XCTAssertTrue(try String(contentsOf: tools.log, encoding: .utf8).contains("notarytool history --keychain-profile B09Attrappe"))
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
        let bad = try run(repo, "nach-build", env: probe(["APP": debugLike.path, "DMG": dmg.path]))
        XCTAssertEqual(bad.status, 1, bad.output)
        XCTAssertTrue(bad.output.contains("[BEFUND] get-task-allow im Bundle"), bad.output)
        XCTAssertTrue(bad.output.contains("[BEFUND] App: Hardened Runtime nicht aktiv"), bad.output)

        let release = try makeApp(build: "3", marketing: "1.2", runtime: true, getTaskAllow: false)
        let releaseDMG = try makeDMG(app: release, marketing: "1.2")
        let good = try run(repo, "nach-build", env: probe(["APP": release.path, "DMG": releaseDMG.path]))
        XCTAssertEqual(good.status, 0, good.output)
        XCTAssertTrue(good.output.contains("[  ok  ] kein get-task-allow"), good.output)
        XCTAssertTrue(good.output.contains("[  ok  ] App: Hardened Runtime"), good.output)
        XCTAssertTrue(good.output.contains("[  ok  ] App im DMG ist das geprüfte Bundle"), good.output)
        XCTAssertTrue(good.output.contains("[ offen] App: ad hoc signiert, keine Developer ID (BF-03) (Probemodus)"), good.output)

        // DMG mit einem anderen Bundle als dem geprüften
        let mismatch = try run(repo, "nach-build", env: probe(["APP": release.path, "DMG": dmg.path]))
        XCTAssertEqual(mismatch.status, 1, mismatch.output)
        XCTAssertTrue(mismatch.output.contains("[BEFUND] App im DMG weicht vom geprüften Bundle ab"), mismatch.output)
    }

    /// BF-03 / BF-09 · Außerhalb des Probemodus ist eine ad-hoc-Signatur ein Befund (Developer ID, Team, Zeitstempel),
    /// ebenso `disable-library-validation`.
    func testBF03_BF09_NachBuildStrengOhneProbemodus() throws {
        let repo = try makeRepo(build: "3", marketing: "1.2")
        let app = try makeApp(build: "3", marketing: "1.2", runtime: true, getTaskAllow: false, libraryValidationDisabled: true)
        let result = try run(repo, "nach-build", env: ["APP": app.path, "BUNDLE_ID": Self.attrappenID])
        XCTAssertEqual(result.status, 1, result.output)
        for finding in ["App: ad hoc signiert, keine Developer ID (BF-03)", "App: Team „<keins>“ statt CWJM4J4HFN",
                        "App: kein sicherer Zeitstempel", "disable-library-validation gesetzt (BF-09"] {
            XCTAssertTrue(result.output.contains("[BEFUND] \(finding)"), "\(finding)\n\(result.output)")
        }
        XCTAssertFalse(result.output.contains("[ offen]"), "ohne Probemodus nichts nur „offen“")
    }

    /// OF-01 / BF-08 / BF-119 · Das Bundle trägt Sprache `de`, die Feed-Pflicht und die Release-Bundle-ID.
    func testOF01_BF08_NachBuildPrueftSpracheFeedPflichtUndBundleID() throws {
        let repo = try makeRepo(build: "3", marketing: "1.2")
        let app = try makeApp(build: "3", marketing: "1.2", runtime: true, getTaskAllow: false, german: false, signedFeed: false)
        let result = try run(repo, "nach-build", env: ["APP": app.path, "PROBEMODUS": "1"])
        XCTAssertEqual(result.status, 1, result.output)
        for finding in ["Bundle-ID \(Self.attrappenID) ≠ lu.daumedia.MikaPlusPlayer", "SURequireSignedFeed fehlt im Bundle (BF-08)",
                        "CFBundleDevelopmentRegion „en“ statt de (OF-01)", "CFBundleLocalizations „“ statt [de] (OF-01)"] {
            XCTAssertTrue(result.output.contains("[BEFUND] \(finding)"), "\(finding)\n\(result.output)")
        }
    }

    /// BF-03 · nach-heften: ohne Developer ID, Ticket und Gatekeeper-Freigabe drei Befunde (im Probemodus „offen“).
    func testBF03_NachHeftenVerlangtSignaturTicketUndGatekeeper() throws {
        let repo = try makeRepo(build: "3", marketing: "1.2")
        let app = try makeApp(build: "3", marketing: "1.2", runtime: true, getTaskAllow: false)
        let dmg = try makeDMG(app: app, marketing: "1.2")
        let tools = try notaryAttrappen()
        let streng = try run(repo, "nach-heften", env: ["APP": app.path, "DMG": dmg.path, "STAPLER": tools.stapler,
                                                         "B09_STAPLER_VALIDATE": "fehlt", "BUNDLE_ID": Self.attrappenID])
        XCTAssertEqual(streng.status, 1, streng.output)
        for finding in ["DMG nicht mit Developer ID signiert", "kein gültiges Notarisierungs-Ticket am DMG (stapler validate)",
                        "Gatekeeper lehnt das DMG ab", "Gatekeeper lehnt die App ab"] {
            XCTAssertTrue(streng.output.contains("[BEFUND] \(finding)"), "\(finding)\n\(streng.output)")
        }
        XCTAssertTrue(streng.output.contains("[  ok  ] App im DMG ist das geprüfte Bundle"), streng.output)

        let probe = try run(repo, "nach-heften", env: probe(["APP": app.path, "DMG": dmg.path, "STAPLER": tools.stapler]))
        XCTAssertEqual(probe.status, 0, probe.output)
        XCTAssertTrue(probe.output.contains("[  ok  ] Notarisierungs-Ticket geheftet und gültig"), probe.output)
        XCTAssertTrue(probe.output.contains("[ offen] Gatekeeper lehnt das DMG ab (Probemodus)"), probe.output)
    }

    // MARK: - release.sh vollständig (Attrappen für Build und DMG, echtes generate_appcast/sign_update)

    func testBUG10_ReleaseSchreibtVersioniertenFeedFort() throws {
        let tools = try sparkleTools()
        let repo = try makeRepo(build: "3", marketing: "1.2", releaseStubs: true)
        let appcastBefore = try Data(contentsOf: repo.appendingPathComponent("appcast.xml"))
        let distBefore = try Data(contentsOf: repo.appendingPathComponent("dist/appcast.xml"))

        let result = try runRelease(repo, tools: tools, keyFile: keyFile)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("!! PROBEMODUS"), "Probemodus sichtbar")
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

    /// BF-03 / Entwurf *Release-Ablauf* · Reihenfolge: DMG signieren → Notarisieren (mit Profil, wartend, JSON) →
    /// Protokoll ablegen → Heften → prüfen → erst dann generate_appcast (mit `--maximum-versions 0`) und sign_update.
    func testBF03_ReleaseNotarisiertUndHeftetVorDemFeed() throws {
        let tools = try sparkleTools()
        let repo = try makeRepo(build: "3", marketing: "1.2", releaseStubs: true)
        let notar = try notaryAttrappen()
        let result = try runRelease(repo, tools: tools, keyFile: keyFile, notary: notar)
        XCTAssertEqual(result.status, 0, result.output)
        let calls = try String(contentsOf: notar.log, encoding: .utf8).components(separatedBy: "\n").filter { !$0.isEmpty }
        print("B09BAU2|BF-03|aufrufe|\(calls.map { $0.components(separatedBy: " ").prefix(2).joined(separator: " ") })")
        let order = ["notarytool submit", "notarytool log", "stapler staple", "stapler validate", "generate_appcast", "sign_update"]
        let positions = order.map { step in calls.firstIndex { $0.hasPrefix(step) } }
        XCTAssertFalse(positions.contains(nil), "alle Schritte aufgerufen: \(calls)")
        XCTAssertEqual(positions.compactMap { $0 }, positions.compactMap { $0 }.sorted(), "Reihenfolge: \(calls)")
        let dmgPath = repo.appendingPathComponent("dist/MikaPlusPlayer-v1.2.dmg").path
        XCTAssertTrue(calls.contains { $0 == "notarytool submit \(dmgPath) --keychain-profile B09Attrappe --wait --output-format json" }, "\(calls)")
        XCTAssertTrue(calls.contains { $0.hasPrefix("generate_appcast") && $0.contains("--maximum-versions 0") }, "BF-47: \(calls)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.appendingPathComponent("dist/notarisierung-v1.2.json").path), "Protokoll abgelegt")
        let dmgSignature = try shell("/usr/bin/codesign", ["-dv", dmgPath], in: repo, check: false).output
        XCTAssertTrue(dmgSignature.contains("Identifier=lu.daumedia.MikaPlusPlayer.dmg"), "DMG signiert mit eigenem Bezeichner\n\(dmgSignature)")
        XCTAssertTrue(result.output.contains("[  ok  ] Notarisierungs-Ticket geheftet und gültig"), result.output)
        XCTAssertTrue(result.output.contains("nach-merge"), "Folgeschritt nach dem Merge genannt")
        XCTAssertTrue(result.output.contains("Pflichtproben"), "Pflichtproben genannt")
    }

    /// BF-03 · Nimmt der Notardienst das DMG nicht an, bricht das Release ab: Protokoll liegt vor, kein Heften, Feed
    /// unverändert. Ausgewertet wird das Ergebnisfeld, nicht der Exit-Code (der hier 0 ist).
    func testBF03_ReleaseBrichtAbWennNotarisierungAbgelehnt() throws {
        let tools = try sparkleTools()
        let repo = try makeRepo(build: "3", marketing: "1.2", releaseStubs: true)
        let appcastBefore = try Data(contentsOf: repo.appendingPathComponent("appcast.xml"))
        let notar = try notaryAttrappen()
        let result = try runRelease(repo, tools: tools, keyFile: keyFile, notary: notar, extra: ["B09_NOTAR_STATUS": "Invalid"])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("FEHLER: Notarisierung nicht angenommen (Status „Invalid“, ID b09-attrappe-id)"), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.appendingPathComponent("dist/notarisierung-v1.2.json").path), "Protokoll trotzdem abgelegt")
        let calls = try String(contentsOf: notar.log, encoding: .utf8)
        XCTAssertFalse(calls.contains("stapler staple"), "nicht geheftet")
        XCTAssertFalse(calls.contains("generate_appcast"), "kein Feed-Eintrag")
        XCTAssertEqual(try Data(contentsOf: repo.appendingPathComponent("appcast.xml")), appcastBefore, "appcast.xml unverändert")
    }

    /// BF-51 / BUG-24 · Ohne generate_appcast meldet release.sh den Grund, statt stumm abzubrechen; nichts geändert.
    func testBF51_ReleaseMeldetFehlendesGenerateAppcast() throws {
        let repo = try makeRepo(build: "3", marketing: "1.2", releaseStubs: true)
        let appcastBefore = try Data(contentsOf: repo.appendingPathComponent("appcast.xml"))
        let notar = try notaryAttrappen()
        let result = try run(repo, script: "scripts/release.sh", args: [], env: releaseEnv(notary: notar))
        print("B09BAU2|BF-51|exit=\(result.status)|\(result.output.components(separatedBy: "\n").filter { $0.contains("FEHLER") })")
        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("FEHLER: generate_appcast nicht gefunden."), result.output)
        XCTAssertFalse(try String(contentsOf: notar.log, encoding: .utf8).contains("notarytool submit"), "vor der Notarisierung gemeldet")
        XCTAssertEqual(try Data(contentsOf: repo.appendingPathComponent("appcast.xml")), appcastBefore)
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

    // MARK: - nach-merge

    /// AK-12 / BF-01 · Nach dem Merge: Die ausgelieferte Datei an jeder Adresse muss byte-gleich mit der gemergten sein
    /// und eine gültige Signatur tragen. Hier zwei lokale Adressen statt GitHub (Prüfnaht `FEED_URLS`).
    func testAK12_NachMergeVergleichtAusgelieferteDateiUndSignatur() throws {
        let tools = try sparkleTools()
        let repo = try makeRepo(build: "3", marketing: "1.2")
        let appcast = repo.appendingPathComponent("appcast.xml")
        _ = try shell(tools.appendingPathComponent("sign_update").path, ["--ed-key-file", keyFile.path, appcast.path], in: repo)
        let served = try tempDir("ausgeliefert")
        let gleich = served.appendingPathComponent("gleich.xml")
        let crlf = served.appendingPathComponent("crlf.xml")
        try FileManager.default.copyItem(at: appcast, to: gleich)
        try Data(String(contentsOf: appcast, encoding: .utf8).replacingOccurrences(of: "\n", with: "\r\n").utf8).write(to: crlf)

        let good = try run(repo, "nach-merge", env: ["FEED_URLS": gleich.absoluteString, "NACH_MERGE_FRIST": "0"])
        XCTAssertEqual(good.status, 0, good.output)
        XCTAssertTrue(good.output.contains("[  ok  ] \(gleich.absoluteString) liefert die gemergte Datei"), good.output)
        XCTAssertTrue(good.output.contains("[  ok  ] \(gleich.absoluteString): Signatur gültig"), good.output)

        let bad = try run(repo, "nach-merge", env: ["FEED_URLS": "\(gleich.absoluteString) \(crlf.absoluteString)", "NACH_MERGE_FRIST": "0"])
        XCTAssertEqual(bad.status, 1, bad.output)
        XCTAssertTrue(bad.output.contains("[BEFUND] \(crlf.absoluteString) liefert nach 0s nicht die gemergte Datei"), bad.output)
    }

    // MARK: - Attrappen

    private static let attrappenID = "lu.daumedia.MikaPlusPlayer.b09attrappe"

    /// Probemodus mit der Bundle-ID der Attrappe.
    private func probe(_ env: [String: String]) -> [String: String] {
        env.merging(["PROBEMODUS": "1", "BUNDLE_ID": Self.attrappenID]) { _, new in new }
    }

    /// Attrappen für `notarytool` und `stapler`: protokollieren jeden Aufruf (eine Zeile, Argumente mit Leerzeichen
    /// verbunden) und antworten wie die Werkzeuge. Steuerung über Umgebung: `B09_NOTAR_STATUS` (Vorgabe „Accepted“),
    /// `B09_NOTAR_HISTORY=fehlt`, `B09_STAPLER_VALIDATE=fehlt`.
    private func notaryAttrappen() throws -> (notarytool: String, stapler: String, log: URL) {
        let dir = try tempDir("notar")
        let log = dir.appendingPathComponent("aufrufe.log")
        try Data().write(to: log)
        let notarytool = dir.appendingPathComponent("notarytool")
        try """
        #!/bin/bash
        echo "notarytool $*" >> "\(log.path)"
        case "$1" in
          history) [ "${B09_NOTAR_HISTORY:-}" = "fehlt" ] && { echo "Error: No Keychain password item found" >&2; exit 1; }; echo '{"history":[]}' ;;
          submit) echo '{"id":"b09-attrappe-id","status":"'"${B09_NOTAR_STATUS:-Accepted}"'","message":"Attrappe"}' ;;
          log) echo '{"status":"Attrappe","issues":null}' > "${@: -1}" ;;
        esac
        exit 0
        """.write(to: notarytool, atomically: true, encoding: .utf8)
        let stapler = dir.appendingPathComponent("stapler")
        try """
        #!/bin/bash
        echo "stapler $*" >> "\(log.path)"
        [ "$1" = "validate" ] && [ "${B09_STAPLER_VALIDATE:-}" = "fehlt" ] && exit 65
        exit 0
        """.write(to: stapler, atomically: true, encoding: .utf8)
        for tool in [notarytool, stapler] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        }
        return (notarytool.path, stapler.path, log)
    }

    /// Hülle um ein Sparkle-Werkzeug, die den Aufruf ins Attrappen-Protokoll schreibt (Reihenfolge-Prüfung).
    private func loggingWrapper(_ tool: URL, log: URL) throws -> String {
        let wrapper = try tempDir("huelle").appendingPathComponent(tool.lastPathComponent)
        try """
        #!/bin/bash
        echo "\(tool.lastPathComponent) $*" >> "\(log.path)"
        exec "\(tool.path)" "$@"
        """.write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        return wrapper.path
    }

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

    /// Minimal-Bundle: `/usr/bin/true` als Programm, ad hoc signiert (Probemodus; das echte Release trägt Developer ID).
    private func makeApp(build: String, marketing: String, runtime: Bool, getTaskAllow: Bool,
                         libraryValidationDisabled: Bool = false, german: Bool = true, signedFeed: Bool = true) throws -> URL {
        let base = try tempDir("app")
        let app = base.appendingPathComponent("MikaPlusPlayer.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appendingPathComponent("MikaPlusPlayer"))
        var info: [String: Any] = [
            "CFBundleExecutable": "MikaPlusPlayer",
            "CFBundleIdentifier": Self.attrappenID,
            "CFBundleName": "Mika+Player",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": marketing,
            "CFBundleVersion": build,
            "LSMinimumSystemVersion": "14.0",
            "SUFeedURL": "https://raw.githubusercontent.com/daumedia/MikaPlusPlayer/main/appcast.xml",
            "SUPublicEDKey": publicKeyBase64,
            "SUVerifyUpdateBeforeExtraction": true,
            "CFBundleDevelopmentRegion": german ? "de" : "en",
        ]
        if german { info["CFBundleLocalizations"] = ["de"] }
        if signedFeed { info["SURequireSignedFeed"] = true }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        var entitlements: [String: Any] = ["com.apple.security.app-sandbox": false]
        if libraryValidationDisabled { entitlements["com.apple.security.cs.disable-library-validation"] = true }
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

    /// release.sh im Probemodus mit Attrappen für Notarisieren und Heften; Sparkle-Werkzeuge echt (protokolliert).
    private func runRelease(_ repo: URL, tools: URL, keyFile: URL,
                            notary: (notarytool: String, stapler: String, log: URL)? = nil,
                            extra: [String: String] = [:]) throws -> (status: Int32, output: String) {
        let notary = try notary ?? notaryAttrappen()
        var env = releaseEnv(notary: notary)
        env["GENERATE_APPCAST"] = try loggingWrapper(tools.appendingPathComponent("generate_appcast"), log: notary.log)
        env["SIGN_UPDATE"] = try loggingWrapper(tools.appendingPathComponent("sign_update"), log: notary.log)
        env["SPARKLE_ED_KEY_FILE"] = keyFile.path
        return try run(repo, script: "scripts/release.sh", args: [], env: env.merging(extra) { _, new in new })
    }

    private func releaseEnv(notary: (notarytool: String, stapler: String, log: URL)) -> [String: String] {
        probe(["NOTARYTOOL": notary.notarytool, "STAPLER": notary.stapler, "NOTARY_PROFILE": "B09Attrappe"])
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
