import XCTest
import SwiftUI
import SwiftData
import AppKit
import OSLog
@testable import MikaPlusPlayer

/// B05 · Datenschutz und Missbrauchsschutz (AK-22 bis AK-27, Angriffe 2, 4, 5).
@MainActor
final class B05DatenschutzTests: B05TestCase {

    typealias E = B05QA.E

    // MARK: AK-22 · AK-23 · AK-24 · Angriff 2

    func testAK22_AK23_AK24_SpeicherortRechteBackupFremderProzess() throws {
        let realSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appPath = AppPersistence.storeURL(applicationSupport: realSupport, bundleID: "lu.daumedia.MikaPlusPlayer").path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
        XCTAssertEqual(appPath, "~/Library/Application Support/lu.daumedia.MikaPlusPlayer/MikaPlusPlayer.store")

        // Pfadbildung und Anlage über die Funktionen der App in einem Probeordner
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("b05-qa-ak22-\(UUID().uuidString)/Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        dirs.append(support.deletingLastPathComponent())
        let (storeURL, outcome) = AppPersistence.prepareStore(applicationSupport: support, bundleID: "lu.daumedia.MikaPlusPlayer")
        let c = try AppPersistence.diskContainer(at: storeURL, schema: AppSchema.schema)
        try seed(c.mainContext, name: "B05ORT Playlist", [("B05ORT Favorit", nil, nil, true, nil), ("B05ORT Kein", nil, nil, false, nil)])

        var lines: [String] = ["app-pfad-macos=\(appPath)", "outcome=\(outcome)"]
        for f in [storeURL.path, storeURL.path + "-wal", storeURL.path + "-shm", storeURL.deletingLastPathComponent().path] {
            let attrs = try? FileManager.default.attributesOfItem(atPath: f)
            let perm = (attrs?[.posixPermissions] as? NSNumber).map { String($0.intValue, radix: 8) } ?? "-"
            let excluded = try? URL(fileURLWithPath: f).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
            lines.append("\(f.replacingOccurrences(of: support.path, with: "<probe>/Application Support"))|rechte=\(perm)|isExcludedFromBackup=\(excluded.map { String($0) } ?? "nil")")
            if f.hasSuffix(".store") {
                XCTAssertEqual(perm, "644")
                XCTAssertEqual(excluded, false, "AK-23: nicht vom Backup ausgeschlossen")
            }
        }
        XCTAssertEqual(outcome, .noLegacyStore)
        let libPerm = (try? FileManager.default.attributesOfItem(atPath: NSHomeDirectory() + "/Library")[.posixPermissions] as? NSNumber)
            .map { String($0.intValue, radix: 8) } ?? "-"
        lines.append("~/Library rechte=\(libPerm) (nur Metadaten gelesen)")
        XCTAssertEqual(libPerm, "700", "andere Benutzer haben keinen Zugriff")

        // Favoriten stehen nicht in den Einstellungen (Domäne des Test-Hosts)
        let defaultsHit = UserDefaults.standard.dictionaryRepresentation().contains { "\($0.key) \($0.value)".contains("B05ORT") }
        lines.append("userdefaults-treffer=\(defaultsHit)")
        XCTAssertFalse(defaultsHit)

        // AK-24: ein anderer Prozess desselben Benutzers liest die Favoriten
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = ["-readonly", storeURL.path, "SELECT ZNAME FROM ZCHANNEL WHERE ZISFAVORITE = 1;"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("fremder-prozess /usr/bin/sqlite3 (pid \(p.processIdentifier))|status=\(p.terminationStatus)|ausgabe=\(out)")
        XCTAssertEqual(out, "B05ORT Favorit")
        for l in lines { B05QA.evidence("AK-22-24-speicherort.txt", l) }
    }

    // MARK: EC-06

    /// Erster Start nach dem Update mit alter `default.store`: Übernahme über `AppPersistence.prepareStore` behält die Favoriten.
    func testEC06_UebernahmeDerAltenDatenbankBehaeltFavoriten() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("b05-qa-ec06-\(UUID().uuidString)/Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        dirs.append(support.deletingLastPathComponent())
        let legacy = support.appendingPathComponent("default.store")
        do {
            let old = try AppPersistence.diskContainer(at: legacy, schema: AppSchema.schema)
            try seed(old.mainContext, name: "QA Alt", [("Alt Favorit", "News", "alt.de", true, nil), ("Alt Kein", nil, nil, false, nil),
                                                    ("Alt Zwei", nil, nil, true, nil)])
        }
        B05QA.spin(0.5)
        let (storeURL, outcome) = AppPersistence.prepareStore(applicationSupport: support, bundleID: "lu.daumedia.MikaPlusPlayer")
        let c = try AppPersistence.diskContainer(at: storeURL, schema: AppSchema.schema)
        let favs = try B05QA.favLabels(c.mainContext)
        B05QA.evidence("EC-06-uebernahme.txt", "outcome=\(outcome)|alte datei noch da=\(FileManager.default.fileExists(atPath: legacy.path))|favoriten=\(favs)")
        XCTAssertEqual(outcome, .adopted)
        XCTAssertEqual(favs, ["Alt Favorit@QA Alt", "Alt Zwei@QA Alt"])
    }

    // MARK: AK-25 · Angriff 5 · FB-03

    func testAK25_Angriff5_TabFragtGenauDieLogosDerFavoritenAn() throws {
        let png = NSBitmapImageRep(data: NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in
            NSColor.systemGreen.setFill(); r.fill(); return true
        }.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        for i in 0..<20 { routes.setReply("/logos/sender-\(i).png", .raw(status: 200, contentType: "image/png", body: png)) }
        let c = try B05QA.memoryContainer()
        let favs: Set<Int> = [3, 11, 17]
        let items = (0..<20).map { i in
            (name: "Logo Sender \(String(format: "%02d", i))", group: Optional(i == 11 ? "Religion" : "Allgemein"), tvg: String?.none,
             fav: favs.contains(i), logo: Optional(url("/logos/sender-\(i).png")))
        }
        let pl = try seed(c.mainContext, name: "QA Logos", items)
        mock.resetLog()

        let tab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 620))
        B05QA.wait(3.0) { self.mock.requests.count >= 3 }
        B05QA.spin(1.0)
        let reqs = mock.requests
        let paths = reqs.map(\.path).sorted()
        tab.shot("AK-25-favoriten-mit-logos")
        B05QA.evidence("AK-25-logo-anfragen.txt", "tab-geoeffnet|anfragen=\(reqs.count)|pfade=\(paths)")
        for r in reqs.prefix(1) {
            B05QA.evidence("AK-25-logo-anfragen.txt", "payload|\(r.requestLine)|" + r.headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: " · "))
        }
        XCTAssertEqual(paths, ["/logos/sender-11.png", "/logos/sender-17.png", "/logos/sender-3.png"])
        let h = reqs.first?.headers ?? [:]
        // Seit B04 · BUG-06 (Build 2026-09-29, gemeinsamer Logo-Loader für Senderliste und Tab): neutrale Kopfzeilen,
        // kein App-Name, kein Build, keine Systemversion, keine Systemsprache.
        XCTAssertEqual(h["user-agent"], "Mozilla/5.0", "\(h)")
        XCTAssertEqual(h["accept-language"], "*", "\(h)")
        XCTAssertNil(h["cookie"])
        XCTAssertNil(h["referer"])

        // Erneutes Öffnen des Tabs
        tab.close()
        B05QA.spin(0.5)
        mock.resetLog()
        let tab2 = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 620))
        B05QA.spin(3.0)
        let again = mock.requests.map(\.path).sorted()
        B05QA.evidence("AK-25-logo-anfragen.txt", "tab-erneut-geoeffnet|anfragen=\(again.count)|pfade=\(again)")
        _ = tab2

        // Zum Vergleich: die Senderliste fragt alle sichtbaren Logos an, nicht nur die Favoriten
        mock.resetLog()
        let list = window(NavigationStack { ChannelListView(playlist: pl) }, c, size: CGSize(width: 760, height: 900), origin: CGPoint(x: 860, y: 0))
        B05QA.spin(3.0)
        B05QA.evidence("AK-25-logo-anfragen.txt", "vergleich-senderliste|anfragen=\(mock.requests.count)|sichtbare-karten=\(list.cards.count)")

        XCTExpectFailure("BUG-03: Der Favoriten-Tab verrät die Favoritenliste an Logo-Hosts (widerspricht FAQ „Nowhere“)") {
            XCTAssertTrue(paths.isEmpty, "Logo-Host erhält genau die Favoriten: \(paths)")
        }
    }

    // MARK: AK-26 · Angriff 4

    func testAK26_Angriff4_KeineSendernamenImSystemprotokoll() async throws {
        let start = Date()
        let (c, _) = try fileContainer("ak26")
        let ctx = c.mainContext
        let path = "/b05/log.m3u"
        let es: [E] = [E(name: "B05LOGMARKER Kanal", tvg: "b05logmarker.tvg", url: B05QA.stream(1), group: "B05LOGGRUPPE"),
                       E(name: "B05LOGMARKER Zwei", url: B05QA.stream(2))]
        let pl = try await importM3U(ctx, path: path, name: "B05LOGPLAYLIST", es)
        let list = window(NavigationStack { ChannelListView(playlist: pl) }, c, size: CGSize(width: 700, height: 360))
        let tab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 700, height: 360), origin: CGPoint(x: 780, y: 60))
        var states: [String] = []
        for i in 0..<6 {
            list.clickStar("B05LOGMARKER Kanal", wait: 0.8)
            states.append("klick\(i)=\(pl.channels.first { $0.name == "B05LOGMARKER Kanal" }?.isFavorite ?? false)/tab=\(tab.cardLabels.count)")
        }
        try B05QA.setFavorite(pl, "B05LOGMARKER Kanal", ctx: ctx)
        try await refreshM3U(ctx, pl, path: path, es)
        try await PlaylistImporter(modelContext: ctx).delete(pl)
        B05QA.spin(1.0)

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(at: store.position(date: start)).compactMap { $0 as? OSLogEntryLog }
        let markers = ["B05LOGMARKER", "B05LOGPLAYLIST", "b05logmarker.tvg", "B05LOGGRUPPE"]
        let hits = entries.filter { e in markers.contains { e.composedMessage.contains($0) } }
        let favLines = entries.filter { $0.composedMessage.localizedCaseInsensitiveContains("favorit") || $0.composedMessage.contains("ZISFAVORITE") }
        B05QA.evidence("AK-26-protokoll.txt", "pid=\(ProcessInfo.processInfo.processIdentifier)|start=\(ISO8601DateFormatter().string(from: start))|eintraege=\(entries.count)|marker-treffer=\(hits.count)|favorit-zeilen=\(favLines.count)|zustaende=\(states)")
        for e in (hits + favLines).prefix(10) {
            B05QA.evidence("AK-26-protokoll.txt", "zeile|\(e.subsystem)|\(e.category)|\(e.composedMessage.prefix(200))")
        }
        XCTAssertEqual(hits.count, 0)
    }

    // MARK: AK-27 · FB-02

    /// Braucht ein vollschreibbares, eingehängtes Datenträgerabbild (`TEST_RUNNER_B05_FULL_VOLUME=<Mountpoint>`).
    func testAK27_SpeicherfehlerBeimUmschaltenWirdVerschluckt() throws {
        guard let volPath = B05QA.env("B05_FULL_VOLUME"), FileManager.default.fileExists(atPath: volPath) else {
            throw XCTSkip("kein Datenträgerabbild (TEST_RUNNER_B05_FULL_VOLUME)")
        }
        let start = Date()
        let vol = URL(fileURLWithPath: volPath)
        let filler = vol.appendingPathComponent("filler")
        try? FileManager.default.removeItem(at: filler)
        let dir = vol.appendingPathComponent("ak27-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: filler); try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("MikaPlusPlayer.store")
        let c = try AppPersistence.diskContainer(at: store, schema: AppSchema.schema)
        let ctx = c.mainContext
        let pl = try seed(ctx, name: "QA Voll", [("Voll Eins", nil, nil, false, nil), ("Voll Zwei", nil, nil, false, nil), ("Voll Drei", nil, nil, false, nil)])
        let list = window(NavigationStack { ChannelListView(playlist: pl) }, c, size: CGSize(width: 700, height: 420))
        let tab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 700, height: 420), origin: CGPoint(x: 780, y: 60))

        func fill() -> Int {
            let fd = Darwin.open(filler.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
            var total = 0
            for size in [1 << 20, 65_536, 4_096, 512, 1] {
                let buf = [UInt8](repeating: 0, count: size)
                while true {
                    let n = buf.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, size) }
                    if n <= 0 { break }
                    total += n
                }
            }
            Darwin.close(fd)
            return total
        }
        let filled = fill()
        let free = (try? vol.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity) ?? -1
        B05QA.evidence("AK-27-speicherfehler.txt", "volume gefüllt|bytes=\(filled)|frei=\(free)|autosave=\(ctx.autosaveEnabled)")

        // Stern drücken wie der Nutzer
        XCTAssertTrue(list.clickStar("Voll Zwei", wait: 0.8))
        let zwei = try XCTUnwrap(pl.channels.first { $0.name == "Voll Zwei" })
        let shown = tab.cardLabels
        let alerts = b05AlertWindows()
        let line1 = "nach-klick-voll|isFavorite=\(zwei.isFavorite)|hasChanges=\(ctx.hasChanges)|db=\(B05QA.dbFavorite(store, name: "Voll Zwei"))|stern=\(list.starColor("Voll Zwei"))|tab=\(shown)|alerts=\(alerts)"
        B05QA.evidence("AK-27-speicherfehler.txt", line1)
        list.shot("AK-27-speicher-voll-stern-gefuellt")
        tab.shot("AK-27-speicher-voll-favoriten-tab")
        XCTAssertTrue(zwei.isFavorite)
        XCTAssertEqual(B05QA.dbFavorite(store, name: "Voll Zwei"), "0", "nichts gespeichert")
        XCTAssertEqual(shown, ["Voll Zwei"])

        // Was `try?` verschluckt
        var saveError = "ok"
        do { try ctx.save() } catch { let ns = error as NSError; saveError = "\(ns.domain) \(ns.code) · \(ns.userInfo["NSSQLiteErrorDomain"] ?? "-")" }
        B05QA.evidence("AK-27-speicherfehler.txt", "expliziter-save|\(saveError)")

        // „Neustart“ bei weiterhin vollem Datenträger
        var restart = "-"
        do {
            let c2 = try B05QA.reopen(store)
            restart = try B05QA.tabQuery(c2.mainContext).map(\.name).description
        } catch { restart = "fehler: \(error.localizedDescription)" }
        B05QA.evidence("AK-27-speicherfehler.txt", "neustart-voll|favoriten=\(restart)")

        // Automatisches Speichern, solange voll / nach dem Freigeben
        B05QA.spin(3.0)
        B05QA.evidence("AK-27-speicherfehler.txt", "3s-voll|db=\(B05QA.dbFavorite(store, name: "Voll Zwei"))|hasChanges=\(ctx.hasChanges)")
        try? FileManager.default.removeItem(at: filler)
        B05QA.spin(3.0)
        B05QA.evidence("AK-27-speicherfehler.txt", "3s-nach-freigabe|db=\(B05QA.dbFavorite(store, name: "Voll Zwei"))|hasChanges=\(ctx.hasChanges)")
        XCTAssertTrue(list.clickStar("Voll Drei", wait: 0.8))
        B05QA.evidence("AK-27-speicherfehler.txt", "weiterer-stern-mit-platz|dbZwei=\(B05QA.dbFavorite(store, name: "Voll Zwei"))|dbDrei=\(B05QA.dbFavorite(store, name: "Voll Drei"))|hasChanges=\(ctx.hasChanges)")

        // Entfernen im Tab bei vollem Datenträger: Karte verschwindet, kommt nach Neustart zurück
        _ = fill()
        XCTAssertTrue(tab.clickStar("Voll Drei", wait: 0.8))
        let drei = try XCTUnwrap(pl.channels.first { $0.name == "Voll Drei" })
        B05QA.evidence("AK-27-speicherfehler.txt", "entfernen-im-tab-voll|tab=\(tab.cardLabels)|isFavorite=\(drei.isFavorite)|db=\(B05QA.dbFavorite(store, name: "Voll Drei"))|alerts=\(b05AlertWindows())")
        var restart2 = "-"
        do { let c3 = try B05QA.reopen(store); restart2 = try B05QA.tabQuery(c3.mainContext).map(\.name).description } catch { restart2 = "fehler" }
        B05QA.evidence("AK-27-speicherfehler.txt", "neustart-nach-entfernen|favoriten=\(restart2)")
        try? FileManager.default.removeItem(at: filler)
        B05QA.spin(0.5)

        // Systemprotokoll: nur SwiftData/Core Data meldet den Fehler
        if let logStore = try? OSLogStore(scope: .currentProcessIdentifier),
           let pos = Optional(logStore.position(date: start)),
           let entries = try? logStore.getEntries(at: pos) {
            let lines = entries.compactMap { $0 as? OSLogEntryLog }.filter { $0.composedMessage.contains("save failed") || $0.composedMessage.contains("disk is full") }
            for l in lines.prefix(3) { B05QA.evidence("AK-27-speicherfehler.txt", "systemprotokoll|\(l.subsystem)|\(l.composedMessage.prefix(220))") }
            B05QA.evidence("AK-27-speicherfehler.txt", "systemprotokoll-zeilen=\(lines.count)")
        }

        XCTExpectFailure("BUG-02: Speicherfehler beim Umschalten wird verschluckt – Stern zeigt den neuen Zustand, nichts gespeichert, keine Meldung") {
            XCTAssertTrue(!zwei.isFavorite || !alerts.isEmpty || line1.contains("db=1"),
                          "erwartet: Zustand zurückgesetzt oder Meldung")
        }
    }
}
