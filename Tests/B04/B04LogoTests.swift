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

    func testAK22_OhneLogoOderUnerreichbarDrehtDerLadeindikatorDauerhaft() throws {
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
        w.shot("AK-22-ladeindikator")
        let busy = w.busyRows.sorted()
        B04QA.log("AK-22|nach10s|busy=\(busy)|spinner=\(w.spinnerCount)|schleifenanfragen=\(host.requests("/redirect-loop").count)")
        B04QA.spin(8.0)
        let busy2 = w.busyRows.sorted()
        B04QA.log("AK-22|nach18s|busy=\(busy2)")
        B04QA.evidence("AK-22-ladeindikator.txt", "nach 10 s: \(busy.joined(separator: ", ")) · nach 18 s: \(busy2.joined(separator: ", "))")
        XCTAssertEqual(busy2, ["B1 ohne Logo, Logos", "B2 Port geschlossen, Logos", "B3 https ohne Gegenstelle, Logos",
                               "B4 Host unbekannt, Logos", "B5 Weiterleitungsschleife, Logos"],
                       "fünf Karten drehen dauerhaft")
        XCTAssertFalse(busy2.contains("B6 Bild kommt, Logos"))
        XCTExpectFailure("BUG-04 · Ladeindikator dreht dauerhaft statt Platzhalter (FB-04)") {
            XCTAssertEqual(busy2, [], "bei fehlender Adresse und bei Verbindungsfehlern erscheint der Platzhalter")
        }
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

    func testAK23_ZeitgrenzeSechzigSekundenOhneDaten() throws {
        let (c, _) = try fileContainer("ak23b")
        let pl = try B04QA.seed(c.mainContext, name: "QA Timeout", items: [
            .init("C1 antwortet nie", "Logos", logo: "\(host.base)/hang?c=1"),
        ])
        let w = window(c, size: CGSize(width: 900, height: 400))
        w.open(pl, wait: 2.0)
        let anfrage = try XCTUnwrap(host.requests("/hang").first)
        XCTAssertEqual(w.busyRows.count, 1)
        // 60-s-Leerlaufgrenze von URLSession abwarten
        let abbruch = B04QA.wait(75, poll: 1.0) { !self.host.events("/hang", kind: "closedBeforeResponse").isEmpty }
        let ereignis = host.events("/hang", kind: "closedBeforeResponse").first
        let dauer = ereignis.map { $0.time.timeIntervalSince(anfrage.time) } ?? -1
        B04QA.spin(2.0)
        B04QA.log("AK-23|timeout|abgebrochenNach=\(B04QA.f1(dauer))s|busyDanach=\(w.busyRows)|spinner=\(w.spinnerCount)")
        B04QA.evidence("AK-23-timeout.txt", "Host antwortet nie: App schloss die Verbindung nach \(B04QA.f1(dauer)) s; Ladeindikator dreht weiter (\(w.busyRows.count) Karte)")
        XCTAssertTrue(abbruch, "Anfrage wird abgebrochen")
        XCTAssertEqual(dauer, 60, accuracy: 8, "Abbruch nach rund 60 s ohne Daten")
        XCTAssertEqual(w.busyRows.count, 1, "Ladeindikator bleibt danach stehen (wie AK-22)")
    }

    // MARK: - AK-24

    func testAK24_KeineGrenzeFuerDateigroesseUndBildabmessung() throws {
        let (c, _) = try fileContainer("ak24")
        B04QA.log("AK-24|bilder|bigdim=\(B04Image.bigDimension.count) Bytes|bigfile=\(B04Image.bigFile.count) Bytes")
        let pl = try B04QA.seed(c.mainContext, name: "QA Groß", items: [
            .init("D1 12000x12000", "Logos", logo: "\(host.base)/bigdim.png"),
            .init("D2 27 MB", "Logos", logo: "\(host.base)/bigfile.png"),
        ])
        let w = window(c, size: CGSize(width: 900, height: 300))
        let vorher = B04QA.footprintMB()
        w.open(pl, wait: 12.0)
        let waehrend = B04QA.footprintMB()
        B04QA.spin(8.0)
        let spaeter = B04QA.footprintMB()
        w.back(wait: 4.0)
        B04QA.spin(4.0)
        let nachher = B04QA.footprintMB()
        B04QA.spin(22.0)
        let nachher30 = B04QA.footprintMB()
        let bytes = host.events.filter { $0.kind == "served" }.map { "\($0.target)=\($0.detail)" }
        B04QA.log("AK-24|speicherMB|vorher=\(B04QA.f0(vorher))|geladen=\(B04QA.f0(waehrend))|nach8s=\(B04QA.f0(spaeter))|nachVerlassen8s=\(B04QA.f0(nachher))|nachVerlassen30s=\(B04QA.f0(nachher30))|antworten=\(bytes)")
        B04QA.evidence("AK-24-speicher.txt",
                       "12.000 × 12.000 px (\(B04Image.bigDimension.count) Bytes) und \(B04Image.bigFile.count) Bytes: "
                       + "Speicher \(B04QA.f0(vorher)) → \(B04QA.f0(waehrend)) MB (nach 8 s \(B04QA.f0(spaeter)) MB), "
                       + "8 s nach dem Verlassen \(B04QA.f0(nachher)) MB, 30 s danach \(B04QA.f0(nachher30)) MB")
        XCTAssertEqual(host.requests("/bigdim").count, 1)
        XCTAssertEqual(host.requests("/bigfile").count, 1)
        XCTAssertGreaterThan(max(waehrend, spaeter) - vorher, 150, "beide Antworten werden vollständig geladen und dekodiert")
        XCTExpectFailure("BUG-05 · keine Grenze für Dateigröße, Bildabmessung oder Dauer eines Logos (FB-05)") {
            XCTAssertLessThan(max(waehrend, spaeter) - vorher, 150,
                              "Logos werden begrenzt (Größe/Abmessung), der Speicher steigt nicht um Hunderte MB")
        }
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
        ])
        let w = window(c, size: CGSize(width: 900, height: 500))
        let start = Date()
        w.open(pl, wait: 5.0)
        let schleife = host.requests("/redirect-loop")
        let dauerSchleife = (schleife.last?.time.timeIntervalSince(schleife.first?.time ?? start) ?? -1)
        B04QA.log("AK-25|anfragenHost1=\(host.requests.map(\.target))")
        B04QA.log("AK-25|anfragenHost2=\(zweiter.requests.map(\.target))|schleife=\(schleife.count) Anfragen in \(B04QA.f1(dauerSchleife * 1000)) ms|busy=\(w.busyRows)")
        XCTAssertEqual(zweiter.requests.count, 1, "die App folgt der Weiterleitung auf anderen Host und Port ohne Rückfrage")
        XCTAssertGreaterThan(schleife.count, 15, "Weiterleitungsschleife wird vielfach verfolgt")
        XCTAssertLessThan(dauerSchleife, 2.0, "Schleife in Millisekunden")
        XCTAssertTrue(w.busyRows.contains { $0.hasPrefix("E3") }, "danach dreht der Ladeindikator weiter")

        // AK-26: der tatsächliche Payload beider Hosts
        let kopf1 = try XCTUnwrap(host.requests("/nocache/e1.png").first)
        let kopf2 = try XCTUnwrap(zweiter.requests.first)
        for (name, req) in [("Logo-Host", kopf1), ("Weiterleitungsziel", kopf2)] {
            B04QA.log("AK-26|\(name)|kopfzeilen=\(req.headers)")
            B04QA.evidence("AK-26-kopfzeilen.txt", "\(name): \(req.rawHead.replacingOccurrences(of: "\r\n", with: " · "))")
            let ua = req.headers["User-Agent"] ?? ""
            XCTAssertTrue(ua.hasPrefix("Mika+Player/"), "\(name): App-Name und Build im User-Agent (\(ua))")
            XCTAssertTrue(ua.contains("CFNetwork/") && ua.contains("Darwin/"), "\(name): Betriebssystemversion im User-Agent")
            XCTAssertNotNil(req.headers["Accept-Language"], "\(name): Systemsprache")
            XCTAssertEqual(req.headers["Accept"], "*/*")
            XCTAssertEqual(req.headers["Accept-Encoding"], "gzip, deflate")
            XCTAssertNil(req.headers["Cookie"], "\(name): keine Cookies")
            XCTAssertNil(req.headers["Referer"], "\(name): kein Referer")
        }
        // http:// ohne Verschlüsselung ist erlaubt (ATS)
        let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
        B04QA.log("AK-25|ATS=\(ats ?? [:])")
        XCTAssertEqual(ats?["NSAllowsArbitraryLoads"] as? Bool, true, "HTTP-Logos erlaubt (Info.plist)")

        XCTExpectFailure("BUG-06 · Logos gehen ungefragt an beliebige Hosts, unverschlüsselt und über Weiterleitungen (FB-06)") {
            XCTAssertEqual(zweiter.requests.count, 0, "Weiterleitungen auf fremde Hosts werden nicht gefolgt")
            XCTAssertNil(kopf1.headers["User-Agent"], "keine App- und Systemdaten an Logo-Hosts")
        }
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
        XCTExpectFailure("BUG-06 · Logo-Hosts erfahren ungefragt, welche Sender der Nutzer gerade ansieht (FB-06)") {
            XCTAssertEqual(nachSuche, [], "Filtern löst keine Anfragen an Dritte aus bzw. ist abschaltbar")
        }
    }

    // MARK: - AK-28

    func testAK28_LogoAntwortenLiegenImPlattencacheUndUeberlebenDasLoeschen() throws {
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
        for (name, adresse) in adressen {
            let url = URL(string: adresse)!
            let antwort = URLCache.shared.cachedResponse(for: URLRequest(url: url))
            imCache[name] = antwort.map { "\(($0.response as? HTTPURLResponse)?.statusCode ?? -1)/\($0.data.count) Bytes" } ?? "nicht im Cache"
        }
        let dbZeilen = B04QA.cacheRows(prefix: host.base)
        B04QA.log("AK-28|imCache=\(imCache.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })")
        B04QA.log("AK-28|CacheDb=\(B04QA.hostCacheDB.path)|zeilen=\(dbZeilen.count)|\(dbZeilen.prefix(8))")
        B04QA.evidence("AK-28-cache.txt",
                       "URLCache: " + imCache.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                       + " · Cache.db-Zeilen: \(dbZeilen.count)")
        XCTAssertEqual(imCache.count, 6)
        XCTAssertFalse(imCache["F3 no-store"]?.hasPrefix("nicht") ?? true, "Antwort mit no-store liegt im Cache")
        XCTAssertFalse(imCache["F5 404"]?.hasPrefix("nicht") ?? true, "404-Antwort liegt im Cache")
        XCTAssertFalse(imCache["F4 HTML"]?.hasPrefix("nicht") ?? true, "HTML-Antwort liegt im Cache")
        XCTAssertGreaterThanOrEqual(dbZeilen.count, 6, "Einträge in Cache.db auf der Platte")

        // Zweites Öffnen: max-age wird nicht erneut angefragt, alles andere schon
        host.resetLog()
        w.back(wait: 1.0)
        w.open(pl, wait: 4.0)
        let zweiteAnfragen = Set(host.requests.map(\.path))
        B04QA.log("AK-28|zweitesOeffnen|anfragen=\(zweiteAnfragen.sorted())")
        XCTAssertFalse(zweiteAnfragen.contains("/maxage/f1.png"), "max-age-Logo kommt aus dem Cache")
        XCTAssertTrue(zweiteAnfragen.contains("/nostore/f3.png"), "no-store wird erneut angefragt – und erneut gespeichert")

        // Playlist löschen: die Cache-Einträge bleiben
        w.back(wait: 1.0)
        try PlaylistImporter(modelContext: ctx).delete(pl)
        B04QA.spin(1.0)
        let nachLoeschen = B04QA.cacheRows(prefix: host.base)
        let nochImCache = adressen.values.filter { URLCache.shared.cachedResponse(for: URLRequest(url: URL(string: $0)!)) != nil }
        B04QA.log("AK-28|nachLoeschen|CacheDbZeilen=\(nachLoeschen.count)|nochImCache=\(nochImCache.count)|kanaeleInDB=\(try ctx.fetch(FetchDescriptor<Channel>()).count)")
        B04QA.evidence("AK-28-cache.txt", "Nach dem Löschen der Playlist: \(nachLoeschen.count) Cache.db-Zeilen, \(nochImCache.count) von 6 Adressen weiter im URLCache, 0 Sender in der Datenbank")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Channel>()).count, 0)
        XCTAssertGreaterThanOrEqual(nochImCache.count, 5, "Logo-Adressen und Antworten überstehen das Löschen")

        XCTExpectFailure("BUG-07 · Logo-Antworten im Plattencache, auch no-store, und über das Löschen hinaus (FB-07)") {
            XCTAssertTrue(imCache["F3 no-store"]?.hasPrefix("nicht") ?? false, "no-store wird nicht gespeichert")
            XCTAssertEqual(nochImCache.count, 0, "Löschen der Playlist entfernt die Logo-Einträge")
        }
    }

    // MARK: - EC-05

    func testEC05_LogoAdresseMitFileSchema() throws {
        let (c, _) = try fileContainer("ec05")
        let datei = "file:///System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns"
        let pl = try B04QA.seed(c.mainContext, name: "QA file", items: [
            .init("G1 file-URL", "Logos", logo: datei),
            .init("G2 Bild", "Logos", logo: "\(host.base)/nocache/g2.png"),
            .init("G3 Platzhalter", "Logos", logo: "\(host.base)/404?g=3"),
        ])
        let w = window(c, size: CGSize(width: 900, height: 400))
        w.open(pl, wait: 4.0)
        w.shot("EC-05-file-logo")
        B04QA.log("EC-05|busy=\(w.busyRows)|netzanfragen=\(host.requests.map(\.path))|logopunkteG1=\(logoTreffer(w, "G1"))")
        XCTAssertFalse(w.busyRows.contains { $0.hasPrefix("G1") }, "lokale Datei wird geladen, der Ladeindikator verschwindet")
        XCTAssertEqual(Set(host.requests.map(\.path)), ["/nocache/g2.png", "/404"], "kein Netzwerkaufruf für die file-Adresse")
        // Wird das Bild angezeigt? Farbsättigung des Logofelds gegen die Karte mit Platzhalter halten
        func saettigung(_ label: String) -> Double {
            guard let row = w.rows.first(where: { $0.label.hasPrefix(label) }) else { return -1 }
            let r = w.inWindow(row.frame)
            return B04Shot.saturation(w.window, in: NSRect(x: r.minX + 8, y: r.minY + 14, width: 48, height: 48))
        }
        let s1 = saettigung("G1"), s3 = saettigung("G3")
        B04QA.log("EC-05|saettigung|fileLogo=\(String(format: "%.3f", s1))|platzhalter=\(String(format: "%.3f", s3))")
        B04QA.evidence("EC-05-file-logo.txt", "file://-Logo: Sättigung \(String(format: "%.3f", s1)) gegenüber Platzhalter \(String(format: "%.3f", s3)); Netzanfragen: \(host.requests.map(\.path))")
        XCTAssertGreaterThan(s1, s3 + 0.02, "das lokale Bild wird angezeigt, nicht der graue Platzhalter")
    }

    // MARK: - EC-06

    func testEC06_TroepfelnderHostHaeltDieVerbindungOffen() throws {
        let (c, _) = try fileContainer("ec06")
        let pl = try B04QA.seed(c.mainContext, name: "QA Tröpfeln", items: [
            .init("H1 tröpfelt", "Logos", logo: "\(host.base)/trickle?i=10"),
        ])
        let w = window(c, size: CGSize(width: 900, height: 400))
        w.open(pl, wait: 2.0)
        let anfrage = try XCTUnwrap(host.requests("/trickle").first)
        B04QA.spin(75.0)
        let abbruch = host.events("/trickle", kind: "closedBeforeResponse").first
        B04QA.log("EC-06|nach75s|busy=\(w.busyRows)|abbruch=\(abbruch.map { B04QA.f1($0.time.timeIntervalSince(anfrage.time)) + "s" } ?? "keiner")|ereignisse=\(host.events("/trickle").map(\.kind))")
        B04QA.evidence("EC-06-troepfeln.txt", "1 Byte je 10 s: nach 75 s \(abbruch == nil ? "keine" : "eine") Trennung, Karte \(w.busyRows.isEmpty ? "ohne" : "mit") Ladeindikator")
        XCTAssertNil(abbruch, "die 60-s-Leerlaufgrenze greift nicht, solange Daten tröpfeln")
        XCTAssertEqual(w.busyRows.count, 1, "Ladeindikator dreht weiter")
        // Beim Verlassen bricht die App ab
        w.back(wait: 2.0)
        let danach = host.events("/trickle", kind: "closedBeforeResponse").first
        B04QA.log("EC-06|nachVerlassen|abbruch=\(danach != nil)")
        XCTAssertNotNil(danach, "beim Verlassen der Liste wird die Verbindung geschlossen")
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
        B04QA.log("EC-07|nachZurueck|busy=\(w.busyRows)|logopunkte0=\(logoTreffer(w, "Sender 00"))")
        w.shot("EC-07-zurueckgescrollt")
        B04QA.evidence("EC-07-neuladen.txt",
                       "40 Sender, Logos 4 s verzögert: beim Öffnen \(ersteAnfragen.count) Anfragen, nach Wegscrollen und "
                       + "Zurückscrollen \(alle.count) Anfragen, davon mehrfach: \(mehrfach.mapValues(\.count))")
        XCTAssertFalse(mehrfach.isEmpty, "die weggescrollten, abgebrochenen Logos werden erneut angefragt")
        XCTAssertGreaterThan(logoTreffer(w, "Sender 00"), 400, "das Logo der obersten Karte ist nach dem Zurückscrollen da")
        XCTAssertLessThanOrEqual(w.busyRows.count, 3, "die übrigen Karten lösen sich auf (6 Verbindungen je Host, 4 s Verzögerung)")
    }
}
