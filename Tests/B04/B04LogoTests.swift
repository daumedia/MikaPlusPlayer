import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B04 · Senderliste — Logos: welche Hosts, welche Antworten, welche Kopfzeilen, welcher Cache (QA Durchlauf 1).
/// Alle Logo-Adressen zeigen auf den eigenen Mock (`B04LogoHost`, 127.0.0.1) oder auf geschlossene Ports.
final class B04LogoTests: B04TestCase {

    /// Anteil der Punkte im Logofeld einer Karte, die dem Mock-Logo (220,60,60) entsprechen.
    private func logoTreffer(_ w: B04Window, _ label: String) -> Int {
        guard let row = w.rows.first(where: { $0.label.hasPrefix(label) }) else { return -1 }
        let region = w.inWindow(row.frame)
        let feld = NSRect(x: region.minX, y: region.minY, width: 70, height: region.height)
        return w.match(NSColor(srgbRed: 220 / 255, green: 60 / 255, blue: 60 / 255, alpha: 1), tolerance: 0.2, in: feld).count
    }

    // MARK: - AK-21

    func testAK21_LogoWirdGeladenFehlerUndNichtBilderZeigenPlatzhalter() throws {
        let (c, _) = try fileContainer("ak21")
        let pl = try B04QA.seed(c.mainContext, name: "QA Logos", items: [
            .init("A1 max-age", "Logos", logo: "\(host.base)/maxage/a.png"),
            .init("A2 zweiter Host", "Logos", logo: "\(host.altBase)/nocache/b.png"),
            .init("A3 ohne Cache-Header", "Logos", logo: "\(host.base)/nocache/c.png"),
            .init("A4 no-store", "Logos", logo: "\(host.base)/nostore/d.png"),
            .init("A5 HTML", "Logos", logo: "\(host.base)/html?a=5"),
            .init("A6 HTML als image/png", "Logos", logo: "\(host.base)/html-as-png?a=6"),
            .init("A7 JSON", "Logos", logo: "\(host.base)/json?a=7"),
            .init("A8 404", "Logos", logo: "\(host.base)/404?a=8"),
        ])
        let w = window(c, size: CGSize(width: 900, height: 820))
        w.open(pl, wait: 4.0)
        w.shot("AK-21-logos")
        let angefragt = host.requests.map(\.target).sorted()
        B04QA.log("AK-21|anfragen=\(angefragt)")
        B04QA.log("AK-21|karten=\(w.rows.map { "\($0.label)|busy=\($0.busy)|logopunkte=\(logoTreffer(w, $0.label))" })")
        XCTAssertEqual(angefragt, ["/404?a=8", "/html-as-png?a=6", "/html?a=5", "/json?a=7", "/maxage/a.png",
                                   "/nocache/b.png", "/nocache/c.png", "/nostore/d.png"],
                       "genau die Adressen aus der Playlist, unverändert")
        XCTAssertEqual(w.busyRows, [], "kein Ladeindikator bleibt stehen, wenn eine Antwort kommt")
        for bild in ["A1 max-age", "A2 zweiter Host", "A3 ohne Cache-Header", "A4 no-store"] {
            XCTAssertGreaterThan(logoTreffer(w, bild), 400, "\(bild): Bild eingepasst angezeigt")
        }
        for platzhalter in ["A5 HTML", "A6 HTML als image/png", "A7 JSON", "A8 404"] {
            XCTAssertLessThan(logoTreffer(w, platzhalter), 40, "\(platzhalter): graues TV-Symbol statt Bild")
        }
        B04QA.evidence("AK-21-logoantworten.txt",
                       "Anfragen: \(angefragt.joined(separator: ", ")) · Karten: "
                       + w.rows.map { "\($0.label)(busy=\($0.busy),logopunkte=\(logoTreffer(w, $0.label)))" }.joined(separator: ", "))
    }

    // MARK: - AK-22

    func testAK22_OhneLogoOderUnerreichbarErscheintDerPlatzhalter() throws {
        let (c, _) = try fileContainer("ak22")
        let pl = try B04QA.seed(c.mainContext, name: "QA Ladeindikator", items: [
            .init("B1 ohne Logo", "Logos", logo: nil),
            .init("B2 Port geschlossen", "Logos", logo: "http://127.0.0.1:9/logo.png"),
            .init("B3 https ohne Gegenstelle", "Logos", logo: "https://127.0.0.1:9/logo.png"),
            .init("B4 Host unbekannt", "Logos", logo: "http://logo-host.invalid/x.png"),
            .init("B5 Weiterleitungsschleife", "Logos", logo: "\(host.base)/redirect-loop?b=5"),
            .init("B6 Bild kommt", "Logos", logo: "\(host.base)/nocache/ok.png"),
        ])
        let w = window(c, size: CGSize(width: 900, height: 760))
        w.open(pl, wait: 10.0)
        w.shot("BUILD-AK-22-platzhalter")
        let busy = w.busyRows.sorted()
        let schleife = host.requests("/redirect-loop").count
        B04QA.log("AK-22|nach10s|busy=\(busy)|spinner=\(w.spinnerCount)|schleifenanfragen=\(schleife)")
        B04QA.spin(8.0)
        let busy2 = w.busyRows.sorted()
        let punkte = w.rows.map { "\($0.label)=\(logoTreffer(w, $0.label))" }
        B04QA.log("AK-22|nach18s|busy=\(busy2)|logopunkte=\(punkte)")
        // Seit B04 · BUG-04 (Build 2026-09-29): ohne Adresse und bei jedem Fehler der Platzhalter, kein Ladeindikator.
        XCTAssertEqual(busy2, [], "bei fehlender Adresse und bei Verbindungsfehlern erscheint der Platzhalter")
        XCTAssertEqual(w.spinnerCount, 0)
        XCTAssertEqual(w.rows.count, 6)
        XCTAssertGreaterThan(logoTreffer(w, "B6 Bild kommt"), 400, "das erreichbare Logo wird angezeigt")
        for platzhalter in ["B1", "B2", "B3", "B4", "B5"] {
            XCTAssertLessThan(logoTreffer(w, platzhalter), 40, "\(platzhalter): graues TV-Symbol statt Bild")
        }
        XCTAssertLessThanOrEqual(schleife, 1 + ChannelLogoLoader.Limits.standard.maxRedirects,
                                 "eine Weiterleitungsschleife endet nach wenigen Anfragen")
    }

    // MARK: - AK-23

    func testAK23_AbbruchBeimWegscrollenUndVerlassen() throws {
        let (c, _) = try fileContainer("ak23")
        let items = (0..<2_000).map { i in
            B04QA.Item("Sender \(String(format: "%04d", i))", "Alle", logo: "\(host.base)/nocache/\(i).png?d=8")
        }
        let pl = try B04QA.seed(c.mainContext, name: "QA Abbruch", items: items)
        let w = window(c, size: CGSize(width: 900, height: 700))
        w.open(pl, wait: 2.5)
        let ersteAnfragen = host.requests.map(\.path)
        B04QA.log("AK-23|nachOeffnen|anfragen=\(ersteAnfragen.count) \(ersteAnfragen.prefix(8))")
        XCTAssertGreaterThan(ersteAnfragen.count, 0, "Logos der sichtbaren Karten angefragt")

        let doc = w.scrollView?.documentView?.bounds.height ?? 0
        let vorScroll = Date()
        w.scroll(toY: doc / 2, wait: 1.5)
        let abbrueche1 = host.events.filter { $0.kind == "closedBeforeResponse" && $0.time > vorScroll }
        B04QA.log("AK-23|nachScrollMitte|abbrueche=\(abbrueche1.count) (\(abbrueche1.prefix(8).map(\.target)))|maxVerzoegerung=\(B04QA.f1((abbrueche1.map { $0.time.timeIntervalSince(vorScroll) }.max() ?? -1)))s")
        XCTAssertGreaterThan(abbrueche1.count, 0, "laufende Anfragen der weggescrollten Karten werden abgebrochen")
        XCTAssertLessThan(abbrueche1.map { $0.time.timeIntervalSince(vorScroll) }.max() ?? 99, 1.5, "Abbruch sofort")

        let vorEnde = Date()
        w.scroll(toY: max(0, doc - 700), wait: 1.5)
        let abbrueche2 = host.events.filter { $0.kind == "closedBeforeResponse" && $0.time > vorEnde }
        let vorVerlassen = Date()
        w.back(wait: 1.5)
        let abbrueche3 = host.events.filter { $0.kind == "closedBeforeResponse" && $0.time > vorVerlassen }
        B04QA.log("AK-23|nachScrollEnde|abbrueche=\(abbrueche2.count)|nachVerlassen|abbrueche=\(abbrueche3.count)")
        XCTAssertGreaterThan(abbrueche2.count, 0)
        XCTAssertGreaterThan(abbrueche3.count, 0, "beim Verlassen der Liste bricht die App die letzten Anfragen ab")
        B04QA.evidence("AK-23-abbruch.txt",
                       "2.000 Sender, Logos 8 s verzögert: \(ersteAnfragen.count) Anfragen beim Öffnen, "
                       + "\(abbrueche1.count) Abbrüche beim Scrollen zur Mitte, \(abbrueche2.count) beim Scrollen ans Ende, "
                       + "\(abbrueche3.count) beim Verlassen")
    }

    func testAK23_ZeitgrenzeOhneDatenDannPlatzhalter() throws {
        let (c, _) = try fileContainer("ak23b")
        let pl = try B04QA.seed(c.mainContext, name: "QA Timeout", items: [
            .init("C1 antwortet nie", "Logos", logo: "\(host.base)/hang?c=1"),
        ])
        let w = window(c, size: CGSize(width: 900, height: 400))
        w.open(pl, wait: 2.0)
        let anfrage = try XCTUnwrap(host.requests("/hang").first)
        XCTAssertEqual(w.busyRows.count, 1, "Ladeindikator, solange die Anfrage läuft")
        // Seit B04 · BUG-04/BUG-05 (Build 2026-09-29): Leerlauffrist 10 s statt 60 s, danach der Platzhalter.
        let abbruch = B04QA.wait(30, poll: 0.5) { !self.host.events("/hang", kind: "closedBeforeResponse").isEmpty }
        let ereignis = host.events("/hang", kind: "closedBeforeResponse").first
        let dauer = ereignis.map { $0.time.timeIntervalSince(anfrage.time) } ?? -1
        B04QA.spin(1.0)
        B04QA.log("AK-23|timeout|abgebrochenNach=\(B04QA.f1(dauer))s|busyDanach=\(w.busyRows)|spinner=\(w.spinnerCount)")
        XCTAssertTrue(abbruch, "Anfrage wird abgebrochen")
        XCTAssertEqual(dauer, ChannelLogoLoader.Limits.standard.idleTimeout, accuracy: 3, "Abbruch nach der Leerlauffrist")
        XCTAssertEqual(w.busyRows.count, 0, "danach der Platzhalter statt des Ladeindikators")
        XCTAssertEqual(host.requests("/hang").count, 1, "kein erneuter Versuch, solange die Karte sichtbar bleibt")
    }

    // MARK: - AK-24

    func testAK24_GrenzenFuerDateigroesseUndBildabmessung() throws {
        let (c, _) = try fileContainer("ak24")
        B04QA.log("AK-24|bilder|bigdim=\(B04Image.bigDimension.count) Bytes|bigfile=\(B04Image.bigFile.count) Bytes")
        let pl = try B04QA.seed(c.mainContext, name: "QA Groß", items: [
            .init("D1 12000x12000", "Logos", logo: "\(host.base)/bigdim.png"),
            .init("D2 27 MB", "Logos", logo: "\(host.base)/bigfile.png"),
            .init("D3 normal", "Logos", logo: "\(host.base)/nocache/d3.png"),
        ])
        let w = window(c, size: CGSize(width: 900, height: 360))
        let vorher = B04QA.footprintMB()
        w.open(pl, wait: 12.0)
        let waehrend = B04QA.footprintMB()
        B04QA.spin(8.0)
        let spaeter = B04QA.footprintMB()
        let karten = w.rows.map { "\($0.label)|busy=\($0.busy)|logopunkte=\(logoTreffer(w, $0.label))" }
        w.back(wait: 4.0)
        B04QA.spin(4.0)
        let nachher = B04QA.footprintMB()
        let bytes = host.events.map { "\($0.target)=\($0.kind) \($0.detail)" }
        B04QA.log("AK-24|speicherMB|vorher=\(B04QA.f0(vorher))|geladen=\(B04QA.f0(waehrend))|nach8s=\(B04QA.f0(spaeter))|nachVerlassen8s=\(B04QA.f0(nachher))|karten=\(karten)|ereignisse=\(bytes)")
        XCTAssertEqual(host.requests("/bigdim").count, 1)
        XCTAssertEqual(host.requests("/bigfile").count, 1)
        // Seit B04 · BUG-05 (Build 2026-09-29): Größen- und Abmessungsgrenze, das Bild wird nie voll dekodiert.
        XCTAssertLessThan(max(waehrend, spaeter) - vorher, 150,
                          "Logos werden begrenzt (Größe/Abmessung), der Speicher steigt nicht um Hunderte MB")
        XCTAssertTrue(karten.contains { $0.hasPrefix("D1 12000x12000, Logos|busy=false") }, "Platzhalter statt Ladeindikator: \(karten)")
        XCTAssertTrue(karten.contains { $0.hasPrefix("D2 27 MB, Logos|busy=false") }, "Platzhalter statt Ladeindikator: \(karten)")
        XCTAssertTrue(karten.contains { $0.hasPrefix("D3 normal, Logos|busy=false|logopunkte=") && (Int($0.split(separator: "=").last ?? "") ?? 0) > 400 },
                      "ein normales Logo daneben wird angezeigt: \(karten)")
    }

    // MARK: - AK-25 / AK-26

    func testAK25_AK26_WeiterleitungenUndWasJederLogoHostErfaehrt() throws {
        let zweiter = B04LogoHost { _ in .image(B04Image.small) }
        try zweiter.start()
        defer { zweiter.purgeCache(); zweiter.stop() }

        let (c, _) = try fileContainer("ak25")
        let ziel = "\(zweiter.base)/nocache/ziel.png"
        let pl = try B04QA.seed(c.mainContext, name: "QA Weiterleitung", items: [
            .init("E1 direkt", "Logos", logo: "\(host.base)/nocache/e1.png"),
            .init("E2 Weiterleitung fremder Host und Port", "Logos",
                  logo: "\(host.base)/redirect?to=\(ziel.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ziel)"),
            .init("E3 Weiterleitungsschleife", "Logos", logo: "\(host.base)/redirect-loop?e=3"),
            .init("E4 Weiterleitung selber Host", "Logos", logo: "\(host.base)/redirect?to=%2Fnocache%2Fe4.png"),
        ])
        let w = window(c, size: CGSize(width: 900, height: 560))
        let start = Date()
        w.open(pl, wait: 5.0)
        let schleife = host.requests("/redirect-loop")
        let dauerSchleife = (schleife.last?.time.timeIntervalSince(schleife.first?.time ?? start) ?? -1)
        B04QA.log("AK-25|anfragenHost1=\(host.requests.map(\.target))")
        B04QA.log("AK-25|anfragenHost2=\(zweiter.requests.map(\.target))|schleife=\(schleife.count) Anfragen in \(B04QA.f1(dauerSchleife * 1000)) ms|busy=\(w.busyRows)")
        B04QA.log("AK-25|karten=\(w.rows.map { "\($0.label)|busy=\($0.busy)|logopunkte=\(logoTreffer(w, $0.label))" })")
        // Seit B04 · BUG-06 (Build 2026-09-29): Weiterleitungen nur auf denselben Host und Port, höchstens drei.
        XCTAssertEqual(zweiter.requests.count, 0, "Weiterleitungen auf fremde Hosts werden nicht gefolgt")
        XCTAssertLessThanOrEqual(schleife.count, 1 + ChannelLogoLoader.Limits.standard.maxRedirects, "Schleife endet nach wenigen Anfragen")
        XCTAssertEqual(w.busyRows, [], "danach Platzhalter statt Ladeindikator (BUG-04)")
        XCTAssertLessThan(logoTreffer(w, "E2"), 40, "fremde Weiterleitung: Platzhalter")
        XCTAssertEqual(host.requests("/nocache/e4.png").count, 1, "Weiterleitung auf demselben Host wird gefolgt")
        XCTAssertGreaterThan(logoTreffer(w, "E4"), 400, "und das Logo angezeigt")

        // AK-26: der tatsächliche Payload an den Logo-Host
        let kopf1 = try XCTUnwrap(host.requests("/nocache/e1.png").first)
        B04QA.log("AK-26|Logo-Host|kopfzeilen=\(kopf1.headers)")
        B04QA.evidence("BUILD-AK-26-kopfzeilen.txt", "Logo-Host: \(kopf1.rawHead.replacingOccurrences(of: "\r\n", with: " · "))")
        let ua = kopf1.headers["User-Agent"] ?? ""
        XCTAssertEqual(ua, "Mozilla/5.0", "neutraler User-Agent")
        XCTAssertFalse(ua.contains("Mika") || ua.contains("CFNetwork") || ua.contains("Darwin"), "keine App- und Systemdaten (\(ua))")
        XCTAssertEqual(kopf1.headers["Accept-Language"], "*", "keine Systemsprache")
        XCTAssertNil(kopf1.headers["Cookie"], "keine Cookies")
        XCTAssertNil(kopf1.headers["Referer"], "kein Referer")
        // Nur HTTPS ist eine offene Produktfrage (spec.md OF-07): http:// bleibt erlaubt (ATS unverändert)
        let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
        B04QA.log("AK-25|ATS=\(ats ?? [:])")
        XCTAssertEqual(ats?["NSAllowsArbitraryLoads"] as? Bool, true, "HTTP-Logos weiter erlaubt (Info.plist, OF-07)")
    }

    // MARK: - AK-27

    func testAK27_LogoHostErfaehrtWonachDerNutzerSuchtOderFiltert() throws {
        let (c, _) = try fileContainer("ak27")
        var items: [B04QA.Item] = []
        for (i, gruppe) in ["Religion", "Sport", "News", "Kino"].enumerated() {
            for k in 0..<12 {
                items.append(.init("\(gruppe) Kanal \(k)", gruppe, logo: "\(host.base)/nocache/\(gruppe.lowercased())-\(i)-\(k).png"))
            }
        }
        let pl = try B04QA.seed(c.mainContext, name: "QA Interessen", items: items)
        let w = window(c, size: CGSize(width: 900, height: 700))
        w.open(pl, wait: 3.0)
        let beimOeffnen = Set(host.requests.map(\.path))
        host.resetLog()
        XCTAssertTrue(w.type("Religion", wait: 2.5))
        let nachSuche = host.requests.map(\.path)
        XCTAssertTrue(w.type("", wait: 2.5))
        host.resetLog()
        // Chip auf eine Gruppe, deren Karten beim Öffnen nicht sichtbar waren (Sortierung: Kino, News, Religion, Sport)
        XCTAssertTrue(w.pressChip("Sport", wait: 2.5))
        let nachChip = host.requests.map(\.path)
        B04QA.log("AK-27|beimOeffnen=\(beimOeffnen.count) Pfade|nachSuche „Religion“=\(nachSuche)|nachChip „Sport“=\(nachChip.prefix(12))")
        B04QA.evidence("AK-27-sichtbare-sender.txt",
                       "Beim Öffnen \(beimOeffnen.count) Logos (\(beimOeffnen.sorted().prefix(3).joined(separator: ", ")) …). "
                       + "Nach der Suche „Religion“ fragte die App genau die Logos der Treffer an: \(nachSuche.joined(separator: ", ")). "
                       + "Nach dem Chip „Sport“: \(nachChip.joined(separator: ", "))")
        XCTAssertTrue(nachSuche.allSatisfy { $0.contains("religion") }, "nur Logos der Treffer")
        XCTAssertGreaterThan(nachSuche.count, 3, "der Host sieht, wonach gesucht wurde")
        XCTAssertFalse(beimOeffnen.contains { $0.contains("religion") || $0.contains("sport") }, "vorher nicht sichtbar")
        XCTAssertGreaterThan(nachChip.count, 3, "der Host sieht, nach welcher Gruppe gefiltert wurde")
        XCTAssertTrue(nachChip.allSatisfy { $0.contains("sport") }, "nur Logos der Gruppe")
        // BUG-06, Teil „Logos abschaltbar“: nicht gebaut, wartet auf spec.md OF-07 (Produktentscheidung).
        XCTExpectFailure("BUG-06 (Teil) · Logo-Hosts erfahren, welche Sender der Nutzer gerade ansieht – Abschalten wartet auf OF-07") {
            XCTAssertEqual(nachSuche, [], "Filtern löst keine Anfragen an Dritte aus bzw. ist abschaltbar")
        }
    }

    // MARK: - AK-28

    func testAK28_KeinPlattencacheUndLoeschenLeertDieLogos() throws {
        let (c, _) = try fileContainer("ak28")
        let ctx = c.mainContext
        let adressen = [
            "F1 max-age": "\(host.base)/maxage/f1.png",
            "F2 ohne Cache-Header": "\(host.base)/nocache/f2.png",
            "F3 no-store": "\(host.base)/nostore/f3.png",
            "F4 HTML": "\(host.base)/html?f=4",
            "F5 404": "\(host.base)/404?f=5",
            "F6 JSON": "\(host.base)/json?f=6",
        ]
        let pl = try B04QA.seed(ctx, name: "QA Cache", items: adressen.sorted { $0.key < $1.key }.map {
            .init($0.key, "Logos", logo: $0.value)
        })
        let w = window(c, size: CGSize(width: 900, height: 760))
        w.open(pl, wait: 4.0)
        let ersteAnfragen = host.requests.map(\.path)
        XCTAssertEqual(Set(ersteAnfragen).count, 6)

        var imCache: [String: String] = [:]
        var imSpeicher: [String: Bool] = [:]
        for (name, adresse) in adressen {
            let url = URL(string: adresse)!
            let antwort = URLCache.shared.cachedResponse(for: URLRequest(url: url))
            imCache[name] = antwort.map { "\(($0.response as? HTTPURLResponse)?.statusCode ?? -1)/\($0.data.count) Bytes" } ?? "nicht im Cache"
            imSpeicher[name] = ChannelLogoLoader.shared.cachedImage(for: url) != nil
        }
        let dbZeilen = B04QA.cacheRows(prefix: host.base)
        B04QA.log("AK-28|URLCache=\(imCache.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })")
        B04QA.log("AK-28|Arbeitsspeicher=\(imSpeicher.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })")
        B04QA.log("AK-28|CacheDb=\(B04QA.hostCacheDB.path)|zeilen=\(dbZeilen.count)|\(dbZeilen.prefix(8))")
        // Seit B04 · BUG-07 (Build 2026-09-29): nichts im gemeinsamen URLCache und in Cache.db; nur fertige Bilder im
        // Arbeitsspeicher, `no-store` und Fehlerantworten nie.
        XCTAssertTrue(imCache.values.allSatisfy { $0 == "nicht im Cache" }, "\(imCache)")
        XCTAssertEqual(dbZeilen.count, 0, "keine Einträge in Cache.db")
        XCTAssertEqual(imSpeicher, ["F1 max-age": true, "F2 ohne Cache-Header": true, "F3 no-store": false,
                                    "F4 HTML": false, "F5 404": false, "F6 JSON": false])

        // Zweites Öffnen: Bilder aus dem Arbeitsspeicher, no-store und Fehler werden erneut angefragt
        host.resetLog()
        w.back(wait: 1.0)
        w.open(pl, wait: 4.0)
        let zweiteAnfragen = Set(host.requests.map(\.path))
        B04QA.log("AK-28|zweitesOeffnen|anfragen=\(zweiteAnfragen.sorted())")
        XCTAssertFalse(zweiteAnfragen.contains("/maxage/f1.png"), "Logo kommt aus dem Arbeitsspeicher")
        XCTAssertFalse(zweiteAnfragen.contains("/nocache/f2.png"), "Logo kommt aus dem Arbeitsspeicher")
        XCTAssertTrue(zweiteAnfragen.contains("/nostore/f3.png"), "no-store wird nicht aufbewahrt")

        // Playlist löschen: die Logos gehen mit
        w.back(wait: 1.0)
        try B04QA.run(60) { try await PlaylistImporter(modelContext: ctx).delete(pl) }
        B04QA.spin(1.0)
        let nachLoeschen = B04QA.cacheRows(prefix: host.base)
        let nochImCache = adressen.values.filter { URLCache.shared.cachedResponse(for: URLRequest(url: URL(string: $0)!)) != nil }
        let nochImSpeicher = adressen.values.filter { ChannelLogoLoader.shared.cachedImage(for: URL(string: $0)!) != nil }
        B04QA.log("AK-28|nachLoeschen|CacheDbZeilen=\(nachLoeschen.count)|nochImURLCache=\(nochImCache.count)|nochImArbeitsspeicher=\(nochImSpeicher.count)|kanaeleInDB=\(try ctx.fetch(FetchDescriptor<Channel>()).count)")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Channel>()).count, 0)
        XCTAssertEqual(nachLoeschen.count, 0)
        XCTAssertEqual(nochImCache.count, 0)
        XCTAssertEqual(nochImSpeicher.count, 0, "Löschen der Playlist entfernt die Logos")
    }

    // MARK: - EC-05

    func testEC05_LogoAdresseMitFileSchemaZeigtPlatzhalter() throws {
        let (c, _) = try fileContainer("ec05")
        let datei = "file:///System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns"
        let pl = try B04QA.seed(c.mainContext, name: "QA file", items: [
            .init("G1 file-URL", "Logos", logo: datei),
            .init("G2 Bild", "Logos", logo: "\(host.base)/nocache/g2.png"),
            .init("G3 Platzhalter", "Logos", logo: "\(host.base)/404?g=3"),
        ])
        let w = window(c, size: CGSize(width: 900, height: 400))
        w.open(pl, wait: 4.0)
        w.shot("BUILD-EC-05-file-logo")
        B04QA.log("EC-05|busy=\(w.busyRows)|netzanfragen=\(host.requests.map(\.path))|logopunkteG1=\(logoTreffer(w, "G1"))")
        XCTAssertFalse(w.busyRows.contains { $0.hasPrefix("G1") }, "kein Ladeindikator")
        XCTAssertEqual(Set(host.requests.map(\.path)), ["/nocache/g2.png", "/404"], "kein Netzwerkaufruf für die file-Adresse")
        func saettigung(_ label: String) -> Double {
            guard let row = w.rows.first(where: { $0.label.hasPrefix(label) }) else { return -1 }
            let r = w.inWindow(row.frame)
            return B04Shot.saturation(w.window, in: NSRect(x: r.minX + 8, y: r.minY + 14, width: 48, height: 48))
        }
        let s1 = saettigung("G1"), s3 = saettigung("G3")
        B04QA.log("EC-05|saettigung|fileLogo=\(String(format: "%.3f", s1))|platzhalter=\(String(format: "%.3f", s3))")
        // Seit B04 (Build 2026-09-29): nur http/https-Logos; file: ergibt den Platzhalter (OF-06 bleibt zur Bestätigung).
        XCTAssertLessThan(abs(s1 - s3), 0.02, "das lokale Bild wird nicht angezeigt, sondern der graue Platzhalter")
    }

    // MARK: - EC-06

    func testEC06_TroepfelnderHostWirdNachDerGesamtfristGetrennt() throws {
        let (c, _) = try fileContainer("ec06")
        let pl = try B04QA.seed(c.mainContext, name: "QA Tröpfeln", items: [
            .init("H1 tröpfelt", "Logos", logo: "\(host.base)/trickle?i=4"),
        ])
        let w = window(c, size: CGSize(width: 900, height: 400))
        w.open(pl, wait: 2.0)
        let anfrage = try XCTUnwrap(host.requests("/trickle").first)
        XCTAssertEqual(w.busyRows.count, 1)
        B04QA.wait(30, poll: 0.5) { !self.host.events("/trickle", kind: "closedBeforeResponse").isEmpty }
        B04QA.spin(1.0)
        let abbruch = host.events("/trickle", kind: "closedBeforeResponse").first
        let dauer = abbruch.map { $0.time.timeIntervalSince(anfrage.time) } ?? -1
        B04QA.log("EC-06|busy=\(w.busyRows)|abbruch=\(B04QA.f1(dauer))s|ereignisse=\(host.events("/trickle").map(\.kind))")
        // Seit B04 · BUG-05 (Build 2026-09-29): Gesamtfrist 15 s je Logo, auch wenn Daten tröpfeln.
        XCTAssertNotNil(abbruch, "die Verbindung wird getrennt, obwohl Daten tröpfeln")
        XCTAssertLessThanOrEqual(dauer, ChannelLogoLoader.Limits.standard.totalTimeout + 2, "spätestens nach der Gesamtfrist")
        XCTAssertEqual(w.busyRows.count, 0, "danach der Platzhalter")
    }

    // MARK: - EC-07

    func testEC07_WegscrollenUndZurueckscrollenWaehrendDesLadens() throws {
        let (c, _) = try fileContainer("ec07")
        let items = (0..<40).map { i in
            B04QA.Item("Sender \(String(format: "%02d", i))", "Alle", logo: "\(host.base)/nocache/e\(i).png?d=4")
        }
        let pl = try B04QA.seed(c.mainContext, name: "QA Zurueck", items: items)
        let w = window(c, size: CGSize(width: 900, height: 700))
        w.open(pl, wait: 1.5)
        let ersteKarten = w.cardNames
        let ersteAnfragen = host.requests.map(\.path)
        let doc = w.scrollView?.documentView?.bounds.height ?? 0
        w.scroll(toY: doc - 700, wait: 2.0)
        w.scroll(toY: 0, wait: 25.0)
        let alle = host.requests.map(\.path)
        let mehrfach = Dictionary(grouping: alle, by: { $0 }).filter { $0.value.count > 1 }
        B04QA.log("EC-07|ersteKarten=\(ersteKarten.count)|ersteAnfragen=\(ersteAnfragen)|gesamt=\(alle.count)|mehrfach=\(mehrfach.mapValues(\.count))")
        // Build 2026-09-29: Die Rahmen der Karten im Accessibility-Baum folgen dem Zurückscrollen nicht immer sofort (einmal
        // 0 Logopunkte gemessen, obwohl die Aufnahme direkt danach alle Logos zeigte) – bis zu 3 s nachmessen.
        var logopunkte0 = logoTreffer(w, "Sender 00")
        if logopunkte0 <= 400 {
            let zeilen = w.rows.prefix(3).map { "\($0.label)@\(w.inWindow($0.frame))" }
            B04QA.log("EC-07|ersteMessung=\(logopunkte0)|zeilen=\(zeilen)")
            B04QA.wait(3, poll: 0.3) { logopunkte0 = self.logoTreffer(w, "Sender 00"); return logopunkte0 > 400 }
        }
        B04QA.log("EC-07|nachZurueck|busy=\(w.busyRows)|logopunkte0=\(logopunkte0)")
        w.shot("EC-07-zurueckgescrollt")
        B04QA.evidence("EC-07-neuladen.txt",
                       "40 Sender, Logos 4 s verzögert: beim Öffnen \(ersteAnfragen.count) Anfragen, nach Wegscrollen und "
                       + "Zurückscrollen \(alle.count) Anfragen, davon mehrfach: \(mehrfach.mapValues(\.count))")
        XCTAssertFalse(mehrfach.isEmpty, "die weggescrollten, abgebrochenen Logos werden erneut angefragt")
        XCTAssertGreaterThan(logopunkte0, 400, "das Logo der obersten Karte ist nach dem Zurückscrollen da")
        // Build 2026-09-30: Alle sichtbaren Karten zeigen ihr Logo, keine den Platzhalter. (Im Gesamtlauf vom 30.09. zeigten
        // „Sender 00“ und „Sender 02“ den Platzhalter: Ihre neuen Anfragen warteten hinter anderen auf eine Verbindung und
        // liefen in der Warteschlange ab – behoben mit `RequestGate`, die Fristen beginnen jetzt mit dem Senden.)
        let sichtbar = (0..<6).map { String(format: "Sender %02d", $0) }
        let ohneLogo = sichtbar.filter { logoTreffer(w, $0) <= 400 }
        XCTAssertEqual(ohneLogo, [], "alle sechs sichtbaren Karten zeigen ihr Logo")
        XCTAssertLessThanOrEqual(w.busyRows.count, 3, "die übrigen Karten lösen sich auf (6 Verbindungen je Host, 4 s Verzögerung)")
    }
}
