import XCTest
import SwiftUI
import SwiftData
import AppKit
import Darwin
@testable import MikaPlusPlayer

/// B04 · Senderliste — Angriffsdurchlauf nach `~/.claude/sdd/angriff.md`, übertragen auf eine lokale App ohne
/// Backend (QA Durchlauf 1): fremde IDs in Predicates, Wiederholversuche, Personendaten in Protokollen, tatsächlicher
/// Payload, Eingaben, Löschen.
final class B04SicherheitTests: B04TestCase {

    // MARK: - 1 · Fremde IDs im Predicate (IDOR-Äquivalent)

    func testAngriff1_ListeZeigtNurSenderDerGeoeffnetenPlaylist() throws {
        let (c, store) = try fileContainer("angriff1")
        let ctx = c.mainContext
        let a = try B04QA.seed(ctx, name: "QA Playlist A", items: [
            .init("A1 Alpha", "Sport"), .init("A2 Beta", "News"),
        ])
        let b = try B04QA.seed(ctx, name: "QA Playlist B", items: [
            .init("B1 Alpha", "Kino"), .init("B2 Gamma", "Doku"),
        ])
        // Sender ohne Playlist-ID und Sender mit widersprüchlicher Denormalisierung
        let ohneID = Channel(name: "X1 ohne playlistID", streamURL: URL(string: "\(B04QA.dead)/x1.m3u8")!, group: "Sport")
        ctx.insert(ohneID)
        let falscheID = Channel(name: "X2 Beziehung A, playlistID B", streamURL: URL(string: "\(B04QA.dead)/x2.m3u8")!,
                               group: "Sport", playlist: a, playlistID: b.id)
        ctx.insert(falscheID)
        try ctx.save()

        let w = window(c)
        w.open(a, wait: 1.5)
        let inA = w.cardNames
        XCTAssertTrue(w.type("alpha", wait: 0.8))
        let sucheA = w.cardNames
        XCTAssertTrue(w.type("", wait: 0.8))
        let chipsA = w.chips.map(\.title)
        w.back()
        w.open(b, wait: 1.5)
        let inB = w.cardNames
        B04QA.log("ANGRIFF-1|inA=\(inA)|sucheAlphaInA=\(sucheA)|chipsA=\(chipsA)|inB=\(inB)")
        XCTAssertEqual(Set(inA), ["A1 Alpha, Sport", "A2 Beta, News"], "nur Sender der geöffneten Playlist")
        XCTAssertEqual(sucheA, ["A1 Alpha, Sport"], "die Suche greift nicht auf andere Playlists über")
        XCTAssertFalse(inA.contains { $0.hasPrefix("X1") }, "Sender ohne playlistID erscheinen nirgends")
        XCTAssertFalse(inA.contains { $0.hasPrefix("X2") }, "die Liste folgt der Kopie playlistID, nicht der Beziehung")
        XCTAssertTrue(inB.contains { $0.hasPrefix("X2") }, "widersprüchliche Denormalisierung zeigt den Sender in B")
        B04QA.evidence("angriff-1-fremde-ids.txt",
                       "Playlist A zeigt \(inA), Playlist B zeigt \(inB); Sender ohne playlistID bleibt unsichtbar, "
                       + "Sender mit Beziehung A und playlistID B erscheint unter B (Denormalisierung).")
        // Gegenprobe in der Datenbank
        B04QA.log("ANGRIFF-1|db|ZCHANNEL=\(B04QA.int(store.path, "select count(*) from ZCHANNEL"))|ohnePlaylistID=\(B04QA.int(store.path, "select count(*) from ZCHANNEL where ZPLAYLISTID is null"))")
    }

    // MARK: - 3 · Wiederholversuche / Bremse für Logo-Anfragen

    func testAngriff3_KeineBremseFuerWiederholteLogoAnfragen() throws {
        let (c, _) = try fileContainer("angriff3")
        let pl = try B04QA.seed(c.mainContext, name: "QA Wiederholung", items: [
            .init("W1", "Logos", logo: "\(host.base)/nocache/w1.png"),
            .init("W2", "Logos", logo: "\(host.base)/nocache/w2.png"),
        ])
        let w = window(c, size: CGSize(width: 900, height: 400))
        for _ in 0..<10 {
            w.open(pl, wait: 0.9)
            w.back(wait: 0.4)
        }
        let anfragen = host.requests.map(\.path)
        let w1 = anfragen.filter { $0 == "/nocache/w1.png" }.count
        B04QA.log("ANGRIFF-3|zehnmalGeoeffnet|anfragenGesamt=\(anfragen.count)|w1=\(w1)")
        B04QA.evidence("angriff-3-wiederholung.txt",
                       "Zehnmal Liste öffnen und verlassen: \(anfragen.count) Logo-Anfragen (davon \(w1) für dasselbe Logo). "
                       + "Es gibt keine Bremse; begrenzt wird nur durch Sichtbarkeit und durch den Plattencache.")
        XCTAssertGreaterThan(w1, 1, "dasselbe Logo wird bei jedem Öffnen erneut geladen (keine Bremse)")
    }

    // MARK: - 4 · Personendaten in Protokollen

    func testAngriff4_SuchtextErscheintNichtInProtokollenOderSpeichern() throws {
        let marke = "QAMARKER\(UInt32.random(in: 100_000...999_999))"
        let (c, store) = try fileContainer("angriff4")
        let ctx = c.mainContext
        let pl = try B04QA.seed(ctx, name: "QA Protokoll", items: [
            .init("Alpha", "Sport", logo: "\(host.base)/nocache/p1.png"), .init("Beta", "News"),
        ])
        let w = window(c)
        w.open(pl, wait: 1.5)
        let seit = Date()
        XCTAssertTrue(w.type(marke, wait: 2.0))
        XCTAssertTrue(w.type("", wait: 1.0))
        w.back(wait: 1.0)
        B04QA.spin(2.0)

        // Systemprotokoll des eigenen Prozesses
        // `--info --debug`: ohne diese Schalter zeigt `log show` nur Notice und Error.
        let log = Self.shell("/usr/bin/log", ["show", "--style", "compact", "--info", "--debug", "--last", "3m",
                                             "--predicate", "processImagePath CONTAINS \"MikaPlusPlayer\" AND eventMessage CONTAINS \"\(marke)\""])
        let treffer = log.split(separator: "\n").filter { $0.contains(marke) }
        // Einstellungen, Datenbank und Plattencache
        let inDefaults = UserDefaults.standard.dictionaryRepresentation().description.contains(marke)
        let inDB = B04QA.rawOccurrences(marke, store)
        let cacheTreffer = B04QA.cacheRows(prefix: host.base).filter { $0.joined().contains(marke) }.count
        let anfragen = host.requests.filter { $0.target.contains(marke) || $0.rawHead.contains(marke) }.count
        let alleZeilen = Self.shell("/usr/bin/log", ["show", "--style", "compact", "--info", "--debug", "--last", "3m",
                                                    "--predicate", "processImagePath CONTAINS \"MikaPlusPlayer\""])
            .split(separator: "\n").count
        B04QA.log("ANGRIFF-4|gegenprobe|zeilenDesProzessesImProtokoll=\(alleZeilen)|logoAdressenDarin=\(alleZeilen > 1 ? Self.shell("/usr/bin/log", ["show", "--style", "compact", "--info", "--debug", "--last", "3m", "--predicate", "processImagePath CONTAINS \"MikaPlusPlayer\" AND eventMessage CONTAINS \"nocache\""]).split(separator: "\n").count - 1 : -1)")
        B04QA.log("ANGRIFF-4|marke=\(marke)|logZeilen=\(treffer.count)|inUserDefaults=\(inDefaults)|inDatenbank=\(inDB)|imCache=\(cacheTreffer)|inAnfragen=\(anfragen)|seit=\(seit)")
        B04QA.evidence("angriff-4-suchtext.txt",
                       "Suchtext \(marke): \(treffer.count) Zeilen im Systemprotokoll (log show, Prozess MikaPlusPlayer), "
                       + "UserDefaults \(inDefaults), Datenbankdatei \(inDB) Vorkommen, Plattencache \(cacheTreffer), "
                       + "Netzanfragen \(anfragen).")
        XCTAssertEqual(treffer.count, 0, "Suchtext steht nicht im Systemprotokoll")
        XCTAssertFalse(inDefaults, "Suchtext wird nicht in den Einstellungen gespeichert")
        XCTAssertEqual(inDB, 0, "Suchtext steht nicht in der Datenbank")
        XCTAssertEqual(cacheTreffer, 0)
        XCTAssertEqual(anfragen, 0, "Suchtext verlässt das Gerät nicht")
    }

    // MARK: - 5 · Tatsächlicher Payload und offene Verbindungen

    func testAngriff5_NurLogoAnfragenVerlassenDieApp() throws {
        let (c, _) = try fileContainer("angriff5")
        let pl = try B04QA.seed(c.mainContext, name: "QA Payload", items: (0..<6).map {
            .init("Sender \($0)", $0 < 3 ? "Logos" : "Andere", logo: "\(host.base)/nocache/s\($0).png")
        })
        let w = window(c, size: CGSize(width: 900, height: 700))
        w.open(pl, wait: 3.0)
        XCTAssertTrue(w.type("Sender 3", wait: 1.5))
        XCTAssertTrue(w.type("", wait: 1.0))
        XCTAssertTrue(w.pressChip("Logos", wait: 1.5))
        let verbindungen = Self.shell("/usr/sbin/lsof", ["-nP", "-a", "-p", "\(getpid())", "-iTCP", "-sTCP:ESTABLISHED"])
            .split(separator: "\n").dropFirst()
            .compactMap { zeile -> String? in
                guard let teil = zeile.split(separator: " ").last(where: { $0.contains("->") }) else { return nil }
                return String(teil)
            }
        let fremd = verbindungen.filter { !$0.contains("127.0.0.1") && !$0.contains("[::1]") }
        B04QA.log("ANGRIFF-5|anfragen=\(host.requests.map(\.target))")
        B04QA.log("ANGRIFF-5|offeneVerbindungen=\(verbindungen)|nichtLoopback=\(fremd)")
        B04QA.evidence("angriff-5-payload.txt",
                       "Alle Anfragen der Liste: \(host.requests.map(\.target).joined(separator: ", ")). "
                       + "Kopfzeilen siehe AK-26-kopfzeilen.txt. Offene Verbindungen des Prozesses: \(verbindungen.joined(separator: ", ")).")
        XCTAssertTrue(host.requests.allSatisfy { $0.target.hasPrefix("/nocache/s") },
                      "es gehen ausschließlich die Logo-Anfragen hinaus")
        XCTAssertTrue(host.requests.allSatisfy { $0.rawHead.contains("GET") && !$0.rawHead.contains("Sender 3") },
                      "kein Suchtext im Payload")
        XCTAssertEqual(fremd, [], "während der Nutzung der Liste gehen keine Verbindungen an Nicht-Loopback-Adressen")
    }

    // MARK: - 7 · Eingaben

    func testAngriff7_BoeseEingabenImSuchfeldUndInDenDaten() throws {
        let (c, store) = try fileContainer("angriff7")
        let ctx = c.mainContext
        let gemein = ["'; drop table ZCHANNEL; --", "<script>alert(1)</script>", "../../etc/passwd", "%00", "😀🎬",
                      "\u{202E}txet trevder", String(repeating: "ä", count: 10_000), "", "a", "\n", "NULL", "1=1"]
        var items: [B04QA.Item] = [
            .init("Normaler Sender", "Sport"),
            .init("<script>alert(1)</script>", "<script>alert('g')</script>"),
            .init("'; drop table ZCHANNEL; --", "'; drop table ZPLAYLIST; --"),
            .init("../../etc/passwd", "../../etc"),
            .init("😀 Emoji", "😀 Gruppe"),
        ]
        items.append(.init("Logo javascript", "Logos", logo: "javascript:alert(1)"))
        items.append(.init("Logo data", "Logos", logo: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
        items.append(.init("Logo etc passwd", "Logos", logo: "file:///etc/passwd"))
        let pl = try B04QA.seed(ctx, name: "QA Eingaben", items: items)
        let vorher = B04QA.int(store.path, "select count(*) from ZCHANNEL")

        let w = window(c, size: CGSize(width: 1_000, height: 820))
        w.open(pl, wait: 2.5)
        var protokoll: [String] = []
        for eingabe in gemein {
            XCTAssertTrue(w.type(eingabe, wait: 0.5))
            let sichtbar = w.cardNames.count
            let label = eingabe.count > 40 ? "<\(eingabe.count) Zeichen>" : eingabe.debugDescription
            protokoll.append("\(label) → \(sichtbar) Karten")
            XCTAssertEqual(B04QA.int(store.path, "select count(*) from ZCHANNEL"), vorher, "Datenbank unverändert (\(label))")
        }
        XCTAssertTrue(w.type("", wait: 1.0))
        B04QA.log("ANGRIFF-7|suchfeld=\(protokoll)")
        // Suchtext wird wörtlich als Text behandelt: der Sender mit dem Skript-Namen wird gefunden
        XCTAssertTrue(w.type("<script>", wait: 0.8))
        B04QA.log("ANGRIFF-7|skriptSuche=\(w.cardNames)")
        XCTAssertEqual(w.cardNames.count, 1, "der Name wird als Text gesucht, nicht ausgeführt")
        XCTAssertTrue(w.type("drop table", wait: 0.8))
        B04QA.log("ANGRIFF-7|sqlSuche=\(w.cardNames)|senderInDB=\(B04QA.int(store.path, "select count(*) from ZCHANNEL"))")
        XCTAssertEqual(w.cardNames.count, 1)
        XCTAssertEqual(B04QA.int(store.path, "select count(*) from ZCHANNEL"), vorher)
        XCTAssertTrue(w.type("", wait: 1.0))

        // Gruppennamen aus fremder Quelle werden ungefiltert zu Chips
        let chips = w.chips.map(\.title)
        B04QA.log("ANGRIFF-7|chips=\(chips)")
        XCTAssertTrue(chips.contains("<script>alert('g')</script>"), "Gruppenname erscheint wörtlich als Chip")
        XCTAssertTrue(w.pressChip("<script>alert('g')</script>"))
        XCTAssertEqual(w.cardNames.count, 1, "der Chip filtert auf genau diesen Gruppenwert")
        XCTAssertTrue(w.pressChip("Alle"))

        // Logo-Adressen mit fremden Schemata
        XCTAssertTrue(w.pressChip("Logos", wait: 3.0))
        let logos = w.rows.map { "\($0.label)|busy=\($0.busy)" }
        B04QA.log("ANGRIFF-7|logoSchemata=\(logos)|netzanfragen=\(host.requests.map(\.path))")
        B04QA.evidence("angriff-7-eingaben.txt",
                       "Suchfeld: " + protokoll.joined(separator: ", ") + "\n  Datenbank vor und nach allen Eingaben: \(vorher) Sender"
                       + "\n  Logo-Schemata: " + logos.joined(separator: ", "))
        w.shot("angriff-7-eingaben")
        XCTAssertEqual(host.requests.count, 0, "javascript:, data: und file: lösen keine Netzanfragen aus")
    }

    // MARK: - 8 · Löschen

    func testAngriff8_LoeschenEntferntSenderAberNichtDieKopienDaneben() throws {
        let (c, store) = try fileContainer("angriff8")
        let ctx = c.mainContext
        let pl = try B04QA.seed(ctx, name: "QA Löschen", items: [
            .init("Löschkanal Eins", "Sport", logo: "\(host.base)/nocache/l1.png"),
            .init("Löschkanal Zwei", "News", logo: "\(host.base)/nocache/l2.png"),
        ])
        let w = window(c, size: CGSize(width: 900, height: 500))
        w.open(pl, wait: 3.0)
        XCTAssertEqual(host.requests.count, 2)
        w.back(wait: 1.0)
        try B04QA.run(60) { try await PlaylistImporter(modelContext: ctx).delete(pl) }
        B04QA.spin(1.0)
        let zeilen = ["ZPLAYLIST": B04QA.int(store.path, "select count(*) from ZPLAYLIST"),
                      "ZCHANNEL": B04QA.int(store.path, "select count(*) from ZCHANNEL")]
        let nameBytes = B04QA.rawOccurrences("Löschkanal Eins", store)
        let cache = B04QA.cacheRows(prefix: host.base).count
        B04QA.log("ANGRIFF-8|nachLoeschen|zeilen=\(zeilen)|nameInDatei=\(nameBytes)|CacheDbZeilen=\(cache)")
        B04QA.evidence("angriff-8-loeschen.txt",
                       "Nach dem Löschen: \(zeilen), Sendername \(nameBytes)× in der Datenbankdatei, \(cache) Logo-Einträge im Plattencache.")
        XCTAssertEqual(zeilen["ZCHANNEL"], 0, "die Sender sind aus der Datenbank entfernt")
        XCTAssertEqual(zeilen["ZPLAYLIST"], 0)
        XCTAssertGreaterThan(cache, 0, "die Logo-Einträge im Plattencache bleiben (FB-07)")
    }

    // MARK: - EC-09

    func testEC09_PlaylistWirdGeloeschtWaehrendDieListeOffenIst() throws {
        let (c, _) = try fileContainer("ec09")
        let ctx = c.mainContext
        let pl = try B04QA.seed(ctx, name: "QA Gelöscht", items: [
            .init("Alpha", "Sport"), .init("Beta", "News"), .init("Gamma", "Sport"),
        ])
        let w = window(c, size: CGSize(width: 900, height: 600))
        w.open(pl, wait: 1.8)
        XCTAssertEqual(w.cardNames.count, 3)
        // Löschen wie B03 es tut, während die Liste offen ist
        try B04QA.run(60) { try await PlaylistImporter(modelContext: ctx).delete(pl) }
        B04QA.spin(2.0)
        let texte = w.staticTexts
        let kopf = w.header
        B04QA.log("EC-09|nachLoeschen|kopf=\(kopf ?? "-")|texte=\(texte)|karten=\(w.cardNames)|chips=\(w.chips.map(\.title))|titel=\(w.window.title)")
        w.shot("EC-09-playlist-geloescht")
        // Neuzeichnen erzwingen: Chip drücken und tippen
        let gedrueckt = w.pressChip("Sport")
        XCTAssertTrue(w.type("alpha", wait: 1.0))
        XCTAssertTrue(w.type("", wait: 1.0))
        B04QA.log("EC-09|nachInteraktion|chipGedrueckt=\(gedrueckt)|texte=\(w.staticTexts)|karten=\(w.cardNames)")
        B04QA.evidence("EC-09-geloescht.txt",
                       "Playlist gelöscht, während ihre Liste offen war: Kopfzeile „\(kopf ?? "-")“, Texte \(texte), "
                       + "Chips \(w.chips.map(\.title)), kein Absturz; nach Chip-Druck und Eingabe: \(w.staticTexts)")
        XCTAssertEqual(w.cardNames.count, 0, "keine Sender mehr")
        // Seit B03 · BUG-05: Die offene Liste meldet die gelöschte Playlist statt eines Leerzustands mit alter Kopfzeile.
        XCTAssertTrue(w.staticTexts.contains { $0.contains("Diese Playlist wurde gelöscht.") }, "\(w.staticTexts)")
        XCTAssertNil(kopf, "keine Kopfzeile mit der alten Senderzahl")
    }

    // MARK: - Hilfen

    private static func shell(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "FEHLER: \(error)" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
