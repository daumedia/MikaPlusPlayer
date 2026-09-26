import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B08 · AK-01 und AK-21 über die **echten Hauptfenster** der App (Szene `WindowGroup`, Menü „File › New Window"):
/// Playlist über das echte Import-Sheet (Reiter „URL", Mock-Adresse), Senderliste im echten Navigationsstapel, ⊞ mit der
/// Session, die `MikaPlusPlayerApp` in jedes Fenster reicht. Kein Ton: MPEG-TS ohne Tonspur, Engines sofort Lautstärke 0.
@MainActor
final class B08HauptfensterTests: B08UITestCase {

    private func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.title == "Playlists" && !B08App.multiviewWindows().contains($0) }
    }

    private func button(_ root: NSWindow, _ text: String, role: String = "AXButton") -> NSObject? {
        B08UI.elements(root) { B08UI.role($0) == role && B08UI.label($0).contains(text) }.first
    }

    private func textFields(_ sheet: NSWindow) -> [NSTextField] {
        func walk(_ v: NSView) -> [NSTextField] { ((v as? NSTextField).map { [$0] } ?? []) + v.subviews.flatMap(walk) }
        return walk(sheet.contentView!).filter(\.isEditable)
    }

    private func type(_ text: String, into field: NSTextField, in sheet: NSWindow) {
        sheet.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView else { return }
        editor.insertText(text, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
    }

    /// Importiert `list.m3u` des Mocks über das echte Sheet im Fenster `w` und öffnet die Senderliste.
    private func importAndOpen(_ w: NSWindow, name: String) async throws {
        let add = try XCTUnwrap(button(w, "Playlist importieren") ?? button(w, "Add"), "Import-Knopf")
        B08UI.click(add, in: w)
        _ = await B08QA.wait(4) { w.attachedSheet != nil }
        let sheet = try XCTUnwrap(w.attachedSheet, "Import-Sheet")
        await B08QA.spin(0.4)
        if let tab = button(sheet, "URL", role: "AXRadioButton") { B08UI.click(tab, in: sheet) }
        await B08QA.spin(0.5)
        let f = textFields(sheet)
        XCTAssertEqual(f.count, 2, "Name + URL")
        type(name, into: f[0], in: sheet)
        type(server.base + "/list.m3u", into: f[1], in: sheet)
        sheet.makeFirstResponder(nil)
        await B08QA.spin(0.4)
        let go = try XCTUnwrap(button(sheet, "Von URL importieren"), "Von URL importieren")
        B08UI.click(go, in: sheet)
        _ = await B08QA.wait(8) { w.attachedSheet == nil }
        await B08QA.spin(0.8)
    }

    private func openPlaylist(_ w: NSWindow, _ name: String) async {
        if let card = B08UI.elements(w).first(where: { B08UI.label($0).hasPrefix(name) && B08UI.role($0) == "AXButton" }) {
            B08UI.click(card, in: w)
        }
        _ = await B08QA.wait(4) { w.title == name }
        await B08QA.spin(0.8)
    }

    func testAK01_AK21_EchteHauptfensterTeilenEinMultiview() async throws {
        // Session der App aus dem echten Multiview-Fenster holen, dann das Fenster schließen (Fokus, leer)
        let (mv0, app) = try await resetAppSession()
        mv0.performClose(nil)
        await B08QA.spin(0.8)
        let w1 = try XCTUnwrap(mainWindow(), "echtes Hauptfenster „Playlists“")
        w1.setFrame(NSRect(x: 20, y: 80, width: 880, height: 820), display: true)   // alle fünf Karten sichtbar
        try await importAndOpen(w1, name: "QA Echt")
        await openPlaylist(w1, "QA Echt")
        B08QA.log("AK-01|echtes Hauptfenster|titel=\(w1.title)|karten=\(cards(w1).map(B08UI.label))")
        XCTAssertEqual(w1.title, "QA Echt", "Senderliste im echten Hauptfenster")
        XCTAssertEqual(cards(w1).count, 5)
        B08UI.shot(w1, "AK-01-echtes-hauptfenster-senderliste")
        await clickPlus(w1, "Echt 1", session: app)
        _ = await B08QA.wait(4) { !B08App.multiviewWindows().isEmpty }
        let mv = try XCTUnwrap(realWindow(), "⊞ im echten Hauptfenster öffnet das echte Fenster „Multiview“")
        B08QA.log("AK-01|echtes Hauptfenster|nach ⊞|slots=\(app.slots.map(\.channel.name))|titel=\(w1.title)|multiview=\(mv.title)")
        XCTAssertEqual(app.slots.map(\.channel.name), ["Echt 1"], "der Sender landet in der Session, die die App in das Fenster reicht")
        XCTAssertEqual(w1.title, "QA Echt", "kein Player")

        // AK-21: zweites Hauptfenster über „File › New Window“
        let before = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        let newItem = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items).first { $0.title == "New Window" || $0.title == "Neues Fenster" }
        let item = try XCTUnwrap(newItem, "Menü „New Window“")
        item.menu?.performActionForItem(at: item.menu!.index(of: item))
        _ = await B08QA.wait(4) { NSApp.windows.contains { $0.isVisible && !before.contains(ObjectIdentifier($0)) && $0.title == "Playlists" } }
        let w2 = try XCTUnwrap(NSApp.windows.first { $0.isVisible && !before.contains(ObjectIdentifier($0)) && $0.title == "Playlists" })
        w2.setFrame(NSRect(x: w1.frame.maxX + 20, y: w1.frame.minY, width: 880, height: 820), display: true)
        await openPlaylist(w2, "QA Echt")
        B08QA.log("AK-21|zweites Hauptfenster|titel=\(w2.title)|tooltips=\(cards(w2).map(B08UI.help))")
        for n in ["Echt 2", "Echt 3", "Echt 4"] { await clickPlus(w2, n, session: app) }
        await B08QA.spin(1)
        let t1 = Set(cards(w1).map(B08UI.help)), t2 = Set(cards(w2).map(B08UI.help))
        B08QA.log("AK-21|nach 3 × ⊞ im zweiten Fenster|slots=\(app.slots.map(\.channel.name))|tooltips erstes=\(t1) zweites=\(t2)")
        B08UI.shot(w1, "AK-21-erstes-hauptfenster-voll")
        B08UI.shot(w2, "AK-21-zweites-hauptfenster-voll")
        XCTAssertEqual(app.slots.count, 4, "beide Hauptfenster füllen dasselbe Multiview")
        XCTAssertEqual(t1, ["Multiview voll (max. 4)"], "⊞ im ersten Fenster abgeblendet")
        XCTAssertEqual(t2, ["Multiview voll (max. 4)"])
        // Schließen des Multiview-Fensters (Fokus-Layout) leert es für beide
        realWindow()?.standardWindowButton(.closeButton)?.performClick(nil)
        await B08QA.spin(1)
        let a1 = Set(cards(w1).map(B08UI.help)), a2 = Set(cards(w2).map(B08UI.help))
        B08QA.log("AK-21|nach Schließen|slots=\(app.slots.count)|tooltips erstes=\(a1) zweites=\(a2)")
        XCTAssertTrue(app.isEmpty)
        XCTAssertEqual(a1, ["Zu Multiview hinzufügen"]); XCTAssertEqual(a2, ["Zu Multiview hinzufügen"])
        w2.performClose(nil)
        await B08QA.spin(0.5)
    }
}
