import XCTest
import SwiftData
@testable import MikaPlusPlayer

/// B03 · Playlist-Verwaltung — Leistung von Aktualisieren und Löschen (AK-37, AK-38; QA Durchlauf 1, 2026-09-16).
///
/// Standard im normalen Testlauf: 1.000 und 2.000 Sender, M3U und Xtream. Messläufe über Umgebungsvariablen
/// (bei `xcodebuild` mit Präfix `TEST_RUNNER_`):
/// - `B03_SIZES=17000` · `B03_KINDS=xtream` · `B03_RESTART_DELETE=1` (zusätzlich: Löschen nach „Neustart“, Sender nicht im Speicher)
/// - `B03_EVIDENCE=1` schreibt jede Messung nach `features/B03-playlist-verwaltung/qa/AK-37-38-messung.txt`.
/// Main-Thread-Blockade per Wachhund (`DispatchQueue.main.async`-Latenz alle 20 ms).
final class B03LeistungTests: B03QATestCase {

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    private func record(_ line: String) {
        let full = "\(ISO8601DateFormatter().string(from: Date()))|\(B03QA.buildConfiguration)|\(line)"
        B03QA.log("AK-37-38|\(full)")
        if env["B03_EVIDENCE"] == "1" { B03QA.appendEvidence("AK-37-38-messung.txt", full) }
    }

    @MainActor private func makePlaylist(_ kind: String, _ n: Int, _ ctx: ModelContext) async throws -> (Playlist, TimeInterval) {
        let t0 = Date()
        var cfg = B03QAPanel()
        if kind == "m3u" {
            cfg.m3u = B03QA.m3u((0..<n).map { ("Sender \($0)", "s.\($0)", "Gruppe \($0 % 40)", "\(B03QA.dead)/\($0).m3u8") })
            mock.handler = cfg.handler()
            let p = try await PlaylistImporter(modelContext: ctx).importFromURL(m3uAddress, name: "QA Leistung")
            return (p, Date().timeIntervalSince(t0))
        }
        cfg.streams = B03QA.streams((0..<n).map { ("Sender \($0)", $0, "s.\($0)", $0 % 2 == 0 ? "1" : "2") }, logoPrefix: "\(B03QA.dead)/logo/")
        mock.handler = cfg.handler()
        let p = try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).importFromXtream(
            XtreamCredentials(host: mock.hostPort, username: "qa-user", password: "qa-pass-b03-perf"), output: .mpegts, name: "QA Leistung")
        return (p, Date().timeIntervalSince(t0))
    }

    /// Favoriten per Abfrage setzen (jeder 1.000. Sender), ohne die Beziehung in den Speicher zu laden.
    @MainActor private func markFavorites(_ p: Playlist, _ ctx: ModelContext) throws -> Int {
        let pid = p.id
        let all = try ctx.fetch(FetchDescriptor<Channel>(predicate: #Predicate { $0.playlistID == pid }))
        var n = 0
        for ch in all where (Int(ch.tvgID?.dropFirst(2) ?? "") ?? 1) % 1_000 == 0 { ch.isFavorite = true; n += 1 }
        try ctx.save()
        return n
    }

    @MainActor func testAK37_AK38_AktualisierenUndLoeschenBlockierenDenMainThread() async throws {
        let sizes = (env["B03_SIZES"] ?? "1000,2000").split(separator: ",").compactMap { Int($0) }
        let kinds = (env["B03_KINDS"] ?? "m3u,xtream").split(separator: ",").map(String.init)
        let load = ProcessInfo.processInfo.activeProcessorCount
        var refreshGaps: [String: [Int: TimeInterval]] = [:]
        var deleteGaps: [String: [Int: TimeInterval]] = [:]
        record("start|groessen=\(sizes)|arten=\(kinds)|kerne=\(load)|speicher=\(Int(B03QA.footprintMB()))MB")

        for kind in kinds {
            for n in sizes {
                let (container, url) = try fileContainer("perf-\(kind)-\(n)")
                let ctx = container.mainContext
                let (p, tImport) = try await makePlaylist(kind, n, ctx)
                let favs = try markFavorites(p, ctx)
                try await Task.sleep(nanoseconds: 500_000_000)

                // AK-37: Aktualisieren (Liste unverändert)
                let mem0 = B03QA.footprintMB()
                let wd = B03QAWatchdog(); wd.start()
                let t0 = Date()
                try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).refresh(p)
                let tRefresh = Date().timeIntervalSince(t0)
                try await Task.sleep(nanoseconds: 300_000_000)
                let gap = wd.stop()
                let mem1 = B03QA.footprintMB()
                let favAfter = try ctx.fetchCount(FetchDescriptor<Channel>(predicate: #Predicate { $0.isFavorite == true }))
                refreshGaps[kind, default: [:]][n] = gap
                record("\(kind)|sender=\(n)|import=\(B03QA.f2(tImport))s|aktualisieren=\(B03QA.f2(tRefresh))s|mainThreadBlockade=\(B03QA.f2(gap))s|speicher=\(Int(mem0))→\(Int(mem1))MB|favoriten=\(favs)→\(favAfter)|\(B03QA.dbSummary(url))")
                XCTAssertEqual(p.channelCount, n)
                XCTAssertEqual(favAfter, favs)

                // AK-38: Löschen nach dem Aktualisieren (Sender im Speicher)
                let wd2 = B03QAWatchdog(); wd2.start()
                let t1 = Date()
                try PlaylistImporter(modelContext: ctx).delete(p)
                let tDelete = Date().timeIntervalSince(t1)
                try await Task.sleep(nanoseconds: 300_000_000)
                let gap2 = wd2.stop()
                deleteGaps[kind, default: [:]][n] = gap2
                record("\(kind)|sender=\(n)|loeschenNachAktualisieren=\(B03QA.f2(tDelete))s|mainThreadBlockade=\(B03QA.f2(gap2))s|\(B03QA.dbSummary(url))")
                XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZCHANNEL"), 0)

                // AK-38: Löschen nach „Neustart“ (neuer Container, Sender nicht geladen) – wie Nutzer: App öffnen, löschen
                if env["B03_RESTART_DELETE"] == "1" || n <= 2_000 {
                    var storeURL: URL!
                    do {
                        let (c2, u2) = try fileContainer("perf-restart-\(kind)-\(n)")
                        storeURL = u2
                        let (p2, _) = try await makePlaylist(kind, n, c2.mainContext)
                        _ = try markFavorites(p2, c2.mainContext)
                        _ = c2
                    }
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    let c3 = try AppPersistence.diskContainer(at: storeURL, schema: AppSchema.schema)
                    let ctx3 = c3.mainContext
                    let p3 = try XCTUnwrap(try ctx3.fetch(FetchDescriptor<Playlist>()).first)
                    let wd3 = B03QAWatchdog(); wd3.start()
                    let t3 = Date()
                    try PlaylistImporter(modelContext: ctx3).delete(p3)
                    let tDelete3 = Date().timeIntervalSince(t3)
                    try await Task.sleep(nanoseconds: 300_000_000)
                    let gap3 = wd3.stop()
                    record("\(kind)|sender=\(n)|loeschenNachNeustart=\(B03QA.f2(tDelete3))s|mainThreadBlockade=\(B03QA.f2(gap3))s|\(B03QA.dbSummary(storeURL))")
                    XCTAssertEqual(B03QA.int(storeURL.path, "select count(*) from ZCHANNEL"), 0)
                }
            }
        }

        // Quadratisches Wachstum: doppelte Senderzahl → mehr als dreifache Blockade
        for kind in kinds {
            let g = refreshGaps[kind] ?? [:]
            let ns = g.keys.sorted()
            if ns.count >= 2, let a = g[ns[0]], let b = g[ns[1]], a > 0.05 {
                let factor = (b / a)
                let expectedQuadratic = pow(Double(ns[1]) / Double(ns[0]), 2)
                record("\(kind)|wachstum \(ns[0])→\(ns[1]) Sender: Blockade ×\(B03QA.f2(factor)) (linear ×\(B03QA.f2(Double(ns[1]) / Double(ns[0]))), quadratisch ×\(B03QA.f2(expectedQuadratic)))")
            }
        }
        // Erwartet (PRD: „bleibt auch bei Anbieterlisten mit mehr als 17.000 Sendern bedienbar“): keine Blockade über 1 s
        let worstRefresh = refreshGaps.values.flatMap(\.values).max() ?? 0
        let worstDelete = deleteGaps.values.flatMap(\.values).max() ?? 0
        if worstRefresh > 1 || worstDelete > 1 {
            XCTExpectFailure("BUG-01 · Aktualisieren und Löschen großer Playlists blockieren den Main-Thread (FB-01)") {
                XCTAssertLessThanOrEqual(worstRefresh, 1, "Aktualisieren: längste Blockade \(B03QA.f2(worstRefresh)) s")
                XCTAssertLessThanOrEqual(worstDelete, 1, "Löschen: längste Blockade \(B03QA.f2(worstDelete)) s")
            }
        }
    }
}
