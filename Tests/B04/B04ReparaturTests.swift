import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B04 · Senderliste — Tests der Reparatur (sdd-build, Fehlerauftrag BUG-01 bis BUG-14, 2026-09-29).
/// Ergänzen die umgestellten QA-Tests um die Bausteine: Logo-Loader (Grenzen, Weiterleitungen, Kopfzeilen, Cache),
/// Abfragen der Liste (Gruppenwerte, Beziehung, gelöschte Sender) und das Leeren der Logos bei „Alle Daten entfernen“.
/// Alle Logo-Hosts sind lokale Mocks (`B04LogoHost`, 127.0.0.1 bzw. `localhost`).
final class B04ReparaturTests: B04TestCase {

    // MARK: - Logo-Loader

    private func laden(_ loader: ChannelLogoLoader, _ adresse: String) throws -> CGImage? {
        try B04QA.run(30) { await loader.image(for: URL(string: adresse)!) }
    }

    /// BUG-04: ohne Adresse und bei fremden Schemata keine Anfrage, sofort Platzhalter.
    func testBUG04_NurHTTPUndHTTPSWerdenAngefragt() throws {
        for adresse in ["file:///etc/passwd", "data:image/png;base64,iVBORw0KGgo=", "javascript:alert(1)", "ftp://127.0.0.1/x.png",
                        "http:///ohne-host.png", "\(host.base)/nocache/ok.png"] {
            let url = URL(string: adresse)
            B04QA.log("BUILD|BUG-04|\(adresse.prefix(40))|akzeptiert=\(ChannelLogoLoader.accepts(url))")
        }
        XCTAssertFalse(ChannelLogoLoader.accepts(nil))
        XCTAssertFalse(ChannelLogoLoader.accepts(URL(string: "file:///etc/passwd")))
        XCTAssertFalse(ChannelLogoLoader.accepts(URL(string: "data:image/png;base64,iVBORw0KGgo=")))
        XCTAssertFalse(ChannelLogoLoader.accepts(URL(string: "javascript:alert(1)")))
        XCTAssertFalse(ChannelLogoLoader.accepts(URL(string: "ftp://127.0.0.1/x.png")))
        XCTAssertTrue(ChannelLogoLoader.accepts(URL(string: "\(host.base)/nocache/ok.png")))
        XCTAssertTrue(ChannelLogoLoader.accepts(URL(string: "HTTPS://example.invalid/logo.png")))
        let loader = ChannelLogoLoader()
        XCTAssertNil(try laden(loader, "file:///System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns"))
        XCTAssertEqual(host.requests.count, 0)
        XCTAssertNotNil(try laden(loader, "\(host.base)/nocache/ok.png"), "http-Logo wird geladen")
    }

    /// BUG-05: Größen-, Abmessungs- und Zeitgrenzen; das Vorschaubild ist klein.
    func testBUG05_GrenzenUndVorschaubild() throws {
        var limits = ChannelLogoLoader.Limits()
        limits.idleTimeout = 2
        limits.totalTimeout = 3
        let loader = ChannelLogoLoader(limits: limits)
        let klein = try laden(loader, "\(host.base)/nocache/klein.png")
        XCTAssertEqual(klein?.width, 64, "kleines Logo bleibt klein (64 px)")
        XCTAssertNil(try laden(loader, "\(host.base)/bigfile.png"), "27 MB > 1 MB: abgelehnt")
        XCTAssertNil(try laden(loader, "\(host.base)/bigdim.png"), "144 Megapixel: abgelehnt")
        let t0 = Date()
        XCTAssertNil(try laden(loader, "\(host.base)/trickle?i=1"), "tröpfelnd: abgebrochen")
        let dauer = Date().timeIntervalSince(t0)
        XCTAssertLessThan(dauer, limits.totalTimeout + 2, "Gesamtfrist")
        // Vorschaubild eines großen, erlaubten Bildes: höchstens `thumbnailPixels`
        let gross = B04Image.solid(width: 1_500, height: 1_000)
        let bild = ChannelLogoLoader.thumbnail(from: gross, limits: .standard)
        B04QA.log("BUILD|BUG-05|klein=\(klein.map { "\($0.width)x\($0.height)" } ?? "-")|tröpfeln=\(B04QA.f1(dauer))s|1500x1000→\(bild.map { "\($0.width)x\($0.height)" } ?? "-")")
        XCTAssertEqual(bild?.width, ChannelLogoLoader.Limits.standard.thumbnailPixels)
        XCTAssertLessThanOrEqual(bild?.height ?? 999, ChannelLogoLoader.Limits.standard.thumbnailPixels)
        XCTAssertNil(ChannelLogoLoader.thumbnail(from: Data("<html>kein Bild</html>".utf8), limits: .standard))
    }

    /// BUG-05 (Nachtrag, EC-07): Anfragen, die auf einen freien Platz beim Host warten, laufen nicht schon in der
    /// Warteschlange ab – die Fristen beginnen mit dem Senden. Wartende lassen sich abbrechen.
    func testBUG05_FristenBeginnenMitDemSenden() throws {
        var limits = ChannelLogoLoader.Limits()
        limits.maxConcurrentPerHost = 2
        limits.totalTimeout = 3
        limits.idleTimeout = 3
        let loader = ChannelLogoLoader(limits: limits)
        let t0 = Date()
        let bilder = try B04QA.run(40) {
            await withTaskGroup(of: Bool.self) { gruppe in
                for i in 0..<6 {
                    gruppe.addTask { await loader.image(for: URL(string: "\(self.host.base)/nocache/warte\(i).png?d=2")!) != nil }
                }
                var n = 0
                for await ok in gruppe where ok { n += 1 }
                return n
            }
        }
        let dauer = Date().timeIntervalSince(t0)
        B04QA.log("BUILD|BUG-05|warteschlange|bilder=\(bilder)/6|dauer=\(B04QA.f1(dauer))s|anfragen=\(host.requests.count)")
        XCTAssertEqual(bilder, 6, "alle sechs Logos kommen an, obwohl die letzten erst nach 4 s gesendet werden (Frist 3 s)")
        XCTAssertGreaterThan(dauer, 5.5, "drei Wellen zu je 2 Anfragen")

        // Abbrechen eines Wartenden gibt keinen Platz frei und blockiert nichts
        let gate = RequestGate(limit: 1)
        try B04QA.run(10) { try await gate.acquire("h") }
        let wartend = Task { try await gate.acquire("h") }
        B04QA.spin(0.2)
        wartend.cancel()
        let ergebnis = try B04QA.run(5) { await wartend.result }
        XCTAssertThrowsError(try ergebnis.get(), "abgebrochener Wartender wirft")
        gate.release("h")
        try B04QA.run(5) { try await gate.acquire("h") }   // Platz ist wieder frei
        gate.release("h")
    }

    /// BUG-06: Weiterleitungen nur auf denselben Host und Port, begrenzt; neutrale Kopfzeilen, keine Cookies.
    func testBUG06_WeiterleitungenUndKopfzeilen() throws {
        let fremd = B04LogoHost { _ in .image(B04Image.small) }
        try fremd.start()
        defer { fremd.stop() }
        let loader = ChannelLogoLoader()
        let ziel = "\(fremd.base)/nocache/fremd.png".addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        XCTAssertNil(try laden(loader, "\(host.base)/redirect?to=\(ziel)"), "anderer Port (anderer Dienst): abgelehnt")
        XCTAssertEqual(fremd.requests.count, 0)
        // derselbe Host unter anderem Namen („localhost“ statt 127.0.0.1) gilt als fremd
        let anderName = "\(host.altBase)/nocache/anders.png".addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        XCTAssertNil(try laden(loader, "\(host.base)/redirect?to=\(anderName)"))
        XCTAssertEqual(host.requests("/nocache/anders.png").count, 0)
        XCTAssertNotNil(try laden(loader, "\(host.base)/redirect?to=%2Fnocache%2Fgleich.png"), "derselbe Host: gefolgt")
        host.resetLog()
        XCTAssertNil(try laden(loader, "\(host.base)/redirect-loop?x=1"), "Schleife endet")
        XCTAssertEqual(host.requests("/redirect-loop").count, 1 + ChannelLogoLoader.Limits.standard.maxRedirects)
        // Kopfzeilen; ein gesetztes Cookie wird nicht zurückgeschickt
        B04TestCase.routes["/cookie"] = .body(status: 200, contentType: "image/png", body: B04Image.small,
                                              headers: ["Set-Cookie": "b04=geheim; Path=/"])
        defer { B04TestCase.routes["/cookie"] = nil }
        host.resetLog()
        _ = try laden(loader, "\(host.base)/cookie/a.png")
        _ = try laden(loader, "\(host.base)/cookie/b.png")
        let kopf = host.requests.map(\.headers)
        B04QA.log("BUILD|BUG-06|kopfzeilen=\(kopf)")
        XCTAssertEqual(kopf.count, 2)
        for h in kopf {
            XCTAssertEqual(h["User-Agent"], "Mozilla/5.0")
            XCTAssertEqual(h["Accept-Language"], "*")
            XCTAssertNil(h["Cookie"])
            XCTAssertNil(h["Referer"])
        }
    }

    /// BUG-06: die Regel für Logo-Weiterleitungen; die Regeln der Importwege (B01, B02) bleiben unverändert.
    func testBUG06_WeiterleitungsregelFuerLogos() {
        func erlaubt(_ policy: PlaylistHTTPLoader.RedirectPolicy, _ von: String, _ nach: String, _ n: Int = 1, start: String? = nil) -> Bool {
            PlaylistHTTPLoader.allowsRedirect(policy, original: URL(string: start ?? von)!, from: URL(string: von)!, to: URL(string: nach)!, count: n)
        }
        let logo = PlaylistHTTPLoader.RedirectPolicy.sameHost(maxRedirects: 3)
        XCTAssertTrue(erlaubt(logo, "http://h.example/a.png", "http://h.example/b.png"))
        XCTAssertTrue(erlaubt(logo, "http://H.example/a.png", "http://h.example:80/b.png"), "Groß-/Kleinschreibung, Standardport")
        XCTAssertTrue(erlaubt(logo, "http://h.example/a.png", "https://h.example/a.png"), "http → https desselben Hosts")
        XCTAssertFalse(erlaubt(logo, "https://h.example/a.png", "http://h.example/a.png"), "kein Rückfall auf http")
        XCTAssertFalse(erlaubt(logo, "http://h.example:8080/a.png", "http://h.example:8081/a.png"), "anderer Port")
        XCTAssertFalse(erlaubt(logo, "http://h.example/a.png", "http://cdn.h.example/a.png"), "anderer Host, auch Subdomain")
        XCTAssertFalse(erlaubt(logo, "http://h.example/a.png", "ftp://h.example/a.png"), "anderes Schema")
        XCTAssertTrue(erlaubt(logo, "http://h.example/a.png", "http://h.example/b.png", 3))
        XCTAssertFalse(erlaubt(logo, "http://h.example/a.png", "http://h.example/b.png", 4), "höchstens drei")
        // unverändert: Xtream (B01 · BUG-10) und M3U (B02 AK-11)
        XCTAssertTrue(erlaubt(.sameOrigin, "http://p.example:8080/x", "http://p.example:8080/y"))
        XCTAssertFalse(erlaubt(.sameOrigin, "http://p.example/x", "https://p.example/x"))
        XCTAssertTrue(erlaubt(.follow, "http://p.example/x", "http://anders.example/y", 9))
    }

    /// BUG-07: nichts im URLCache, `no-store` und Fehler nicht im Arbeitsspeicher, `removeAll` leert.
    func testBUG07_ArbeitsspeicherStattPlattencache() throws {
        let loader = ChannelLogoLoader()
        let bild = "\(host.base)/nocache/r7.png", nostore = "\(host.base)/nostore/r7.png", fehler = "\(host.base)/404?r=7"
        XCTAssertNotNil(try laden(loader, bild))
        XCTAssertNotNil(try laden(loader, nostore))
        XCTAssertNil(try laden(loader, fehler))
        XCTAssertNotNil(loader.cachedImage(for: URL(string: bild)!))
        XCTAssertNil(loader.cachedImage(for: URL(string: nostore)!), "no-store wird nicht aufbewahrt")
        XCTAssertNil(loader.cachedImage(for: URL(string: fehler)!))
        for adresse in [bild, nostore, fehler] {
            XCTAssertNil(URLCache.shared.cachedResponse(for: URLRequest(url: URL(string: adresse)!)), "nicht im URLCache")
        }
        XCTAssertEqual(B04QA.cacheRows(prefix: host.base).count, 0, "nicht in Cache.db")
        host.resetLog()
        XCTAssertNotNil(try laden(loader, bild))
        XCTAssertEqual(host.requests.count, 0, "zweites Mal aus dem Arbeitsspeicher")
        loader.removeAll()
        XCTAssertNil(loader.cachedImage(for: URL(string: bild)!))
    }

    /// BUG-07: „Alle Daten entfernen“ leert auch die Logos.
    func testBUG07_AlleDatenEntfernenLeertDieLogos() throws {
        let (c, _) = try fileContainer("r7reset")
        _ = try B04QA.seed(c.mainContext, name: "QA Reset", items: [.init("R1", "Sport")])
        let loader = ChannelLogoLoader()
        let bild = "\(host.base)/nocache/reset.png"
        XCTAssertNotNil(try laden(loader, bild))
        var targets = AppDataReset.Targets()
        targets.httpCache = URLCache(memoryCapacity: 0, diskCapacity: 0)
        targets.logoLoader = loader
        try B04QA.run(60) { try await AppDataReset.eraseAll(context: c.mainContext, targets: targets) }
        XCTAssertNil(loader.cachedImage(for: URL(string: bild)!))
    }

    // MARK: - Abfragen der Liste

    /// BUG-01: ein Chip steht für alle gespeicherten Werte, die gekürzt so heißen; auch mit Suche.
    func testBUG01_GruppenwerteJeChipUndFilter() throws {
        let (c, _) = try fileContainer("r1")
        let pl = try B04QA.seed(c.mainContext, name: "QA Werte", items: [
            .init("Alpha", "Sport"), .init("Beta", " Sport"), .init("Gamma", "Sport "), .init("Delta", "\tSport\t"),
            .init("Epsilon", "sport"), .init("Zeta", "News\n"), .init("Eta", "   "), .init("Theta", nil),
        ])
        let owner = pl.persistentModelID
        let gruppen = try ChannelListQuery.groups(in: c, playlist: owner)
        B04QA.log("BUILD|BUG-01|gruppen=\(gruppen)")
        XCTAssertEqual(gruppen.chips, ["News\n", "Sport", "sport"])
        XCTAssertEqual(Set(gruppen.values["Sport"] ?? []), ["Sport", " Sport", "Sport ", "\tSport\t"])
        func namen(_ search: String, _ chip: String?) throws -> [String] {
            try ChannelListQuery.identifiers(in: c, playlist: owner, search: search, groupValues: chip.map { gruppen.values[$0] ?? [$0] })
                .compactMap { ChannelListQuery.channel($0, in: c.mainContext)?.name }
        }
        XCTAssertEqual(try namen("", "Sport"), ["Alpha", "Beta", "Delta", "Gamma"])
        XCTAssertEqual(try namen("a", "Sport"), ["Alpha", "Beta", "Delta", "Gamma"])
        XCTAssertEqual(try namen("et", "Sport"), ["Beta"])
        XCTAssertEqual(try namen("", "sport"), ["Epsilon"], "Groß-/Kleinschreibung trennt weiter (AK-11, OF-02)")
        XCTAssertEqual(try namen("", "News\n"), ["Zeta"])
        XCTAssertEqual(try namen("", nil).count, 8)
    }

    /// BUG-12: die Liste filtert über die Beziehung; ein gelöschter Sender ergibt beim Auflösen `nil`, keinen Absturz.
    func testBUG12_BeziehungStattKopieUndGeloeschteKennung() throws {
        let (c, _) = try fileContainer("r12")
        let ctx = c.mainContext
        let a = try B04QA.seed(ctx, name: "QA A", items: [.init("A1"), .init("A2")])
        let b = try B04QA.seed(ctx, name: "QA B", items: [.init("B1")])
        let kopie = Channel(name: "X Beziehung A, Kopie B", streamURL: URL(string: "\(B04QA.dead)/x.m3u8")!, playlist: a, playlistID: b.id)
        ctx.insert(kopie)
        try ctx.save()
        let inA = try ChannelListQuery.identifiers(in: c, playlist: a.persistentModelID, search: "", groupValues: nil)
        let inB = try ChannelListQuery.identifiers(in: c, playlist: b.persistentModelID, search: "", groupValues: nil)
        XCTAssertEqual(inA.count, 3)
        XCTAssertEqual(inB.count, 1)
        // Sender in einem anderen Kontext löschen: die Kennung löst sich zu nil auf
        let fremd = ModelContext(c)
        let ziel = try XCTUnwrap(try fremd.fetch(FetchDescriptor<Channel>(predicate: #Predicate { $0.name == "A2" })).first)
        let kennung = ziel.persistentModelID
        fremd.delete(ziel)
        try fremd.save()
        let frisch = ModelContext(c)
        XCTAssertNil(ChannelListQuery.channel(kennung, in: frisch), "gelöschter Sender: nil statt Absturz")
        XCTAssertEqual(try ChannelListQuery.identifiers(in: c, playlist: a.persistentModelID, search: "", groupValues: nil).count, 2)
    }

    /// BUG-02: Aktualisieren meldet ersetzte Sender (für offene Listen in allen Fenstern).
    func testBUG02_AktualisierenMeldetErsetzteSender() throws {
        let (c, _) = try fileContainer("r2")
        let ctx = c.mainContext
        let mock = MockXtreamServer()
        let body = B04Antwort("#EXTM3U\n#EXTINF:-1 group-title=\"A\",Eins\n\(B04QA.dead)/1.m3u8\n")
        mock.handler = { _ in .raw(status: 200, contentType: "audio/x-mpegurl", body: body.data) }
        try mock.start()
        defer { B01.removeCachedResponses(for: mock); mock.stop() }
        let importer = PlaylistImporter(modelContext: ctx)
        let pl = try B04QA.run(30) { try await importer.importFromURL("http://\(mock.hostPort)/r2.m3u", name: "QA R2") }
        var gemeldet: [Set<UUID>] = []
        let beobachter = NotificationCenter.default.addObserver(forName: PlaylistEvents.didReplaceChannels, object: nil, queue: nil) {
            gemeldet.append(PlaylistEvents.ids(in: $0))
        }
        defer { NotificationCenter.default.removeObserver(beobachter) }
        body.data = Data("#EXTM3U\n#EXTINF:-1 group-title=\"B\",Zwei\n\(B04QA.dead)/2.m3u8\n".utf8)
        try B04QA.run(60) { try await importer.refresh(pl) }
        B04QA.log("BUILD|BUG-02|gemeldet=\(gemeldet)")
        XCTAssertEqual(gemeldet, [[pl.id]])
        XCTAssertEqual(try ChannelListQuery.groups(in: c, playlist: pl.persistentModelID).chips, ["B"])
    }
}

/// Veränderliche Antwort des Mock-Servers, von dessen Warteschlange gelesen (ohne Sendable-Warnung).
final class B04Antwort: @unchecked Sendable {
    private let lock = NSLock()
    private var inhalt: Data
    init(_ text: String) { inhalt = Data(text.utf8) }
    var data: Data {
        get { lock.withLock { inhalt } }
        set { lock.withLock { inhalt = newValue } }
    }
}
