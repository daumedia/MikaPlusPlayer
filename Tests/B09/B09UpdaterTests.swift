#if os(macOS)
import Foundation
import Observation
import XCTest
@testable import MikaPlusPlayer

/// Steht für `SPUUpdater`: `canCheckForUpdates` ist dort ebenfalls nur per KVO beobachtbar.
private final class KVOUpdaterAttrappe: NSObject, @unchecked Sendable {
    @objc dynamic var canCheckForUpdates = true
}

/// Das Muster vor der Reparatur: berechnete Durchreiche über `@ObservationIgnored`-Speicher.
@Observable
private final class AltesMuster {
    @ObservationIgnored let source: KVOUpdaterAttrappe
    init(source: KVOUpdaterAttrappe) { self.source = source }
    var canCheckForUpdates: Bool { source.canCheckForUpdates }
}

private final class Merker: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func erhoehen() { lock.lock(); value += 1; lock.unlock() }
    var anzahl: Int { lock.lock(); defer { lock.unlock() }; return value }
}

/// B09 · BUG-18 — der Menüeintrag „Nach Updates suchen …“ folgt Sparkles `canCheckForUpdates`.
///
/// SwiftUI registriert Abhängigkeiten über `withObservationTracking`; genau das prüfen die Tests. Es wird kein echter
/// Sparkle-Updater angelegt (keine Feed-Abfrage).
@MainActor
final class B09UpdaterTests: XCTestCase {

    /// Reproduktion: Das alte Muster meldet SwiftUI keine Änderung, obwohl sich der Wert ändert.
    func testBUG18_AltesMusterMeldeteKeineAenderung() {
        let attrappe = KVOUpdaterAttrappe()
        let alt = AltesMuster(source: attrappe)
        let merker = Merker()
        withObservationTracking { _ = alt.canCheckForUpdates } onChange: { merker.erhoehen() }
        attrappe.canCheckForUpdates = false
        XCTAssertFalse(alt.canCheckForUpdates, "Wert hat sich geändert …")
        XCTAssertEqual(merker.anzahl, 0, "… aber SwiftUI wurde nicht benachrichtigt (Befund BUG-18)")
    }

    func testBUG18_MenueZustandFolgtSparkle() {
        let attrappe = KVOUpdaterAttrappe()
        var pruefungen = 0
        let updater = SparkleUpdater(source: attrappe, canCheckForUpdates: \.canCheckForUpdates) { pruefungen += 1 }
        XCTAssertTrue(updater.canCheckForUpdates, "Anfangswert übernommen")

        // Sparkle beginnt eine Prüfung → Menüeintrag muss sich deaktivieren
        let beginn = Merker()
        withObservationTracking { _ = updater.canCheckForUpdates } onChange: { beginn.erhoehen() }
        attrappe.canCheckForUpdates = false
        XCTAssertEqual(beginn.anzahl, 1, "SwiftUI wird über den Beginn der Prüfung benachrichtigt")
        XCTAssertFalse(updater.canCheckForUpdates)

        // Prüfung beendet → wieder aktiv
        let ende = Merker()
        withObservationTracking { _ = updater.canCheckForUpdates } onChange: { ende.erhoehen() }
        attrappe.canCheckForUpdates = true
        XCTAssertEqual(ende.anzahl, 1, "SwiftUI wird über das Ende der Prüfung benachrichtigt")
        XCTAssertTrue(updater.canCheckForUpdates)

        updater.checkForUpdates()
        XCTAssertEqual(pruefungen, 1, "Menüaktion löst die Prüfung aus")
    }

    /// Ändert Sparkle den Wert außerhalb des Main-Threads, kommt er trotzdem (auf dem Main-Actor) an.
    func testBUG18_AenderungAusAnderemThreadKommtAn() async throws {
        let attrappe = KVOUpdaterAttrappe()
        let updater = SparkleUpdater(source: attrappe, canCheckForUpdates: \.canCheckForUpdates) {}
        let merker = Merker()
        withObservationTracking { _ = updater.canCheckForUpdates } onChange: { merker.erhoehen() }
        await Task.detached { attrappe.canCheckForUpdates = false }.value
        let frist = Date().addingTimeInterval(2)
        while updater.canCheckForUpdates, Date() < frist {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(updater.canCheckForUpdates)
        XCTAssertEqual(merker.anzahl, 1)
    }
}
#endif
