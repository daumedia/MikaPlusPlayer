import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// Hilfen, um SwiftUI-Ansichten im Test-Host in einem echten Fenster zu bedienen (AppKit-Accessibility).
@MainActor
enum UIHarness {
    static func window<V: View>(_ view: V, size: CGSize = CGSize(width: 900, height: 700)) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: 80, y: 80), size: size),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.makeKeyAndOrderFront(nil)
        return w
    }

    static func spin(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    static func children(_ e: NSObject) -> [NSObject] {
        (e.accessibilityAttributeValue(.children) as? [Any] ?? []).compactMap { $0 as? NSObject }
    }

    static func str(_ e: NSObject, _ a: NSAccessibility.Attribute) -> String {
        let v = e.accessibilityAttributeValue(a)
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    static func all(_ root: NSObject, depth: Int = 0, into list: inout [(Int, NSObject)]) {
        guard depth < 40 else { return }
        list.append((depth, root))
        for c in children(root) { all(c, depth: depth + 1, into: &list) }
    }

    static func views(_ v: NSView, depth: Int = 0, into list: inout [(Int, NSView)]) {
        list.append((depth, v))
        for s in v.subviews { views(s, depth: depth + 1, into: &list) }
    }

    static func dumpViews(_ root: NSView, _ tag: String) {
        var list: [(Int, NSView)] = []
        views(root, into: &list)
        for (d, v) in list {
            var info = ""
            if let b = v as? NSButton { info = "button title=\(b.title) enabled=\(b.isEnabled)" }
            else if let t = v as? NSTextField { info = "textfield value=\(t.stringValue) placeholder=\(t.placeholderString ?? "") editable=\(t.isEditable) secure=\(v is NSSecureTextField)" }
            else if let s = v as? NSSegmentedControl { info = "segmented selected=\(s.selectedSegment) labels=\((0..<s.segmentCount).map { s.label(forSegment: $0) ?? "" }) enabled=\(s.isEnabled)" }
            else if let c = v as? NSControl { info = "control enabled=\(c.isEnabled)" }
            print("B01UI|\(tag)|\(String(repeating: "  ", count: d))\(type(of: v)) \(info)")
        }
    }

    static func dump(_ root: NSObject, _ tag: String) {
        var list: [(Int, NSObject)] = []
        all(root, into: &list)
        for (d, e) in list {
            let role = str(e, .role)
            let label = [str(e, .title), str(e, .description), str(e, .value), str(e, .placeholderValue)]
                .filter { !$0.isEmpty }.joined(separator: " | ")
            let enabled = (e.accessibilityAttributeValue(.enabled) as? NSNumber)?.boolValue
            print("B01UI|\(tag)|\(String(repeating: "  ", count: d))\(role) [\(type(of: e))] \(label) enabled=\(enabled.map { $0 ? "true" : "false" } ?? "-")")
        }
    }
}


@MainActor
enum AX {
    static func obj(_ e: NSObject, _ name: String) -> Any? {
        let sel = NSSelectorFromString(name)
        guard e.responds(to: sel) else { return nil }
        return e.perform(sel)?.takeUnretainedValue()
    }
    static func bool(_ e: NSObject, _ name: String) -> Bool? {
        let sel = NSSelectorFromString(name)
        guard e.responds(to: sel), let imp = e.method(for: sel) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(imp, to: F.self)(e, sel)
    }
    static func frame(_ e: NSObject) -> NSRect {
        let sel = NSSelectorFromString("accessibilityFrame")
        guard e.responds(to: sel), let imp = e.method(for: sel) else { return .zero }
        typealias F = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(imp, to: F.self)(e, sel)
    }
    static func text(_ e: NSObject, _ name: String) -> String {
        let v = obj(e, name)
        if let s = v as? String { return s }
        if let a = v as? NSAttributedString { return a.string }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }
    static func role(_ e: NSObject) -> String { text(e, "accessibilityRole") }
    static func label(_ e: NSObject) -> String {
        [text(e, "accessibilityLabel"), text(e, "accessibilityTitle"), text(e, "accessibilityValue"), text(e, "accessibilityPlaceholderValue")]
            .filter { !$0.isEmpty }.joined(separator: " | ")
    }
    static func kids(_ e: NSObject) -> [NSObject] { (obj(e, "accessibilityChildren") as? [Any] ?? []).compactMap { $0 as? NSObject } }
    static func flatten(_ root: NSObject, depth: Int = 0, into list: inout [(Int, NSObject)]) {
        guard depth < 50 else { return }
        list.append((depth, root))
        for k in kids(root) { flatten(k, depth: depth + 1, into: &list) }
    }
    static func all(_ root: NSObject) -> [NSObject] { var l: [(Int, NSObject)] = []; flatten(root, into: &l); return l.map(\.1) }
    static func wake(_ window: NSWindow) {
        if let v = window.contentView { _ = v.accessibilityHitTest(NSPoint(x: window.frame.midX, y: window.frame.midY)) }
    }
    static func dump(_ root: NSObject, _ tag: String) {
        var l: [(Int, NSObject)] = []; flatten(root, into: &l)
        for (d, e) in l {
            print("B01AX|\(tag)|\(String(repeating: "  ", count: d))\(role(e)) \(label(e)) enabled=\(bool(e, "isAccessibilityEnabled").map { $0 ? "1" : "0" } ?? "-") [\(type(of: e))]")
        }
    }
    static func find(_ root: NSObject, role r: String? = nil, contains t: String) -> NSObject? {
        all(root).first { (r == nil || role($0) == r) && label($0).contains(t) }
    }
    @discardableResult static func press(_ e: NSObject) -> Bool { bool(e, "accessibilityPerformPress") ?? false }

    /// Klick per synthetischem Maus-Ereignis auf die Bildschirm-Mitte eines AX-Elements
    static func click(_ e: NSObject, in window: NSWindow, twice: Bool = false) {
        let f = frame(e)
        let pWin = window.convertPoint(fromScreen: NSPoint(x: f.midX, y: f.midY))
        for _ in 0..<(twice ? 2 : 1) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let ev = NSEvent.mouseEvent(with: type, location: pWin, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                window.sendEvent(ev)
            }
        }
    }
}

/// B01 · Xtream-Codes-Login — Oberfläche des Import-Sheets, bedient in einem echten Fenster des macOS-Test-Hosts
/// (synthetische Mausklicks, Texteingabe über den Feld-Editor, Zustand über AppKit-Accessibility). QA 2026-09-15.
/// Kein Ton: keine Tastaturereignisse, keine Wiedergabe.
final class B01OberflaecheTests: B01MockTestCase {

    private var window: NSWindow?
    private var container: ModelContainer?

    override func tearDown() {
        MainActor.assumeIsolated {
            window?.attachedSheet?.attachedSheet?.close()
            for win in NSApp.windows where win.isVisible && (String(describing: Swift.type(of: win)).contains("SheetPresentationWindow") || String(describing: Swift.type(of: win)).contains("AlertPanel")) {
                win.close()
            }
            window?.close()
            window = nil
            container = nil
        }
        super.tearDown()
    }

    // MARK: - Hilfen

    @MainActor private func openPlaylists() async throws -> NSWindow {
        let c = try B01.inMemoryContainer()
        container = c
        let w = UIHarness.window(NavigationStack { PlaylistsView() }.modelContainer(c))
        window = w
        await UIHarness.spin(0.8)
        AX.wake(w)
        await UIHarness.spin(0.2)
        return w
    }

    @MainActor private func openSheet(_ w: NSWindow, via label: String = "Playlist importieren") async throws -> NSWindow {
        AX.wake(w)
        let btn = try XCTUnwrap(AX.find(w, role: "AXButton", contains: label), "Button \(label)")
        AX.click(btn, in: w)
        let sheet = try await waitFor("Sheet") { w.attachedSheet }
        AX.wake(sheet)
        await UIHarness.spin(0.2)
        return sheet
    }

    @MainActor private func waitFor<T>(_ what: String, timeout: TimeInterval = 5, _ probe: () -> T?) async throws -> T {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let v = probe() { return v }
            await UIHarness.spin(0.05)
        }
        throw NSError(domain: "B01UI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Zeitüberschreitung: \(what)"])
    }

    @MainActor private func fields(_ sheet: NSWindow) -> [NSTextField] {
        var list: [(Int, NSView)] = []
        UIHarness.views(sheet.contentView!, into: &list)
        return list.map(\.1).compactMap { $0 as? NSTextField }
    }

    /// Tippt `text` über den Feld-Editor (ersetzt den bisherigen Inhalt, löst die SwiftUI-Bindung aus).
    @MainActor private func type(_ text: String, into field: NSTextField, in sheet: NSWindow) {
        sheet.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView else { return }
        let all = NSRange(location: 0, length: (editor.string as NSString).length)
        editor.insertText(text, replacementRange: all)
    }

    @MainActor private func fill(_ sheet: NSWindow, host: String, user: String, pass: String, name: String = "") async {
        let f = fields(sheet)  // Reihenfolge: Name, Host, Benutzer, Passwort
        type(name, into: f[0], in: sheet)
        type(host, into: f[1], in: sheet)
        type(user, into: f[2], in: sheet)
        type(pass, into: f[3], in: sheet)
        sheet.makeFirstResponder(nil)
        await UIHarness.spin(0.3)
        AX.wake(sheet)
    }

    @MainActor private func enabled(_ root: NSObject, button label: String) -> Bool? {
        AX.find(root, role: "AXButton", contains: label).flatMap { AX.bool($0, "isAccessibilityEnabled") }
    }

    @MainActor private func hasText(_ root: NSObject, _ text: String) -> Bool {
        AX.all(root).contains { AX.label($0).contains(text) }
    }

    /// Nur für NSHostingView-Fenster verlässlich; Sheets und Alerts rendert `cacheDisplay` unvollständig.
    @MainActor private func snapshot(_ w: NSWindow, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["B01_QA_SCREENSHOTS"], let v = w.contentView,
              let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }

    @MainActor private func playlistCount() throws -> Int {
        try container!.mainContext.fetchCount(FetchDescriptor<Playlist>())
    }

    // MARK: - Tests

    /// AK-01: „Playlist importieren" bzw. „+" öffnet das Sheet; Reiter Xtream vorausgewählt; Felder, Format, Button; macOS ≥ 420 × 360.
    @MainActor func testAK01_SheetFelderUndMindestgroesse() async throws {
        let w = try await openPlaylists()
        let sheet = try await openSheet(w)
        XCTAssertTrue(hasText(sheet, "Playlist importieren"))
        XCTAssertEqual(AX.find(sheet, role: "AXRadioButton", contains: "Xtream").map(AX.label), "Xtream | 1", "Reiter Xtream gewählt")
        for t in ["Name (optional)", "Host (z. B. http://dein-anbieter.tld)", "Benutzername", "Passwort", "Stream-Format"] {
            XCTAssertTrue(hasText(sheet, t), t)
        }
        XCTAssertNotNil(AX.find(sheet, role: "AXButton", contains: "Anmelden & importieren"))
        let f = fields(sheet)
        XCTAssertEqual(f.count, 4)
        XCTAssertTrue(f.last is NSSecureTextField, "Passwort verdeckt")
        let size = try XCTUnwrap(sheet.contentView?.frame.size)
        XCTAssertGreaterThanOrEqual(size.width, 420)
        XCTAssertGreaterThanOrEqual(size.height, 360)
        print("B01QA|AK-01|sheetContent=\(size)")

        // Verdeckte Eingabe: Wert des Passwortfelds ist über Accessibility nicht lesbar
        await fill(sheet, host: mock.hostPort, user: "qa-user", pass: "qa-pass-ak01")
        let secureAX = AX.all(sheet).first { AX.role($0) == "AXTextField" && String(describing: Swift.type(of: $0)).contains("Secure") }
        let secureValue = secureAX.map { AX.text($0, "accessibilityValue") } ?? "-"
        print("B01QA|AK-01|passwortfeldAXWert=\(secureValue.unicodeScalars.map { String(format: "U+%04X", $0.value) })")
        XCTAssertFalse(secureValue.contains("qa-pass-ak01"), "Passwort nicht im Klartext lesbar")
        XCTAssertTrue(fields(sheet).last?.stringValue == "qa-pass-ak01", "Eingabe ist angekommen")

        // Abbrechen und über „+" (AX-Label „Add") erneut öffnen
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Abbrechen")), in: sheet)
        _ = try await waitFor("Sheet zu") { w.attachedSheet == nil ? true : nil }
        let again = try await openSheet(w, via: "Add")
        XCTAssertEqual(AX.find(again, role: "AXRadioButton", contains: "Xtream").map(AX.label), "Xtream | 1")
    }

    /// AK-02: Standardformat MPEG-TS mit Hinweis; Umschalten auf HLS ändert den Hinweis.
    @MainActor func testAK02_FormatStandardUndHinweis() async throws {
        let w = try await openPlaylists()
        let sheet = try await openSheet(w)
        XCTAssertEqual(AX.find(sheet, role: "AXRadioButton", contains: "MPEG-TS").map(AX.label), "MPEG-TS (.ts) | 1")
        XCTAssertTrue(hasText(sheet, "Originalformat des Anbieters – benötigt VLCKit."))
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXRadioButton", contains: "HLS (.m3u8)")), in: sheet)
        await UIHarness.spin(0.4)
        AX.wake(sheet)
        XCTAssertEqual(AX.find(sheet, role: "AXRadioButton", contains: "HLS").map(AX.label), "HLS (.m3u8) | 1")
        XCTAssertTrue(hasText(sheet, "Spielt direkt mit AVKit – kein VLCKit nötig."))
        XCTAssertFalse(hasText(sheet, "Originalformat des Anbieters"))
    }

    /// AK-03: Button nur aktiv, wenn Host, Benutzer und Passwort je ein Nicht-Leerzeichen enthalten.
    @MainActor func testAK03_ButtonNurMitAllenDreiFeldern() async throws {
        let w = try await openPlaylists()
        let sheet = try await openSheet(w)
        let label = "Anmelden & importieren"
        XCTAssertEqual(enabled(sheet, button: label), false, "frisch geöffnet")
        let cases: [(String, String, String, Bool)] = [
            (mock.hostPort, "", "", false),
            (mock.hostPort, "qa-user", "", false),
            ("", "qa-user", "qa-pass-ak03", false),
            (mock.hostPort, "qa-user", "   ", false),
            (mock.hostPort, "qa-user", "\t\t", false),
            ("  ", "qa-user", "qa-pass-ak03", false),
            (mock.hostPort, " \t ", "qa-pass-ak03", false),
            (mock.hostPort, "qa-user", "x", true),
            ("h", "u", "p", true)
        ]
        for (host, user, pass, expected) in cases {
            await fill(sheet, host: host, user: user, pass: pass)
            XCTAssertEqual(enabled(sheet, button: label), expected, "Host=\(host.debugDescription) User=\(user.debugDescription) Pass=\(pass.debugDescription)")
        }
        XCTAssertEqual(mock.requests.count, 0)
    }

    /// AK-04 (macOS-Teil): Host und Benutzername ohne automatische Rechtschreibkorrektur; Namensfeld zum Vergleich.
    @MainActor func testAK04_KeineAutokorrekturMacOS() async throws {
        let w = try await openPlaylists()
        let sheet = try await openSheet(w)
        let f = fields(sheet)
        var result: [Bool] = []
        for field in f.prefix(3) {
            sheet.makeFirstResponder(field)
            result.append((field.currentEditor() as? NSTextView)?.isAutomaticSpellingCorrectionEnabled ?? true)
        }
        print("B01QA|AK-04|autokorrektur Name=\(result[0]) Host=\(result[1]) Benutzer=\(result[2])")
        XCTAssertFalse(result[1], "Host")
        XCTAssertFalse(result[2], "Benutzername")
    }

    /// AK-05 + EC-21: Während des Imports „Importiere…" mit Fortschritt, Import-Buttons aller Reiter deaktiviert, „Abbrechen" aktiv.
    @MainActor func testAK05_EC21_ZustandWaehrendDesImports() async throws {
        let w = try await openPlaylists()
        let sheet = try await openSheet(w)
        // URL-Reiter vorbelegen, damit dessen Button nur wegen des Imports deaktiviert sein kann
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXRadioButton", contains: "URL")), in: sheet)
        await UIHarness.spin(0.3)
        if let urlField = fields(sheet).dropFirst().first { type("http://127.0.0.1:9/qa.m3u", into: urlField, in: sheet) }
        sheet.makeFirstResponder(nil)
        await UIHarness.spin(0.2)
        AX.wake(sheet)
        XCTAssertEqual(enabled(sheet, button: "Von URL importieren"), true, "vor dem Import")
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXRadioButton", contains: "Xtream")), in: sheet)
        await UIHarness.spin(0.3)

        await fill(sheet, host: mock.hostPort, user: "qa-user", pass: "qa-pass-ak05")
        mock.handler = { req in req.action == nil ? .delayed(3, .json(["user_info": ["auth": 0]], status: 200)) : .json([Any](), status: 200) }
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Anmelden & importieren")), in: sheet)
        _ = try await waitFor("Importiere…") { AX.wake(sheet); return self.hasText(sheet, "Importiere…") ? true : nil }
        XCTAssertTrue(AX.all(sheet).contains { AX.role($0) == "AXBusyIndicator" }, "Fortschrittsanzeige")
        XCTAssertEqual(enabled(sheet, button: "Anmelden & importieren"), false)
        XCTAssertEqual(enabled(sheet, button: "Abbrechen"), true)

        // EC-21: Reiterwechsel während des Imports
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXRadioButton", contains: "URL")), in: sheet)
        await UIHarness.spin(0.3); AX.wake(sheet)
        XCTAssertTrue(hasText(sheet, "Importiere…"), "EC-21 URL-Reiter")
        XCTAssertEqual(enabled(sheet, button: "Von URL importieren"), false, "EC-21 URL-Button")
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXRadioButton", contains: "Datei")), in: sheet)
        await UIHarness.spin(0.3); AX.wake(sheet)
        XCTAssertTrue(hasText(sheet, "Importiere…"), "EC-21 Datei-Reiter")
        XCTAssertEqual(enabled(sheet, button: "Datei auswählen"), false, "EC-21 Datei-Button")
        XCTAssertEqual(mock.requests.count, 1, "Import läuft weiter")
        // Ende abwarten, Alert schließen
        let alert = try await waitFor("Alert", timeout: 8) { sheet.attachedSheet }
        AX.press(try XCTUnwrap(AX.find(alert, role: "AXButton", contains: "OK")))
    }

    /// AK-06: Erfolg schließt das Sheet; neue Playlist an erster Stelle mit Globus und „N Sender".
    @MainActor func testAK06_ErfolgSchliesstSheetNeuePlaylistOben() async throws {
        let w = try await openPlaylists()
        for name in ["QA Erste", "QA Zweite"] {
            let sheet = try await openSheet(w, via: name == "QA Erste" ? "Playlist importieren" : "Add")
            await fill(sheet, host: mock.hostPort, user: "qa-user", pass: "qa-pass-ak06", name: name)
            AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Anmelden & importieren")), in: sheet)
            _ = try await waitFor("Sheet schließt", timeout: 8) { w.attachedSheet == nil ? true : nil }
            await UIHarness.spin(0.5)
            AX.wake(w)
        }
        snapshot(w, "AK-06-playlists.png")
        let texts = AX.all(w).map(AX.label)
        print("B01QA|AK-06|texte=\(texts.filter { !$0.isEmpty })")
        let first = try XCTUnwrap(texts.firstIndex { $0.contains("QA Zweite") })
        let second = try XCTUnwrap(texts.firstIndex { $0.contains("QA Erste") })
        XCTAssertLessThan(first, second, "neueste Playlist oben")
        XCTAssertEqual(texts.filter { $0.contains("\(MockXtreamServer.streams.count) Sender") }.count, 2)
        // Globus-Symbol ist Teil der zusammengefassten Zeile und nicht einzeln exponiert → Beleg: Screenshot AK-06-playlists.png
        XCTAssertEqual(try playlistCount(), 2)
    }

    /// AK-16 … AK-22 (gemeinsam): Alert „Fehler" mit „OK" im Sheet; danach Eingaben erhalten, Button sofort bedienbar; nichts angelegt.
    @MainActor func testAK16bis22_FehlerAlertEingabenBleibenButtonSofortAktiv() async throws {
        let w = try await openPlaylists()
        let sheet = try await openSheet(w)
        await fill(sheet, host: mock.hostPort, user: "qa-user", pass: "qa-pass-alert", name: "QA Alert")
        mock.handler = MockXtreamServer.panel(auth: ["user_info": ["auth": 0]])
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Anmelden & importieren")), in: sheet)
        let alert = try await waitFor("Alert", timeout: 8) { sheet.attachedSheet }
        XCTAssertTrue(hasText(alert, "Fehler"))
        XCTAssertTrue(hasText(alert, "Anmeldung fehlgeschlagen. Benutzername/Passwort prüfen."))
        AX.press(try XCTUnwrap(AX.find(alert, role: "AXButton", contains: "OK")))
        _ = try await waitFor("Alert zu") { sheet.attachedSheet == nil ? true : nil }
        AX.wake(sheet)
        let f = fields(sheet)
        XCTAssertEqual(f.map(\.stringValue), ["QA Alert", mock.hostPort, "qa-user", "qa-pass-alert"], "Eingaben bleiben")
        XCTAssertEqual(enabled(sheet, button: "Anmelden & importieren"), true, "sofort wieder bedienbar (FB-04)")
        XCTAssertEqual(try playlistCount(), 0)
        XCTAssertNotNil(w.attachedSheet, "Sheet bleibt offen")
    }

    /// EC-18 / BUG-11 behoben: „Abbrechen" während des Imports schließt das Sheet **und bricht den Import ab**.
    /// (a) Ein Panel, das danach erfolgreich antworten würde, erzeugt keine Playlist. (b) Ein späterer Fehler erscheint
    /// nirgends: kein verwaistes Sheet-Fenster, kein Alert.
    @MainActor func testEC18_AbbrechenBrichtImportAb() async throws {
        let w = try await openPlaylists()
        // a) Erfolg wäre nach dem Abbrechen gekommen
        var sheet = try await openSheet(w)
        await fill(sheet, host: mock.hostPort, user: "qa-user", pass: "qa-pass-ec18")
        let panel = MockXtreamServer.panel()
        mock.handler = { req in req.action == nil ? .delayed(2, panel(req)) : panel(req) }
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Anmelden & importieren")), in: sheet)
        await UIHarness.spin(0.4)
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Abbrechen")), in: sheet)
        _ = try await waitFor("Sheet zu") { w.attachedSheet == nil ? true : nil }
        XCTAssertEqual(try playlistCount(), 0, "direkt nach Abbrechen")
        await UIHarness.spin(4.0)
        print("B01BUILD|EC-18|nachAbbrechen playlists=\(try playlistCount()) anfragen=\(mock.requests.map { $0.action ?? "(ohne)" })")
        XCTAssertEqual(try playlistCount(), 0, "abgebrochener Import legt nichts an")
        XCTAssertEqual(mock.requests.filter { $0.action != nil }.count, 0, "nach dem Abbrechen keine weitere Anfrage")

        // b) Fehler nach dem Abbrechen
        mock.resetLog()
        let alertsBefore = Set(NSApp.windows.filter { $0.isVisible && String(describing: Swift.type(of: $0)).contains("Alert") }.map(ObjectIdentifier.init))
        sheet = try await openSheet(w)
        await fill(sheet, host: mock.hostPort, user: "qa-user", pass: "qa-pass-ec18b")
        mock.handler = { req in .delayed(2, .json(["user_info": ["auth": 0]], status: 200)) }
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Anmelden & importieren")), in: sheet)
        await UIHarness.spin(0.4)
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Abbrechen")), in: sheet)
        _ = try await waitFor("Sheet zu") { w.attachedSheet == nil ? true : nil }
        await UIHarness.spin(3.0)
        XCTAssertEqual(mock.requests.count, 1, "Anmeldeanfrage lief")
        let visibleAlerts = NSApp.windows.filter { $0.isVisible && String(describing: Swift.type(of: $0)).contains("Alert") && !alertsBefore.contains(ObjectIdentifier($0)) }
        let orphanSheets = NSApp.windows.filter {
            $0.isVisible && String(describing: Swift.type(of: $0)).contains("SheetPresentationWindow") && $0.sheetParent == nil
        }
        print("B01BUILD|EC-18|fehlerNachAbbrechen neueSichtbareAlerts=\(visibleAlerts.count) verwaisteSheets=\(orphanSheets.count) sheet=\(w.attachedSheet != nil)")
        XCTAssertEqual(visibleAlerts.count, 0, "kein Alert nach Abbrechen")
        XCTAssertEqual(orphanSheets.count, 0, "Kein verwaistes Sheet-Fenster nach Abbrechen")
        XCTAssertNil(w.attachedSheet)
        XCTAssertEqual(try playlistCount(), 0)

        // Das Sheet lässt sich danach normal wieder öffnen, ohne Alert
        let again = try await openSheet(w, via: "Playlist importieren")
        XCTAssertNil(again.attachedSheet)
    }

    /// EC-19: Doppelklick auf „Anmelden & importieren" — (a) zwei Klicks im selben Durchlauf, (b) 150 ms Abstand wie ein echter Doppelklick.
    @MainActor func testEC19_DoppelklickAufAnmelden() async throws {
        let w = try await openPlaylists()
        let panel = MockXtreamServer.panel()
        mock.handler = { req in req.action == nil ? .delayed(1, panel(req)) : panel(req) }
        var results: [String: (Int, Int)] = [:]
        for variant in ["a-selberDurchlauf", "b-150ms"] {
            mock.resetLog()
            let before = try playlistCount()
            let sheet = try await openSheet(w, via: before == 0 ? "Playlist importieren" : "Add")
            await fill(sheet, host: mock.hostPort, user: "qa-user", pass: "qa-pass-ec19")
            let btn = try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Anmelden & importieren"))
            if variant.hasPrefix("a") {
                AX.click(btn, in: sheet, twice: true)
            } else {
                AX.click(btn, in: sheet)
                await UIHarness.spin(0.15)
                AX.click(btn, in: sheet)
            }
            _ = try? await waitFor("Sheet schließt", timeout: 8) { w.attachedSheet == nil ? true : nil }
            await UIHarness.spin(2.5)
            let auths = mock.requests.filter { $0.action == nil }.count
            results[variant] = (auths, try playlistCount() - before)
            print("B01QA|EC-19|\(variant)|anmeldeanfragen=\(auths)|neuePlaylists=\(try playlistCount() - before)")
        }
        XCTAssertEqual(results["b-150ms"]?.1, 1, "echter Doppelklick mit 150 ms Abstand")
        // BUG-09 (Teil Doppelklick) behoben: zwei Klicks im selben Durchlauf starten nur einen Import
        XCTAssertEqual(results["a-selberDurchlauf"]?.0, 1, "eine Anmeldeanfrage")
        XCTAssertEqual(results["a-selberDurchlauf"]?.1, 1, "eine Playlist")
    }

    /// BUG-02: Hinweis im Sheet, solange der Host nicht mit `https://` beginnt; bei `https://` verschwindet er.
    @MainActor func testBUG02_HinweisAufUnverschluesselteUebertragung() async throws {
        let w = try await openPlaylists()
        let sheet = try await openSheet(w)
        let hint = "Ohne „https://“ gehen Benutzername und Passwort unverschlüsselt über das Netz."
        XCTAssertTrue(hasText(sheet, hint), "leeres Formular")
        await fill(sheet, host: "dein-anbieter.tld", user: "qa-user", pass: "qa-pass-hint")
        XCTAssertTrue(hasText(sheet, hint), "ohne Schema")
        await fill(sheet, host: "http://dein-anbieter.tld", user: "qa-user", pass: "qa-pass-hint")
        XCTAssertTrue(hasText(sheet, hint), "http://")
        await fill(sheet, host: "HTTPS://dein-anbieter.tld:8443", user: "qa-user", pass: "qa-pass-hint")
        XCTAssertFalse(hasText(sheet, hint), "https://")
        XCTAssertEqual(mock.requests.count, 0)
    }
}
