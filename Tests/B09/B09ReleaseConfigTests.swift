import XCTest

/// B09 · Auto-Update — Konfigurations- und Feed-Guards.
///
/// Übernommen aus dem QA-Vorschlag (Durchlauf 1, 2026-09-15), nach der Reparatur vom 2026-09-16 angepasst:
/// Behobene Befunde sind normale Tests, offene behalten `XCTExpectFailure` mit Grund.
///
/// Reine Datei-Tests: sie lesen `Info.plist`, `MikaPlusPlayer.entitlements`, `appcast.xml`, `project.yml`
/// und `scripts/release.sh` aus dem Repository. Kein laufendes Sparkle, kein Netzzugriff, kein Build.
/// Das tatsächlich gebaute Bundle prüft `scripts/b09_release_check.sh` (siehe `B09ReleaseSkriptTests`).
final class B09ReleaseConfigTests: XCTestCase {

    // MARK: - Repo-Wurzel finden (Env-Override oder Aufstieg zu project.yml)

    static func repoRoot() throws -> URL {
        if let env = ProcessInfo.processInfo.environment["B09_REPO_ROOT"] {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("project.yml").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("Repo-Wurzel (project.yml) nicht gefunden — B09_REPO_ROOT setzen.")
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: Self.repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func plist(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.repoRoot().appendingPathComponent(relativePath))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// Einträge unter einem Pfad aus Schlüsseln in `project.yml`, z. B. `["targets", "MikaPlusPlayer-macOS",
    /// "settings", "configs", "Release"]` → `["ENABLE_HARDENED_RUNTIME": "YES", …]`. Genügt für die flache
    /// Struktur dieser Datei (Einrückung mit Leerzeichen, `schlüssel: wert`).
    static func yamlBlock(_ path: [String], in text: String) -> [String: String] {
        var stack: [(indent: Int, key: String)] = []
        var result: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let colon = trimmed.firstIndex(of: ":") else { continue }
            let indent = line.prefix(while: { $0 == " " }).count
            while let last = stack.last, last.indent >= indent { stack.removeLast() }
            let key = String(trimmed[..<colon])
            var value = String(trimmed[trimmed.index(after: colon)...])
            if let comment = value.range(of: " #") { value = String(value[..<comment.lowerBound]) }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            if value.isEmpty {
                stack.append((indent, key))
            } else if stack.map(\.key) == path {
                result[key] = value
            }
        }
        return result
    }

    static func highestFeedVersion(_ feed: String) -> Int? {
        let regex = try! NSRegularExpression(pattern: "<sparkle:version>(\\d+)</sparkle:version>")
        let range = NSRange(feed.startIndex..., in: feed)
        return regex.matches(in: feed, range: range)
            .compactMap { Range($0.range(at: 1), in: feed).flatMap { Int(feed[$0]) } }
            .max()
    }

    // MARK: - Bestehende, korrekte Werte absichern

    /// AK-05 · Der ausgelieferte Feed (`main`) zeigt auf den daumedia-Namensraum (FB-01).
    func testAK05_mainFeedURLUsesDaumediaNamespace() throws {
        let feed = try XCTUnwrap(try plist("Sources/Resources/Info.plist")["SUFeedURL"] as? String, "SUFeedURL fehlt")
        XCTAssertEqual(feed, "https://raw.githubusercontent.com/daumedia/MikaPlusPlayer/main/appcast.xml")
        XCTAssertFalse(feed.lowercased().contains("mukaarts"), "Feed zeigt wieder auf den freien Mukaarts-Namensraum (FB-01)")
    }

    /// AK-09/AK-10 · SUPublicEDKey ist ein 32-Byte-Ed25519-Schlüssel (sonst fehlt die einzige Integritätsprüfung).
    func testAK09_publicEdKeyPresent() throws {
        let key = try XCTUnwrap(try plist("Sources/Resources/Info.plist")["SUPublicEDKey"] as? String, "SUPublicEDKey fehlt")
        XCTAssertEqual(Data(base64Encoded: key)?.count, 32, "SUPublicEDKey ist kein 32-Byte-Schlüssel: \(key)")
    }

    /// AK-11/FB-10 · Der versionierte `appcast.xml` ist sauber: daumedia-URL, Signatur, kein Mukaarts,
    /// kein nie veröffentlichter 1.0-Eintrag, Titel „Mika+Player“.
    func testFB10_shippedAppcastIsClean() throws {
        let feed = try read("appcast.xml")
        XCTAssertTrue(feed.contains("sparkle:edSignature"), "Feed-Eintrag ohne EdDSA-Signatur")
        XCTAssertTrue(feed.contains("/daumedia/"), "Feed-Download-URL nicht auf daumedia")
        XCTAssertFalse(feed.lowercased().contains("mukaarts"), "appcast.xml enthält wieder Mukaarts-URLs (FB-10)")
        XCTAssertFalse(feed.contains("<sparkle:version>1</sparkle:version>"), "nie veröffentlichter 1.0-Eintrag zurück im Feed (FB-10)")
        XCTAssertTrue(feed.contains("<title>Mika+Player</title>"), "Kanaltitel nicht mehr „Mika+Player“")
    }

    // MARK: - Behoben 2026-09-16

    /// FB-02 / BUG-04 · Die Build-Nummer liegt über der höchsten `sparkle:version` im Feed; nur dann bekommen
    /// bestehende Installationen das nächste Release angeboten (Sparkle vergleicht CFBundleVersion).
    func testFB02_buildNumberAdvancedPastReleasedBuild() throws {
        let yml = try read("project.yml")
        let base = Self.yamlBlock(["targetTemplates", "AppBase", "settings", "base"], in: yml)
        let build = try XCTUnwrap(base["CURRENT_PROJECT_VERSION"].flatMap(Int.init), "CURRENT_PROJECT_VERSION fehlt oder ist keine Zahl")
        let highest = try XCTUnwrap(Self.highestFeedVersion(try read("appcast.xml")))
        XCTAssertGreaterThan(build, highest, "Build-Nummer \(build) nicht über der veröffentlichten sparkle:version \(highest)")
    }

    /// FB-03 / BUG-02 · Release des macOS-Targets: Hardened Runtime an, keine eingebettete Debug-Berechtigung.
    /// (Am gebauten Bundle belegt im Build-Bericht: `codesign -dv` → `flags=0x10002(adhoc,runtime)`, Entitlements
    /// ohne `get-task-allow`.)
    func testFB03_hardenedRuntimeEnabledInRelease() throws {
        let yml = try read("project.yml")
        let release = Self.yamlBlock(["targets", "MikaPlusPlayer-macOS", "settings", "configs", "Release"], in: yml)
        XCTAssertEqual(release["ENABLE_HARDENED_RUNTIME"], "YES", "Hardened Runtime im macOS-Release nicht aktiviert")
        XCTAssertEqual(release["CODE_SIGN_INJECT_BASE_ENTITLEMENTS"], "NO", "Xcode bettet im Release get-task-allow ein")
        let entitlements = try plist("Sources/Resources/MikaPlusPlayer.entitlements")
        XCTAssertNil(entitlements["com.apple.security.get-task-allow"], "get-task-allow darf nicht in den Entitlements stehen")
    }

    /// FB-08 / BUG-08 (Teil) · Sparkle prüft die EdDSA-Signatur des Archivs vor dem Einhängen/Entpacken.
    func testFB08_updateVerifiedBeforeExtraction() throws {
        XCTAssertEqual(try plist("Sources/Resources/Info.plist")["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
    }

    /// FB-10 / BUG-10 · `release.sh` schreibt den Feed aus der versionierten `appcast.xml` fort, nicht aus `dist/`.
    /// Das Verhalten selbst prüft `B09ReleaseSkriptTests.testBUG10_ReleaseSchreibtVersioniertenFeedFort`.
    func testFB10_releaseScriptDoesNotUseDistAppcast() throws {
        let script = try read("scripts/release.sh")
        let code = script.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.joined(separator: "\n")
        XCTAssertFalse(code.contains("dist/appcast.xml"), "release.sh liest oder kopiert wieder dist/appcast.xml")
        XCTAssertTrue(code.contains(#"cp "$ROOT/appcast.xml" "$STAGE/appcast.xml""#), "release.sh geht nicht von der versionierten appcast.xml aus")
        XCTAssertTrue(code.contains("b09_release_check.sh"), "Gegenprüfungen nicht eingehängt (BUG-11)")
    }

    /// FB-12 / BUG-14 · Sparkle ist exakt gepinnt.
    func testFB12_sparklePinnedExactly() throws {
        let sparkle = Self.yamlBlock(["packages", "Sparkle"], in: try read("project.yml"))
        XCTAssertEqual(sparkle["exactVersion"], "2.9.3")
        XCTAssertNil(sparkle["from"], "Sparkle wieder mit Bereichsangabe statt exakter Version")
    }

    // MARK: - Offene Befunde (XCTExpectFailure, bis behoben)

    /// FB-05 / BUG-03 · Release ist ad-hoc signiert (`CODE_SIGN_IDENTITY: "-"`) statt mit Developer ID.
    /// Offen: braucht Apple-Developer-Team, Zertifikat und Notarisierung.
    func testFB05_releaseSignedWithDeveloperID() throws {
        XCTExpectFailure("BUG-03 offen: ad-hoc-Signatur statt Developer ID, keine Notarisierung (braucht Apple-Team)")
        let yml = try read("project.yml")
        XCTAssertFalse(yml.contains(#"CODE_SIGN_IDENTITY: "-""#), "macOS-Target ist ad-hoc signiert (CODE_SIGN_IDENTITY \"-\")")
    }

    /// FB-08 / BUG-08 (Teil) · Der Feed wird nicht als signiert verlangt. Offen: Mit `SURequireSignedFeed` verwirft
    /// Sparkle jeden unsignierten Feed, die veröffentlichte `appcast.xml` ist noch unsigniert (release.sh signiert ab
    /// dem nächsten Release).
    func testFB08_signedFeedRequired() throws {
        XCTExpectFailure("BUG-08 offen: SURequireSignedFeed erst nach einem veröffentlichten signierten Feed")
        XCTAssertEqual(try plist("Sources/Resources/Info.plist")["SURequireSignedFeed"] as? Bool, true)
    }

    /// FB-04 / BUG-09 · `disable-library-validation` ist bei ad-hoc-Signatur nötig: ohne bricht das Release mit
    /// Hardened Runtime beim Laden von VLCKit ab („different Team IDs“, Build-Bericht). Offen bis Developer ID.
    func testFB04_libraryValidationNotDisabled() throws {
        XCTExpectFailure("BUG-09 offen: ohne Team-ID lädt VLCKit unter Hardened Runtime nur mit disable-library-validation")
        let entitlements = try plist("Sources/Resources/MikaPlusPlayer.entitlements")
        XCTAssertNil(entitlements["com.apple.security.cs.disable-library-validation"])
    }
}
