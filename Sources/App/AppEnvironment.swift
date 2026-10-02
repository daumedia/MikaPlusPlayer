import Foundation

/// Laufzeitumgebung der App.
enum AppEnvironment {
    /// True, wenn die App als Test-Host von XCTest läuft (`xcodebuild test`, Xcode-Tests).
    ///
    /// Dann öffnet die App weder die echte Datenbank noch den echten Schlüsselbund-Dienst des
    /// Nutzers (B01 · BUG-04: „Der Test-Host benutzt dieselbe Datei wie die echte App") und startet Sparkle nicht
    /// (B09 · BF-49).
    static let isRunningTests: Bool = detectTests(environment: ProcessInfo.processInfo.environment,
                                                  xcTestLoaded: NSClassFromString("XCTestCase") != nil)

    /// Umgebungsmarke, die die Testaktion des Schemas `MikaPlusPlayer-macOS` setzt (`project.yml`, B09 · BF-119).
    static let testHostMarker = "MIKA_TEST_HOST"

    /// Bundle-ID der ausgelieferten App. Debug-Build und Test-Host des macOS-Targets tragen
    /// `lu.daumedia.MikaPlusPlayer.debug` (B09 · BF-119); iOS und Release tragen diese.
    static let releaseBundleID = "lu.daumedia.MikaPlusPlayer"

    /// Bundle-ID des laufenden Programms.
    static var bundleID: String { Bundle.main.bundleIdentifier ?? releaseBundleID }

    static func detectTests(environment env: [String: String], xcTestLoaded: Bool) -> Bool {
        if env[testHostMarker] == "1" { return true }
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestSessionIdentifier"] != nil
            || env["XCTestBundlePath"] != nil {
            return true
        }
        return xcTestLoaded
    }
}
