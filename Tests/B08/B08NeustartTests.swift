import XCTest
import SwiftUI
import AppKit
@testable import MikaPlusPlayer

/// B08 · AK-02 (Größe über den Neustart), AK-24 (nach dem Neustart leer, „Fokus"), EC-09 (Wiederherstellung).
///
/// Zwei Prozesse nacheinander, **opt-in**: `TEST_RUNNER_B08_NEUSTART=1`, danach `TEST_RUNNER_B08_NEUSTART=2`
/// (jeweils `-only-testing:MikaPlusPlayerTests/B08NeustartTests`). Phase 1 ändert Größe/Lage des echten Fensters,
/// stellt „Raster" ein und lässt das Fenster offen; Phase 2 (neuer Prozess = Neustart) prüft.
@MainActor
final class B08NeustartTests: B08UITestCase {
    private static let marker = FileManager.default.temporaryDirectory.appendingPathComponent("b08-qa-neustart.txt")
    private static let frame = NSRect(x: 200, y: 150, width: 960, height: 600)

    private func phase() throws -> String {
        guard let p = ProcessInfo.processInfo.environment["B08_NEUSTART"], ["1", "2"].contains(p) else {
            throw XCTSkip("Neustart-Prüfung nur mit TEST_RUNNER_B08_NEUSTART=1 bzw. 2 (zwei Prozesse nacheinander)")
        }
        return p
    }

    func testAK02_AK24_EC09_NeustartGroesseBleibtBelegungNicht() async throws {
        let p = try phase()
        if p == "1" {
            let (w, s) = try await resetAppSession()
            add(s, channel("Vor dem Neustart", "/hang/neustart.ts"))
            w.setFrame(Self.frame, display: true)
            await B08QA.spin(1)
            s.layout = .focus
            s.clear()
            s.layout = .grid        // leer im Raster: Schließen/Beenden stürzt so nicht ab
            try "phase1 \(Date()) frame=\(w.frame)".write(to: Self.marker, atomically: true, encoding: .utf8)
            B08QA.log("NEUSTART|Phase 1|fenster=\(w.frame)|layout=\(s.layout.rawValue)|fenster bleibt offen|autosave=\(UserDefaults.standard.string(forKey: "NSWindow Frame multiview") ?? "-")")
            appSession = nil          // tearDown soll Layout nicht zurücksetzen …
            keepMultiviewOpen = true  // … und das Fenster offen lassen (EC-09)
            return
        }
        let prev = (try? String(contentsOf: Self.marker, encoding: .utf8)) ?? "-"
        let restored = B08App.multiviewWindows()
        B08QA.log("NEUSTART|Phase 2|marker=\(prev)|beim Start sichtbare Multiview-Fenster=\(restored.count)|argumente=\(ProcessInfo.processInfo.arguments.dropFirst().joined(separator: " "))")
        XCTAssertTrue(B08App.openViaMenu())
        _ = await B08QA.wait(4) { !B08App.multiviewWindows().isEmpty }
        let w = try XCTUnwrap(realWindow())
        let s = try XCTUnwrap(B08App.session(in: w))
        appSession = s
        B08QA.log("NEUSTART|Phase 2|fenster=\(w.frame)|slots=\(s.slots.count)|layout=\(s.layout.rawValue)|fokus=\(s.focusedIndex)")
        XCTAssertEqual(w.frame, Self.frame, "AK-02: Größe und Lage über den Neustart gemerkt")
        XCTAssertTrue(s.isEmpty, "AK-24: leer nach dem Neustart")
        XCTAssertEqual(s.layout, .focus, "AK-24: „Fokus“ nach dem Neustart")
        try? FileManager.default.removeItem(at: Self.marker)
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
    }
}
