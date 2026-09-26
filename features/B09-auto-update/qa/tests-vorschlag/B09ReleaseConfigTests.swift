import XCTest

/// B09 · Auto-Update — Konfigurations- und Feed-Guards (QA Durchlauf 1, 2026-09-15).
///
/// Reine Datei-Tests: sie lesen `Info.plist`, `MikaPlusPlayer.entitlements`,
/// `appcast.xml`, `dist/appcast.xml` und `project.yml` aus dem Repository und
/// sichern die Update-Kette gegen Regressionen ab (FB-01, FB-02, FB-03, FB-05,
/// FB-08, FB-10). Sie brauchen **kein** laufendes Sparkle, keinen Netzzugriff
/// und keinen Build — deshalb laufen sie sowohl im macOS-Testtarget als auch
/// standalone (`swift test`).
///
/// Tests mit `XCTExpectFailure` belegen einen **offenen Befund**: Sie sind rot,
/// solange der Befund besteht, und halten die Suite trotzdem grün. Wird der
/// Befund behoben, schlägt `XCTExpectFailure` (strict) fehl und erinnert daran,
/// die Markierung zu entfernen.
final class B09ReleaseConfigTests: XCTestCase {

    // MARK: - Repo-Wurzel finden (portabel: Env-Override oder Aufstieg zu project.yml)

    private func repoRoot() throws -> URL {
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
        let url = try repoRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Wert eines <key>…</key><string>WERT</string>-Paars aus einer plist lesen.
    private func plistString(_ key: String, in plist: String) -> String? {
        guard let keyRange = plist.range(of: "<key>\(key)</key>") else { return nil }
        let rest = plist[keyRange.upperBound...]
        guard let open = rest.range(of: "<string>"),
              let close = rest.range(of: "</string>", range: open.upperBound..<rest.endIndex)
        else { return nil }
        return String(rest[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Bestehende, korrekte Werte absichern (müssen grün bleiben)

    /// AK-05 · Der ausgelieferte Feed (`main`) zeigt auf den daumedia-Namensraum,
    /// nicht mehr auf den freien `Mukaarts`-Namensraum (FB-01).
    func testAK05_mainFeedURLUsesDaumediaNamespace() throws {
        let info = try read("Sources/Resources/Info.plist")
        let feed = try XCTUnwrap(plistString("SUFeedURL", in: info), "SUFeedURL fehlt in Info.plist")
        XCTAssertTrue(feed.contains("raw.githubusercontent.com"), "Feed liegt nicht auf raw.githubusercontent: \(feed)")
        XCTAssertTrue(feed.contains("/daumedia/"), "Feed nutzt nicht den daumedia-Namensraum: \(feed)")
        XCTAssertFalse(feed.lowercased().contains("mukaarts"), "Feed zeigt wieder auf den freien Mukaarts-Namensraum (FB-01): \(feed)")
    }

    /// SUPublicEDKey ist vorhanden und nicht leer (ohne ihn ist die einzige
    /// Integritätsprüfung der Kette weg — AK-09/AK-10).
    func testAK09_publicEdKeyPresent() throws {
        let info = try read("Sources/Resources/Info.plist")
        let key = try XCTUnwrap(plistString("SUPublicEDKey", in: info), "SUPublicEDKey fehlt in Info.plist")
        XCTAssertGreaterThanOrEqual(key.count, 40, "SUPublicEDKey wirkt zu kurz: \(key)")
    }

    /// AK-11/FB-10 · Der versionierte `appcast.xml` ist sauber: genau der
    /// 1.1-Eintrag, daumedia-URL, gültige Signatur, **kein** Mukaarts, **kein**
    /// nie veröffentlichter 1.0-Eintrag. Guard gegen FB-10 (release.sh-Overwrite).
    func testFB10_shippedAppcastIsClean() throws {
        let feed = try read("appcast.xml")
        XCTAssertTrue(feed.contains("sparkle:edSignature"), "Feed-Eintrag ohne EdDSA-Signatur")
        XCTAssertTrue(feed.contains("/daumedia/"), "Feed-Download-URL nicht auf daumedia")
        XCTAssertFalse(feed.lowercased().contains("mukaarts"), "appcast.xml enthält wieder Mukaarts-URLs (FB-10)")
        XCTAssertFalse(feed.contains("<sparkle:version>1</sparkle:version>"), "nie veröffentlichter 1.0-Eintrag zurück im Feed (FB-10)")
        XCTAssertTrue(feed.contains("<title>Mika+Player</title>"), "Kanaltitel nicht mehr „Mika+Player“ (FB-10 setzt ihn auf „MikaPlusPlayer“ zurück)")
    }

    // MARK: - Offene Befunde (XCTExpectFailure, bis behoben)

    /// FB-02 · Build-Nummer (`CURRENT_PROJECT_VERSION`) ist seit v1.1 nicht
    /// erhöht. Ein Release erreicht keine bestehende Installation, solange die
    /// Build-Nummer ≤ 2 bleibt (Sparkle vergleicht CFBundleVersion).
    func testFB02_buildNumberAdvancedPastReleasedBuild() throws {
        XCTExpectFailure("BUG-FB-02: CURRENT_PROJECT_VERSION seit v1.1 unverändert (2)")
        let yml = try read("project.yml")
        let build = firstInt(after: "CURRENT_PROJECT_VERSION", in: yml)
        XCTAssertGreaterThan(build ?? -1, 2, "Build-Nummer nicht über die veröffentlichte v1.1 (Build 2) hinaus erhöht")
    }

    /// FB-05 · Release ist ad-hoc signiert (`CODE_SIGN_IDENTITY: "-"`) statt mit
    /// Developer ID. Erstinstallation/Downloads sind nur durch TLS geschützt,
    /// Gatekeeper lehnt ab.
    func testFB05_releaseSignedWithDeveloperID() throws {
        XCTExpectFailure("BUG-FB-05: ad-hoc-Signatur statt Developer ID, keine Notarisierung")
        let yml = try read("project.yml")
        XCTAssertFalse(yml.contains(#"CODE_SIGN_IDENTITY: "-""#), "macOS-Target ist ad-hoc signiert (CODE_SIGN_IDENTITY \"-\")")
    }

    /// FB-03 · Hardened Runtime ist im Release aus; dadurch injiziert Xcode
    /// `get-task-allow=true`. Jeder Nutzerprozess kann sich anhängen und den
    /// Speicher (inkl. Xtream-Zugangsdaten) lesen.
    func testFB03_hardenedRuntimeEnabledInRelease() throws {
        XCTExpectFailure("BUG-FB-03: ENABLE_HARDENED_RUNTIME nicht gesetzt -> get-task-allow im Release")
        let yml = try read("project.yml")
        XCTAssertTrue(yml.contains("ENABLE_HARDENED_RUNTIME: YES"), "Hardened Runtime im macOS-Release nicht aktiviert")
    }

    /// FB-08 · Der Feed selbst ist unsigniert (`SURequireSignedFeed` fehlt).
    /// Feed-Inhalte hängen allein an TLS und am GitHub-Zugang.
    func testFB08_signedFeedRequired() throws {
        XCTExpectFailure("BUG-FB-08: SURequireSignedFeed nicht gesetzt")
        let info = try read("Sources/Resources/Info.plist")
        XCTAssertTrue(info.contains("<key>SURequireSignedFeed</key>"), "SURequireSignedFeed nicht in Info.plist gesetzt")
    }

    /// FB-10 · Die lokale, nicht versionierte `dist/appcast.xml` enthält den
    /// Altstand (1.0 + Mukaarts). `release.sh` würde sie über den sauberen Feed
    /// kopieren. Solange sie existiert und schmutzig ist: offener Befund.
    func testFB10_localDistAppcastNotStale() throws {
        let root = try repoRoot()
        let dist = root.appendingPathComponent("dist/appcast.xml")
        guard FileManager.default.fileExists(atPath: dist.path) else {
            return // keine dist/appcast.xml -> kein Altstand, nichts zu beanstanden
        }
        XCTExpectFailure("BUG-FB-10: dist/appcast.xml enthält 1.0-Eintrag + Mukaarts-URLs; release.sh überschreibt den Feed damit")
        let feed = try String(contentsOf: dist, encoding: .utf8)
        XCTAssertFalse(feed.lowercased().contains("mukaarts"), "dist/appcast.xml enthält Mukaarts-URLs")
        XCTAssertFalse(feed.contains("<sparkle:version>1</sparkle:version>"), "dist/appcast.xml enthält den nie veröffentlichten 1.0-Eintrag")
    }

    // MARK: - Hilfen

    /// erste ganze Zahl, die (in Anführungszeichen o. ä.) hinter einem Schlüssel steht
    private func firstInt(after key: String, in text: String) -> Int? {
        guard let r = text.range(of: key) else { return nil }
        let tail = text[r.upperBound...]
        var digits = ""
        var started = false
        for ch in tail {
            if ch.isNumber { digits.append(ch); started = true }
            else if started { break }
            else if ch == "\n" { break }
        }
        return Int(digits)
    }
}
