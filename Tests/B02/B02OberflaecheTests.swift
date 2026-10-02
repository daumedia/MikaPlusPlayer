import XCTest
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
@testable import MikaPlusPlayer

/// B02 · M3U-Import — Oberfläche der Reiter „URL" und „Datei" in einem echten Fenster des macOS-Test-Hosts:
/// `PlaylistsView` → Sheet, synthetische Mausklicks, Texteingabe über den Feld-Editor, Zustand über Accessibility
/// (`AX`, `UIHarness` aus `Tests/B01/B01OberflaecheTests.swift`), Fenster über den Fenster-Server. Tonlos: keine
/// Tastaturereignisse, keine Wiedergabe.
final class B02OberflaecheTests: B02TestCase {

    private var window: NSWindow?
    private var container: ModelContainer?

    override func tearDown() {
        MainActor.assumeIsolated {
            for win in NSApp.windows where win !== window && win.isVisible {
                if let panel = win as? NSOpenPanel { panel.cancel(nil); continue }
                let name = String(describing: Swift.type(of: win))
                if name.contains("SheetPresentationWindow") || name.contains("Alert") || name.contains("Panel") { win.close() }
            }
            window?.close()
            window = nil
            container = nil
        }
        super.tearDown()
    }

    // MARK: Hilfen

    @MainActor private func openPlaylists() async throws -> NSWindow {
        let c = try B02.memory()
        container = c
        let w = UIHarness.window(NavigationStack { PlaylistsView() }.modelContainer(c))
        window = w
        await UIHarness.spin(0.8)
        AX.wake(w)
        await UIHarness.spin(0.2)
        return w
    }

    @MainActor private func openSheet(_ w: NSWindow, tab: String = "URL") async throws -> NSWindow {
        AX.wake(w)
        let label = playlistCount() == 0 ? "Playlist importieren" : "Add"
        AX.click(try XCTUnwrap(SystemSprache.namensVarianten(label).lazy.compactMap { AX.find(w, role: "AXButton", contains: $0) }.first, label),
                 in: w) // B09 · OF-01: englisch oder deutsch
        let sheet = try await waitFor("Sheet") { w.attachedSheet }
        AX.wake(sheet)
        await UIHarness.spin(0.2)
        try await select(tab, in: sheet)
        return sheet
    }

    @MainActor private func select(_ tab: String, in sheet: NSWindow) async throws {
        AX.wake(sheet)
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXRadioButton", contains: tab), "Reiter \(tab)"), in: sheet)
        await UIHarness.spin(0.35)
        AX.wake(sheet)
    }

    @MainActor private func fields(_ sheet: NSWindow) -> [NSTextField] {
        var list: [(Int, NSView)] = []
        UIHarness.views(sheet.contentView!, into: &list)
        return list.map(\.1).compactMap { $0 as? NSTextField }.filter(\.isEditable)
    }

    @MainActor private func type(_ text: String, into field: NSTextField, in sheet: NSWindow) {
        sheet.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView else { return }
        editor.insertText(text, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
    }

    /// Reiter „URL": Name und URL eintragen.
    @MainActor private func fillURL(_ sheet: NSWindow, url: String, name: String = "") async throws {
        let f = fields(sheet)
        XCTAssertEqual(f.count, 2, "Name + URL")
        guard f.count == 2 else { return }
        type(name, into: f[0], in: sheet)
        type(url, into: f[1], in: sheet)
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

    @MainActor private func texts(_ root: NSObject) -> [String] {
        AX.all(root).compactMap { e in
            let l = AX.label(e)
            return l.isEmpty ? nil : "\(AX.role(e)):\(l)"
        }
    }

    @MainActor private func playlistCount() -> Int {
        (try? container?.mainContext.fetchCount(FetchDescriptor<Playlist>())) ?? -1
    }

    private func onScreenWindows() -> [[String: Any]] {
        let pid = ProcessInfo.processInfo.processIdentifier
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
    }

    private func onScreenNumbers() -> Set<Int> {
        Set(onScreenWindows().compactMap { $0[kCGWindowNumber as String] as? Int })
    }

    /// Aufnahme eines eigenen Fensters über den Fenster-Server nach `features/B02-m3u-import/qa/<name>.png`.
    @MainActor private func shot(_ w: NSWindow, _ name: String) {
        guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.boundsIgnoreFraming, .nominalResolution]) else {
            B02.log("SHOT|\(name)|fehlgeschlagen"); return
        }
        guard let data = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: B02.qaFolder, withIntermediateDirectories: true)
        try? data.write(to: B02.qaFolder.appendingPathComponent("\(name).png"))
        B02.log("SHOT|\(name)|\(img.width)x\(img.height)")
    }

    /// Öffnet das Kontextmenü einer Zeile per Rechtsklick, liest die Einträge und schließt es wieder.
    @MainActor private func contextMenuTitles(_ w: NSWindow, row: String) async -> [String]? {
        AX.wake(w)
        guard let el = AX.all(w).first(where: { AX.label($0).contains(row) && AX.role($0) == "AXButton" }) else { return nil }
        let f = AX.frame(el)
        let pt = w.convertPoint(fromScreen: NSPoint(x: f.midX, y: f.midY))
        final class Box: @unchecked Sendable { var titles: [String]? }
        let box = Box()
        let obs = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            guard let menu = note.object as? NSMenu else { return }
            box.titles = menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
            DispatchQueue.main.async { menu.cancelTracking() }
        }
        defer { NotificationCenter.default.removeObserver(obs) }
        if let down = NSEvent.mouseEvent(with: .rightMouseDown, location: pt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
            w.sendEvent(down)
        }
        await UIHarness.spin(0.4)
        return box.titles
    }

    // MARK: AK-01

    /// AK-01: Reiter „URL" und „Datei" mit Abschnitten, Platzhaltern und Buttons; die URL bleibt beim Reiterwechsel stehen.
    @MainActor func testAK01_ReiterURLUndDatei() async throws {
        let w = try await openPlaylists()
        let sheet = try await openSheet(w, tab: "URL")
        let urlTexts = texts(sheet)
        B02.log("AK-01|reiterURL|\(urlTexts)")
        XCTAssertEqual(AX.find(sheet, role: "AXRadioButton", contains: "URL").map(AX.label), "URL | 1")
        for t in ["Name (optional)", "z. B. Mein IPTV-Anbieter", "Playlist-URL", "https://… .m3u8"] { XCTAssertTrue(hasText(sheet, t), t) }
        XCTAssertNotNil(AX.find(sheet, role: "AXButton", contains: "Von URL importieren"))
        XCTAssertEqual(fields(sheet).count, 2)
        shot(sheet, "AK-01-reiter-url")

        let url = server.url("/liste.m3u")
        try await fillURL(sheet, url: url)
        try await select("Datei", in: sheet)
        B02.log("AK-01|reiterDatei|\(texts(sheet))")
        for t in ["Name (optional)", "Lokale Datei"] { XCTAssertTrue(hasText(sheet, t), t) }
        XCTAssertNotNil(AX.find(sheet, role: "AXButton", contains: "Datei auswählen (.m3u/.m3u8)"))
        XCTAssertFalse(hasText(sheet, "Playlist-URL"))
        XCTAssertEqual(fields(sheet).count, 1, "nur Name")
        shot(sheet, "AK-01-reiter-datei")

        try await select("URL", in: sheet)
        let back = fields(sheet).map(\.stringValue)
        B02.log("AK-01|zurueckURL|felder=\(back)")
        XCTAssertEqual(back.last, url)
        XCTAssertEqual(server.requests.count, 0)
    }

    // MARK: AK-02 (macOS-Anteil)

    /// AK-02 (macOS-Anteil): keine automatische Rechtschreibkorrektur im URL-Feld; Namensfeld zum Vergleich.
    @MainActor func testAK02_KeineAutokorrekturImURLFeldMacOS() async throws {
        let w = try await openPlaylists()
        let sheet = try await openSheet(w, tab: "URL")
        let f = fields(sheet)
        var result: [Bool] = []
        for field in f {
            sheet.makeFirstResponder(field)
            let editor = field.currentEditor() as? NSTextView
            result.append(editor?.isAutomaticSpellingCorrectionEnabled ?? true)
        }
        B02.log("AK-02|autokorrektur Name=\(result.first ?? true) URL=\(result.last ?? true)")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.last, false, "URL-Feld")
    }

    // MARK: AK-03

    /// AK-03: leer → „Von URL importieren" deaktiviert; ein Leerzeichen aktiviert; „Datei auswählen" aktiv.
    @MainActor func testAK03_ButtonZustaende() async throws {
        let w = try await openPlaylists()
        let sheet = try await openSheet(w, tab: "URL")
        var seen: [String] = []
        XCTAssertEqual(enabled(sheet, button: "Von URL importieren"), false, "leer")
        seen.append("leer=\(enabled(sheet, button: "Von URL importieren").map(String.init) ?? "-")")
        for (input, expected) in [(" ", true), ("\t", true), ("x", true), (server.url("/liste.m3u"), true), ("", false)] {
            try await fillURL(sheet, url: input)
            let e = enabled(sheet, button: "Von URL importieren")
            seen.append("\(input.debugDescription)=\(e.map(String.init) ?? "-")")
            XCTAssertEqual(e, expected, input.debugDescription)
        }
        try await select("Datei", in: sheet)
        let datei = enabled(sheet, button: "Datei auswählen")
        seen.append("dateiButton=\(datei.map(String.init) ?? "-")")
        XCTAssertEqual(datei, true)
        B02.log("AK-03|\(seen)")
        XCTAssertEqual(server.requests.count, 0)
    }

    // MARK: AK-04 / EC-20

    /// AK-04: während eines URL-Imports „Importiere…" mit Fortschritt, Import-Buttons deaktiviert, „Abbrechen" bedienbar.
    /// EC-20: Reiterwechsel während des Imports — der Import läuft weiter, „Importiere…" auf jedem Reiter.
    @MainActor func testAK04_EC20_ZustandWaehrendDesURLImports() async throws {
        let w = try await openPlaylists()
        let sheet = try await openSheet(w, tab: "URL")
        server.handler = { _ in .delayed(3, B02Server.ok(B02.zweiSenderData)) }
        try await fillURL(sheet, url: server.url("/langsam.m3u"))
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Von URL importieren")), in: sheet)
        _ = try await waitFor("Importiere…") { AX.wake(sheet); return hasText(sheet, "Importiere…") ? true : nil }
        let busy = AX.all(sheet).contains { AX.role($0) == "AXBusyIndicator" || AX.role($0) == "AXProgressIndicator" }
        let urlBtn = enabled(sheet, button: "Von URL importieren")
        let cancel = enabled(sheet, button: "Abbrechen")
        try await select("Datei", in: sheet)
        let dateiImportiere = hasText(sheet, "Importiere…")
        let dateiBtn = enabled(sheet, button: "Datei auswählen")
        try await select("Xtream", in: sheet)
        let xtreamImportiere = hasText(sheet, "Importiere…")
        try await select("URL", in: sheet)
        B02.log("AK-04|importiere=true|fortschritt=\(busy)|urlButton=\(urlBtn.map(String.init) ?? "-")|abbrechen=\(cancel.map(String.init) ?? "-")|EC-20 datei: importiere=\(dateiImportiere) button=\(dateiBtn.map(String.init) ?? "-")|xtream: importiere=\(xtreamImportiere)|anfragen=\(server.requests.count)")
        XCTAssertTrue(busy)
        XCTAssertEqual(urlBtn, false)
        XCTAssertEqual(cancel, true)
        XCTAssertTrue(dateiImportiere)
        XCTAssertEqual(dateiBtn, false)
        XCTAssertTrue(xtreamImportiere)
        _ = try await waitFor("Sheet schließt", timeout: 8) { w.attachedSheet == nil ? true : nil }
        XCTAssertEqual(playlistCount(), 1, "Import lief über den Reiterwechsel weiter")
        XCTAssertEqual(server.requests.count, 1)
    }

    // MARK: AK-05 / AK-16 / AK-27 / AK-29 (Datei) über den Systemdialog

    /// AK-05: „Datei auswählen" öffnet den Systemdialog für **eine** Datei; erlaubte Typen am geöffneten Dialog abgelesen und
    /// gegen Beispieldateien geprüft (Typkonformität). Abbrechen des Dialogs hinterlässt keinen Alert.
    @MainActor func testAK05_Dateidialog() async throws {
        let w = try await openPlaylists()
        let sheet = try await openSheet(w, tab: "Datei")
        let dir = try tempDir("ak05")
        let chosen = dir.appendingPathComponent("qa-dialog.m3u")
        try B02.zweiSenderData.write(to: chosen)

        let btn = try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Datei auswählen"))
        DispatchQueue.main.async { AX.click(btn, in: sheet) }
        let panel = try await waitFor("Dateidialog", timeout: 8) { NSApp.windows.compactMap { $0 as? NSOpenPanel }.first { $0.isVisible } }
        await UIHarness.spin(0.8)
        let allowed = panel.allowedContentTypes
        let exts = ["m3u", "m3u8", "M3U8", "txt", "csv", "swift", "log", "md", "json", "html", "pls", "xspf", ""]
        var selectable: [String: Bool] = [:]
        for e in exts {
            let t = e.isEmpty ? UTType.data : (UTType(filenameExtension: e) ?? .data)
            selectable[e.isEmpty ? "(ohne Endung)" : e] = allowed.contains { t.conforms(to: $0) }
        }
        B02.evidence("AK-05-dateidialog.txt", "AK-05|klasse=\(Swift.type(of: panel))|alsSheet=\(panel.sheetParent != nil)|erlaubteTypen=\(allowed.map(\.identifier))|mehrfachauswahl=\(panel.allowsMultipleSelection)|dateien=\(panel.canChooseFiles)|ordner=\(panel.canChooseDirectories)|waehlbar=\(selectable.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })")
        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertTrue(panel.canChooseFiles)
        XCTAssertFalse(panel.canChooseDirectories)
        for e in ["m3u", "m3u8", "M3U8", "txt", "csv", "swift", "log", "md"] { XCTAssertEqual(selectable[e], true, e) }
        for e in ["json", "html", "pls", "xspf", "(ohne Endung)"] { XCTAssertEqual(selectable[e], false, e) }

        // Abbrechen des Dialogs: kein Alert, nichts angelegt, Sheet bleibt offen und bedienbar
        panel.cancel(nil)
        await UIHarness.spin(1.0)
        AX.wake(sheet)
        let alert = sheet.attachedSheet.map { texts($0) } ?? []
        B02.evidence("AK-05-dateidialog.txt", "AK-05|dialogAbgebrochen|alertNachAbbruch=\(alert)|playlists=\(playlistCount())|sheetOffen=\(w.attachedSheet != nil)|dateiButton=\(enabled(sheet, button: "Datei auswählen").map(String.init) ?? "-")")
        XCTAssertTrue(alert.isEmpty, "kein Fehler-Alert nach Abbrechen des Dialogs")
        XCTAssertEqual(playlistCount(), 0)
        XCTAssertNotNil(w.attachedSheet)
        XCTAssertEqual(enabled(sheet, button: "Datei auswählen"), true)
    }

    /// Öffnet über „Datei auswählen" den Systemdialog und wartet, bis er sichtbar ist.
    @MainActor private func openFileDialog(_ sheet: NSWindow) async throws -> NSOpenPanel {
        let btn = try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Datei auswählen"))
        DispatchQueue.main.async { AX.click(btn, in: sheet) }
        let panel = try await waitFor("Dateidialog", timeout: 8) { NSApp.windows.compactMap { $0 as? NSOpenPanel }.first { $0.isVisible } }
        await UIHarness.spin(0.8)
        return panel
    }

    /// Schließt den Dialog so, wie es der Systemdienst des Dialogs nach „Öffnen" tut (`completeWithReturnCode:url:urls:`):
    /// Der Inhalt des Dialogs läuft außerhalb des Prozesses und ist ohne Bedienungshilfen-Freigabe nicht klickbar. Ab hier
    /// laufen der Abschluss-Handler von `fileImporter` und der Import der App unverändert.
    @MainActor private func complete(_ panel: NSOpenPanel, with url: URL) -> Bool {
        let sel = NSSelectorFromString("completeWithReturnCode:url:urls:")
        guard panel.responds(to: sel), let imp = panel.method(for: sel) else { return false }
        typealias F = @convention(c) (AnyObject, Selector, Int, NSURL?, NSArray?) -> Void
        unsafeBitCast(imp, to: F.self)(panel, sel, NSApplication.ModalResponse.OK.rawValue, url as NSURL, [url] as NSArray)
        return true
    }

    /// AK-16 (über den Dialog): Datei gewählt → Sheet schließt, Playlist „qa-dialog" mit 2 Sendern oben, Dokument-Symbol.
    /// AK-27 (Datei): Datei ohne gültige Einträge → Alert „Fehler" im Sheet, Name bleibt, nichts angelegt.
    /// AK-29 (Datei) ⚠ / BUG-08: „Abbrechen" während eines Datei-Imports (3.000 Sender) — der Klick kommt erst nach dem Import an.
    @MainActor func testAK16_AK27_AK29_DateiImportUeberDialog() async throws {
        let w = try await openPlaylists()
        let dir = try tempDir("dialog")
        let good = dir.appendingPathComponent("qa-dialog.m3u"); try B02.zweiSenderData.write(to: good)
        let bad = dir.appendingPathComponent("notizen.txt"); try Data("Einkaufsliste\nhttp://example.invalid/a.ts\n".utf8).write(to: bad)
        // Seit BUG-04 ist ein Datei-Import mit 3.000 Sendern nach Bruchteilen einer Sekunde fertig; damit „Abbrechen“ nach
        // 0,5 s einen *laufenden* Import trifft, ist die Liste größer (40.000 Sender).
        let big = dir.appendingPathComponent("gross-40000.m3u"); try B02.grosseListe(40_000).write(to: big)

        // AK-27 (Datei)
        var sheet = try await openSheet(w, tab: "Datei")
        let nameField = try XCTUnwrap(fields(sheet).first)
        type("QA Datei Fehler", into: nameField, in: sheet); sheet.makeFirstResponder(nil); await UIHarness.spin(0.3)
        var panel = try await openFileDialog(sheet)
        XCTAssertTrue(complete(panel, with: bad), "Abschluss des Dialogs nicht möglich")
        let alert = try await waitFor("Alert", timeout: 8) { sheet.attachedSheet.flatMap { $0 is NSOpenPanel ? nil : $0 } }
        AX.wake(alert)
        let alertTexts = texts(alert)
        XCTAssertTrue(hasText(alert, "Die Playlist enthält keine gültigen Sender."))
        AX.press(try XCTUnwrap(AX.find(alert, role: "AXButton", contains: "OK")))
        _ = try await waitFor("Alert zu") { sheet.attachedSheet == nil ? true : nil }
        AX.wake(sheet)
        B02.evidence("AK-05-dateidialog.txt", "AK-27|datei|alert=\(alertTexts)|nachOK felder=\(fields(sheet).map(\.stringValue))|button=\(enabled(sheet, button: "Datei auswählen").map(String.init) ?? "-")|sheetOffen=\(w.attachedSheet != nil)|playlists=\(playlistCount())")
        XCTAssertEqual(fields(sheet).map(\.stringValue), ["QA Datei Fehler"])
        XCTAssertEqual(enabled(sheet, button: "Datei auswählen"), true)
        XCTAssertEqual(playlistCount(), 0)

        // AK-16 (über den Dialog)
        type("", into: try XCTUnwrap(fields(sheet).first), in: sheet); sheet.makeFirstResponder(nil); await UIHarness.spin(0.3)
        panel = try await openFileDialog(sheet)
        XCTAssertTrue(complete(panel, with: good))
        _ = try await waitFor("Sheet schließt", timeout: 8) { w.attachedSheet == nil ? true : nil }
        await UIHarness.spin(0.6)
        AX.wake(w)
        let rows = texts(w).filter { $0.contains("Sender") }
        B02.evidence("AK-05-dateidialog.txt", "AK-16|ueberDialog|sheetGeschlossen=\(w.attachedSheet == nil)|playlists=\(playlistCount())|zeilen=\(rows)")
        shot(w, "AK-16-datei-playlist-ueber-dialog")
        XCTAssertEqual(playlistCount(), 1)
        XCTAssertTrue(rows.contains { $0.contains("qa-dialog, 2 Sender") })

        // AK-29 (Datei): „Abbrechen" wird 0,5 s nach Start des Imports geklickt (Ereignis aus einem Hintergrund-Thread eingereiht)
        sheet = try await openSheet(w, tab: "Datei")
        let cancel = try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Abbrechen"))
        let f = AX.frame(cancel)
        let point = sheet.convertPoint(fromScreen: NSPoint(x: f.midX, y: f.midY))
        let sheetNumber = sheet.windowNumber
        panel = try await openFileDialog(sheet)
        let watchdog = MainThreadWatchdog(); watchdog.start()
        let t = Date()
        XCTAssertTrue(complete(panel, with: big))
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 0.5)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let ev = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: sheetNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    NSApp.postEvent(ev, atStart: false)
                }
            }
        }
        _ = try await waitFor("Sheet schließt", timeout: 120) { w.attachedSheet == nil ? true : nil }
        let elapsed = Date().timeIntervalSince(t)
        await UIHarness.spin(2.0)
        let gap = watchdog.stop()
        let names = (try? container?.mainContext.fetch(FetchDescriptor<Playlist>()).map { "\($0.name)=\($0.channelCount)" }) ?? []
        B02.evidence("AK-05-dateidialog.txt", "AK-29|datei|abbrechenNach0.5s|sheetZuNach=\(B02.f2(elapsed))s|maxMainThreadBlockade=\(B02.f2(gap))s|playlists=\(names)|build=\(B02.buildConfiguration)")
        // BUG-08 behoben: „Abbrechen“ bricht den Datei-Import ab, nichts wird angelegt (BUG-04: der Klick kommt sofort an).
        XCTAssertEqual(playlistCount(), 1)
        XCTAssertLessThan(gap, 0.5, "Main-Thread bleibt bedienbar")
    }

    // MARK: AK-06

    /// AK-06: Erfolg schließt das Sheet; neue Playlist an erster Stelle mit Globus-Symbol und „N Sender" (Aufnahme).
    @MainActor func testAK06_ErfolgSchliesstSheetNeuePlaylistOben() async throws {
        let w = try await openPlaylists()
        for name in ["QA Erste", "QA Zweite"] {
            let sheet = try await openSheet(w, tab: "URL")
            try await fillURL(sheet, url: server.url("/\(name.replacingOccurrences(of: " ", with: "-")).m3u"), name: name)
            AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Von URL importieren")), in: sheet)
            _ = try await waitFor("Sheet schließt", timeout: 8) { w.attachedSheet == nil ? true : nil }
            await UIHarness.spin(0.6)
        }
        AX.wake(w)
        let rows = texts(w).filter { $0.contains("QA ") }
        B02.log("AK-06|zeilen=\(rows)")
        shot(w, "AK-06-playlists-nach-url-import")
        let first = try XCTUnwrap(rows.firstIndex { $0.contains("QA Zweite") })
        let second = try XCTUnwrap(rows.firstIndex { $0.contains("QA Erste") })
        XCTAssertLessThan(first, second, "neueste oben")
        XCTAssertEqual(rows.filter { $0.contains("2 Sender") }.count, 2)
        XCTAssertEqual(playlistCount(), 2)
    }

    // MARK: AK-16 (Oberfläche) · Symbol und Kontextmenü

    /// AK-16: Datei-Playlist mit Dokument-Symbol und ohne „Aktualisieren" im Kontextmenü; URL-Playlist zum Vergleich.
    @MainActor func testAK16_DateiPlaylistSymbolUndKontextmenue() async throws {
        let w = try await openPlaylists()
        let ctx = try XCTUnwrap(container?.mainContext)
        let dir = try tempDir("ak16ui")
        let file = dir.appendingPathComponent("QA Datei.m3u")
        try B02.zweiSenderData.write(to: file)
        _ = try await B02.importURL(server.url("/liste.m3u"), name: "QA URL", ctx).get()
        _ = try await B02.importFile(file, ctx).get()
        await UIHarness.spin(0.8)
        AX.wake(w)
        shot(w, "AK-16-symbole-datei-und-url")
        let dateiMenu = await contextMenuTitles(w, row: "QA Datei")
        let urlMenu = await contextMenuTitles(w, row: "QA URL")
        let symbols = AX.all(w).map { AX.text($0, "accessibilityDescription") + "/" + AX.label($0) }.filter { $0.lowercased().contains("globe") || $0.lowercased().contains("doc") || $0.lowercased().contains("dokument") || $0.lowercased().contains("globus") }
        B02.log("AK-16|kontextmenue datei=\(dateiMenu ?? ["nicht geöffnet"])|url=\(urlMenu ?? ["nicht geöffnet"])|symbolLabels=\(symbols)")
        XCTAssertEqual(dateiMenu, ["Löschen"])
        XCTAssertEqual(urlMenu, ["Aktualisieren", "Löschen"])
    }

    // MARK: AK-27

    /// AK-27: Fehler → Alert „Fehler" mit Meldung und „OK"; danach Name und URL erhalten, Button sofort bedienbar, nichts angelegt.
    @MainActor func testAK27_FehlerAlertEingabenBleiben() async throws {
        let w = try await openPlaylists()
        let sheet = try await openSheet(w, tab: "URL")
        server.handler = { _ in B02Server.status(404) }
        for (input, message) in [(server.url("/fehlt.m3u"), "Netzwerkfehler: HTTP 404"), ("   ", "Die angegebene URL ist ungültig.")] {
            try await fillURL(sheet, url: input, name: "QA Alert")
            AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Von URL importieren")), in: sheet)
            let alert = try await waitFor("Alert", timeout: 8) { sheet.attachedSheet }
            AX.wake(alert)
            let alertTexts = texts(alert)
            B02.log("AK-27|\(input.debugDescription)|alert=\(alertTexts)")
            XCTAssertTrue(hasText(alert, "Fehler"))
            XCTAssertTrue(hasText(alert, message), message)
            AX.press(try XCTUnwrap(AX.find(alert, role: "AXButton", contains: "OK")))
            _ = try await waitFor("Alert zu") { sheet.attachedSheet == nil ? true : nil }
            AX.wake(sheet)
            let values = fields(sheet).map(\.stringValue)
            B02.log("AK-27|nachOK|felder=\(values)|button=\(enabled(sheet, button: "Von URL importieren").map(String.init) ?? "-")|sheetOffen=\(w.attachedSheet != nil)|playlists=\(playlistCount())")
            XCTAssertEqual(values, ["QA Alert", input])
            XCTAssertEqual(enabled(sheet, button: "Von URL importieren"), true)
            XCTAssertNotNil(w.attachedSheet)
            XCTAssertEqual(playlistCount(), 0)
        }
    }

    // MARK: AK-29 / EC-21 · BUG-08

    /// AK-29 ⚠ / BUG-08: „Abbrechen" während eines URL-Imports schließt nur das Sheet. (a) Erfolg → Playlist erscheint später.
    /// (b) Fehler → das geschlossene Sheet taucht losgelöst mit Alert auf dem Bildschirm auf. EC-21: danach öffnet das Sheet
    /// normal, ohne Alert.
    @MainActor func testAK29_EC21_AbbrechenBrichtURLImportAb() async throws {
        let w = try await openPlaylists()
        // a) Erfolg nach dem Abbrechen
        server.handler = { _ in .delayed(2, B02Server.ok(B02.zweiSenderData)) }
        var sheet = try await openSheet(w, tab: "URL")
        try await fillURL(sheet, url: server.url("/erfolg.m3u"))
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Von URL importieren")), in: sheet)
        await UIHarness.spin(0.4)
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Abbrechen")), in: sheet)
        _ = try await waitFor("Sheet zu") { w.attachedSheet == nil ? true : nil }
        let direkt = playlistCount()
        await UIHarness.spin(4.0)
        let spaeter = playlistCount()
        B02.log("AK-29|a-erfolgNachAbbrechen|playlistsDirekt=\(direkt)|playlistsNach4s=\(spaeter)|anfragen=\(server.requests.count)")
        XCTAssertEqual(direkt, 0)

        // b) Fehler nach dem Abbrechen
        server.resetLog()
        server.handler = { _ in .delayed(2, B02Server.status(500)) }
        let screenBefore = onScreenNumbers()
        sheet = try await openSheet(w, tab: "URL")
        try await fillURL(sheet, url: server.url("/fehler.m3u"))
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Von URL importieren")), in: sheet)
        await UIHarness.spin(0.4)
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Abbrechen")), in: sheet)
        _ = try await waitFor("Sheet zu") { w.attachedSheet == nil ? true : nil }
        await UIHarness.spin(4.0)
        let newOnScreen = onScreenNumbers().subtracting(screenBefore).subtracting([w.windowNumber])
        let orphans = NSApp.windows.filter { newOnScreen.contains($0.windowNumber) }
        let orphanTexts = orphans.flatMap { texts($0) }
        for (i, o) in orphans.enumerated() {
            B02.log("AK-29|b-fenster\(i)|klasse=\(Swift.type(of: o))|sheetParent=\(o.sheetParent.map { String(describing: Swift.type(of: $0)) } ?? "nil")|frame=\(o.frame)")
            shot(o, "AK-29-losgeloestes-fenster-\(i)")
        }
        B02.log("AK-29|b-fehlerNachAbbrechen|neueFensterAufBildschirm=\(newOnScreen.count)|texte=\(orphanTexts.filter { $0.contains("Fehler") || $0.contains("HTTP") || $0.contains("URL") })|sheetAmHauptfenster=\(w.attachedSheet != nil)|anfragen=\(server.requests.count)")
        XCTAssertFalse(orphanTexts.contains { $0.contains("Netzwerkfehler: HTTP 500") })
        XCTAssertNil(w.attachedSheet)

        // EC-21: erneut öffnen — kein Alert am neuen Sheet
        let again = try await openSheet(w, tab: "URL")
        await UIHarness.spin(0.5)
        B02.log("EC-21|erneutGeoeffnet|alertAmSheet=\(again.attachedSheet != nil)")
        XCTAssertNil(again.attachedSheet)

        // BUG-08 behoben: nach „Abbrechen“ entsteht nichts und es erscheint nichts (wie beim Xtream-Reiter).
        XCTAssertEqual(spaeter, 0)
        XCTAssertEqual(newOnScreen.count, 0)
    }

    // MARK: AK-30 · BUG-09

    /// AK-30 ⚠ / BUG-09: zwei Klicks im selben Durchlauf → zwei Anfragen, zwei Playlists; mit 150 ms Abstand → eine.
    @MainActor func testAK30_DoppelklickAufVonURLImportierenEinImport() async throws {
        let w = try await openPlaylists()
        server.handler = { _ in .delayed(1, B02Server.ok(B02.zweiSenderData)) }
        var results: [String: (Int, Int)] = [:]
        for variant in ["a-selberDurchlauf", "b-150ms"] {
            server.resetLog()
            let before = playlistCount()
            let sheet = try await openSheet(w, tab: "URL")
            try await fillURL(sheet, url: server.url("/doppel-\(variant).m3u"))
            let btn = try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Von URL importieren"))
            if variant.hasPrefix("a") {
                AX.click(btn, in: sheet, twice: true)
            } else {
                AX.click(btn, in: sheet)
                await UIHarness.spin(0.15)
                AX.click(btn, in: sheet)
            }
            _ = try? await waitFor("Sheet schließt", timeout: 8) { w.attachedSheet == nil ? true : nil }
            await UIHarness.spin(2.5)
            results[variant] = (server.requests.count, playlistCount() - before)
            B02.log("AK-30|\(variant)|anfragen=\(server.requests.count)|neuePlaylists=\(playlistCount() - before)")
        }
        XCTAssertEqual(results["b-150ms"]?.0, 1)
        XCTAssertEqual(results["b-150ms"]?.1, 1)
        // BUG-09 behoben: `isImporting` wird vor dem Start gesetzt – ein Import, eine Anfrage.
        XCTAssertEqual(results["a-selberDurchlauf"]?.0, 1)
        XCTAssertEqual(results["a-selberDurchlauf"]?.1, 1)
    }

    // MARK: AK-31 / AK-32 · BUG-06 / BUG-07

    /// AK-31 (b)(c) ⚠ / BUG-06: Das „Dokumente öffnen"-Ereignis, das LaunchServices bei „Öffnen mit" an die laufende App
    /// schickt, wird hier direkt an den eigenen Prozess (Test-Host = die App, Datenbank im Speicher) gesendet. Je Ereignis
    /// entsteht ein zusätzliches leeres Fenster „Playlists"; es wird nichts importiert, keine Meldung.
    @MainActor func testAK31_OeffnenEreignisImportiertImOffenenFenster() async throws {
        let dir = try tempDir("ak31")
        let visibleBefore = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        // Review R-06: Fenster der Hauptszene (SwiftUI-Szenenfenster außer „Multiview") vor dem ersten Ereignis. Ist eines
        // offen, darf kein Fenster entstehen; sonst genau eines (für alle Ereignisse zusammen).
        let sceneWindowsBefore = NSApp.windows.filter {
            $0.isVisible && $0.sheetParent == nil && NSStringFromClass(Swift.type(of: $0)).contains("AppKitWindow") && $0.title != "Multiview"
        }
        var created: [NSWindow] = []
        defer { created.forEach { $0.close() } }
        var lines: [String] = []
        var rejectedTxt = false
        for file in ["qa-oeffnen.m3u", "qa-oeffnen.m3u8", "qa-oeffnen.txt"] {
            let url = dir.appendingPathComponent(file)
            try B02.zweiSenderData.write(to: url)
            let target = NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier)
            let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenDocuments),
                                               targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                               transactionID: AETransactionID(kAnyTransactionID))
            let list = NSAppleEventDescriptor.list()
            list.insert(NSAppleEventDescriptor(fileURL: url), at: 0)
            event.setParam(list, forKeyword: keyDirectObject)
            // Über den AppKit-Handler des Prozesses zustellen (wie ein von LaunchServices gesendetes Ereignis).
            var reply = AEDesc(descriptorType: DescType(typeNull), dataHandle: nil)
            var refCon = 0
            let status: OSErr = withUnsafeMutablePointer(to: &refCon) { ref in
                guard let desc = event.aeDesc else { return OSErr(paramErr) }
                return NSAppleEventManager.shared().dispatchRawAppleEvent(desc, withRawReply: &reply, handlerRefCon: UnsafeMutableRawPointer(ref))
            }
            AEDisposeDesc(&reply)
            lines.append("\(file)|dispatchStatus=\(status)")
            await UIHarness.spin(2.0)
            let newWindows = NSApp.windows.filter {
                $0.isVisible && $0.sheetParent == nil && !($0 is NSPanel) && !visibleBefore.contains(ObjectIdentifier($0)) && !created.contains($0)
            }
            created.append(contentsOf: newWindows)
            for nw in newWindows { AX.wake(nw) }
            await UIHarness.spin(0.3)
            let windowTexts = newWindows.map { texts($0).filter { $0.contains("Playlist") || $0.contains("Sender") || $0.contains("Fehler") } }
            lines.append("\(file)|neueFenster=\(newWindows.count)|titel=\(newWindows.map(\.title))|texte=\(windowTexts)")
            if file.hasSuffix(".txt") {
                // Review R-09: keine M3U-Playlist → Meldung statt Import; Meldung bestätigen, damit nichts offen bleibt.
                let sheets = NSApp.windows.compactMap(\.attachedSheet)
                for sheet in sheets { AX.wake(sheet) }
                await UIHarness.spin(0.3)
                let sheetTexts = sheets.flatMap { texts($0) }
                rejectedTxt = sheetTexts.contains { $0.contains(ImportError.unsupportedFile.errorDescription ?? "?") }
                lines.append("\(file)|meldung=\(sheetTexts.filter { $0.contains("Import") || $0.contains("M3U") })")
                for sheet in sheets where texts(sheet).contains(where: { $0.contains("Import fehlgeschlagen") }) {
                    _ = B03UI.pressButton(sheet, "OK")
                }
                await UIHarness.spin(0.5)
            }
        }
        // BUG-06 behoben: Das Ereignis landet im offenen Fenster (höchstens eines entsteht, wenn keines offen war) und
        // importiert die Datei über denselben Weg wie der Datei-Reiter.
        await UIHarness.spin(1.0)
        let appWindows = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
        for aw in appWindows { AX.wake(aw) }
        await UIHarness.spin(0.3)
        let imported = appWindows.flatMap { texts($0) }.filter { $0.contains("qa-oeffnen, 2 Sender") }
        let failures = appWindows.flatMap { texts($0) }.filter { $0.contains("Import fehlgeschlagen") }
        let openSheets = NSApp.windows.compactMap(\.attachedSheet).count
        B02.evidence("AK-31-32-oeffnen.txt", "AK-31|testHost|" + lines.joined(separator: "\nAK-31|testHost|")
                     + "\nAK-31|testHost|szenenfensterVorher=\(sceneWindowsBefore.count)|neueFenster=\(created.count)|importiertSichtbar=\(imported.count)|txtAbgelehnt=\(rejectedTxt)|fehler=\(failures)|offeneMeldungen=\(openSheets)")
        if let shown = appWindows.first(where: { texts($0).contains { $0.contains("qa-oeffnen") } }) { shot(shown, "AK-31-import-nach-oeffnen") }
        XCTAssertEqual(created.count, sceneWindowsBefore.isEmpty ? 1 : 0,
                       "kein zusätzliches Fenster (Hauptfenster vorher offen: \(!sceneWindowsBefore.isEmpty))")
        XCTAssertEqual(imported.count, 2, "jede geöffnete M3U-Datei als Playlist importiert (.m3u, .m3u8)")
        XCTAssertTrue(rejectedTxt, "Textdatei abgelehnt mit Meldung (Review R-09)")
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(openSheets, 0, "keine Meldung bleibt offen")
    }

    /// AK-31 (d) / AK-32 ⚠ / BUG-07: Standard-App je Typ und ob sich Mika+Player als Öffner anbietet (LaunchServices, nur lesend).
    @MainActor func testAK31d_AK32_OeffnerRegistrierung() async throws {
        let dir = try tempDir("ak32")
        var lines: [String] = []
        var offered: [String: Bool] = [:]
        var offeredByThisBuild: [String: Bool] = [:]
        let thisBuild = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        func registered() -> Bool {
            NSWorkspace.shared.urlsForApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .contains { $0.resolvingSymlinksInPath().standardizedFileURL == thisBuild }
        }
        // Review R-05: Die LaunchServices-Liste prüft nur etwas, wenn dieses gebaute Bundle registriert ist. Kennt
        // LaunchServices es noch nicht (z. B. Build-Ordner außerhalb des Repositorys), registriert der Test es für die
        // Dauer der Prüfung selbst und nimmt die Registrierung danach wieder zurück (`lsregister -u`, nur dieser Pfad).
        let registeredByTest = !registered()
        if registeredByTest {
            LSRegisterURL(thisBuild as CFURL, true)
            _ = try? await waitFor("LaunchServices-Registrierung", timeout: 10) { registered() ? true : nil }
        }
        defer {
            if registeredByTest {
                let lsregister = Process()
                lsregister.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
                lsregister.arguments = ["-u", thisBuild.path]
                try? lsregister.run()
                lsregister.waitUntilExit()
            }
        }
        let thisBuildRegistered = registered()
        for ext in ["m3u", "m3u8", "txt", "json", "html", "csv", "swift", "md", "log", "pls", "xspf", ""] {
            let url = dir.appendingPathComponent(ext.isEmpty ? "qa-ohne-endung" : "qa.\(ext)")
            try Data("#EXTM3U\n".utf8).write(to: url)
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier) ?? "-"
            let std = NSWorkspace.shared.urlForApplication(toOpen: url)
            let stdName: String = {
                guard let std else { return "-" }
                let id = Bundle(url: std)?.bundleIdentifier ?? ""
                return id.hasPrefix("com.apple.") || id.hasPrefix("lu.daumedia.") ? std.lastPathComponent : "<Drittanbieter-App>"
            }()
            let candidates = NSWorkspace.shared.urlsForApplications(toOpen: url)
            let mika = candidates.filter { Bundle(url: $0)?.bundleIdentifier?.hasPrefix("lu.daumedia.MikaPlusPlayer") == true }
            let label = ext.isEmpty ? "(ohne Endung)" : ext
            offered[label] = !mika.isEmpty
            offeredByThisBuild[label] = candidates.contains { $0.resolvingSymlinksInPath().standardizedFileURL == thisBuild }
            lines.append("\(label)|typ=\(type)|standardApp=\(stdName)|mikaPlusPlayerKandidaten=\(mika.count)")
        }
        // LaunchServices kennt alle je gebauten Kopien (auch ältere Stände in anderen Build-Ordnern). Maßgeblich für diesen
        // Stand ist die Registrierung des gebauten Bundles selbst: seine Dokumenttypen aus dem Info.plist.
        let declared = ((Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]]) ?? [])
            .flatMap { ($0["LSItemContentTypes"] as? [String]) ?? [] }.compactMap { UTType($0) }
        var ownBuild: [String: Bool] = [:]
        for ext in ["m3u", "m3u8", "txt", "json", "html", "csv", "swift", "md", "log", "pls", "xspf", ""] {
            let label = ext.isEmpty ? "(ohne Endung)" : ext
            let type = ext.isEmpty ? UTType.data : (UTType(filenameExtension: ext) ?? .data)
            ownBuild[label] = declared.contains { type.conforms(to: $0) }
        }
        lines.append("diesesBundle|dokumenttypen=\(declared.map(\.identifier))|angeboten=\(ownBuild.filter(\.value).keys.sorted())")
        // Review R-05: die wörtliche Reproduktion von BUG-07 – bietet LaunchServices **dieses** gebaute Bundle als Öffner an?
        // (Andere, ältere Kopien in anderen Build-Ordnern zählen nicht.) Erfasst jeden Registrierungsweg, nicht nur
        // `LSItemContentTypes`.
        lines.append("diesesBundle|launchServices|angeboten=\(offeredByThisBuild.filter(\.value).keys.sorted())|registriert=\(thisBuildRegistered)|vomTestRegistriert=\(registeredByTest)")
        B02.evidence("AK-31-32-oeffnen.txt", "AK-31d/AK-32|" + lines.joined(separator: "\nAK-31d/AK-32|"))
        _ = offered
        // BUG-07 behoben: nur noch M3U-Playlists (.m3u, .m3u8), keine beliebigen Textdateien.
        XCTAssertEqual(declared.map(\.identifier), ["public.m3u-playlist"])
        for e in ["m3u", "m3u8"] { XCTAssertEqual(ownBuild[e], true, e) }
        for e in ["txt", "json", "html", "csv", "swift", "md", "log", "pls", "xspf", "(ohne Endung)"] { XCTAssertEqual(ownBuild[e], false, e) }
        let docTypes = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]]) ?? []
        XCTAssertTrue(docTypes.allSatisfy { $0["CFBundleTypeExtensions"] == nil && $0["CFBundleTypeOSTypes"] == nil && $0["CFBundleTypeMIMETypes"] == nil },
                      "kein weiterer Registrierungsweg im Info.plist: \(docTypes)")
        XCTAssertTrue(thisBuildRegistered, "dieses Bundle ist bei LaunchServices registriert (sonst prüft die Liste nichts)")
        for e in ["m3u", "m3u8"] { XCTAssertEqual(offeredByThisBuild[e], true, "LaunchServices: \(e)") }
        for e in ["txt", "json", "html", "csv", "swift", "md", "log", "pls", "xspf", "(ohne Endung)"] {
            XCTAssertEqual(offeredByThisBuild[e], false, "LaunchServices bietet dieses Bundle für \(e) an")
        }
    }
}
