import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B04 · Nacharbeit nach dem Review vom 2026-09-30 (Fund R-1; R-2 steht in `B04LeistungTests`).
/// Temp-Datenbanken, Streams auf den geschlossenen Port 9 (Player scheitert sofort, kein Ton), erfundene Daten.
@MainActor
final class B04NacharbeitTests: B04TestCase {

    private struct Messung {
        let taste: String
        let modus: String
        let zustand: String
        let flaeche: NSColor
        let schrift: NSColor
        let kontrast: Double
        /// Rot deutlich über Grün und Blau: gemessen wurde die Akzentfläche eines aktiven Fensters, nicht die graue Taste
        /// eines inaktiven.
        var flaecheIstAkzent: Bool { flaeche.redComponent - max(flaeche.greenComponent, flaeche.blueComponent) > 0.25 }
    }

    private func rgb(_ c: NSColor) -> String {
        String(format: "(%.0f, %.0f, %.0f)", c.redComponent * 255, c.greenComponent * 255, c.blueComponent * 255)
    }

    private func miss(_ w: NSWindow, _ element: NSObject, _ taste: String, _ modus: String, _ zustand: String) -> Messung {
        let screen = B04AX.frame(element)
        let r = NSRect(x: screen.minX - w.frame.minX, y: w.frame.maxY - screen.maxY, width: screen.width, height: screen.height)
        let (flaeche, schrift) = B04Shot.fillAndText(w, in: r)
        return Messung(taste: taste, modus: modus, zustand: zustand, flaeche: flaeche, schrift: schrift,
                       kontrast: B04Shot.contrast(flaeche, schrift))
    }

    // MARK: R-1 · Schrift auf den Akzent-Tasten

    /// R-1: Die hervorgehobenen Tasten in Akzentfarbe – „Playlist importieren“ und „+“ (Playlists), „Alle Sender zeigen“
    /// (Gruppe ohne Treffer), „Erneut versuchen“ (Player) – tragen die Schrift `playerOnAccent` wie der gewählte Chip
    /// (B04 · BUG-10). Gerendert in einem aktiven Fenster, hell und dunkel: mindestens 4,5 : 1 (vorher Weiß: 3,16 : 1 hell,
    /// 2,33 : 1 dunkel laut Review). `.active` (Hauptfenster, aber nicht key) zeichnet wie `.key` die Akzentfläche. In
    /// einem inaktiven Fenster zeichnet macOS die Tasten grau mit Systemschrift; auch dort mindestens 4,5 : 1
    /// (B05-Abschluss: fest gesetztes `playerOnAccent` ergab dort im Dunkelmodus 1,35 : 1).
    func testR1_AkzentTastenSchriftMindestensViereinhalbZuEins() throws {
        var messungen: [Messung] = []
        for (appearance, modus) in [(NSAppearance.Name.aqua, "hell"), (NSAppearance.Name.darkAqua, "dunkel")] {
            for (state, zustand) in [(ControlActiveState.key, "aktiv"), (ControlActiveState.active, "aktiv-nicht-key"),
                                     (ControlActiveState.inactive, "inaktiv")] {
                let suffix = state == .key ? modus : "\(modus)-\(zustand)"
                // Playlists ohne Inhalt: „Playlist importieren“ und „+“
                let (leer, _) = try fileContainer("r1-leer-\(suffix)")
                let w1 = window(leer, size: CGSize(width: 700, height: 520), appearance: appearance, controlState: state)
                B04QA.spin(0.8)
                let knoepfe1 = w1.elements.filter { B04AX.role($0) == "AXButton" }
                B04QA.log("R-1|\(modus)|\(zustand)|playlists|tasten=\(knoepfe1.map { "\(B04AX.label($0))@\(Int(B04AX.frame($0).width))x\(Int(B04AX.frame($0).height))" })")
                let importieren = try XCTUnwrap(knoepfe1.first { B04AX.label($0) == "Playlist importieren" }, "Playlist importieren")
                messungen.append(miss(w1.window, importieren, "Playlist importieren", modus, zustand))
                let plus = try XCTUnwrap(knoepfe1.first { ["Add", "Hinzufügen", "plus", "Plus"].contains(B04AX.label($0)) }, "Taste „+“")
                messungen.append(miss(w1.window, plus, "+", modus, zustand))
                w1.shot("BUILD-R1-playlists-\(suffix)")
                w1.close()

                // Senderliste, gewählte Gruppe ohne Treffer: „Alle Sender zeigen“
                let (c, _) = try fileContainer("r1-gruppe-\(suffix)")
                let ctx = c.mainContext
                let pl = try B04QA.seed(ctx, name: "QA R-1", items: [.init("N1", "News"), .init("S1", "Sport")])
                let w2 = window(c, size: CGSize(width: 700, height: 520), appearance: appearance, controlState: state)
                w2.open(pl, wait: 1.5)
                for ch in try ctx.fetch(FetchDescriptor<Channel>()) where ch.group == "News" { ch.group = "Kino" }
                try ctx.save()
                XCTAssertTrue(w2.pressChip("News", wait: 1.5))
                let alle = try XCTUnwrap(w2.element("Alle Sender zeigen", role: "AXButton"), "Alle Sender zeigen")
                messungen.append(miss(w2.window, alle, "Alle Sender zeigen", modus, zustand))
                w2.shot("BUILD-R1-alle-sender-zeigen-\(suffix)")
                w2.close()

                // Player mit gescheitertem Stream: „Erneut versuchen“
                let (pc, _) = try fileContainer("r1-player-\(suffix)")
                let ch = Channel(name: "QA R-1 Player", streamURL: URL(string: "\(B04QA.dead)/r1-\(suffix).m3u8")!)
                pc.mainContext.insert(ch)
                try pc.mainContext.save()
                let pw = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 640, height: 420),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                pw.isReleasedWhenClosed = false
                pw.appearance = NSAppearance(named: appearance)
                let hosting = NSHostingView(rootView: NavigationStack { PlayerView(channel: ch) }
                    .tint(.playerAccent)
                    .environment(\.controlActiveState, state)
                    .modelContainer(pc))
                pw.contentView = hosting
                pw.makeKeyAndOrderFront(nil)
                defer { pw.contentView = nil; pw.orderOut(nil); pw.close() }
                var erneut: NSObject?
                let bis = Date().addingTimeInterval(15)
                while erneut == nil && Date() < bis {
                    B04QA.spin(0.3)
                    _ = hosting.accessibilityHitTest(NSPoint(x: pw.frame.midX, y: pw.frame.midY))
                    erneut = B04AX.all(hosting).first { B04AX.role($0) == "AXButton" && B04AX.label($0) == "Erneut versuchen" }
                }
                let taste = try XCTUnwrap(erneut, "Fehleransicht des Players mit „Erneut versuchen“")
                B04QA.spin(0.5)
                messungen.append(miss(pw, taste, "Erneut versuchen", modus, zustand))
                B04Shot.window(pw, "BUILD-R1-erneut-versuchen-\(suffix)")
            }
        }

        let zeilen = messungen.map { "\($0.taste) \($0.modus) \($0.zustand): Fläche \(rgb($0.flaeche)), Schrift \(rgb($0.schrift)), \(String(format: "%.2f", $0.kontrast)) : 1" }
        for z in zeilen { B04QA.log("R-1|gerendert|\(z)") }
        B04QA.evidence("BUILD-R1-kontrast.txt", "Nacharbeit R-1 · hervorgehobene Tasten, gerendert im Fensterzustand key, active und inactive (WCAG AA 4,5 : 1):\n  "
                       + zeilen.joined(separator: "\n  "))
        XCTAssertEqual(messungen.count, 24, "vier Tasten × zwei Modi × drei Fensterzustände")
        for m in messungen {
            if m.zustand != "inaktiv" {
                XCTAssertTrue(m.flaecheIstAkzent, "\(m.taste) \(m.modus) \(m.zustand): Akzentfläche gemessen (\(rgb(m.flaeche)))")
            } else {
                XCTAssertFalse(m.flaecheIstAkzent, "\(m.taste) \(m.modus) inaktiv: graue Taste gemessen (\(rgb(m.flaeche)))")
            }
            let meldung = "\(m.taste) \(m.modus) \(m.zustand): \(String(format: "%.2f", m.kontrast)) : 1"
            if m.taste == "Erneut versuchen" && m.modus == "hell" && m.zustand == "inaktiv" {
                // Systemdarstellung schon vor R-1: halbtransparente graue Taste über dem dunklen Video, dunkle Systemschrift
                XCTExpectFailure("B04 spec.md OF-09 · „Erneut versuchen“ im inaktiven Fenster (hell) unter 4,5 : 1") {
                    XCTAssertGreaterThanOrEqual(m.kontrast, 4.5, meldung)
                }
            } else {
                XCTAssertGreaterThanOrEqual(m.kontrast, 4.5, meldung)
            }
        }
    }
}
