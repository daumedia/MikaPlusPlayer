import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B04 · Senderliste — Abfragen, Indizes und Blockaden der Oberfläche (QA Durchlauf 1).
///
/// Größen über Umgebungsvariablen (`TEST_RUNNER_B04_SIZE`, `TEST_RUNNER_B04_LISTS`); Standard sind 17.000 Sender
/// in einer Playlist, wie in der Spec. Alle Messwerte landen zusätzlich in `qa/AK-31-34-messung.txt` samt
/// Build-Konfiguration und Systemlast.
final class B04LeistungTests: B04TestCase {

    private var size: Int { Int(B04QA.env("B04_SIZE") ?? "") ?? 17_000 }
    private var lists: Int { Int(B04QA.env("B04_LISTS") ?? "") ?? 1 }

    /// Legt `lists` Playlists mit je `size` Sendern an (ohne Logo-Adressen: keine Netzanfragen während der Messung).
    private func seedLarge(_ label: String) throws -> (ModelContainer, URL, Playlist, TimeInterval) {
        let (c, store) = try fileContainer(label)
        let ctx = c.mainContext
        var first: Playlist?
        let t0 = Date()
        for k in 0..<lists {
            let items = B04QA.perfItems(size, offset: k * 3).map {
                B04QA.Item($0.name, $0.group)   // ohne Logo
            }
            let pl = try B04QA.seed(ctx, name: "QA Leistung \(k)", items: items)
            if first == nil { first = pl }
        }
        let dauer = Date().timeIntervalSince(t0)
        B04QA.log("SEED|\(label)|listen=\(lists)|jeSender=\(size)|dauer=\(B04QA.f1(dauer))s|dateiMB=\(B04QA.f1(Double((try? FileManager.default.attributesOfItem(atPath: store.path)[.size] as? Int) ?? 0 ?? 0) / 1_048_576))")
        return (c, store, first!, dauer)
    }

    // MARK: - AK-31 / AK-32

    func testAK31_AK32_AbfrageLaeuftInDerDatenbankAberOhneIndex() throws {
        let (c, store, pl, _) = try seedLarge("ak31")
        let ctx = c.mainContext
        let gesamt = try ctx.fetchCount(FetchDescriptor<Channel>())

        // Dauer je Abfrage: ein kalter, vier warme Läufe
        let faelle: [(String, String, String?)] = [
            ("ohne Filter", "", nil),
            ("Suche „a“", "a", nil),
            ("Suche „Sport“", "Sport", nil),
            ("Suche „fußball“", "fußball", nil),
            ("Suche „Anime 97 4K“", "Anime 97 4K", nil),
            ("Suche ohne Treffer", "zzzqqq", nil),
            ("Suche 10.000 Zeichen", String(repeating: "a", count: 10_000), nil),
            ("Gruppe „DE | Sport“", "", "DE | Sport"),
            ("Gruppe + Suche „HD“", "HD", "DE | Sport"),
        ]
        var zeilen: [String] = []
        for (label, s, g) in faelle {
            var treffer = 0
            let kalt = messen { treffer = (try? ctx.fetch(B04QA.resultsDescriptor(pl.id, s, g)))?.count ?? -1 }
            var warm: [Double] = []
            for _ in 0..<4 { warm.append(messen { _ = try? ctx.fetch(B04QA.resultsDescriptor(pl.id, s, g)) }) }
            let zeile = "\(label): \(treffer) Treffer, kalt \(B04QA.f1(kalt)) ms, warm \(warm.map(B04QA.f1).joined(separator: "/")) ms"
            zeilen.append(zeile)
            B04QA.log("AK-31|\(zeile)")
        }
        var gruppen = 0
        let chipKalt = messen { gruppen = B04QA.groupsMirror(ctx, pl.id).count }
        var chipWarm: [Double] = []
        for _ in 0..<3 { chipWarm.append(messen { _ = B04QA.groupsMirror(ctx, pl.id) }) }
        zeilen.append("Chips berechnen (loadGroups): \(gruppen) Gruppen, kalt \(B04QA.f1(chipKalt)) ms, warm \(chipWarm.map(B04QA.f1).joined(separator: "/")) ms")
        B04QA.log("AK-33|\(zeilen.last!)")

        // AK-32: Abfragepläne auf der Testdatei (eigene Funktionen/Kollation durch Vergleichbares ersetzt)
        let plaene = [
            "Filter der App (ZPLAYLISTID)": "explain query plan select t0.Z_PK from ZCHANNEL t0 where t0.ZPLAYLISTID = x'00' order by t0.ZNAME",
            "Filter + Gruppe": "explain query plan select t0.Z_PK from ZCHANNEL t0 where t0.ZPLAYLISTID = x'00' and t0.ZGROUP = 'x' order by t0.ZNAME",
            "über die Beziehung (ZPLAYLIST, von der App nicht benutzt)": "explain query plan select t0.Z_PK from ZCHANNEL t0 where t0.ZPLAYLIST = 1 order by t0.ZNAME",
        ]
        var planText: [String] = []
        for (label, sql) in plaene.sorted(by: { $0.key < $1.key }) {
            let details = B04QA.rows(store.path, sql).map { $0.last ?? "" }
            planText.append("\(label): \(details.joined(separator: " / "))")
            B04QA.log("AK-32|\(planText.last!)")
        }
        let indizes = B04QA.rows(store.path, "select name from sqlite_master where type='index' and tbl_name='ZCHANNEL'").flatMap { $0 }
        B04QA.log("AK-32|indizesAufZCHANNEL=\(indizes)")
        B04QA.evidence("AK-31-34-messung.txt",
                       "AK-31/32/33 · \(gesamt) Sender in \(lists) Playlist(s), Last \(B04QA.loadAverage())\n  "
                       + zeilen.joined(separator: "\n  ") + "\n  " + planText.joined(separator: "\n  ")
                       + "\n  Indizes auf ZCHANNEL: \(indizes.joined(separator: ", "))")

        let appPlan = B04QA.rows(store.path, plaene["Filter der App (ZPLAYLISTID)"]!).map { $0.last ?? "" }.joined(separator: " ")
        let relPlan = B04QA.rows(store.path, plaene["über die Beziehung (ZPLAYLIST, von der App nicht benutzt)"]!).map { $0.last ?? "" }.joined(separator: " ")
        XCTAssertTrue(appPlan.contains("SCAN"), "Filter der App liest alle Sender aller Playlists")
        XCTAssertTrue(appPlan.contains("TEMP B-TREE"), "Sortierung über einen temporären B-Baum")
        XCTAssertTrue(relPlan.contains("USING INDEX"), "über die Beziehung gäbe es einen Index")
        XCTAssertEqual(indizes.filter { $0.contains("ZPLAYLISTID") || $0.contains("ZNAME") || $0.contains("ZGROUP") }, [],
                       "kein Index auf ZPLAYLISTID, ZNAME oder ZGROUP")
        XCTExpectFailure("BUG-12 · Der Filter umgeht den einzigen Index; ZPLAYLISTID, ZNAME, ZGROUP sind unindiziert (FB-08)") {
            XCTAssertTrue(appPlan.contains("USING INDEX"), "Filter der Liste nutzt einen Index")
        }
    }

    // MARK: - AK-33 / AK-34 / EC-12

    func testAK33_AK34_EC12_OberflaecheBlockiertBeimOeffnenUndTippen() throws {
        let (c, _, pl, seedDauer) = try seedLarge("ak34")
        let ctx = c.mainContext
        XCTAssertEqual(pl.channelCount, size)
        var messwerte: [String] = []
        func mit(_ label: String, _ wartezeit: TimeInterval = 1.5, _ block: () -> Void) -> Double {
            let hb = B04Heartbeat()
            hb.start()
            block()
            B04QA.spin(wartezeit)
            let r = hb.stop()
            messwerte.append("\(label): längste Blockade \(B04QA.f0(r.maxMs)) ms")
            B04QA.log("AK-34|\(label)|maxBlockadeMs=\(B04QA.f0(r.maxMs))|ueber50ms=\(B04QA.f0(r.over50Ms))")
            return r.maxMs
        }

        let w = window(c, size: CGSize(width: 1_100, height: 850))
        var oeffnen: [Double] = []
        for runde in 1...2 {
            oeffnen.append(mit("Liste öffnen (Runde \(runde))", 5.0) { w.nav.path.append(pl) })
            B04QA.log("AK-34|nachOeffnen\(runde)|karten=\(w.cardNames.count)|speicherMB=\(B04QA.f0(B04QA.footprintMB()))")
            _ = mit("Liste verlassen (Runde \(runde))", 2.5) { w.nav.path.removeLast(w.nav.path.count) }
        }
        w.nav.path.append(pl)
        B04QA.spin(5.0)
        let sf = try XCTUnwrap(w.searchField, "Suchfeld in der Toolbar")

        // Zeichen für Zeichen, je 0,8 s Abstand
        var getippt = ""
        var einzelzeichen: [Double] = []
        for ch in "Fußball 12" {
            getippt.append(ch)
            let text = getippt
            einzelzeichen.append(mit("tippen „\(text)“", 0.8) { self.setze(text, sf) })
        }
        let leeren = mit("Suchfeld leeren", 2.5) { self.setze("", sf) }
        let einZeichen = mit("ein Zeichen „a“", 2.5) { self.setze("a", sf) }
        B04QA.log("AK-34|trefferA=\(w.cardNames.count) sichtbar von \(B04QA.results(ctx, pl.id, "a").count)")
        let leeren2 = mit("Suchfeld leeren (2)", 2.5) { self.setze("", sf) }
        let chip = mit("Chip „DE | Sport“ wählen", 2.5) { _ = w.pressChip("DE | Sport", wait: 0) }
        let chipWeg = mit("Chip abwählen", 2.5) { _ = w.pressChip("DE | Sport", wait: 0) }

        // EC-12: acht Zeichen im Abstand von 100 ms
        let hb = B04Heartbeat()
        hb.start()
        let start = Date()
        var schnell = ""
        for ch in "Doku 5 H" {
            schnell.append(ch)
            setze(schnell, sf)
            B04QA.spin(0.1)
        }
        let eingabedauer = Date().timeIntervalSince(start)
        B04QA.spin(2.0)
        let schnellBlock = hb.stop()
        let speicher = B04QA.footprintMB()
        messwerte.append("8 Zeichen im Abstand von 100 ms: längste Blockade \(B04QA.f0(schnellBlock.maxMs)) ms, Eingabe dauerte \(B04QA.f1(eingabedauer)) s statt 0,8 s")
        messwerte.append("Speicherbedarf mit offener Liste: \(B04QA.f0(speicher)) MB")
        B04QA.log("EC-12|schnellTippen|maxBlockadeMs=\(B04QA.f0(schnellBlock.maxMs))|dauer=\(B04QA.f1(eingabedauer))s|speicherMB=\(B04QA.f0(speicher))")
        B04QA.evidence("AK-31-34-messung.txt",
                       "AK-34/EC-12 · \(size) Sender, \(lists) Playlist(s), Fenster 1.100 × 850 pt, Last \(B04QA.loadAverage()), "
                       + "Anlegen der Daten \(B04QA.f1(seedDauer)) s\n  " + messwerte.joined(separator: "\n  "))

        XCTAssertGreaterThan(oeffnen.max() ?? 0, 0)
        if size >= 17_000 {
            XCTExpectFailure("BUG-13 · „the list responds immediately“ ist bei 17.000 Sendern nicht eingelöst (FB-10)") {
                XCTAssertLessThan(oeffnen.max() ?? 0, 100, "Öffnen blockiert die Oberfläche nicht merklich")
                XCTAssertLessThan(max(leeren, max(leeren2, chipWeg)), 100, "Leeren der Suche und Abwählen eines Chips unter 100 ms")
                XCTAssertLessThan(schnellBlock.maxMs, 100, "schnelles Tippen staut sich nicht")
                XCTAssertLessThan(eingabedauer, 1.0, "acht Zeichen in 0,8 s")
                XCTAssertLessThan(einzelzeichen.max() ?? 0, 50, "einzelne Zeichen unter der Wahrnehmungsgrenze")
                XCTAssertLessThan(einZeichen, 100)
                XCTAssertLessThan(chip, 100)
            }
        }
    }

    // MARK: - Hilfen

    private func messen(_ block: () -> Void) -> Double {
        let t0 = DispatchTime.now().uptimeNanoseconds
        block()
        return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
    }

    private func setze(_ text: String, _ sf: NSSearchField) {
        sf.stringValue = text
        if let editor = sf.currentEditor() { editor.string = text }
        let note = Notification(name: NSControl.textDidChangeNotification, object: sf)
        sf.delegate?.controlTextDidChange?(note)
        NotificationCenter.default.post(note)
    }
}
