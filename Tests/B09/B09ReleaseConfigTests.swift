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

    // MARK: - Durchlauf 2 (2026-10-02): Fehlerauftrag und Zielentwurf

    /// FB-05 / BUG-03 (BF-03) · Das Release des macOS-Targets wird mit Developer ID signiert; Debug und Test-Bundle
    /// bleiben ad hoc (Entwurf, Entscheidung 1 und 12).
    func testFB05_releaseSignedWithDeveloperID() throws {
        let yml = try read("project.yml")
        let release = Self.yamlBlock(["targets", "MikaPlusPlayer-macOS", "settings", "configs", "Release"], in: yml)
        XCTAssertEqual(release["CODE_SIGN_IDENTITY"], "Developer ID Application", "macOS-Release nicht mit Developer ID signiert")
        let base = Self.yamlBlock(["targets", "MikaPlusPlayer-macOS", "settings", "base"], in: yml)
        XCTAssertEqual(base["DEVELOPMENT_TEAM"], "CWJM4J4HFN")
        XCTAssertEqual(base["CODE_SIGN_STYLE"], "Manual")
    }

    /// FB-08 / BUG-08 (BF-08, AK-12) · Ab 1.2 verlangt die App einen signierten Feed. Ohne Prüfung vor dem Entpacken
    /// startet Sparkle dann nicht (SPUUpdater.m: SUInvalidUpdaterError), deshalb beide Schlüssel gemeinsam.
    func testFB08_signedFeedRequired() throws {
        let info = try plist("Sources/Resources/Info.plist")
        XCTAssertEqual(info["SURequireSignedFeed"] as? Bool, true, "SURequireSignedFeed fehlt")
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true, "Feed-Pflicht ohne Prüfung vor dem Entpacken: Updater startet nicht")
        XCTAssertNil(info["SUSignedFeedFailureExpirationInterval"], "Notweg-Frist bleibt Sparkles Vorgabe (OF-15)")
    }

    /// FB-04 / BUG-09 (BF-09) · Mit Developer ID tragen Sparkle und VLCKit dieselbe Team-ID wie die App;
    /// `disable-library-validation` entfällt.
    func testFB04_libraryValidationNotDisabled() throws {
        let entitlements = try plist("Sources/Resources/MikaPlusPlayer.entitlements")
        XCTAssertNil(entitlements["com.apple.security.cs.disable-library-validation"])
    }

    /// AK-01 / AK-02 (OF-01) · Die App deklariert sich als deutschsprachig: Entwicklungssprache `de` im Projekt,
    /// einzige Lokalisierung `de`, keine gemischten Lokalisierungen (sonst folgten Frameworks evtl. der Systemsprache).
    func testAK01_appDeclaresGermanOnly() throws {
        let options = Self.yamlBlock(["options"], in: try read("project.yml"))
        XCTAssertEqual(options["developmentLanguage"], "de", "Entwicklungssprache des Projekts nicht de")
        let info = try plist("Sources/Resources/Info.plist")
        XCTAssertEqual(info["CFBundleDevelopmentRegion"] as? String, "$(DEVELOPMENT_LANGUAGE)")
        XCTAssertEqual(info["CFBundleLocalizations"] as? [String], ["de"], "CFBundleLocalizations ist nicht [de]")
        XCTAssertNil(info["CFBundleAllowMixedLocalizations"])
    }

    /// BF-119 / OF-10 · Debug-Build und Test-Host tragen eine eigene Bundle-ID; Release und iOS bleiben unverändert.
    func testBF119_debugUsesOwnBundleID() throws {
        let yml = try read("project.yml")
        let debug = Self.yamlBlock(["targets", "MikaPlusPlayer-macOS", "settings", "configs", "Debug"], in: yml)
        XCTAssertEqual(debug["PRODUCT_BUNDLE_IDENTIFIER"], "lu.daumedia.MikaPlusPlayer.debug")
        let release = Self.yamlBlock(["targets", "MikaPlusPlayer-macOS", "settings", "configs", "Release"], in: yml)
        XCTAssertNil(release["PRODUCT_BUNDLE_IDENTIFIER"], "Release darf die Bundle-ID nicht ändern")
        let base = Self.yamlBlock(["targetTemplates", "AppBase", "settings", "base"], in: yml)
        XCTAssertEqual(base["PRODUCT_BUNDLE_IDENTIFIER"], "lu.daumedia.MikaPlusPlayer")
        let templateDebug = Self.yamlBlock(["targetTemplates", "AppBase", "settings", "configs", "Debug"], in: yml)
        XCTAssertNil(templateDebug["PRODUCT_BUNDLE_IDENTIFIER"], "Debug-ID gehört nicht ins gemeinsame Template (iOS)")
    }

    /// AK-03 / Entwurf Entscheidung 8 · Vorgabe der automatischen Prüfung je Konfiguration: Release an, Debug aus.
    /// Sparkle liest den Info.plist-Wert auch als Text („YES“/„NO“, SUHost.m `convertObjectToBoolNumber`).
    func testAK03_automaticChecksDefaultPerConfiguration() throws {
        let info = try plist("Sources/Resources/Info.plist")
        XCTAssertEqual(info["SUEnableAutomaticChecks"] as? String, "$(MIKA_SPARKLE_AUTOMATIC_CHECKS)")
        let yml = try read("project.yml")
        let base = Self.yamlBlock(["targetTemplates", "AppBase", "settings", "base"], in: yml)
        XCTAssertEqual(base["MIKA_SPARKLE_AUTOMATIC_CHECKS"], "YES")
        let debug = Self.yamlBlock(["targets", "MikaPlusPlayer-macOS", "settings", "configs", "Debug"], in: yml)
        XCTAssertEqual(debug["MIKA_SPARKLE_AUTOMATIC_CHECKS"], "NO")
        let release = Self.yamlBlock(["targets", "MikaPlusPlayer-macOS", "settings", "configs", "Release"], in: yml)
        XCTAssertNil(release["MIKA_SPARKLE_AUTOMATIC_CHECKS"], "Release erbt die Vorgabe „an“")
    }

    /// OF-06 · Das nächste Release heißt 1.2.
    func testOF06_marketingVersionIs12() throws {
        let base = Self.yamlBlock(["targetTemplates", "AppBase", "settings", "base"], in: try read("project.yml"))
        XCTAssertEqual(base["MARKETING_VERSION"], "1.2")
    }

    /// BF-119 · Die Testaktion ignoriert gespeicherten Fensterzustand und markiert den Test-Host.
    func testBF119_testActionIgnoresSavedStateAndMarksTestHost() throws {
        let yml = try read("project.yml")
        let args = Self.yamlBlock(["schemes", "MikaPlusPlayer-macOS", "test", "commandLineArguments"], in: yml)
        XCTAssertEqual(args["\"-ApplePersistenceIgnoreState YES\""], "true", "Startargument fehlt: \(args)")
        let env = Self.yamlBlock(["schemes", "MikaPlusPlayer-macOS", "test", "environmentVariables"], in: yml)
        XCTAssertEqual(env["MIKA_TEST_HOST"], "1")
    }

    /// BF-03 · Exportoptionen für „Developer ID“ liegen im Repository, ohne Geheimnisse.
    func testBF03_exportOptionsForDeveloperID() throws {
        let options = try plist("scripts/ExportOptions-DeveloperID.plist")
        XCTAssertEqual(options["method"] as? String, "developer-id")
        XCTAssertEqual(options["teamID"] as? String, "CWJM4J4HFN")
        XCTAssertEqual(options["signingStyle"] as? String, "manual")
        XCTAssertEqual(options["signingCertificate"] as? String, "Developer ID Application")
        XCTAssertEqual(options["destination"] as? String, "export")
    }

    /// AK-12 · Ein signierter Feed muss byte-genau ausgeliefert werden: keine Zeilenende-Umwandlung durch Git.
    func testAK12_appcastIsNotTransformedByGit() throws {
        let attributes = try read(".gitattributes")
        let line = attributes.components(separatedBy: "\n").first { $0.hasPrefix("appcast.xml ") }
        XCTAssertNotNil(line, "kein Eintrag für appcast.xml in .gitattributes")
        XCTAssertTrue(line?.contains("-text") == true || line?.contains("binary") == true, "appcast.xml nicht vor Zeilenende-Umwandlung geschützt: \(line ?? "-")")
    }
}
