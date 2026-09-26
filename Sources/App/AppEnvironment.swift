import Foundation

/// Laufzeitumgebung der App.
enum AppEnvironment {
    /// True, wenn die App als Test-Host von XCTest läuft (`xcodebuild test`, Xcode-Tests).
    ///
    /// Dann öffnet die App weder die echte Datenbank noch den echten Schlüsselbund-Dienst des
    /// Nutzers (B01 · BUG-04: „Der Test-Host benutzt dieselbe Datei wie die echte App").
    static let isRunningTests: Bool = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestSessionIdentifier"] != nil
            || env["XCTestBundlePath"] != nil {
            return true
        }
        return NSClassFromString("XCTestCase") != nil
    }()
}
