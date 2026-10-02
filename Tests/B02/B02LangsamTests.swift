import XCTest
import SwiftData
@testable import MikaPlusPlayer

/// B02 · M3U-Import — lange Läufe: Leerlaufgrenze, `ftp://`, tröpfelnde Antwort (gleichzeitig, ≈ 100 s) und die
/// Stillstandsmessung großer Listen (AK-40). Größen über `TEST_RUNNER_B02_QA_SIZES` (Standard 1500,3000,6000).
final class B02LangsamTests: B02TestCase {

    // MARK: AK-12 (ftp) · AK-28 (Leerlauf) · AK-38 (tröpfeln) · EC-17

    /// AK-28: 60 s ohne Daten → „The request timed out.". AK-12/EC-17: `ftp://` ohne Benutzerinfo → Wartezeit bis zur
    /// Leerlaufgrenze, dann „timed out". AK-38 ⚠ / BUG-03: 20 Sender in 10 Stücken alle 10 s (≈ 100 s) werden importiert —
    /// keine Gesamtfrist. Alle drei laufen gleichzeitig.
    @MainActor func testAK12_AK28_AK38_EC17_LeerlaufFtpUndTroepfeln() async throws {
        let c = try B02.memory()
        let ctx = c.mainContext
        var s = "#EXTM3U\n"
        for i in 0..<20 { s += "#EXTINF:-1 tvg-id=\"t\(i)\" group-title=\"Langsam\",Tröpfel \(i)\n\(B02.dead)/live/\(i).ts\n" }
        let body = Data(s.utf8)
        let head = Data("HTTP/1.1 200 OK\r\nContent-Type: audio/x-mpegurl\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        server.handler = { req in
            req.path == "/haengt.m3u" ? .hang : .trickle(head: head, body: body, chunks: 10, interval: 10)
        }
        let ftpTarget = try extraServer { _ in .hang }

        @Sendable @MainActor func timed(_ input: String) async -> (String, TimeInterval) {
            let t = Date()
            let r = await B02.importURL(input, ctx)
            return (B02.message(r) ?? "OK (\((try? r.get())?.channelCount ?? 0) Sender)", Date().timeIntervalSince(t))
        }
        async let haengt = timed(server.url("/haengt.m3u"))
        async let troepfelt = timed(server.url("/troepfelt.m3u"))
        async let ftp = timed("ftp://127.0.0.1:\(ftpTarget.port)/liste.m3u")
        let (h, t, f) = await (haengt, troepfelt, ftp)
        B02.evidence("AK-40-messung.txt", "AK-28|haengt|dauer=\(B02.f2(h.1))s|\(h.0)")
        B02.evidence("AK-40-messung.txt", "AK-38|troepfelt-10x10s|bytes=\(body.count)|dauer=\(B02.f2(t.1))s|\(t.0)")
        B02.evidence("AK-40-messung.txt", "AK-12/EC-17|ftp|dauer=\(B02.f2(f.1))s|\(f.0)|verbindungenAmZiel=\(ftpTarget.connectionCount)|anfragenAmZiel=\(ftpTarget.requests.count)")
        XCTAssertEqual(SystemSprache.englisch(h.0), "Netzwerkfehler: The request timed out.")  // B09 · OF-01: Systemtext englisch oder deutsch
        XCTAssertEqual(h.1, 60, accuracy: 3)
        XCTAssertEqual(SystemSprache.englisch(f.0), "Netzwerkfehler: The request timed out.")
        XCTAssertEqual(f.1, 60, accuracy: 5)
        // BUG-03 behoben: Nach der Anlaufzeit gilt ein Mindestdurchsatz (dazu eine Gesamtfrist von 180 s) – die
        // tröpfelnde Antwort hält den Import nicht mehr offen.
        XCTAssertEqual(t.0, "Netzwerkfehler: Der Server liefert die Playlist zu langsam.")
        XCTAssertLessThan(t.1, 60)
    }

    // MARK: AK-40 · BUG-04

    /// AK-40 ⚠ / BUG-04: Stillstand des Main-Threads und Gesamtdauer beim URL-Import großer Listen (in-memory) und für eine
    /// Größe zusätzlich mit Store-Datei. Wachstum doppelte Menge → Zeitfaktor.
    @MainActor func testAK40_GrosseListeBlockiertMainThread() async throws {
        let env = ProcessInfo.processInfo.environment
        let sizes = (env["B02_QA_SIZES"] ?? "1500,3000,6000").split(separator: ",").compactMap { Int($0) }
        let storeSizes = Set((env["B02_QA_STORE_SIZES"] ?? "6000").split(separator: ",").compactMap { Int($0) })
        var totals: [Int: TimeInterval] = [:]
        var gaps: [Int: TimeInterval] = [:]
        for n in sizes {
            let data = B02.grosseListe(n, tag: "")
            server.handler = { _ in B02Server.ok(data) }
            for variant in storeSizes.contains(n) ? ["inMemory", "storeDatei"] : ["inMemory"] {
                let container: ModelContainer
                if variant == "inMemory" {
                    container = try B02.memory()
                } else {
                    container = try B02.fileContainer(in: try tempDir("ak40-\(n)")).0
                }
                let watchdog = MainThreadWatchdog(); watchdog.start()
                let t = Date()
                let p = try await B02.importURL(server.url("/gross-\(n).m3u"), container.mainContext).get()
                let elapsed = Date().timeIntervalSince(t)
                try await Task.sleep(nanoseconds: 300_000_000)
                let gap = watchdog.stop()
                let pid = p.id
                let stored = try container.mainContext.fetchCount(FetchDescriptor<Channel>(predicate: #Predicate { $0.playlistID == pid }))
                B02.evidence("AK-40-messung.txt", "AK-40|\(variant)|sender=\(n)|bytes=\(data.count)|gesamt=\(B02.f2(elapsed))s|maxMainThreadBlockade=\(B02.f2(gap))s|playlistID=\(stored)|beziehung=\(p.channels.count)|build=\(B02.buildConfiguration)|cpuKerne=\(ProcessInfo.processInfo.activeProcessorCount)|last=\(Self.loadAverage())")
                XCTAssertEqual(p.channelCount, n)
                XCTAssertEqual(stored, n)
                if variant == "inMemory" { totals[n] = elapsed; gaps[n] = gap }
            }
        }
        if let t3 = totals[3_000], let t6 = totals[6_000] {
            B02.evidence("AK-40-messung.txt", "AK-40|wachstum 3000→6000 Faktor=\(B02.f2(t6 / t3))|build=\(B02.buildConfiguration)")
        }
        let worst = gaps.values.max() ?? 0
        // BUG-04 behoben: Abruf, Parsen und Speichern laufen abseits des Main-Actors (`PlaylistStore`).
        B02.evidence("AK-40-messung.txt", "AK-40|laengsteBlockade=\(B02.f2(worst))s|build=\(B02.buildConfiguration)")
        XCTAssertLessThan(worst, 0.5, "längste Blockade \(B02.f2(worst)) s")
    }

    static func loadAverage() -> String {
        var l = [Double](repeating: 0, count: 3)
        return getloadavg(&l, 3) == 3 ? l.map { String(format: "%.1f", $0) }.joined(separator: "/") : "-"
    }
}
