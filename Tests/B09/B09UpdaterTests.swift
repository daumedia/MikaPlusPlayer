#if os(macOS)
import Foundation
import Observation
import SwiftUI
import XCTest
@testable import MikaPlusPlayer

/// Steht für `SPUUpdater`: Die vier Werte, die das Update-Menü zeigt, sind dort nur per KVO beobachtbar.
/// Zählt Schreibvorgänge auf die beiden Einstellungen (Sparkle verlangt: nur auf Nutzeraktion setzen).
private final class KVOUpdaterAttrappe: NSObject, @unchecked Sendable {
    @objc dynamic var canCheckForUpdates = true
    @objc dynamic var automaticallyChecksForUpdates = true { didSet { schreibvorgaenge += 1 } }
    @objc dynamic var automaticallyDownloadsUpdates = false { didSet { schreibvorgaenge += 1 } }
    @objc dynamic var allowsAutomaticUpdates = true
    var schreibvorgaenge = 0
}

private extension SparkleUpdater.KeyPaths where Source == KVOUpdaterAttrappe {
    static let attrappe = SparkleUpdater.KeyPaths<KVOUpdaterAttrappe>(
        canCheckForUpdates: \.canCheckForUpdates,
        automaticallyChecksForUpdates: \.automaticallyChecksForUpdates,
        automaticallyDownloadsUpdates: \.automaticallyDownloadsUpdates,
        allowsAutomaticUpdates: \.allowsAutomaticUpdates)
}

/// Das Muster vor der Reparatur vom 2026-09-16: berechnete Durchreiche über `@ObservationIgnored`-Speicher.
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

/// B09 · BUG-18 / BF-18, AK-31 — das Update-Menü folgt Sparkles Zustand.
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
        let updater = SparkleUpdater(source: attrappe, keyPaths: .attrappe) { pruefungen += 1 }
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
        let updater = SparkleUpdater(source: attrappe, keyPaths: .attrappe) {}
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

    // MARK: - Durchlauf 2 (2026-10-02): vier gespiegelte Werte, Schreibwege, eigene Menü-Ansicht

    /// AK-31 / Entwurf Entscheidung 7 · Alle vier Werte werden gespiegelt und melden jede Änderung an SwiftUI —
    /// auch Änderungen, die nicht aus dem Menü kommen (z. B. Kontrollkästchen in Sparkles Update-Fenster).
    func testAK31_VierWerteWerdenGespiegelt() {
        let attrappe = KVOUpdaterAttrappe()
        attrappe.automaticallyDownloadsUpdates = true
        attrappe.schreibvorgaenge = 0
        let updater = SparkleUpdater(source: attrappe, keyPaths: .attrappe) {}
        XCTAssertEqual(updater.automaticallyChecksForUpdates, true, "Anfangswert automatisch prüfen")
        XCTAssertEqual(updater.automaticallyDownloadsUpdates, true, "Anfangswert automatisch installieren")
        XCTAssertEqual(updater.allowsAutomaticUpdates, true, "Anfangswert automatisch installieren erlaubt")

        let aenderungen: [(String, () -> Void, () -> Bool)] = [
            ("automatisch prüfen", { attrappe.automaticallyChecksForUpdates = false }, { updater.automaticallyChecksForUpdates == false }),
            ("automatisch installieren", { attrappe.automaticallyDownloadsUpdates = false }, { updater.automaticallyDownloadsUpdates == false }),
            ("erlaubt", { attrappe.allowsAutomaticUpdates = false }, { updater.allowsAutomaticUpdates == false }),
        ]
        for (name, aendern, gespiegelt) in aenderungen {
            let merker = Merker()
            withObservationTracking {
                _ = (updater.automaticallyChecksForUpdates, updater.automaticallyDownloadsUpdates, updater.allowsAutomaticUpdates)
            } onChange: { merker.erhoehen() }
            aendern()
            XCTAssertTrue(gespiegelt(), "\(name): Wert nicht gespiegelt")
            XCTAssertEqual(merker.anzahl, 1, "\(name): SwiftUI nicht benachrichtigt")
        }
    }

    /// Entwurf Entscheidung 7 · Der Dienst schreibt Sparkles Einstellungen nie von selbst (beim Anlegen), nur über die
    /// Schreibwege; der Spiegel folgt dann Sparkles gemeldetem Wert.
    func testAK31_SchreibenNurAufNutzeraktion() {
        let attrappe = KVOUpdaterAttrappe()
        let updater = SparkleUpdater(source: attrappe, keyPaths: .attrappe) {}
        XCTAssertEqual(attrappe.schreibvorgaenge, 0, "beim Anlegen nichts geschrieben")

        updater.setAutomaticallyChecksForUpdates(false)
        XCTAssertEqual(attrappe.automaticallyChecksForUpdates, false, "Sparkle-Einstellung gesetzt")
        XCTAssertEqual(updater.automaticallyChecksForUpdates, false, "Spiegel folgt")
        updater.setAutomaticallyDownloadsUpdates(true)
        XCTAssertEqual(attrappe.automaticallyDownloadsUpdates, true)
        XCTAssertEqual(updater.automaticallyDownloadsUpdates, true)
        XCTAssertEqual(attrappe.schreibvorgaenge, 2, "genau die zwei Nutzeraktionen")
    }

    /// BF-49 / Entwurf Entscheidung 8 · Ohne gestarteten Updater (Test-Host) sind alle drei Einträge inaktiv, und die
    /// Schreibwege schreiben nichts.
    func testBF49_OhneGestartetenUpdaterAllesInaktivUndNichtsGeschrieben() {
        let attrappe = KVOUpdaterAttrappe()
        attrappe.canCheckForUpdates = false
        let updater = SparkleUpdater(source: attrappe, keyPaths: .attrappe, isRunning: false) {}
        XCTAssertFalse(updater.isRunning)
        XCTAssertEqual(updater.menuState, UpdateMenuState(checkEnabled: false, automaticChecksOn: true, automaticChecksEnabled: false,
                                                          automaticDownloadsOn: false, automaticDownloadsEnabled: false))
        updater.setAutomaticallyChecksForUpdates(false)
        updater.setAutomaticallyDownloadsUpdates(true)
        XCTAssertEqual(attrappe.schreibvorgaenge, 0, "nichts geschrieben, solange Sparkle nicht läuft")
    }

    /// AK-31 / OF-12 (Entwurf) · Zustände des Menüs: „Updates automatisch installieren“ ist gesperrt, solange Sparkle
    /// automatisches Installieren nicht erlaubt (automatische Prüfung aus); „Nach Updates suchen …“ folgt Sparkle.
    func testAK31_MenueZustaende() {
        let attrappe = KVOUpdaterAttrappe()
        let updater = SparkleUpdater(source: attrappe, keyPaths: .attrappe) {}
        XCTAssertEqual(updater.menuState, UpdateMenuState(checkEnabled: true, automaticChecksOn: true, automaticChecksEnabled: true,
                                                          automaticDownloadsOn: false, automaticDownloadsEnabled: true), "Ruhezustand")
        attrappe.canCheckForUpdates = false
        XCTAssertFalse(updater.menuState.checkEnabled, "geplante Prüfung läuft")
        XCTAssertTrue(updater.menuState.automaticChecksEnabled, "Schalter bleiben bedienbar")
        attrappe.canCheckForUpdates = true
        attrappe.automaticallyChecksForUpdates = false
        attrappe.allowsAutomaticUpdates = false
        XCTAssertEqual(updater.menuState, UpdateMenuState(checkEnabled: true, automaticChecksOn: false, automaticChecksEnabled: true,
                                                          automaticDownloadsOn: false, automaticDownloadsEnabled: false),
                       "automatische Prüfung aus → Installieren gesperrt")
    }

    /// BF-18 / Entwurf Entscheidung 6 · Die Menü-Ansicht liest alle Werte in ihrem eigenen Rumpf; jede Änderung
    /// macht ihn ungültig (Grund für BUG-18: Der Rumpf der App wurde für das Menü nicht neu ausgewertet).
    func testBF18_MenueAnsichtBeobachtetAlleWerteImEigenenRumpf() {
        let attrappe = KVOUpdaterAttrappe()
        let updater = SparkleUpdater(source: attrappe, keyPaths: .attrappe) {}
        let aenderungen: [(String, () -> Void)] = [
            ("Prüfung möglich", { attrappe.canCheckForUpdates.toggle() }),
            ("automatisch prüfen", { attrappe.automaticallyChecksForUpdates.toggle() }),
            ("automatisch installieren", { attrappe.automaticallyDownloadsUpdates.toggle() }),
            ("erlaubt", { attrappe.allowsAutomaticUpdates.toggle() }),
        ]
        for (name, aendern) in aenderungen {
            let merker = Merker()
            withObservationTracking { _ = UpdateMenu(updater: updater).body } onChange: { merker.erhoehen() }
            aendern()
            XCTAssertEqual(merker.anzahl, 1, "\(name): Menü-Rumpf nicht neu ausgewertet")
        }
    }
}
#endif
