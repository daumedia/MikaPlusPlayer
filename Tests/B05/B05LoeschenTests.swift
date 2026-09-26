import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B05 · Löschen (AK-20, AK-28, Angriff 8). Gelöscht wird wie `PlaylistsView.delete` über
/// `PlaylistImporter.delete` (der Weg über das Kontextmenü ist in B03 belegt).
@MainActor
final class B05LoeschenTests: B05TestCase {

    typealias E = B05QA.E

    // MARK: AK-20 · OF-04

    func testAK20_Angriff8_LoeschenNimmtFavoritenOhneHinweisMit() async throws {
        let (c, store) = try fileContainer("ak20")
        let ctx = c.mainContext
        let la: [E] = [E(name: "B05MARKER Glaube TV", url: "\(B05QA.dead)/a/1.m3u8", group: "Religion"),
                       E(name: "B05MARKER Partei TV", url: "\(B05QA.dead)/a/2.m3u8", group: "Politik"),
                       E(name: "Neutral A", url: "\(B05QA.dead)/a/3.m3u8")]
        let a = try await importM3U(ctx, path: "/b05/a.m3u", name: "Anbieter A", la)
        let b = try await importM3U(ctx, path: "/b05/b.m3u", name: "Anbieter B", [E(name: "Neutral B", url: "\(B05QA.dead)/b/1.m3u8")])
        try B05QA.setFavorite(a, "B05MARKER Glaube TV", ctx: ctx)
        try B05QA.setFavorite(a, "B05MARKER Partei TV", ctx: ctx)
        try B05QA.setFavorite(b, "Neutral B", ctx: ctx)
        let aPK = B05QA.int(store.path, "SELECT Z_PK FROM ZPLAYLIST WHERE ZNAME = 'Anbieter A'")

        let tab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 520))
        XCTAssertEqual(tab.cardLabels, ["B05MARKER Glaube TV, Religion", "B05MARKER Partei TV, Politik", "Neutral B"])
        tab.shot("AK-20-favoriten-vor-loeschen")
        let alertsBefore = b05AlertWindows()

        // wie PlaylistsView.delete (dort mit try?)
        try? await PlaylistImporter(modelContext: ctx).delete(a)
        let gone = B05QA.wait(1.0) { tab.cardLabels == ["Neutral B"] }
        let alertsAfter = b05AlertWindows()
        tab.shot("AK-20-favoriten-nach-loeschen")
        XCTAssertTrue(gone, "sofort aus dem Tab: \(tab.cardLabels)")
        XCTAssertEqual(alertsAfter, alertsBefore, "keine Meldung")
        XCTAssertEqual(try B05QA.favLabels(ctx), ["Neutral B@Anbieter B"])

        // Angriff 8: jede Tabelle nachzählen
        let counts = [
            "ZPLAYLIST": B05QA.int(store.path, "SELECT COUNT(*) FROM ZPLAYLIST"),
            "ZCHANNEL gesamt": B05QA.int(store.path, "SELECT COUNT(*) FROM ZCHANNEL"),
            "ZCHANNEL der gelöschten Playlist": B05QA.int(store.path, "SELECT COUNT(*) FROM ZCHANNEL WHERE ZPLAYLIST = \(aPK)"),
            "ZCHANNEL ohne Playlist": B05QA.int(store.path, "SELECT COUNT(*) FROM ZCHANNEL WHERE ZPLAYLIST IS NULL"),
            "ZCHANNEL Marker": B05QA.int(store.path, "SELECT COUNT(*) FROM ZCHANNEL WHERE ZNAME LIKE 'B05MARKER%'"),
            "ZISFAVORITE=1": B05QA.int(store.path, "SELECT COUNT(*) FROM ZCHANNEL WHERE ZISFAVORITE = 1"),
        ]
        B05QA.evidence("AK-20-loeschen.txt", "tab vorher=3 Karten, nachher=\(tab.cardLabels) · alerts vorher=\(alertsBefore) nachher=\(alertsAfter)")
        B05QA.evidence("AK-20-loeschen.txt", "sqlite nach dem Löschen: \(counts.sorted { $0.key < $1.key })")
        XCTAssertEqual(counts["ZPLAYLIST"], 1)
        XCTAssertEqual(counts["ZCHANNEL gesamt"], 1)
        XCTAssertEqual(counts["ZCHANNEL der gelöschten Playlist"], 0)
        XCTAssertEqual(counts["ZCHANNEL ohne Playlist"], 0)
        XCTAssertEqual(counts["ZCHANNEL Marker"], 0)
        XCTAssertEqual(counts["ZISFAVORITE=1"], 1)

        // Erneuter Import derselben Quelle → keine Favoriten
        let a2 = try await importM3U(ctx, path: "/b05/a.m3u", name: "Anbieter A", la)
        B05QA.evidence("AK-20-loeschen.txt", "neu importiert → favoriten der neuen Playlist=\(a2.channels.filter(\.isFavorite).count)")
        XCTAssertEqual(a2.channels.filter(\.isFavorite).count, 0)

        XCTExpectFailure("BUG-08: Löschen nimmt Favoriten ohne Hinweis und ohne Rückweg mit (wartet auf OF-04)") {
            XCTAssertNotEqual(alertsAfter, alertsBefore, "Hinweis auf verlorene Favoriten erwartet")
        }
    }

    // MARK: AK-28

    /// Löscht eine Playlist mit markierten Favoriten, zählt die Namen als Bytes in Datei, `-wal` und `-shm` – bei
    /// offener Datenbank und nachdem der Container freigegeben und die Datei neu geöffnet und wieder geschlossen wurde.
    /// Mit `TEST_RUNNER_B05_KEEP_STORES=1` bleibt der Ordner für die Nachkontrolle nach Prozessende liegen.
    func testAK28_NamenGeloeschterFavoritenInDatenbankdateien() async throws {
        let label = "ak28"
        let store: URL
        var open: [String: Int] = [:]
        do {
            let (c, s) = try fileContainer(label)
            store = s
            let ctx = c.mainContext
            var es: [E] = (0..<300).map { E(name: "Füllsender \($0)", url: "\(B05QA.dead)/f/\($0).m3u8", group: "Füllgruppe") }
            es.insert(E(name: "B05REST Glaube TV", url: "\(B05QA.dead)/r/1.m3u8", group: "Religion"), at: 150)
            es.insert(E(name: "B05REST Partei TV", url: "\(B05QA.dead)/r/2.m3u8", group: "Politik"), at: 10)
            let a = try await importM3U(ctx, path: "/b05/r.m3u", name: "Anbieter Rest", es)
            try B05QA.setFavorite(a, "B05REST Glaube TV", ctx: ctx)
            try B05QA.setFavorite(a, "B05REST Partei TV", ctx: ctx)
            B05QA.evidence("AK-28-restbytes.txt", "vor-loeschen|\(B05QA.rawOccurrences("B05REST", store))")
            try await PlaylistImporter(modelContext: ctx).delete(a)
            B05QA.spin(0.5)
            open = B05QA.rawOccurrences("B05REST", store)
            B05QA.evidence("AK-28-restbytes.txt", "nach-loeschen-offen|\(open)|zeilen=\(B05QA.int(store.path, "SELECT COUNT(*) FROM ZCHANNEL"))")
        }
        // Container freigegeben; neu öffnen und schließen („Neustart“)
        B05QA.spin(1.0)
        let afterRelease = B05QA.rawOccurrences("B05REST", store)
        do {
            let c2 = try B05QA.reopen(store)
            XCTAssertEqual(try c2.mainContext.fetchCount(FetchDescriptor<Channel>()), 0)
        }
        B05QA.spin(1.0)
        let afterRestart = B05QA.rawOccurrences("B05REST", store)
        let pragmas = ["secure_delete", "journal_mode", "freelist_count", "page_count"].map { "\($0)=\(B05QA.rows(store.path, "PRAGMA \($0)").first?.first ?? "?")" }
        B05QA.evidence("AK-28-restbytes.txt", "nach-freigabe|\(afterRelease)")
        B05QA.evidence("AK-28-restbytes.txt", "nach-neustart|\(afterRestart)|\(pragmas)|datei=\(store.path)")
        let total = afterRestart.values.reduce(0, +)
        // Seit B03 · BUG-07 (BF-59, gleiche Ursache wie dieser BUG-10) verdichtet das Löschen die Datei sofort: Der Name steht
        // weder im -wal noch in freien Seiten – schon bei laufender App, nicht erst nach dem Neustart.
        XCTAssertEqual(open.values.reduce(0, +), 0, "nach dem Löschen kein Vorkommen, auch nicht im -wal: \(open)")
        XCTAssertEqual(total, 0, "nach dem Neustart keine Vorkommen mehr: \(afterRestart)")
    }
}
