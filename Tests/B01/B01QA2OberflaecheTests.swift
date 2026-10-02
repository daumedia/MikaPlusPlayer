import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B01 · QA-Durchlauf 2 — Oberfläche mit derselben Methode wie Durchlauf 1: `PlaylistsView` in einem echten Fenster des
/// Test-Hosts, synthetische Mausklicks, Texteingabe über den Feld-Editor, Zustand über Accessibility (`AX`, `UIHarness`
/// aus `B01OberflaecheTests.swift`). Kein Ton: keine Tastaturereignisse, keine Wiedergabe.
final class B01QA2OberflaecheTests: B01MockTestCase {

    private var window: NSWindow?
    private var container: ModelContainer?
    private let hint = "Ohne „https://“ gehen Benutzername und Passwort unverschlüsselt über das Netz."

    override func tearDown() {
        MainActor.assumeIsolated {
            for win in NSApp.windows where win !== window && win.isVisible {
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
        let c = try B01.inMemoryContainer()
        container = c
        let w = UIHarness.window(NavigationStack { PlaylistsView() }.modelContainer(c))
        window = w
        await UIHarness.spin(0.8)
        AX.wake(w)
        await UIHarness.spin(0.2)
        return w
    }

    @MainActor private func openSheet(_ w: NSWindow) async throws -> NSWindow {
        AX.wake(w)
        let label = (try playlistCount()) == 0 ? "Playlist importieren" : "Add"
        let btn = try XCTUnwrap(SystemSprache.namensVarianten(label).lazy.compactMap { AX.find(w, role: "AXButton", contains: $0) }.first,
                                label) // B09 · OF-01: englisch oder deutsch
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
        throw NSError(domain: "B01QA2UI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Zeitüberschreitung: \(what)"])
    }

    @MainActor private func fields(_ sheet: NSWindow) -> [NSTextField] {
        var list: [(Int, NSView)] = []
        UIHarness.views(sheet.contentView!, into: &list)
        return list.map(\.1).compactMap { $0 as? NSTextField }
    }

    @MainActor private func type(_ text: String, into field: NSTextField, in sheet: NSWindow) {
        sheet.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView else { return }
        editor.insertText(text, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
    }

    @MainActor private func fill(_ sheet: NSWindow, host: String, user: String = "qa-user", pass: String) async {
        let f = fields(sheet)
        type(host, into: f[1], in: sheet)
        type(user, into: f[2], in: sheet)
        type(pass, into: f[3], in: sheet)
        sheet.makeFirstResponder(nil)
        await UIHarness.spin(0.3)
        AX.wake(sheet)
    }

    @MainActor private func hasText(_ root: NSObject, _ text: String) -> Bool {
        AX.all(root).contains { AX.label($0).contains(text) }
    }

    @MainActor private func playlistCount() throws -> Int {
        try container!.mainContext.fetchCount(FetchDescriptor<Playlist>())
    }

    /// Alle Fenster dieses Prozesses, die laut Fenster-Server auf dem Bildschirm liegen (unabhängig vom Klassennamen).
    private func onScreenWindowNumbers() -> Set<Int> {
        let pid = ProcessInfo.processInfo.processIdentifier
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(info.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }.compactMap { $0[kCGWindowNumber as String] as? Int })
    }

    // MARK: BUG-02 · HTTPS-Hinweis

    /// BUG-02: Hinweis erscheint, solange die Eingabe nicht zu einer `https`-Adresse wird – auch bei Tippfehlern,
    /// fremdem Schema oder „https" nur im Hostnamen; verschwindet bei `https://` in jeder Schreibweise und mit führendem
    /// Leerzeichen; kommt zurück, wenn `https://` wieder entfernt wird.
    @MainActor func testQA2_BUG02_HinweisVarianten() async throws {
        let w = try await openPlaylists()
        let sheet = try await openSheet(w)
        let cases: [(String, Bool)] = [
            ("https://", true), ("https:/dein-anbieter.tld", true), ("ftp://dein-anbieter.tld", true),
            ("http://https.dein-anbieter.tld", true), ("dein-anbieter.tld:443", true),
            (" https://dein-anbieter.tld", false), ("hTtPs://dein-anbieter.tld:8443/panel/?x=1", false),
            ("https://qa-u:qa-pw@dein-anbieter.tld", false), ("http://dein-anbieter.tld", true)
        ]
        var observed: [String] = []
        for (host, expected) in cases {
            await fill(sheet, host: host, pass: "qa-pass-qa2hint")
            let visible = hasText(sheet, hint)
            observed.append("\(host.debugDescription)=\(visible ? "sichtbar" : "weg")")
            XCTAssertEqual(visible, expected, host.debugDescription)
        }
        print("B01QA2|UI|BUG-02|\(observed)")
        XCTAssertEqual(mock.requests.count, 0)
    }

    // MARK: BUG-11 / EC-18 · ursprüngliche Reproduktion

    /// BUG-11, Reproduktion aus Durchlauf 1 ohne Annahmen über Fensterklassen: Panel antwortet nach 2 s mit `auth: 0`;
    /// „Abbrechen" während des Imports. Geprüft über den Fenster-Server (Fenster des Prozesses auf dem Bildschirm vorher/
    /// nachher), über den Text aller Fenster („Anmeldung fehlgeschlagen") und über Datenbank und Schlüsselbund.
    /// Zweite Runde: Abbruch nach erfolgreicher Anmeldung (Kategorien verzögert) → keine Playlist, kein Eintrag.
    @MainActor func testQA2_BUG11_AbbrechenOriginalReproduktion() async throws {
        let w = try await openPlaylists()
        for round in ["auth0-verzoegert", "kategorien-verzoegert"] {
            mock.resetLog()
            let screenBefore = onScreenWindowNumbers()
            let sheet = try await openSheet(w)
            await fill(sheet, host: mock.hostPort, pass: "qa-pass-qa2ec18")
            let panel = MockXtreamServer.panel()
            if round == "auth0-verzoegert" {
                mock.handler = { _ in .delayed(2, .json(["user_info": ["auth": 0]], status: 200)) }
            } else {
                mock.handler = { req in req.action == "get_live_categories" ? .delayed(2, panel(req)) : panel(req) }
            }
            AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Anmelden & importieren")), in: sheet)
            await UIHarness.spin(round == "auth0-verzoegert" ? 0.4 : 0.8)
            AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Abbrechen")), in: sheet)
            _ = try await waitFor("Sheet zu") { w.attachedSheet == nil ? true : nil }
            await UIHarness.spin(4.0)
            let screenAfter = onScreenWindowNumbers()
            let newOnScreen = screenAfter.subtracting(screenBefore)
            let texts = NSApp.windows.filter(\.isVisible).flatMap { AX.all($0).map(AX.label) }
            let errorVisible = texts.contains { $0.contains("Anmeldung fehlgeschlagen") || $0.contains("Fehler") }
            let keychain = B01QA2.keychainCount(service: XtreamCredentialStore.standard.service)
            print("B01QA2|UI|EC-18|\(round)|neueFensterAufBildschirm=\(newOnScreen.count)|fehlertextSichtbar=\(errorVisible)|anfragen=\(mock.requests.map { $0.action ?? "(ohne)" })|playlists=\(try playlistCount())|schluesselbund=\(keychain)|sheet=\(w.attachedSheet != nil)")
            XCTAssertEqual(newOnScreen.count, 0, "\(round): kein Fenster taucht wieder auf")
            XCTAssertFalse(errorVisible, round)
            XCTAssertNil(w.attachedSheet)
            XCTAssertEqual(try playlistCount(), 0, round)
            XCTAssertEqual(keychain, 0, round)
            if round == "auth0-verzoegert" {
                XCTAssertEqual(mock.requests.count, 1)
            } else {
                XCTAssertFalse(mock.requests.contains { $0.action == "get_live_streams" }, "nach Abbruch keine Streams-Anfrage")
            }
        }
    }

    // MARK: Review-Fund · Abbrechen beim M3U-Import (B02)

    /// Hinweis für B02: „Abbrechen" während eines Imports über den Reiter „URL" desselben Sheets. Bricht es ab?
    @MainActor func testQA2_HinweisB02_AbbrechenBeiURLImport() async throws {
        let w = try await openPlaylists()
        let m3u = Data("#EXTM3U\n#EXTINF:-1,QA Sender\nhttp://127.0.0.1:9/qa.ts\n".utf8)
        mock.handler = { req in
            req.path == "/qa2.m3u" ? .delayed(2, .raw(status: 200, contentType: "audio/x-mpegurl", body: m3u)) : .raw(status: 404, contentType: "text/plain", body: Data())
        }
        let sheet = try await openSheet(w)
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXRadioButton", contains: "URL")), in: sheet)
        await UIHarness.spin(0.3)
        let urlField = try XCTUnwrap(fields(sheet).dropFirst().first)
        type("http://\(mock.hostPort)/qa2.m3u", into: urlField, in: sheet)
        sheet.makeFirstResponder(nil)
        await UIHarness.spin(0.3)
        AX.wake(sheet)
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Von URL importieren")), in: sheet)
        await UIHarness.spin(0.4)
        AX.click(try XCTUnwrap(AX.find(sheet, role: "AXButton", contains: "Abbrechen")), in: sheet)
        _ = try await waitFor("Sheet zu") { w.attachedSheet == nil ? true : nil }
        await UIHarness.spin(3.5)
        print("B01QA2|UI|B02-HINWEIS|urlImportNachAbbrechen|playlists=\(try playlistCount())|anfragen=\(mock.requests.count)")
    }
}
