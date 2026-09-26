import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B05 · Leistung (AK-29, AK-30, EC-09). Ist-Werte, keine Zielwerte; Messumgebung in `qa/AK-29-30-messung.txt`.
@MainActor
final class B05LeistungTests: B05TestCase {

    static let genres = ["Sport", "News", "Kino", "Doku", "Kinder", "Musik", "Serie", "Anime", "Reise", "Kochen", "Natur", "Talk",
                         "Comedy", "Krimi", "Wetter", "Auto", "Tech", "Mode", "Kunst", "Gesundheit", "Religion", "Politik", "Wissen", "Jagd", "Fußball"]
    static let prefixes = ["DE", "AT", "CH", "UK", "FR", "IT", "ES", "PL", "TR", "NL", "US", "AR"]

    private func items(_ count: Int, favEvery: Int, offset: Int) -> [(name: String, group: String?, tvg: String?, fav: Bool, logo: String?)] {
        (0..<count).map { i in
            let pre = Self.prefixes[i % Self.prefixes.count]
            let genre = Self.genres[(i / 12) % Self.genres.count]
            return (name: "\(pre): \(genre) \(i % 100) \(["HD", "FHD", "SD", "4K"][i % 4])", group: "\(pre) | \(genre)",
                    tvg: "\(genre.lowercased()).\(offset + i).\(pre.lowercased())", fav: i % favEvery == 0, logo: nil)
        }
    }

    private func seedLarge(_ ctx: ModelContext, name: String, count: Int, favEvery: Int, offset: Int) throws -> Playlist {
        let pl = Playlist(name: name)
        ctx.insert(pl)
        var batch: [Channel] = []
        for (i, it) in items(count, favEvery: favEvery, offset: offset).enumerated() {
            let ch = Channel(name: it.name, streamURL: URL(string: "\(B05QA.dead)/live/\(offset + i).ts")!, group: it.group,
                             tvgID: it.tvg, isFavorite: it.fav, playlistID: pl.id)
            ctx.insert(ch)
            batch.append(ch)
            if batch.count == 5_000 { pl.channels.append(contentsOf: batch); batch.removeAll(); try ctx.save() }
        }
        pl.channels.append(contentsOf: batch)
        pl.channelCount = count
        try ctx.save()
        return pl
    }

    private func env() -> String { "\(B05QA.loadAverage()) (Last 1/5/15 min)" }

    // MARK: AK-29 · AK-30

    func testAK29_AK30_FavoritenBei17000Und34000Sendern() throws {
        let (c0, store) = try fileContainer("ak29")
        let t = try B05QA.ms { _ = try seedLarge(c0.mainContext, name: "Groß 1", count: 17_000, favEvery: 340, offset: 0) }
        B05QA.evidence("AK-29-30-messung.txt", "anlegen 17.000 (50 Favoriten)|\(Int(t)) ms|last=\(env())")
        let favPred = #Predicate<Channel> { $0.isFavorite == true }

        func measure(_ label: String) throws {
            let c = try B05QA.reopen(store)
            let ctx = c.mainContext
            var n = 0
            let cold = try B05QA.ms { n = try ctx.fetch(FetchDescriptor(predicate: favPred, sortBy: [B05QA.comparableSort(\Channel.name)])).count }
            var warm: [Double] = []
            for _ in 0..<4 { warm.append(try B05QA.ms { _ = try ctx.fetch(FetchDescriptor(predicate: favPred, sortBy: [B05QA.comparableSort(\Channel.name)])) }) }
            var cnt = 0
            let countMs = try B05QA.ms { cnt = try ctx.fetchCount(FetchDescriptor(predicate: favPred)) }
            let total = try ctx.fetchCount(FetchDescriptor<Channel>())
            B05QA.evidence("AK-29-30-messung.txt", "AK-29|\(label)|sender=\(total)|favoriten=\(n)|count=\(cnt)|laden kalt=\(B05QA.f1(cold)) ms|warm=\(warm.map(B05QA.f1).joined(separator: "/")) ms|zählen=\(B05QA.f1(countMs)) ms|last=\(env())")
            XCTAssertLessThan(cold, 200, "Favoriten laden bleibt schnell")

            // AK-30: Schlüssel merken wie `PlaylistImporter.refresh` Zeile 253 (gleicher Ausdruck, frischer Container)
            let pls = try ctx.fetch(FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\.name)]))
            if let big = pls.first {
                var keys = Set<String>()
                let hb = B05Heartbeat(); hb.start()
                let k1 = B05QA.ms { keys = Set(big.channels.filter(\.isFavorite).map(\.favoriteKey)) }
                let block = hb.stopMaxGapMs()
                let k2 = B05QA.ms { keys = Set(big.channels.filter(\.isFavorite).map(\.favoriteKey)) }
                B05QA.evidence("AK-29-30-messung.txt", "AK-30|\(label)|playlist=\(big.name) (\(big.channelCount) Sender)|schlüssel=\(keys.count)|kalt=\(Int(k1)) ms (Main-Thread)|warm=\(Int(k2)) ms|blockade=\(Int(block)) ms")
            }
        }
        try measure("17.000/50")

        // Oberfläche: Tab öffnen, im Tab entfernen; Senderliste + Tab gleichzeitig, Stern in der Liste
        let c = try B05QA.reopen(store)
        let ctx = c.mainContext
        let hb = B05Heartbeat(); hb.start()
        let tab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 900))
        B05QA.spin(0.5)
        B05QA.evidence("AK-29-30-messung.txt", "AK-29|tab öffnen (17.000/50)|längste Blockade=\(Int(hb.stopMaxGapMs())) ms|sichtbare Karten=\(tab.cards.count)")
        let first = try XCTUnwrap(try ctx.fetch(FetchDescriptor(predicate: favPred, sortBy: [B05QA.comparableSort(\Channel.name)])).first)
        let hb2 = B05Heartbeat(); hb2.start()
        var clickMs = 0.0
        clickMs = B05QA.ms { tab.clickStar(first.name, wait: 0) }
        B05QA.spin(1.0)
        B05QA.evidence("AK-29-30-messung.txt", "AK-29|stern im tab entfernen|klick=\(Int(clickMs)) ms|längste Blockade=\(Int(hb2.stopMaxGapMs())) ms|favoriten=\(try ctx.fetchCount(FetchDescriptor(predicate: favPred)))")
        first.isFavorite = true
        try ctx.save()
        B05QA.spin(0.5)

        let pl = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Playlist>()).first)
        let list = window(NavigationStack { ChannelListView(playlist: pl) }, c, size: CGSize(width: 760, height: 900), origin: CGPoint(x: 860, y: 0))
        B05QA.spin(1.5)
        if let target = list.cards.first?.label.components(separatedBy: ", ").first {
            for (label, keepTab) in [("mit offenem Tab", true), ("ohne Tab", false)] {
                if !keepTab { tab.close(); B05QA.spin(0.5) }
                for round in 0..<2 {
                    let h = B05Heartbeat(); h.start()
                    var s = 0.0
                    s = B05QA.ms { list.clickStar(target, wait: 0) }
                    B05QA.spin(1.0)
                    B05QA.evidence("AK-29-30-messung.txt", "AK-29|stern in senderliste 17.000 \(label)|runde \(round)|klick=\(Int(s)) ms|längste Blockade=\(Int(h.stopMaxGapMs())) ms")
                }
            }
        }
        list.close()
        B05QA.spin(0.3)

        // 34.000 Sender, 100 Favoriten
        _ = try seedLarge(c0.mainContext, name: "Groß 2", count: 17_000, favEvery: 340, offset: 17_000)
        try measure("34.000/100")

        // Abfrageplan der Tab-Abfrage (SQL aus com.apple.CoreData.SQLDebug, siehe Bericht)
        let plan = B05QA.rows(store.path, "EXPLAIN QUERY PLAN SELECT 0, t0.Z_PK FROM ZCHANNEL t0 WHERE t0.ZISFAVORITE = 1 ORDER BY t0.ZNAME, t0.Z_PK")
        let indexes = B05QA.rows(store.path, "SELECT name, sql FROM sqlite_master WHERE type = 'index' AND tbl_name = 'ZCHANNEL'")
        B05QA.evidence("AK-29-30-messung.txt", "AK-29|explain query plan|\(plan.map { $0.last ?? "" })|indizes=\(indexes.map { $0.first ?? "" })")
    }

    // MARK: EC-09

    func testEC09_SehrVieleFavoriten() throws {
        let (c0, store) = try fileContainer("ec09")
        _ = try seedLarge(c0.mainContext, name: "Groß Viele", count: 17_000, favEvery: 3, offset: 0)
        let c = try B05QA.reopen(store)
        let ctx = c.mainContext
        let favPred = #Predicate<Channel> { $0.isFavorite == true }
        var n = 0
        let cold = try B05QA.ms { n = try ctx.fetch(FetchDescriptor(predicate: favPred, sortBy: [B05QA.comparableSort(\Channel.name)])).count }
        let hb = B05Heartbeat(); hb.start()
        let tab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 900))
        B05QA.spin(1.0)
        let block = hb.stopMaxGapMs()
        let first = tab.cards.first?.label ?? "-"
        let h2 = B05Heartbeat(); h2.start()
        var clickMs = 0.0
        if let name = first.components(separatedBy: ", ").first { clickMs = B05QA.ms { tab.clickStar(name, wait: 0) } }
        B05QA.spin(1.0)
        B05QA.evidence("AK-29-30-messung.txt", "EC-09|17.000 Sender, \(n) Favoriten|laden kalt=\(B05QA.f1(cold)) ms|tab öffnen längste Blockade=\(Int(block)) ms|stern im tab klick=\(Int(clickMs)) ms, längste Blockade=\(Int(h2.stopMaxGapMs())) ms|last=\(env())")
        XCTAssertGreaterThan(n, 5_000)
    }
}
