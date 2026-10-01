import Foundation
import Network
import XCTest
import SwiftUI
import SwiftData
import AppKit
import SQLite3
import zlib
import Darwin
import QuartzCore
@testable import MikaPlusPlayer

// B04 · Senderliste — gemeinsame Hilfen der QA (Durchlauf 1, 2026-09-26).
//
// Regeln für alle B04-Tests:
// - Datenbanken nur als Datei im Temp-Verzeichnis (Produktionsweg `AppPersistence.diskContainer`) oder in-memory.
//   Die Datenbank des Nutzers wird nie geöffnet; der Test-Host selbst arbeitet im Speicher.
// - Logo-Hosts und Anbieter nur als Mock auf 127.0.0.1 bzw. `localhost` (`B04LogoHost`, `MockXtreamServer`),
//   erfundene Zugangsdaten (`qa-user` / `qa-pass-b04…`).
// - Plattencache: `~/Library/Caches/<Bundle-ID des Test-Hosts>/Cache.db`. Die QA lief mit eigener Bundle-ID
//   (`lu.daumedia.MikaPlusPlayer.qa1b04`, nur in der Kopie gesetzt), damit der Cache der App nie berührt wird.
//   Tests lesen dort nur Einträge des eigenen Mock-Ports und entfernen sie am Ende (`B04LogoHost.purgeCache`).
// - Tonlos: Stream-Adressen zeigen auf den geschlossenen Port 9, keine Tastaturereignisse.
// - Fenster: Die Hosting-View wird in eine eigene Halter-View eingebettet; sonst bestimmt sie die Fenstergröße
//   (42 × 48 pt, Hinweis der Rückerfassung) und `LazyVStack` realisiert keine Karten.

enum B04QA {
    static let dead = "http://127.0.0.1:9"

    static func log(_ s: String) {
        print("B04QA|\(s)")
        fflush(stdout)
    }

    static func f1(_ t: Double) -> String { String(format: "%.1f", t) }
    static func f0(_ t: Double) -> String { String(format: "%.0f", t) }

    #if DEBUG
    static let configuration = "Debug"
    #else
    static let configuration = "Release"
    #endif

    /// `features/B04-senderliste/qa/` im Repository (aus dem Pfad dieser Datei). Läuft die QA in einer Kopie,
    /// zeigt `TEST_RUNNER_B04_QA_DIR` auf den Nachweisordner im Repository.
    static var qaFolder: URL {
        if let dir = env("B04_QA_DIR"), !dir.isEmpty { return URL(fileURLWithPath: dir, isDirectory: true) }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("features/B04-senderliste/qa", isDirectory: true)
    }

    static func evidence(_ file: String, _ line: String) {
        try? FileManager.default.createDirectory(at: qaFolder, withIntermediateDirectories: true)
        let url = qaFolder.appendingPathComponent(file)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("\(stamp) [\(configuration)] \(line)\n".utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    static func loadAverage() -> String {
        var load = [Double](repeating: 0, count: 3)
        return getloadavg(&load, 3) == 3 ? String(format: "%.1f/%.1f/%.1f", load[0], load[1], load[2]) : "-"
    }

    static func env(_ key: String) -> String? { ProcessInfo.processInfo.environment[key] }

    // MARK: Datenbank

    @MainActor
    static func fileContainer(_ label: String) throws -> (container: ModelContainer, store: URL, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("b04-qa-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("MikaPlusPlayer.store")
        return (try AppPersistence.diskContainer(at: url, schema: AppSchema.schema), url, dir)
    }

    struct Item {
        var name: String
        var group: String?
        var logo: String?
        var tvgID: String?
        var stream: String?

        init(_ name: String, _ group: String? = nil, logo: String? = nil, tvg: String? = nil, stream: String? = nil) {
            self.name = name
            self.group = group
            self.logo = logo
            self.tvgID = tvg
            self.stream = stream
        }
    }

    /// Legt Playlist und Sender an wie der Xtream-Import der App (Blöcke, `channels.append(contentsOf:)`,
    /// `playlistID`, `channelCount`). Dieselben Datenbankzeilen wie `PlaylistImporter.attach`.
    @MainActor @discardableResult
    static func seed(_ ctx: ModelContext, name: String, items: [Item], createdAt: Date = Date()) throws -> Playlist {
        let playlist = Playlist(name: name, createdAt: createdAt)
        ctx.insert(playlist)
        var start = 0
        repeat {
            let end = min(start + 5_000, items.count)
            var batch: [Channel] = []
            batch.reserveCapacity(end - start)
            for i in start..<end {
                let it = items[i]
                let channel = Channel(
                    name: it.name,
                    streamURL: URL(string: it.stream ?? "\(dead)/live/\(i).m3u8")!,
                    logoURL: it.logo.flatMap { URL(string: $0) },
                    group: it.group,
                    tvgID: it.tvgID,
                    playlistID: playlist.id
                )
                ctx.insert(channel)
                batch.append(channel)
            }
            playlist.channels.append(contentsOf: batch)
            playlist.channelCount = end
            try ctx.save()
            start = end
        } while start < items.count
        return playlist
    }

    /// 17.000 erfundene Sender wie in der Rückerfassung: 12 Länderpräfixe × 25 Genres = 300 Gruppen.
    static let countries = ["DE", "AT", "CH", "UK", "FR", "IT", "ES", "TR", "PL", "NL", "AR", "US"]
    static let genres = ["Sport", "News", "Kino", "Kids", "Doku", "Musik", "Serien", "Regional", "Radio", "Religion",
                         "Shopping", "Wetter", "Comedy", "Action", "Drama", "Natur", "Reisen", "Kochen", "Wissen",
                         "Geschichte", "Auto", "Fußball", "Tennis", "Formel", "Anime"]
    static let quality = ["HD", "FHD", "SD", "4K", "HEVC"]

    static func perfItems(_ count: Int, offset: Int = 0, logoBase: String = "http://127.0.0.1:9/logo") -> [Item] {
        (0..<count).map { i in
            let ci = (i + offset) % countries.count
            let gi = ((i + offset) / 7) % genres.count
            let name = "\(countries[ci]): \(genres[gi]) \((i % 97) + 1) \(quality[i % 5])"
            return Item(name, "\(countries[ci]) | \(genres[gi])", logo: "\(logoBase)/\(offset)-\(i).png")
        }
    }

    // MARK: Abfragen der Liste

    /// Seit der Reparatur (B04 · BUG-12 bis BUG-14, 2026-09-29) liegt die Abfrage der Liste als `ChannelListQuery`
    /// offen; statt eines Spiegels benutzen die Tests sie selbst. Die Gegenprobe gegen die echte Ansicht steht weiter
    /// in `B04SucheTests.testAK07_…Oberflaeche`.
    @MainActor
    static func owner(_ ctx: ModelContext, _ playlistID: UUID) -> PersistentIdentifier? {
        var descriptor = FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == playlistID })
        descriptor.fetchLimit = 1
        return (try? ctx.fetch(descriptor))?.first?.persistentModelID
    }

    static func resultsDescriptor(_ owner: PersistentIdentifier, _ searchText: String, _ group: String?) -> FetchDescriptor<Channel> {
        ChannelListQuery.descriptor(playlist: owner, search: searchText, groupValues: group.map { [$0] })
    }

    @MainActor
    static func results(_ ctx: ModelContext, _ pid: UUID, _ search: String = "", _ group: String? = nil) -> [String] {
        guard let owner = owner(ctx, pid) else { return [] }
        return ((try? ctx.fetch(resultsDescriptor(owner, search, group))) ?? []).map(\.name)
    }

    /// Chip-Titel wie die Leiste sie zeigt (`ChannelListQuery.groups`).
    @MainActor
    static func groupsMirror(_ ctx: ModelContext, _ pid: UUID) -> [String] {
        guard let owner = owner(ctx, pid) else { return [] }
        return (try? ChannelListQuery.groups(in: ctx.container, playlist: owner).chips) ?? []
    }

    // MARK: SQLite (nur Test-Dateien)

    static func rows(_ path: String, _ sql: String) -> [[String]] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return [] }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return [["SQL-FEHLER: " + String(cString: sqlite3_errmsg(db))]]
        }
        defer { sqlite3_finalize(stmt) }
        var result: [[String]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var cols: [String] = []
            for i in 0..<sqlite3_column_count(stmt) {
                if let c = sqlite3_column_text(stmt, i) { cols.append(String(cString: c)) } else { cols.append("NULL") }
            }
            result.append(cols)
        }
        return result
    }

    static func int(_ path: String, _ sql: String) -> Int { Int(rows(path, sql).first?.first ?? "") ?? -1 }

    /// Wie oft kommt `marker` als Bytefolge in der Datenbankdatei samt `-wal`/`-shm` vor (nur Testdateien).
    static func rawOccurrences(_ marker: String, _ store: URL) -> Int {
        B01.rawOccurrences(of: marker, inFilesWithPrefix: store).values.reduce(0, +)
    }

    /// Plattencache des Test-Hosts (gleiche Bundle-ID wie die App): `~/Library/Caches/<Bundle-ID>/Cache.db`.
    static var hostCacheDB: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "lu.daumedia.MikaPlusPlayer")
            .appendingPathComponent("Cache.db")
    }

    /// Einträge im Plattencache, deren Schlüssel mit `prefix` beginnt (nur eigene Mock-Adressen).
    static func cacheRows(prefix: String) -> [[String]] {
        precondition(prefix.hasPrefix("http://127.0.0.1:") || prefix.hasPrefix("http://localhost:"), "nur eigene Mock-Adressen")
        let escaped = prefix.replacingOccurrences(of: "'", with: "''")
        return rows(hostCacheDB.path,
                    "select r.request_key, length(d.receiver_data), d.isDataOnFS from cfurl_cache_response r "
                    + "left join cfurl_cache_receiver_data d on d.entry_ID = r.entry_ID "
                    + "where substr(r.request_key, 1, \(prefix.utf8.count)) = '\(escaped)' order by r.entry_ID")
    }

    // MARK: Warten

    static func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    @discardableResult
    static func wait(_ timeout: TimeInterval, poll: TimeInterval = 0.05, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            spin(poll)
        }
        return condition()
    }

    /// Führt eine async-Aufgabe auf dem Main-Actor aus und dreht die Run-Loop, bis sie fertig ist.
    @MainActor
    static func run<T>(_ timeout: TimeInterval = 60, _ body: @escaping @MainActor () async throws -> T) throws -> T {
        var result: Result<T, Error>?
        Task { @MainActor in
            do { result = .success(try await body()) } catch { result = .failure(error) }
        }
        let end = Date().addingTimeInterval(timeout)
        while result == nil && Date() < end { spin(0.02) }
        guard let result else { throw NSError(domain: "B04QA", code: 1, userInfo: [NSLocalizedDescriptionKey: "Zeitüberschreitung"]) }
        return try result.get()
    }
}

/// Misst die längste Blockade des Main-Thread über einen 5-ms-Timer (wie die Sonde der Rückerfassung).
@MainActor
final class B04Heartbeat {
    private var stamps: [CFTimeInterval] = []
    private var timer: Timer?

    func start() {
        stamps = [CACurrentMediaTime()]
        let t = Timer(timeInterval: 0.005, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stamps.append(CACurrentMediaTime()) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Längste Lücke in ms, Summe aller Lücken über 50 ms in ms.
    func stop() -> (maxMs: Double, over50Ms: Double) {
        timer?.invalidate()
        stamps.append(CACurrentMediaTime())
        var maxGap = 0.0, over = 0.0
        for i in 1..<stamps.count {
            let gap = (stamps[i] - stamps[i - 1]) * 1000
            maxGap = max(maxGap, gap)
            if gap > 50 { over += gap }
        }
        return (maxGap, over)
    }
}

// MARK: - Oberfläche

@Observable
final class B04Nav {
    var path = NavigationPath()
}

/// Wie `ContentView`, Tab „Playlists“: `NavigationStack { PlaylistsView() }`, nur mit steuerbarem Pfad.
struct B04Root: View {
    @Bindable var nav: B04Nav
    /// Zeichnet Bedienelemente wie in einem aktiven Fenster, auch wenn der Test-Host nicht vorn ist (Nacharbeit R-1:
    /// hervorgehobene Tasten sind in inaktiven Fenstern grau).
    var forceActive = false
    /// Erzwingt einen Fensterzustand (z. B. `.inactive`); hat Vorrang vor `forceActive`.
    var controlState: ControlActiveState? = nil

    var body: some View {
        let stack = NavigationStack(path: $nav.path) {
            PlaylistsView()
        }
        .tint(.playerAccent)
        if let state = controlState ?? (forceActive ? .key : nil) {
            stack.environment(\.controlActiveState, state)
        } else {
            stack
        }
    }
}

@MainActor
final class B04Window {
    let window: NSWindow
    let hosting: NSView
    let nav = B04Nav()
    let multiview: MultiviewSession

    init(_ container: ModelContainer, size: CGSize = CGSize(width: 900, height: 700),
         origin: CGPoint = CGPoint(x: 60, y: 60), appearance: NSAppearance.Name? = nil,
         multiview: MultiviewSession? = nil, forceActive: Bool = false, controlState: ControlActiveState? = nil) {
        let multiview = multiview ?? MultiviewSession()
        self.multiview = multiview
        let root = B04Root(nav: nav, forceActive: forceActive, controlState: controlState).environment(multiview).modelContainer(container)
        let hv = NSHostingView(rootView: root)
        let w = NSWindow(contentRect: NSRect(origin: origin, size: size),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        if let appearance { w.appearance = NSAppearance(named: appearance) }
        // Einbetten: Die Halter-View bestimmt die Größe, nicht die Hosting-View.
        hv.sizingOptions = []
        // Fenstertitel und Toolbar (Suchfeld aus `.searchable`) brauchen die Szenenbrücke.
        hv.sceneBridgingOptions = [.all]
        let holder = NSView(frame: NSRect(origin: .zero, size: size))
        hv.frame = holder.bounds
        hv.autoresizingMask = [.width, .height]
        holder.addSubview(hv)
        w.contentView = holder
        w.setContentSize(size)
        w.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
        w.makeKeyAndOrderFront(nil)
        window = w
        hosting = hv
        B04QA.spin(0.6)
        w.setContentSize(size)
        B04QA.spin(0.2)
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }

    func open(_ playlist: Playlist, wait: TimeInterval = 1.2) {
        nav.path.append(playlist)
        B04QA.spin(wait)
    }

    func back(wait: TimeInterval = 0.8) {
        if !nav.path.isEmpty { nav.path.removeLast(nav.path.count) }
        B04QA.spin(wait)
    }

    var sizeText: String {
        "fenster=\(Int(window.frame.width))x\(Int(window.frame.height))|inhalt=\(Int(hosting.frame.width))x\(Int(hosting.frame.height))"
    }

    // MARK: Accessibility

    func wake() {
        _ = hosting.accessibilityHitTest(NSPoint(x: window.frame.midX, y: window.frame.midY))
    }

    var elements: [NSObject] {
        wake()
        return B04AX.all(hosting)
    }

    /// Alle Texte (Label/Titel/Wert) im Inhalt.
    var texts: [String] { elements.map(B04AX.label).filter { !$0.isEmpty } }

    var staticTexts: [String] {
        elements.filter { B04AX.role($0) == "AXStaticText" }.map(B04AX.label)
    }

    func element(_ text: String, role: String? = nil) -> NSObject? {
        let list = elements
        return list.first { (role == nil || B04AX.role($0) == role) && B04AX.label($0) == text }
    }

    /// Chips der Leiste in Leserichtung: Buttons oberhalb der Kopfzeile, sortiert nach x.
    var chips: [(title: String, frame: NSRect, element: NSObject)] {
        let all = elements
        guard let header = all.first(where: { B04AX.label($0).hasPrefix("MIKA+PLAYER · ") }) else { return [] }
        let headerTop = B04AX.frame(header).maxY
        return all.filter { B04AX.role($0) == "AXButton" }
            .map { (B04AX.label($0), B04AX.frame($0), $0) }
            .filter { $0.1.minY > headerTop && !$0.0.isEmpty }
            .sorted { $0.1.minX < $1.1.minX }
    }

    /// Scrollt die Chip-Leiste, bis der Chip aufgebaut ist (Leiste mit vielen Gruppen baut nur sichtbare Chips auf).
    @discardableResult
    func revealChip(_ title: String) -> Bool {
        if chips.contains(where: { $0.title == title }) { return true }
        // Die Leiste ist die rein waagerecht scrollbare Ansicht (die Seite selbst scrollt senkrecht).
        guard let bar = B04AX.views(hosting, of: NSScrollView.self).first(where: {
            ($0.documentView?.bounds.width ?? 0) > $0.contentSize.width + 10
                && ($0.documentView?.bounds.height ?? .infinity) <= $0.contentSize.height + 1
        }) else { return false }
        let breite = bar.contentSize.width
        var x: CGFloat = 0
        while x < (bar.documentView?.bounds.width ?? 0) {
            x += breite * 0.8
            bar.contentView.scroll(to: NSPoint(x: x, y: 0))
            bar.reflectScrolledClipView(bar.contentView)
            B04QA.spin(0.3)
            if chips.contains(where: { $0.title == title }) { return true }
        }
        return false
    }

    @discardableResult
    func pressChip(_ title: String, wait: TimeInterval = 1.0) -> Bool {
        guard let chip = chips.first(where: { $0.title == title }) else { return false }
        let ok = B04AX.press(chip.element)
        B04QA.spin(wait)
        return ok
    }

    /// Senderkarten in Bildschirmreihenfolge (oben zuerst). Eine Karte mit drehendem Ladeindikator erscheint im
    /// Accessibility-Baum als `AXBusyIndicator` statt `AXButton`; ihr Wert (`| 0`) wird abgeschnitten.
    var rows: [(label: String, frame: NSRect, busy: Bool, element: NSObject)] {
        let all = elements
        // Seit der Reparatur (B04 · BUG-13) ist bei vielen Gruppen auch die Chip-Leiste ein Lazy-Container (eine Zeile,
        // rund 28 pt hoch); die Senderliste ist der höchste Container mit gültigem Rahmen.
        let gruppen = all.filter { B04AX.role($0) == "AXOpaqueProviderGroup" }
        let gueltig = gruppen.filter { let f = B04AX.frame($0); return f.width > 0 && f.height.isFinite && f.minY.isFinite }
        guard let list = gueltig.max(by: { B04AX.frame($0).height < B04AX.frame($1).height }) ?? gruppen.first else { return [] }
        return B04AX.all(list).dropFirst()
            .filter { ["AXButton", "AXBusyIndicator"].contains(B04AX.role($0)) }
            .map { e -> (String, NSRect, Bool, NSObject) in
                var label = B04AX.label(e)
                if let cut = label.range(of: " | ", options: .backwards) { label = String(label[..<cut.lowerBound]) }
                return (label, B04AX.frame(e), B04AX.role(e) == "AXBusyIndicator", e)
            }
            .sorted { $0.1.maxY > $1.1.maxY }
            .map { (label: $0.0, frame: $0.1, busy: $0.2, element: $0.3) }
    }

    /// Nur die Beschriftungen der Karten („Name, Gruppe“ bzw. „Name“ ohne Gruppe), oben zuerst.
    var cardNames: [String] { rows.map(\.label) }

    /// Karten, in denen ein Ladeindikator dreht.
    var busyRows: [String] { rows.filter(\.busy).map(\.label) }

    var header: String? { staticTexts.first { $0.hasPrefix("MIKA+PLAYER · ") } }

    // MARK: Suchfeld

    var searchField: NSSearchField? {
        if let items = window.toolbar?.items {
            for item in items {
                if let sf = (item as? NSSearchToolbarItem)?.searchField { return sf }
                if let v = item.view, let sf = B04AX.firstSearchField(v) { return sf }
            }
        }
        if let frame = window.contentView?.superview { return B04AX.firstSearchField(frame) }
        return nil
    }

    /// Setzt den Text des Suchfelds wie eine Eingabe (ohne Tastaturereignisse, die piepen könnten).
    @discardableResult
    func type(_ text: String, wait: TimeInterval = 0.8) -> Bool {
        guard let sf = searchField else { return false }
        sf.stringValue = text
        if let editor = sf.currentEditor() { editor.string = text }
        let note = Notification(name: NSControl.textDidChangeNotification, object: sf,
                                userInfo: ["NSFieldEditor": sf.currentEditor() as Any])
        sf.delegate?.controlTextDidChange?(note)
        NotificationCenter.default.post(note)
        if let action = sf.action { NSApp.sendAction(action, to: sf.target, from: sf) }
        B04QA.spin(wait)
        return true
    }

    // MARK: Ansichten

    var scrollView: NSScrollView? {
        B04AX.views(hosting, of: NSScrollView.self)
            .filter { ($0.documentView?.bounds.height ?? 0) > $0.contentSize.height + 10 }
            .max { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) }
    }

    func scroll(toY y: CGFloat, wait: TimeInterval = 0.5) {
        guard let sv = scrollView else { return }
        sv.contentView.scroll(to: NSPoint(x: 0, y: y))
        sv.reflectScrolledClipView(sv.contentView)
        B04QA.spin(wait)
    }

    /// Sichtbare Ladeindikatoren (drehende `NSProgressIndicator` im Inhalt).
    var spinnerCount: Int {
        B04AX.views(hosting, of: NSProgressIndicator.self).filter { !$0.isHiddenOrHasHiddenAncestor && $0.window != nil }.count
    }

    func shot(_ name: String) {
        B04Shot.window(window, name)
    }

    /// Linksklick als synthetisches Mausereignis auf einen Punkt des Elements (Verschiebung in pt von der Mitte).
    func click(_ e: NSObject, dx: CGFloat = 0, dy: CGFloat = 0, wait: TimeInterval = 1.0) {
        let f = B04AX.frame(e)
        let p = window.convertPoint(fromScreen: NSPoint(x: f.midX + dx, y: f.midY + dy))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let ev = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil,
                                           eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(ev)
            }
        }
        B04QA.spin(wait)
    }

    /// Klickt eine Karte links (außerhalb von Stern und ⊞) bzw. mit `atRightInset` von rechts.
    @discardableResult
    func clickRow(_ label: String, atRightInset: CGFloat? = nil, wait: TimeInterval = 1.2) -> Bool {
        guard let row = rows.first(where: { $0.label == label || $0.label.hasPrefix(label + ",") }) else { return false }
        let dx = atRightInset.map { row.frame.width / 2 - $0 } ?? -(row.frame.width / 2 - 100)
        click(row.element, dx: dx, wait: wait)
        return true
    }

    /// Farbe eines Punkts in Fensterkoordinaten von oben links (pt) aus einer Aufnahme dieses Fensters.
    func color(atTopLeft p: CGPoint) -> NSColor? { B04Shot.color(window, atTopLeft: p) }

    /// Punkte in Fensterkoordinaten, deren Farbe `color` nahe kommt.
    func match(_ color: NSColor, tolerance: CGFloat = 0.12, in region: NSRect? = nil) -> (count: Int, total: Int, box: NSRect?) {
        B04Shot.match(window, color: color, tolerance: tolerance, in: region)
    }

    /// Rechteck aus Bildschirmkoordinaten (Accessibility) in Fensterkoordinaten mit Ursprung oben links.
    func inWindow(_ screenRect: NSRect) -> NSRect {
        NSRect(x: screenRect.minX - window.frame.minX, y: window.frame.maxY - screenRect.maxY,
               width: screenRect.width, height: screenRect.height)
    }
}

@MainActor
enum B04Shot {
    static func window(_ w: NSWindow, _ name: String) {
        guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber),
                                                [.boundsIgnoreFraming, .nominalResolution]) else {
            B04QA.log("SHOT|\(name)|fehlgeschlagen")
            return
        }
        let rep = NSBitmapImageRep(cgImage: img)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: B04QA.qaFolder, withIntermediateDirectories: true)
        try? data.write(to: B04QA.qaFolder.appendingPathComponent("\(name).png"))
        B04QA.log("SHOT|\(name)|\(img.width)x\(img.height)")
    }

    /// Farbe eines Bildschirmpunkts (Fensterkoordinaten in pt, Ursprung oben links) aus einer Fensteraufnahme.
    static func color(_ w: NSWindow, atTopLeft p: CGPoint) -> NSColor? {
        guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber),
                                                [.boundsIgnoreFraming, .bestResolution]) else { return nil }
        let scale = CGFloat(img.width) / w.frame.width
        let rep = NSBitmapImageRep(cgImage: img)
        return rep.colorAt(x: Int(p.x * scale), y: Int(p.y * scale))?.usingColorSpace(.sRGB)
    }

    /// Punkte einer Fensteraufnahme, deren Farbe der gesuchten nahe kommt — Anzahl, Gesamtzahl und umschließendes
    /// Rechteck (Fensterkoordinaten in pt, Ursprung oben links). `region` grenzt den Bereich ein.
    static func match(_ w: NSWindow, color: NSColor, tolerance: CGFloat = 0.12,
                      in region: NSRect? = nil) -> (count: Int, total: Int, box: NSRect?) {
        guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber),
                                                [.boundsIgnoreFraming, .bestResolution]),
              let target = color.usingColorSpace(.sRGB) else { return (0, 0, nil) }
        let scale = CGFloat(img.width) / w.frame.width
        let rep = NSBitmapImageRep(cgImage: img)
        let area = region ?? NSRect(x: 0, y: 0, width: w.frame.width, height: w.frame.height)
        let x0 = max(0, Int(area.minX * scale)), x1 = min(rep.pixelsWide, Int(area.maxX * scale))
        let y0 = max(0, Int(area.minY * scale)), y1 = min(rep.pixelsHigh, Int(area.maxY * scale))
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1, count = 0, total = 0
        for y in y0..<max(y0, y1) {
            for x in x0..<max(x0, x1) {
                total += 1
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(c.redComponent - target.redComponent) < tolerance,
                   abs(c.greenComponent - target.greenComponent) < tolerance,
                   abs(c.blueComponent - target.blueComponent) < tolerance {
                    count += 1
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        let box = maxX >= 0 ? NSRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                                     width: CGFloat(maxX - minX + 1) / scale,
                                     height: CGFloat(maxY - minY + 1) / scale) : nil
        return (count, total, box)
    }

    /// Mittlere Farbsättigung eines Fensterbereichs (unterscheidet ein farbiges Logo vom grauen Platzhalter).
    static func saturation(_ w: NSWindow, in region: NSRect) -> Double {
        guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber),
                                                [.boundsIgnoreFraming, .bestResolution]) else { return -1 }
        let scale = CGFloat(img.width) / w.frame.width
        let rep = NSBitmapImageRep(cgImage: img)
        let x0 = max(0, Int(region.minX * scale)), x1 = min(rep.pixelsWide, Int(region.maxX * scale))
        let y0 = max(0, Int(region.minY * scale)), y1 = min(rep.pixelsHigh, Int(region.maxY * scale))
        var sum = 0.0, n = 0.0
        for y in y0..<max(y0, y1) {
            for x in x0..<max(x0, x1) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let maxC = max(c.redComponent, max(c.greenComponent, c.blueComponent))
                let minC = min(c.redComponent, min(c.greenComponent, c.blueComponent))
                sum += maxC - minC
                n += 1
            }
        }
        return n > 0 ? sum / n : -1
    }

    /// Kontrastverhältnis nach WCAG zweier Farben.
    static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        func lum(_ c: NSColor) -> Double {
            guard let s = c.usingColorSpace(.sRGB) else { return 0 }
            func f(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * f(s.redComponent) + 0.7152 * f(s.greenComponent) + 0.0722 * f(s.blueComponent)
        }
        let l1 = lum(a), l2 = lum(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}

@MainActor
enum B04AX {
    static func obj(_ e: NSObject, _ name: String) -> Any? {
        let sel = NSSelectorFromString(name)
        guard e.responds(to: sel) else { return nil }
        return e.perform(sel)?.takeUnretainedValue()
    }

    static func text(_ e: NSObject, _ name: String) -> String {
        let v = obj(e, name)
        if let s = v as? String { return s }
        if let a = v as? NSAttributedString { return a.string }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    static func frame(_ e: NSObject) -> NSRect {
        let sel = NSSelectorFromString("accessibilityFrame")
        guard e.responds(to: sel), let imp = e.method(for: sel) else { return .zero }
        typealias F = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(imp, to: F.self)(e, sel)
    }

    static func bool(_ e: NSObject, _ name: String) -> Bool? {
        let sel = NSSelectorFromString(name)
        guard e.responds(to: sel), let imp = e.method(for: sel) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(imp, to: F.self)(e, sel)
    }

    static func role(_ e: NSObject) -> String { text(e, "accessibilityRole") }

    static func label(_ e: NSObject) -> String {
        [text(e, "accessibilityLabel"), text(e, "accessibilityTitle"), text(e, "accessibilityValue")]
            .filter { !$0.isEmpty }.joined(separator: " | ")
    }

    static func kids(_ e: NSObject) -> [NSObject] {
        (obj(e, "accessibilityChildren") as? [Any] ?? []).compactMap { $0 as? NSObject }
    }

    static func all(_ root: NSObject, depth: Int = 0) -> [NSObject] {
        guard depth < 60 else { return [] }
        return [root] + kids(root).flatMap { all($0, depth: depth + 1) }
    }

    @discardableResult
    static func press(_ e: NSObject) -> Bool {
        bool(e, "accessibilityPerformPress") ?? false
    }

    static func describe(_ root: NSObject) -> [String] {
        var out: [String] = []
        func walk(_ e: NSObject, _ d: Int) {
            guard d < 60 else { return }
            let f = frame(e)
            var extra = ""
            if let sel = bool(e, "isAccessibilitySelected"), sel { extra += " selected" }
            let v = text(e, "accessibilityValue")
            if !v.isEmpty { extra += " value=\(v)" }
            let h = text(e, "accessibilityRoleDescription")
            out.append("\(String(repeating: " ", count: d))\(role(e)) [\(h)] \"\(label(e))\"\(extra) @\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))")
            for k in kids(e) { walk(k, d + 1) }
        }
        walk(root, 0)
        return out
    }

    static func views<T: NSView>(_ root: NSView, of type: T.Type) -> [T] {
        var out: [T] = []
        func walk(_ v: NSView) {
            if let t = v as? T { out.append(t) }
            v.subviews.forEach(walk)
        }
        walk(root)
        return out
    }

    static func firstSearchField(_ v: NSView) -> NSSearchField? {
        if let s = v as? NSSearchField { return s }
        for sub in v.subviews { if let f = firstSearchField(sub) { return f } }
        return nil
    }
}

// MARK: - Bilder für Logo-Antworten

enum B04Image {
    private static func chunk(_ type: String, _ data: Data) -> Data {
        var out = Data()
        var len = UInt32(data.count).bigEndian
        out.append(Data(bytes: &len, count: 4))
        let typeData = Data(type.utf8)
        out.append(typeData)
        out.append(data)
        var crc = crc32(0, nil, 0)
        (typeData + data).withUnsafeBytes { crc = crc32(crc, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) }
        var crcBE = UInt32(crc).bigEndian
        out.append(Data(bytes: &crcBE, count: 4))
        return out
    }

    private static func png(width: Int, height: Int, idat: Data) -> Data {
        var header = Data()
        for v in [UInt32(width), UInt32(height)] {
            var be = v.bigEndian
            header.append(Data(bytes: &be, count: 4))
        }
        header.append(contentsOf: [8, 2, 0, 0, 0]) // 8 Bit, RGB
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            + chunk("IHDR", header) + chunk("IDAT", idat) + chunk("IEND", Data())
    }

    /// Einfarbiges PNG; die Zeilen werden gestreamt komprimiert (12.000 × 12.000 px ergibt < 1 MB Datei,
    /// dekodiert aber 432 MB RGB bzw. 576 MB RGBA).
    static func solid(width: Int, height: Int, rgb: (UInt8, UInt8, UInt8) = (220, 60, 60)) -> Data {
        var row = [UInt8](repeating: 0, count: 1 + width * 3)
        for x in 0..<width {
            row[1 + x * 3] = rgb.0
            row[2 + x * 3] = rgb.1
            row[3 + x * 3] = rgb.2
        }
        var stream = z_stream()
        deflateInit_(&stream, 9, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
        var out = Data()
        let bufSize = 1 << 16
        var buffer = [UInt8](repeating: 0, count: bufSize)
        func pump(flush: Int32) {
            repeat {
                buffer.withUnsafeMutableBufferPointer { b in
                    stream.next_out = b.baseAddress
                    stream.avail_out = uInt(bufSize)
                    deflate(&stream, flush)
                    out.append(b.baseAddress!, count: bufSize - Int(stream.avail_out))
                }
            } while stream.avail_out == 0
        }
        row.withUnsafeMutableBufferPointer { r in
            for _ in 0..<height {
                stream.next_in = r.baseAddress
                stream.avail_in = uInt(r.count)
                pump(flush: Z_NO_FLUSH)
            }
        }
        stream.next_in = nil
        stream.avail_in = 0
        pump(flush: Z_FINISH)
        deflateEnd(&stream)
        return png(width: width, height: height, idat: out)
    }

    /// PNG aus Zufallsrauschen, praktisch unkomprimierbar (3.000 × 3.000 px ≈ 27 MB Datei).
    static func noise(width: Int, height: Int) -> Data {
        var raw = Data(count: (1 + width * 3) * height)
        raw.withUnsafeMutableBytes { p in
            arc4random_buf(p.baseAddress!, p.count)
            for y in 0..<height { p[y * (1 + width * 3)] = 0 }
        }
        var destLen = compressBound(uLong(raw.count))
        var dest = Data(count: Int(destLen))
        dest.withUnsafeMutableBytes { d in
            raw.withUnsafeBytes { s in
                _ = compress2(d.bindMemory(to: Bytef.self).baseAddress, &destLen,
                              s.bindMemory(to: Bytef.self).baseAddress, uLong(raw.count), 0)
            }
        }
        return png(width: width, height: height, idat: dest.prefix(Int(destLen)))
    }

    static let small = solid(width: 64, height: 64)
}

// MARK: - Logo-Host (Mock)

/// Lokaler HTTP-Server für Logo-Adressen, nur auf 127.0.0.1. Schreibt jede Anfrage mit (Anfragezeile und
/// Kopfzeilen, wie sie über TCP ankamen) und bemerkt, wenn die App eine Verbindung vor oder während der Antwort
/// schließt.
final class B04LogoHost: @unchecked Sendable {
    struct Request: Sendable {
        let id: Int
        let time: Date
        let target: String
        let path: String
        let headers: [String: String]
        let rawHead: String
    }

    struct Event: Sendable {
        let id: Int
        let time: Date
        let target: String
        /// `served`, `closedBeforeResponse`, `closedDuringBody`, `trickleEnd`
        let kind: String
        let detail: String
    }

    indirect enum Reply {
        case body(status: Int, contentType: String, body: Data, headers: [String: String])
        case redirect(String)
        case delayed(TimeInterval, Reply)
        case hang
        /// Kopfzeilen sofort, danach je `interval` Sekunden ein Byte
        case trickle(Data, interval: TimeInterval)

        static func image(_ data: Data, headers: [String: String] = [:]) -> Reply {
            .body(status: 200, contentType: "image/png", body: data, headers: headers)
        }
    }

    private final class Conn {
        let id: Int
        let connection: NWConnection
        var target = ""
        var responded = false
        var closedLogged = false
        init(id: Int, connection: NWConnection) { self.id = id; self.connection = connection }
    }

    private let queue = DispatchQueue(label: "b04.logohost")
    private let lock = NSLock()
    private var listener: NWListener?
    private var conns: [Int: Conn] = [:]
    private var nextID = 0
    private var _requests: [Request] = []
    private var _events: [Event] = []
    private let handler: @Sendable (String) -> Reply
    private(set) var port: UInt16 = 0

    init(handler: @escaping @Sendable (String) -> Reply) {
        self.handler = handler
    }

    var requests: [Request] { lock.withLock { _requests } }
    var events: [Event] { lock.withLock { _events } }
    var base: String { "http://127.0.0.1:\(port)" }
    /// Derselbe Server unter anderem Host-Namen (für „fremder Host“).
    var altBase: String { "http://localhost:\(port)" }

    func requests(_ contains: String) -> [Request] { requests.filter { $0.target.contains(contains) } }
    func events(_ contains: String, kind: String? = nil) -> [Event] {
        events.filter { $0.target.contains(contains) && (kind == nil || $0.kind == kind) }
    }
    func resetLog() { lock.withLock { _requests.removeAll(); _events.removeAll() } }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params)
        let ready = DispatchSemaphore(value: 0)
        l.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
            if case .failed = state { ready.signal() }
        }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        listener = l
        port = l.port?.rawValue ?? 0
        guard port != 0 else { throw NSError(domain: "B04LogoHost", code: 1) }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        let all = lock.withLock { () -> [Conn] in let c = Array(conns.values); conns.removeAll(); return c }
        all.forEach { $0.connection.cancel() }
    }

    /// Entfernt alle Plattencache-Einträge dieses Mocks (beide Host-Namen).
    func purgeCache() {
        for r in requests {
            for b in [base, altBase] {
                if let url = URL(string: b + r.target) {
                    URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
                }
            }
        }
    }

    private func accept(_ c: NWConnection) {
        let conn = lock.withLock { () -> Conn in
            nextID += 1
            let st = Conn(id: nextID, connection: c)
            conns[st.id] = st
            return st
        }
        c.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.closed(conn, "state")
            default: break
            }
        }
        c.start(queue: queue)
        receive(conn, Data())
    }

    private func receive(_ conn: Conn, _ buffer: Data) {
        conn.connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                self.handle(conn, head: buf.subdata(in: buf.startIndex..<end.lowerBound))
            } else if complete || error != nil {
                self.closed(conn, "eof")
            } else {
                self.receive(conn, buf)
            }
        }
    }

    private func watchEOF(_ conn: Conn) {
        conn.connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] data, _, complete, error in
            guard let self else { return }
            if complete || error != nil || data == nil {
                self.closed(conn, error.map { "\($0)" } ?? "eof")
            } else {
                self.watchEOF(conn)
            }
        }
    }

    private func closed(_ conn: Conn, _ reason: String) {
        let log = lock.withLock { () -> Bool in
            guard !conn.closedLogged else { return false }
            conn.closedLogged = true
            conns.removeValue(forKey: conn.id)
            return !conn.responded && !conn.target.isEmpty
        }
        if log { record(conn, "closedBeforeResponse", reason) }
    }

    private func record(_ conn: Conn, _ kind: String, _ detail: String) {
        lock.withLock { _events.append(Event(id: conn.id, time: Date(), target: conn.target, kind: kind, detail: detail)) }
    }

    private func handle(_ conn: Conn, head: Data) {
        let text = String(decoding: head, as: UTF8.self)
        var lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.isEmpty ? "" : lines.removeFirst()
        let parts = requestLine.split(separator: " ").map(String.init)
        let target = parts.count > 1 ? parts[1] : ""
        var headers: [String: String] = [:]
        for line in lines {
            guard let i = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<i])] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
        lock.withLock {
            conn.target = target
            _requests.append(Request(id: conn.id, time: Date(), target: target, path: path, headers: headers, rawHead: text))
        }
        watchEOF(conn)
        respond(conn, handler(target))
    }

    private func respond(_ conn: Conn, _ reply: Reply) {
        switch reply {
        case .hang:
            return
        case .delayed(let seconds, let inner):
            queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self, self.lock.withLock({ !conn.closedLogged }) else { return }
                self.respond(conn, inner)
            }
        case .redirect(let location):
            send(conn, status: 302, contentType: "text/plain", body: Data(), headers: ["Location": location])
        case .body(let status, let contentType, let body, let headers):
            send(conn, status: status, contentType: contentType, body: body, headers: headers)
        case .trickle(let body, let interval):
            let head = "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            conn.connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
            trickle(conn, body, 0, interval, started: Date())
        }
    }

    private func trickle(_ conn: Conn, _ body: Data, _ offset: Int, _ interval: TimeInterval, started: Date) {
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self else { return }
            if self.lock.withLock({ conn.closedLogged }) {
                self.record(conn, "trickleEnd", "abgebrochen nach \(offset) Bytes, \(Int(Date().timeIntervalSince(started))) s")
                return
            }
            guard offset < body.count else {
                self.lock.withLock { conn.responded = true }
                self.record(conn, "trickleEnd", "vollständig")
                conn.connection.cancel()
                return
            }
            conn.connection.send(content: body.subdata(in: offset..<(offset + 1)), completion: .contentProcessed { _ in })
            self.trickle(conn, body, offset + 1, interval, started: started)
        }
    }

    private func send(_ conn: Conn, status: Int, contentType: String, body: Data, headers: [String: String]) {
        var head = "HTTP/1.1 \(status) Mock\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        lock.withLock { conn.responded = true }
        conn.connection.send(content: data, completion: .contentProcessed { [weak self] error in
            self?.record(conn, "served", "status=\(status) bytes=\(body.count)\(error.map { " fehler=\($0)" } ?? "")")
            conn.connection.cancel()
        })
    }
}

/// Basisklasse: Logo-Host je Test, Temp-Ordner, Fenster; räumt Cache-Einträge des Mocks und Fenster auf.
@MainActor
class B04TestCase: XCTestCase {
    var host: B04LogoHost!
    var windows: [B04Window] = []
    var dirs: [URL] = []

    /// Standardverhalten des Logo-Hosts; Tests können `route` überschreiben, bevor sie Anfragen auslösen.
    nonisolated(unsafe) static var routes: [String: B04LogoHost.Reply] = [:]

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
        host = B04LogoHost { target in
            B04TestCase.reply(for: target)
        }
        try host.start()
    }

    override func tearDown() {
        for w in windows { w.close() }
        windows = []
        B04QA.spin(0.3)
        if let host {
            host.purgeCache()
            host.stop()
        }
        host = nil
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        dirs = []
        super.tearDown()
    }

    func window(_ c: ModelContainer, size: CGSize = CGSize(width: 900, height: 700),
                origin: CGPoint = CGPoint(x: 60, y: 60), appearance: NSAppearance.Name? = nil,
                forceActive: Bool = false, controlState: ControlActiveState? = nil) -> B04Window {
        let w = B04Window(c, size: size, origin: origin, appearance: appearance, forceActive: forceActive,
                          controlState: controlState)
        windows.append(w)
        return w
    }

    func fileContainer(_ label: String) throws -> (ModelContainer, URL) {
        let r = try B04QA.fileContainer(label)
        dirs.append(r.dir)
        return (r.container, r.store)
    }

    /// Antworten des Logo-Hosts nach Pfad-Präfix.
    nonisolated static func reply(for target: String) -> B04LogoHost.Reply {
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
        let query = target.contains("?") ? String(target.split(separator: "?", maxSplits: 1)[1]) : ""
        func q(_ key: String) -> String? {
            for pair in query.components(separatedBy: "&") {
                let kv: [String] = pair.components(separatedBy: "=")
                if kv.count > 1, kv[0] == key { return kv[1] }
            }
            return nil
        }
        let delay = q("d").flatMap(Double.init) ?? 0
        let reply: B04LogoHost.Reply
        if path.hasPrefix("/maxage/") {
            reply = .image(B04Image.small, headers: ["Cache-Control": "public, max-age=86400"])
        } else if path.hasPrefix("/nocache/") || path.hasPrefix("/logo/") {
            reply = .image(B04Image.small)
        } else if path.hasPrefix("/nostore/") {
            reply = .image(B04Image.small, headers: ["Cache-Control": "no-store"])
        } else if path.hasPrefix("/html-as-png") {
            reply = .body(status: 200, contentType: "image/png", body: Data("<html><body>kein Bild</body></html>".utf8), headers: [:])
        } else if path.hasPrefix("/html") {
            reply = .body(status: 200, contentType: "text/html; charset=utf-8", body: Data("<html><body>kein Bild</body></html>".utf8), headers: [:])
        } else if path.hasPrefix("/json") {
            reply = .body(status: 200, contentType: "application/json", body: Data("{\"x\":1}".utf8), headers: [:])
        } else if path.hasPrefix("/404") {
            reply = .body(status: 404, contentType: "text/plain", body: Data("not found".utf8), headers: [:])
        } else if path.hasPrefix("/redirect-loop") {
            reply = .redirect(target)
        } else if path.hasPrefix("/redirect") {
            reply = .redirect(q("to")?.removingPercentEncoding ?? "/nocache/ziel.png")
        } else if path.hasPrefix("/bigdim") {
            reply = .image(B04Image.bigDimension, headers: ["Cache-Control": "public, max-age=86400"])
        } else if path.hasPrefix("/bigfile") {
            reply = .image(B04Image.bigFile, headers: ["Cache-Control": "public, max-age=86400"])
        } else if path.hasPrefix("/hang") {
            reply = .hang
        } else if path.hasPrefix("/trickle") {
            reply = .trickle(B04Image.small, interval: q("i").flatMap(Double.init) ?? 10)
        } else if let custom = routes.first(where: { path.hasPrefix($0.key) })?.value {
            reply = custom
        } else {
            reply = .body(status: 404, contentType: "text/plain", body: Data("unbekannt".utf8), headers: [:])
        }
        return delay > 0 ? .delayed(delay, reply) : reply
    }
}

extension B04Image {
    /// 12.000 × 12.000 px, Datei < 1 MB
    static let bigDimension = solid(width: 12_000, height: 12_000, rgb: (60, 160, 60))
    /// 3.000 × 3.000 px Rauschen, ≈ 27 MB
    static let bigFile = noise(width: 3_000, height: 3_000)
}
