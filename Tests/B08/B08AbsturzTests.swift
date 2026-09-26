import XCTest
import SwiftUI
import AppKit
@testable import MikaPlusPlayer

/// B08 · AK-23 ⚠ / FB-01 — Absturz im Raster-Layout, nachgestellt am echten Fenster „Multiview" (Nutzerwege: roter Knopf,
/// X-Knopf per Mausklick).
///
/// **Opt-in**, weil ein Absturz den Test-Host beendet: Jeder Fall läuft nur, wenn `TEST_RUNNER_B08_ABSTURZ` seinen Namen
/// enthält (oder `alle`), und zwar einzeln je `xcodebuild`-Aufruf, z. B.
/// `TEST_RUNNER_B08_ABSTURZ=x-3auf2 xcodebuild test-without-building … -only-testing:MikaPlusPlayerTests/B08AbsturzTests`.
/// Solange FB-01 besteht, endet der Test-Host bei den Fällen mit „stürzt ab" mit `Fatal error: Index out of range`
/// (`MultiviewScreen.swift:79`); nach der Reparatur bestehen die Tests (Session leer bzw. erwartete Anzahl, kein Absturz).
/// Kein Ton: Die Kacheln zeigen auf `/hang/…` (der Mock antwortet nie, es fließen keine Mediendaten).
@MainActor
final class B08AbsturzTests: B08UITestCase {

    private func gate(_ fall: String) throws {
        let env = ProcessInfo.processInfo.environment["B08_ABSTURZ"] ?? ""
        guard env.split(separator: ",").contains(where: { $0 == fall || $0 == "alle" }) else {
            throw XCTSkip("Absturz-Nachstellung „\(fall)“ nur mit TEST_RUNNER_B08_ABSTURZ=\(fall) (beendet den Test-Host)")
        }
        B08QA.log("AK-23|FALL \(fall)|Build \(Bundle.main.bundleIdentifier ?? "-")|Konfiguration \(Self.configuration)")
    }

    static var configuration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    private func grid(_ n: Int) async throws -> (NSWindow, MultiviewSession) {
        let (w, s) = try await resetAppSession()
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
        for i in 1...n { add(s, channel("Absturz \(i)", "/hang/ak23-\(i).ts")) }
        s.layout = .grid
        await B08QA.spin(1.5)
        B08UI.shot(w, "AK-23-vorher-raster-\(n)")
        return (w, s)
    }

    /// Klick auf das X der letzten Kachel (unten rechts bzw. rechts).
    private func clickLastX(_ w: NSWindow) async {
        var p = NSPoint.zero
        do {
            let xs = closeButtons(w).map(B08UI.frame)
            if let last = xs.min(by: { ($0.minY, -$0.minX) < ($1.minY, -$1.minX) }) { p = NSPoint(x: last.midX, y: last.midY) }
        }
        B08QA.log("AK-23|Klick auf X bei \(p)")
        await humanClick(w, screen: p)
    }

    // Fälle mit Absturz laut Spec

    func testAK23_RasterMitVierFensterSchliessen() async throws {
        try gate("schliessen-raster-4")
        let (w, s) = try await grid(4)
        B08QA.log("AK-23|roter Knopf im Raster mit 4")
        w.standardWindowButton(.closeButton)?.performClick(nil)
        await B08QA.spin(2)
        XCTAssertTrue(s.isEmpty, "nach dem Schließen leer, kein Absturz")
    }

    func testAK23_RasterMitEinemFensterSchliessen() async throws {
        try gate("schliessen-raster-1")
        let (w, s) = try await grid(1)
        B08QA.log("AK-23|roter Knopf im Raster mit 1")
        w.standardWindowButton(.closeButton)?.performClick(nil)
        await B08QA.spin(2)
        XCTAssertTrue(s.isEmpty)
    }

    func testAK23_RasterXVonDreiAufZwei() async throws {
        try gate("x-3auf2")
        let (w, s) = try await grid(3)
        await clickLastX(w)
        await B08QA.spin(2)
        XCTAssertEqual(s.slots.count, 2)
    }

    func testAK23_RasterXVonEinsAufNull() async throws {
        try gate("x-1auf0")
        let (w, s) = try await grid(1)
        await clickLastX(w)
        await B08QA.spin(2)
        XCTAssertTrue(s.isEmpty)
    }

    // Gegenproben ohne Absturz laut Spec

    func testAK23_Gegenprobe_RasterXVonVierAufDrei() async throws {
        try gate("x-4auf3")
        let (w, s) = try await grid(4)
        await clickLastX(w)
        await B08QA.spin(2)
        XCTAssertEqual(s.slots.count, 3)
        B08QA.log("AK-23|4→3 ohne Absturz|slots=\(s.slots.count)")
    }

    func testAK23_Gegenprobe_RasterXVonZweiAufEins() async throws {
        try gate("x-2auf1")
        let (w, s) = try await grid(2)
        await clickLastX(w)
        await B08QA.spin(2)
        XCTAssertEqual(s.slots.count, 1)
        B08QA.log("AK-23|2→1 ohne Absturz|slots=\(s.slots.count)")
    }

    func testAK23_Gegenprobe_FokusMitVierFensterSchliessen() async throws {
        try gate("fokus-schliessen-4")
        let (w, s) = try await grid(4)
        s.layout = .focus
        await B08QA.spin(1)
        w.standardWindowButton(.closeButton)?.performClick(nil)
        await B08QA.spin(2)
        XCTAssertTrue(s.isEmpty)
        B08QA.log("AK-23|Fokus, 4, Schließen ohne Absturz|slots=\(s.slots.count)")
    }

    /// EC-15 · Beenden der App (wie ⌘Q) bei offenem Raster: der Prozess endet regulär (Rückgabewert 0, kein Absturzbericht).
    func testEC15_BeendenBeiOffenemRaster() async throws {
        try gate("beenden-raster")
        _ = try await grid(2)
        B08QA.log("EC-15|NSApp.terminate bei offenem Raster mit 2")
        NSApp.terminate(nil)
        await B08QA.spin(5)
        XCTFail("App hat sich nicht beendet")
    }
}
