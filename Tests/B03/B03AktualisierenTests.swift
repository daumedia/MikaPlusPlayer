import XCTest
import SwiftData
import SQLite3
@testable import MikaPlusPlayer

/// B03 · Playlist-Verwaltung — Aktualisieren über den echten `PlaylistImporter` (QA Durchlauf 1, 2026-09-16).
/// Datenbank als Datei im Temp-Verzeichnis, Anbieter als Mock auf 127.0.0.1, erfundene Zugangsdaten, tonlos.
final class B03AktualisierenTests: B03QATestCase {

    // MARK: - AK-07 / EC-02 · M3U

    /// AK-07: gespeicherte Adresse genau einmal abgerufen, **alle** Sender ersetzt (neue IDs), Badge-Zahl neu,
    /// Name/Adresse/Anlagezeitpunkt/Position bleiben. EC-02: auch bei unveränderter Liste wird alles neu angelegt.
    @MainActor func testAK07_EC02_M3UAktualisierenErsetztAlleSender() async throws {
        let (container, url) = try fileContainer("ak07")
        let ctx = container.mainContext
        _ = try await importM3U(ctx, name: "QA Ältere")
        try await Task.sleep(nanoseconds: 30_000_000)
        let p = try await importM3U(ctx, name: "QA Aktualisiert", address: "http://\(mock.hostPort)/list.m3u?token=qa-b03-tok-ak07")
        try await Task.sleep(nanoseconds: 30_000_000)
        _ = try await importM3U(ctx, name: "QA Neuere")
        let sorted = FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let order0 = try ctx.fetch(sorted).map(\.name)
        let created = p.createdAt, source = p.sourceURL, name = p.name
        try await Task.sleep(nanoseconds: 1_100_000_000)

        // EC-02: unveränderte Liste
        var cfg = B03QAPanel()
        cfg.m3u = B03QA.m3u(B03QA.v1)
        mock.handler = cfg.handler()
        mock.resetLog()
        let ids0 = Set(p.channels.map(\.id))
        let lr0 = p.lastRefreshed
        try await refresh(p, ctx)
        let ids1 = Set(p.channels.map(\.id))
        B03QA.log("EC-02|anfragen=\(mock.requests.map(\.target))|sender=\(p.channelCount)|gleicheIDs=\(ids0.intersection(ids1).count)")
        XCTAssertEqual(mock.requests.map(\.target), ["/list.m3u?token=qa-b03-tok-ak07"])
        XCTAssertEqual(p.channelCount, 7)
        XCTAssertEqual(ids0.intersection(ids1).count, 0, "EC-02: unveränderte Sender bekommen trotzdem neue IDs")
        XCTAssertNotEqual(p.lastRefreshed, lr0)

        // AK-07: neue Liste mit 9 Sendern
        cfg.m3u = B03QA.m3u(B03QA.v1 + [("Delta", nil, "Neu", "\(B03QA.dead)/d.m3u8"), ("Epsilon", nil, "Neu", "\(B03QA.dead)/e.m3u8")])
        mock.handler = cfg.handler()
        mock.resetLog()
        try await refresh(p, ctx)
        let ids2 = Set(p.channels.map(\.id))
        let pk = "(select Z_PK from ZPLAYLIST where ZNAME = 'QA Aktualisiert')"
        let dbRows = B03QA.int(url.path, "select count(*) from ZCHANNEL where ZPLAYLIST = \(pk)")
        let dbDenorm = B03QA.int(url.path, "select count(*) from ZCHANNEL c join ZPLAYLIST p on c.ZPLAYLISTID = p.ZID where p.ZNAME = 'QA Aktualisiert'")
        let dbCount = B03QA.int(url.path, "select ZCHANNELCOUNT from ZPLAYLIST where ZNAME = 'QA Aktualisiert'")
        B03QA.log("AK-07|anfragen=\(mock.requests.count)|channelCount=\(p.channelCount)|dbZeilen=\(dbRows)|dbPlaylistID=\(dbDenorm)|dbChannelCount=\(dbCount)|gleicheIDs=\(ids1.intersection(ids2).count)|\(B03QA.dbSummary(url))|reihenfolge=\(try ctx.fetch(sorted).map(\.name))")
        XCTAssertEqual(mock.requests.count, 1, "genau ein Abruf")
        XCTAssertEqual(p.channelCount, 9)
        XCTAssertEqual(p.channels.count, 9)
        XCTAssertEqual(dbRows, 9)
        XCTAssertEqual(dbDenorm, 9, "playlistID der neuen Sender gesetzt")
        XCTAssertEqual(dbCount, 9, "Badge-Zahl in der Datenbank")
        XCTAssertEqual(ids1.intersection(ids2).count, 0, "keine Sender-ID bleibt")
        XCTAssertEqual(p.name, name)
        XCTAssertEqual(p.sourceURL, source)
        XCTAssertEqual(p.createdAt, created)
        XCTAssertEqual(try ctx.fetch(sorted).map(\.name), order0, "Position in der Übersicht")
        XCTAssertEqual(order0, ["QA Neuere", "QA Aktualisiert", "QA Ältere"])
        XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZCHANNEL"), 7 + 9 + 7, "keine verwaisten Zeilen")
        XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZCHANNEL where ZPLAYLIST is null"), 0)
        XCTAssertFalse(ctx.hasChanges)
    }

    // MARK: - AK-08 / AK-32 / EC-01 · Xtream

    /// AK-08: drei Anfragen an `player_api.php` des gespeicherten Hosts mit Zugangsdaten aus dem Schlüsselbund,
    /// Format bleibt, Adressen ohne Zugangsdaten, Schlüsselbund-Eintrag unverändert, Passwort nicht in der Datenbankdatei.
    /// AK-32: keine anderen Hosts, keine `player_api`-Einträge im Plattencache. EC-01: unbekannter Formatwert → HLS.
    @MainActor func testAK08_AK32_EC01_XtreamAktualisierenMitSchluesselbund() async throws {
        let (container, url) = try fileContainer("ak08")
        let ctx = container.mainContext
        let pass = "qa-pass-b03-ak08-\(UInt32.random(in: 1000...9999))"
        let p = try await importXtream(ctx, streams: B03QA.streams([
            ("Kanal A", 101, "a.epg", "1"), ("Kanal B", 102, nil, "1"), ("Sport 1", 103, "sport.epg", "2"),
            ("Sport 1 HD", 104, "sport.epg", "2"), ("Kanal C", 105, nil, "2")
        ]), pass: pass, output: .mpegts)
        let secret0 = try XtreamCredentialStore.standard.load(for: p.id)
        XCTAssertNotNil(secret0)

        var cfg = B03QAPanel()
        cfg.streams = B03QA.streams([
            ("Kanal A (neu)", 201, "a.epg", "2"), ("Kanal B", 102, nil, "1"), ("Sport 1", 103, "sport.epg", "2"),
            ("Sport 1 HD", 104, "sport.epg", "2"), ("Sport 1 4K", 106, "sport.epg", "2"), ("Kanal C", 105, nil, "1")
        ])
        mock.handler = cfg.handler()
        mock.resetLog()
        try await refresh(p, ctx)
        let reqs = mock.requests
        B03QA.log("AK-08|anfragen=\(reqs.map { "\($0.path)?action=\($0.action ?? "-")[\($0.username ?? "-")/\($0.password == pass ? "<pass>" : ($0.password ?? "-"))]:\($0.port)" })")
        XCTAssertEqual(reqs.count, 3)
        XCTAssertEqual(reqs.map(\.path), Array(repeating: "/player_api.php", count: 3))
        XCTAssertEqual(reqs.map { $0.action ?? "" }, ["", "get_live_categories", "get_live_streams"])
        XCTAssertTrue(reqs.allSatisfy { $0.username == "qa-user" && $0.password == pass && $0.port == mock.port })
        XCTAssertEqual(p.channelCount, 6)
        XCTAssertEqual(Set(p.channels.map(\.streamURL.pathExtension)), ["ts"])
        XCTAssertTrue(p.channels.allSatisfy { !$0.streamURL.absoluteString.contains(pass) && !$0.streamURL.absoluteString.contains("qa-user") })
        XCTAssertFalse(p.sourceURL?.absoluteString.contains(pass) ?? true)
        XCTAssertEqual(try XtreamCredentialStore.standard.load(for: p.id), secret0, "Schlüsselbund-Eintrag unverändert")
        let inFiles = B01.rawOccurrences(of: pass, inFilesWithPrefix: url)
        let inCache = B01.sqliteCount(B01.hostCacheDB.path, "select count(*) from cfurl_cache_response where instr(request_key, '\(pass)') > 0") ?? 0
        B03QA.log("AK-08|passwortInDateien=\(inFiles)|cacheEintraegeMitPasswort=\(inCache)|adressen=\(p.channels.map(\.streamURL.absoluteString).sorted().prefix(2))")
        XCTAssertEqual(inFiles.values.reduce(0, +), 0, "Passwort nicht in Store, -wal, -shm")
        XCTAssertEqual(inCache, 0, "AK-32: nichts im Plattencache")

        // Format HLS bleibt HLS
        let h = try await importXtream(ctx, pass: pass, output: .hls, name: "QA HLS")
        try await refresh(h, ctx)
        XCTAssertEqual(Set(h.channels.map(\.streamURL.pathExtension)), ["m3u8"])
        XCTAssertEqual(h.xtreamOutput, "hls")

        // EC-01: unbekannte Formatwerte
        var ec01: [String] = []
        for raw in ["ts", "m3u8", "", nil, "mpegts"] as [String?] {
            p.xtreamOutput = raw
            try ctx.save()
            try await refresh(p, ctx)
            let ext = Set(p.channels.map(\.streamURL.pathExtension))
            ec01.append("\(raw.map { "\"\($0)\"" } ?? "nil")→\(ext.sorted())")
            XCTAssertEqual(ext, raw == "mpegts" ? ["ts"] : ["m3u8"], "EC-01 \(raw ?? "nil")")
        }
        B03QA.log("EC-01|\(ec01)")
    }

    // MARK: - AK-09 · Favoriten bleiben

    /// AK-09 (M3U): Schlüssel tvg-ID bzw. Name in Kleinbuchstaben; umbenannt mit gleicher tvg-ID bleibt Favorit,
    /// umbenannt ohne tvg-ID nicht; Reihenfolge egal.
    @MainActor func testAK09_FavoritenBleibenUeberSchluessel_M3U() async throws {
        let (container, _) = try fileContainer("ak09m")
        let ctx = container.mainContext
        let entries: [B03QA.M3UEntry] = [
            ("Alpha", "alpha.id", "News", "\(B03QA.dead)/a.m3u8"),
            ("Beta", nil, "News", "\(B03QA.dead)/b.m3u8"),
            ("Gamma", nil, "Doku", "\(B03QA.dead)/g.m3u8"),
            ("Omega", nil, "Doku", "\(B03QA.dead)/o.m3u8")
        ]
        let p = try await importM3U(ctx, entries: entries)
        for ch in p.channels where ["Alpha", "Beta", "Gamma"].contains(ch.name) { ch.isFavorite = true }
        try ctx.save()
        var cfg = B03QAPanel()
        cfg.m3u = B03QA.m3u([
            ("Omega", nil, "Doku", "\(B03QA.dead)/o.m3u8"),
            ("Gamma Plus", nil, "Doku", "\(B03QA.dead)/g.m3u8"),
            ("BETA", nil, "News", "\(B03QA.dead)/b.m3u8"),
            ("Alpha Neu", "alpha.id", "News", "\(B03QA.dead)/a2.m3u8")
        ])
        mock.handler = cfg.handler()
        try await refresh(p, ctx)
        B03QA.log("AK-09|m3u|favoriten=\(favorites(p))")
        XCTAssertEqual(favorites(p), ["Alpha Neu", "BETA"])
        let tab = try ctx.fetch(FetchDescriptor<Channel>(predicate: #Predicate { $0.isFavorite == true })).map(\.name).sorted()
        XCTAssertEqual(tab, ["Alpha Neu", "BETA"], "Favoriten-Tab-Abfrage")
    }

    /// AK-09 (Xtream): Schlüssel `epg_channel_id` bzw. Name.
    @MainActor func testAK09_FavoritenBleibenUeberSchluessel_Xtream() async throws {
        let (container, _) = try fileContainer("ak09x")
        let ctx = container.mainContext
        let p = try await importXtream(ctx, streams: B03QA.streams([
            ("Kanal A", 101, "a.epg", "1"), ("Kanal B", 102, nil, "1"), ("Kanal C", 103, nil, "2"), ("Kanal D", 104, nil, "2")
        ]))
        for ch in p.channels where ["Kanal A", "Kanal B", "Kanal C"].contains(ch.name) { ch.isFavorite = true }
        try ctx.save()
        var cfg = B03QAPanel()
        cfg.streams = B03QA.streams([
            ("Kanal D", 104, nil, "2"), ("Kanal C2", 103, nil, "2"), ("Kanal B", 102, nil, "1"), ("Kanal A (neu)", 201, "a.epg", "1")
        ])
        mock.handler = cfg.handler()
        try await refresh(p, ctx)
        B03QA.log("AK-09|xtream|favoriten=\(favorites(p))")
        XCTAssertEqual(favorites(p), ["Kanal A (neu)", "Kanal B"])
    }

    // MARK: - AK-10 ⚠ · Favoriten vervielfachen sich (BUG-02)

    @MainActor func testAK10_EinFavoritBleibtEinFavorit() async throws {
        let (container, _) = try fileContainer("ak10")
        let ctx = container.mainContext
        let p = try await importM3U(ctx)
        for ch in p.channels where ["Sport HD", "Film HD", "Alpha", "Gamma"].contains(ch.name) { ch.isFavorite = true }
        try ctx.save()
        let before = favorites(p).count
        var cfg = B03QAPanel()
        cfg.m3u = B03QA.m3u(B03QA.v1 + [("Film 4K", "film.id", "Film", "\(B03QA.dead)/f3.m3u8")])
        mock.handler = cfg.handler()
        try await refresh(p, ctx)
        let afterM3U = favorites(p)

        // zweimal „Kanal X" mit derselben tvg-ID, einer markiert
        cfg.m3u = B03QA.m3u([("Kanal X", "x.id", nil, "\(B03QA.dead)/x1.m3u8"), ("Kanal X", "x.id", nil, "\(B03QA.dead)/x2.m3u8"),
                             ("Kanal Y", nil, nil, "\(B03QA.dead)/y.m3u8")])
        mock.handler = cfg.handler()
        try await refresh(p, ctx)
        p.channels.first { $0.name == "Kanal X" }?.isFavorite = true
        try ctx.save()
        try await refresh(p, ctx)
        let kanalX = favorites(p)
        try await refresh(p, ctx)
        let kanalXZweimal = favorites(p)

        // Xtream: ein Stern auf „Sport 1"
        let x = try await importXtream(ctx, streams: B03QA.streams([
            ("Sport 1", 103, "sport.epg", "2"), ("Sport 1 HD", 104, "sport.epg", "2"), ("Kanal C", 105, nil, "2")
        ]))
        x.channels.first { $0.name == "Sport 1" }?.isFavorite = true
        try ctx.save()
        var xc = B03QAPanel()
        xc.streams = B03QA.streams([("Sport 1", 103, "sport.epg", "2"), ("Sport 1 HD", 104, "sport.epg", "2"),
                                    ("Sport 1 4K", 106, "sport.epg", "2"), ("Kanal C", 105, nil, "2")])
        mock.handler = xc.handler()
        try await refresh(x, ctx)
        let afterX = favorites(x)
        B03QA.log("AK-10|m3u|vorher=\(before)|nachher=\(afterM3U)|kanalX=\(kanalX)|kanalXnochmal=\(kanalXZweimal)|xtream=1→\(afterX)")

        // BUG-02 behoben: ein Stern bleibt ein Stern – je Schlüssel höchstens so viele Favoriten wie vorher, und zwar
        // derselbe Sender (gleiche Stream-Adresse).
        XCTAssertEqual(afterM3U.count, before, "M3U: aus 4 Favoriten dürfen nicht 7 werden")
        XCTAssertEqual(afterM3U, ["Alpha", "Film HD", "Gamma", "Sport HD"])
        XCTAssertEqual(kanalX.count, 1, "Kanal X: aus 1 dürfen nicht 2 werden")
        XCTAssertEqual(afterX, ["Sport 1"], "Xtream: aus 1 dürfen nicht 3 werden")
        XCTAssertEqual(kanalXZweimal.count, 1, "weiteres Aktualisieren vervielfacht nicht")
    }

    // MARK: - AK-11 ⚠ · Kürzere Liste (BUG-11)

    @MainActor func testAK11_KuerzereListeErsetztOhneRueckfrageFavoritenWeg() async throws {
        let (container, _) = try fileContainer("ak11")
        let ctx = container.mainContext
        let p = try await importM3U(ctx)
        for ch in p.channels where ["Alpha", "Sport HD", "Film HD", "Gamma"].contains(ch.name) { ch.isFavorite = true }
        try ctx.save()
        let before = favorites(p)
        var cfg = B03QAPanel()
        cfg.m3u = B03QA.m3u([("Beta", nil, "News", "\(B03QA.dead)/b.m3u8")])
        mock.handler = cfg.handler()
        var thrown: Error?
        do { try await refresh(p, ctx) } catch { thrown = error }
        let short = (p.channelCount, favorites(p))
        cfg.m3u = B03QA.m3u(B03QA.v1)
        mock.handler = cfg.handler()
        try await refresh(p, ctx)
        let back = (p.channelCount, favorites(p))
        B03QA.log("AK-11|7→\(short.0)→\(back.0) Sender|Favoriten \(before.count)→\(short.1.count)→\(back.1.count)|fehler=\(String(describing: thrown))")
        XCTAssertNil(thrown, "keine Rückfrage, kein Fehler")
        XCTAssertEqual(short.0, 1)
        XCTAssertEqual(short.1, [])
        XCTAssertEqual(back.0, 7)
        XCTExpectFailure("BUG-11 · Kürzere Liste ersetzt ohne Rückfrage, Favoriten kommen nicht zurück (OF-02)") {
            XCTAssertEqual(back.1, before)
        }
    }

    // MARK: - AK-14 ⚠ · Mehrfach, AK-15 · parallel

    /// AK-14: gleichzeitig gestartete Aktualisierungen derselben Playlist → je ein vollständiger Abruf; Ergebnis richtig.
    @MainActor func testAK14_MehrfachesAktualisierenDerselbenPlaylistGesperrt() async throws {
        let (container, url) = try fileContainer("ak14")
        let ctx = container.mainContext
        let p = try await importM3U(ctx)
        p.channels.first { $0.name == "Alpha" }?.isFavorite = true
        try ctx.save()
        let counter = B03QACounter()
        let body = B03QA.m3u(B03QA.v1)
        mock.handler = { req in
            guard req.path.hasSuffix(".m3u") else { return .raw(status: 404, contentType: "text/plain", body: Data()) }
            return .delayed(counter.next() == 1 ? 1.5 : 0.4, .raw(status: 200, contentType: "audio/x-mpegurl", body: body))
        }
        mock.resetLog()
        let t1 = Task { @MainActor in try await PlaylistImporter(modelContext: ctx).refresh(p) }
        try await Task.sleep(nanoseconds: 100_000_000)
        let t2 = Task { @MainActor in try await PlaylistImporter(modelContext: ctx).refresh(p) }
        _ = try await t1.value
        _ = try await t2.value
        let m3uFetches = mock.requests.count
        let m3uState = (p.channelCount, B03QA.int(url.path, "select count(*) from ZCHANNEL"), favorites(p))

        let x = try await importXtream(ctx)
        x.channels.first?.isFavorite = true
        try ctx.save()
        var cfg = B03QAPanel(); cfg.streamsDelay = 1
        mock.handler = cfg.handler()
        mock.resetLog()
        let tasks = (0..<3).map { _ in Task { @MainActor in try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).refresh(x) } }
        for t in tasks { _ = try await t.value }
        let xRequests = mock.requests.count
        let xWithPassword = mock.requests.filter { $0.password == "qa-pass-b03" }.count
        B03QA.log("AK-14|m3u 2× gestartet: abrufe=\(m3uFetches) sender=\(m3uState.0) zeilen=\(m3uState.1) favoriten=\(m3uState.2)|xtream 3× gestartet: anfragen=\(xRequests) mitPasswort=\(xWithPassword) sender=\(x.channelCount) favoriten=\(favorites(x))")
        XCTAssertEqual(m3uState.0, 7)
        XCTAssertEqual(m3uState.1, 7, "keine doppelten Sender")
        XCTAssertEqual(m3uState.2, ["Alpha"])
        XCTAssertEqual(x.channelCount, 4)
        XCTAssertEqual(favorites(x).count, 1)
        // BUG-04 behoben: Ein zweiter Aufruf während des ersten bleibt ohne Wirkung.
        XCTAssertEqual(m3uFetches, 1, "zweiter Aufruf während des ersten darf keinen zweiten Abruf auslösen")
        XCTAssertEqual(xRequests, 3, "Xtream: Zugangsdaten nur einmal senden")
    }

    /// AK-15: zwei verschiedene Playlists gleichzeitig → beide richtig ersetzt, je mit ihren Favoriten.
    @MainActor func testAK15_ZweiPlaylistsGleichzeitig() async throws {
        let (container, url) = try fileContainer("ak15")
        let ctx = container.mainContext
        let m = try await importM3U(ctx)
        let x = try await importXtream(ctx)
        m.channels.first { $0.name == "Alpha" }?.isFavorite = true
        x.channels.first { $0.name == "Kanal Int" }?.isFavorite = true
        try ctx.save()
        var cfg = B03QAPanel()
        cfg.m3u = B03QA.m3u(B03QA.v1 + [("Delta", nil, nil, "\(B03QA.dead)/d.m3u8")])
        cfg.m3uDelay = 1.5; cfg.streamsDelay = 1.0
        mock.handler = cfg.handler()
        let t0 = Date()
        let a = Task { @MainActor in try await PlaylistImporter(modelContext: ctx).refresh(m) }
        let b = Task { @MainActor in try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).refresh(x) }
        try await a.value
        try await b.value
        B03QA.log("AK-15|dauer=\(B03QA.f2(Date().timeIntervalSince(t0)))s|m3u=\(m.channelCount) \(favorites(m))|xtream=\(x.channelCount) \(favorites(x))|\(B03QA.dbSummary(url))")
        XCTAssertEqual(m.channelCount, 8)
        XCTAssertEqual(x.channelCount, 4)
        XCTAssertEqual(favorites(m), ["Alpha"])
        XCTAssertEqual(favorites(x), ["Kanal Int"])
        XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZCHANNEL"), 12)
        XCTAssertTrue(m.channels.allSatisfy { $0.playlistID == m.id })
        XCTAssertTrue(x.channels.allSatisfy { $0.playlistID == x.id })
    }

    // MARK: - AK-16 / EC-12 · lokale Datei

    @MainActor func testAK16_EC12_LokaleDateiNichtAktualisierbar() async throws {
        let (container, url) = try fileContainer("ak16")
        let ctx = container.mainContext
        let file = url.deletingLastPathComponent().appendingPathComponent("qa-b03-lokal.m3u")
        try B03QA.m3u(B03QA.v1).write(to: file)
        let p = try await PlaylistImporter(modelContext: ctx).importFromFile(file)
        p.channels.first?.isFavorite = true
        try ctx.save()
        let ids = Set(p.channels.map(\.id))
        mock.resetLog()
        try await refresh(p, ctx)
        XCTAssertFalse(p.isRemote)
        XCTAssertNil(p.sourceURL)
        XCTAssertEqual(mock.requests.count, 0)
        XCTAssertEqual(Set(p.channels.map(\.id)), ids)
        try B03QA.m3u([("Nur noch einer", nil, nil, "\(B03QA.dead)/1.m3u8")]).write(to: file)
        try await refresh(p, ctx)
        XCTAssertEqual(p.channelCount, 7, "geänderte Datei wird nicht neu eingelesen")
        XCTAssertEqual(Set(p.channels.map(\.id)), ids)
        let second = try await PlaylistImporter(modelContext: ctx).importFromFile(file)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Playlist>()), 2, "Neu einlesen nur als zweite Playlist")
        XCTAssertEqual(second.channelCount, 1)
        // EC-12: Datei gelöscht → ohne Wirkung
        try FileManager.default.removeItem(at: file)
        try await refresh(p, ctx)
        B03QA.log("AK-16|EC-12|nachDateiLoeschen|sender=\(p.channelCount)|ids gleich=\(Set(p.channels.map(\.id)) == ids)|favorit=\(favorites(p))")
        XCTAssertEqual(p.channelCount, 7)
        XCTAssertEqual(Set(p.channels.map(\.id)), ids)
        XCTAssertEqual(favorites(p).count, 1)
    }

    // MARK: - AK-17 · Altbestand

    @MainActor func testAK17_AltbestandWirdBeimAktualisierenUmgestellt() async throws {
        let (container, url) = try fileContainer("ak17")
        let ctx = container.mainContext
        let pass = "qa-pass-b03-legacy-\(UInt32.random(in: 1000...9999))"
        mock.handler = B03QAPanel().handler()
        let api = URL(string: "http://\(mock.hostPort)/player_api.php?username=qa-user&password=\(pass)")!
        let p = Playlist(name: "QA Altbestand", sourceURL: api, lastRefreshed: Date(), isXtream: true, xtreamOutput: "mpegts")
        ctx.insert(p)
        let ch = Channel(name: "Kanal Int", streamURL: URL(string: "http://\(mock.hostPort)/live/qa-user/\(pass)/101.ts")!,
                         tvgID: "kanal.int", isFavorite: true, playlist: p, playlistID: p.id)
        ctx.insert(ch)
        p.channelCount = 1
        try ctx.save()
        XCTAssertNil(try XtreamCredentialStore.standard.load(for: p.id))
        mock.resetLog()
        try await refresh(p, ctx)
        let secret = try XtreamCredentialStore.standard.load(for: p.id)
        let colSource = B03QA.int(url.path, "select count(*) from ZPLAYLIST where instr(cast(ZSOURCEURL as text), '\(pass)') > 0")
        let colStream = B03QA.int(url.path, "select count(*) from ZCHANNEL where instr(cast(ZSTREAMURL as text), '\(pass)') > 0")
        B03QA.log("AK-17|anfragenMitAltZugang=\(mock.requests.filter { $0.password == pass }.count)|schluesselbund=\(secret != nil)|sourceURL=\(p.sourceURL?.absoluteString.replacingOccurrences(of: mock.hostPort, with: "<mock>") ?? "nil")|spalten=\(colSource)/\(colStream)|favoriten=\(favorites(p))")
        XCTAssertEqual(mock.requests.filter { $0.password == pass && $0.username == "qa-user" }.count, 3)
        XCTAssertEqual(secret?.password, pass)
        XCTAssertEqual(secret?.username, "qa-user")
        XCTAssertFalse(p.sourceURL?.absoluteString.contains(pass) ?? true)
        XCTAssertEqual(colSource, 0)
        XCTAssertEqual(colStream, 0)
        XCTAssertTrue(p.channels.allSatisfy { !$0.streamURL.absoluteString.contains(pass) })
        XCTAssertEqual(favorites(p), ["Kanal Int"])
        let playable = try StreamURLResolver.playableURL(for: try XCTUnwrap(p.channels.first { $0.name == "Kanal Int" }))
        XCTAssertTrue(playable.absoluteString.contains(pass), "danach über den Schlüsselbund abspielbar")
    }

    // MARK: - AK-18 bis AK-21, AK-30 · Fehler

    private struct Snapshot: Equatable {
        let ids: Set<UUID>
        let favorites: [String]
        let count: Int
        let lastRefreshed: Date?
        let db: String
    }

    @MainActor private func snapshot(_ p: Playlist, _ url: URL) -> Snapshot {
        Snapshot(ids: Set(p.channels.map(\.id)), favorites: favorites(p), count: p.channelCount, lastRefreshed: p.lastRefreshed,
                 db: B03QA.dbSummary(url))
    }

    /// Führt einen fehlschlagenden Aufruf aus und prüft den Erhalt der alten Liste und die Meldung.
    @MainActor private func expectFailure(_ label: String, _ p: Playlist, _ ctx: ModelContext, _ url: URL, message expected: String,
                                          forbidden: [String], _ op: () async throws -> Void) async {
        let before = snapshot(p, url)
        var message = "KEIN FEHLER"
        do { try await op() } catch { message = error.localizedDescription }
        let after = snapshot(p, url)
        let leaks = forbidden.filter { message.contains($0) }
        B03QA.log("AK-18-21|\(label)|meldung=\(message)|alteListe=\(before == after)|hasChanges=\(ctx.hasChanges)|verboten=\(leaks)")
        XCTAssertEqual(message, expected, label)
        XCTAssertEqual(after, before, "\(label): alte Liste unverändert")
        XCTAssertFalse(ctx.hasChanges, "\(label): Kontext unverändert")
        XCTAssertEqual(leaks, [], "\(label): AK-30")
    }

    @MainActor func testAK18_AK30_M3UFehlerBehaltenAlteListe() async throws {
        let (container, url) = try fileContainer("ak18")
        let ctx = container.mainContext
        let token = "qa-b03-tok-ak18"
        let m = try await importM3U(ctx, name: "QA M3U", address: "http://\(mock.hostPort)/list.m3u?token=\(token)")
        m.channels.first?.isFavorite = true
        try ctx.save()
        let down = MockXtreamServer(handler: { _ in .raw(status: 200, contentType: "audio/x-mpegurl", body: B03QA.m3u(B03QA.v1)) })
        try down.start()
        let m2 = try await PlaylistImporter(modelContext: ctx).importFromURL("http://\(down.hostPort)/weg.m3u?token=\(token)", name: "QA weg")
        B01.removeCachedResponses(for: down)
        down.stop()
        try await Task.sleep(nanoseconds: 1_100_000_000)
        let forbidden = [token, "127.0.0.1", "list.m3u", "weg.m3u", "qa-"]

        var c = B03QAPanel()
        mock.handler = c.handler()   // m3u nil → 404
        await expectFailure("HTTP404", m, ctx, url, message: "Netzwerkfehler: HTTP 404", forbidden: forbidden) { try await refresh(m, ctx) }
        c.m3u = B03QA.m3u(B03QA.v1); c.m3uStatus = 500; mock.handler = c.handler()
        await expectFailure("HTTP500", m, ctx, url, message: "Netzwerkfehler: HTTP 500", forbidden: forbidden) { try await refresh(m, ctx) }
        c = B03QAPanel(); c.m3u = Data("<html><body>Wartung</body></html>".utf8); mock.handler = c.handler()
        await expectFailure("HTML", m, ctx, url, message: "Die Playlist enthält keine gültigen Sender.", forbidden: forbidden) { try await refresh(m, ctx) }
        c.m3u = Data(); mock.handler = c.handler()
        await expectFailure("leer", m, ctx, url, message: "Die Playlist enthält keine gültigen Sender.", forbidden: forbidden) { try await refresh(m, ctx) }
        c.m3u = Data("#EXTM3U\n".utf8); mock.handler = c.handler()
        await expectFailure("nurKopfzeile", m, ctx, url, message: "Die Playlist enthält keine gültigen Sender.", forbidden: forbidden) { try await refresh(m, ctx) }
        await expectFailure("HostNichtErreichbar", m2, ctx, url, message: "Netzwerkfehler: Could not connect to the server.", forbidden: forbidden) { try await refresh(m2, ctx) }
    }

    @MainActor func testAK19_AK30_XtreamFehlerBehaltenAlteListe() async throws {
        let (container, url) = try fileContainer("ak19")
        let ctx = container.mainContext
        let pass = "qa-pass-b03-ak19"
        let x = try await importXtream(ctx, pass: pass)
        x.channels.first?.isFavorite = true
        try ctx.save()
        let down = MockXtreamServer(handler: B03QAPanel().handler())
        try down.start()
        let x2 = try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).importFromXtream(
            XtreamCredentials(host: down.hostPort, username: "qa-user", password: pass), output: .mpegts, name: "QA weg")
        down.stop()
        try await Task.sleep(nanoseconds: 1_100_000_000)
        let forbidden = [pass, "qa-user", "127.0.0.1", "player_api"]

        var c = B03QAPanel(); c.streams = Data("[]".utf8); mock.handler = c.handler()
        await expectFailure("leer", x, ctx, url, message: "Die Playlist enthält keine gültigen Sender.", forbidden: forbidden) { try await refresh(x, ctx) }
        c = B03QAPanel(); c.streamsStatus = 500; mock.handler = c.handler()
        await expectFailure("HTTP500", x, ctx, url, message: "Netzwerkfehler: HTTP 500", forbidden: forbidden) { try await refresh(x, ctx) }
        c = B03QAPanel(); c.streams = Data("{\"a\":1}".utf8); mock.handler = c.handler()
        await expectFailure("unerwartet", x, ctx, url,
                            message: "Netzwerkfehler: Unerwartete Serverantwort (The data couldn’t be read because it isn’t in the correct format.)",
                            forbidden: forbidden) { try await refresh(x, ctx) }
        mock.handler = B03QAPanel().handler()
        var small = XtreamClient.Limits.standard; small.maxStreams = 2
        await expectFailure("zuGross", x, ctx, url, message: "Die Senderliste ist zu groß (mehr als 2 Sender).", forbidden: forbidden) {
            try await refresh(x, ctx, limits: small)
        }
        let standardText = XtreamClient.XtreamError.tooManyStreams(XtreamClient.Limits.standard.maxStreams).localizedDescription
        XCTAssertEqual(standardText, "Die Senderliste ist zu groß (mehr als 100.000 Sender).")
        await expectFailure("HostNichtErreichbar", x2, ctx, url, message: "Netzwerkfehler: Could not connect to the server.", forbidden: forbidden) {
            try await refresh(x2, ctx)
        }
    }

    /// AK-20: Ablehnung; ab der vierten Ablehnung in Folge am selben Panel greift die Bremse (Import und Aktualisieren gemeinsam).
    @MainActor func testAK20_AnmeldebremseBeimAktualisieren() async throws {
        let (container, url) = try fileContainer("ak20")
        let ctx = container.mainContext
        let x = try await importXtream(ctx, pass: "qa-pass-b03-ak20")
        x.channels.first?.isFavorite = true
        try ctx.save()
        var c = B03QAPanel()
        c.auth = try JSONSerialization.data(withJSONObject: ["user_info": ["auth": 0]])
        mock.handler = c.handler()
        mock.resetLog()
        let shared = XtreamLoginThrottle()
        let forbidden = ["qa-pass-b03-ak20", "qa-user", "127.0.0.1"]
        // eine gescheiterte Anmeldung beim Import …
        let imp = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-falsch", context: ctx, throttle: shared)
        XCTAssertEqual(B01.message(imp), "Anmeldung fehlgeschlagen. Benutzername/Passwort prüfen.")
        // … und zwei beim Aktualisieren
        for i in 1...2 {
            await expectFailure("abgelehnt\(i)", x, ctx, url, message: "Anmeldung fehlgeschlagen. Benutzername/Passwort prüfen.",
                                forbidden: forbidden) { try await refresh(x, ctx, throttle: shared) }
        }
        let beforeThrottle = mock.requests.filter { $0.path == "/player_api.php" && $0.action == nil }.count
        await expectFailure("gebremst", x, ctx, url, message: "Zu viele fehlgeschlagene Anmeldungen. Bitte in 30 Sekunden erneut versuchen.",
                            forbidden: forbidden) { try await refresh(x, ctx, throttle: shared) }
        let afterThrottle = mock.requests.filter { $0.path == "/player_api.php" && $0.action == nil }.count
        B03QA.log("AK-20|anmeldeanfragen vor/nach Bremse=\(beforeThrottle)/\(afterThrottle)")
        XCTAssertEqual(beforeThrottle, 3)
        XCTAssertEqual(afterThrottle, 3, "gebremster Versuch erreicht das Panel nicht")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Playlist>()), 1, "gescheiterter Import legt nichts an")
    }

    /// AK-21 ⚠: Schlüsselbund-Eintrag fehlt → Meldung, keine Anfrage. Der empfohlene Weg (löschen, neu importieren) kostet die Favoriten.
    @MainActor func testAK21_FehlenderSchluesselbundEintrag() async throws {
        let (container, url) = try fileContainer("ak21")
        let ctx = container.mainContext
        let x = try await importXtream(ctx, pass: "qa-pass-b03-ak21")
        for ch in x.channels.prefix(2) { ch.isFavorite = true }
        try ctx.save()
        let favBefore = favorites(x)
        try XtreamCredentialStore.standard.delete(for: x.id)
        mock.resetLog()
        await expectFailure("SchluesselbundFehlt", x, ctx, url,
                            message: "Die Zugangsdaten dieser Xtream-Playlist fehlen auf diesem Gerät. Bitte die Playlist löschen und neu importieren.",
                            forbidden: ["qa-pass-b03-ak21", "qa-user", "127.0.0.1"]) { try await refresh(x, ctx) }
        XCTAssertEqual(mock.requests.count, 0, "keine Anfrage")

        // empfohlener Weg
        try await PlaylistImporter(modelContext: ctx).delete(x)
        let again = try await importXtream(ctx, pass: "qa-pass-b03-ak21")
        B03QA.log("AK-21|favoriten vorher=\(favBefore)|nach löschen+neu importieren=\(favorites(again))")
        XCTAssertEqual(favorites(again), [])
        XCTExpectFailure("BUG-12 · Die Meldung „Zugangsdaten fehlen“ führt nur über Löschen, das alle Favoriten kostet (OF-06)") {
            XCTAssertEqual(favorites(again), favBefore)
        }
    }

    // MARK: - EC-06 · defekte Einträge

    /// EC-06: Eintrag ohne `stream_id` wird beim Aktualisieren still übersprungen, ein Favorit darauf geht verloren.
    /// Ein Eintrag mit `name: null` wird dagegen **nicht** übersprungen, sondern als Sender ohne Namen übernommen.
    @MainActor func testEC06_DefekteEintraegeBeimAktualisieren() async throws {
        let (container, _) = try fileContainer("ec06")
        let ctx = container.mainContext
        let x = try await importXtream(ctx, streams: B03QA.streams([("Kanal A", 101, "a.epg", "1"), ("Kanal B", 102, nil, "1"), ("Kanal C", 103, nil, "1")]))
        for ch in x.channels where ["Kanal A", "Kanal B"].contains(ch.name) { ch.isFavorite = true }
        try ctx.save()
        let broken: [[String: Any]] = [
            ["name": NSNull(), "stream_id": 101, "epg_channel_id": "a.epg", "category_id": "1"],   // Name null
            ["name": "Kanal B", "epg_channel_id": NSNull(), "category_id": "1"],                   // ohne stream_id
            ["name": "Kanal C", "stream_id": 103, "category_id": "1"]
        ]
        var c = B03QAPanel()
        c.streams = try JSONSerialization.data(withJSONObject: broken)
        mock.handler = c.handler()
        var thrown: Error?
        do { try await refresh(x, ctx) } catch { thrown = error }
        B03QA.log("EC-06|fehler=\(String(describing: thrown))|sender=\(x.channels.map { $0.name.isEmpty ? "<leer>" : $0.name }.sorted())|favoriten=\(favorites(x).map { $0.isEmpty ? "<leer>" : $0 })")
        XCTAssertNil(thrown, "kein Fehler, still")
        XCTAssertEqual(x.channels.map(\.name).sorted(), ["", "Kanal C"], "ohne stream_id übersprungen; name null → leerer Name")
        XCTAssertEqual(favorites(x), [""], "Favorit „Kanal B“ (ohne stream_id) verloren; „Kanal A“ bleibt über die tvg-ID, jetzt ohne Namen")
    }

    // MARK: - AK-26 / EC-07 · Löschen während Aktualisieren

    @MainActor func testAK26_EC07_LoeschenWaehrendAktualisieren_M3U() async throws {
        let (container, url) = try fileContainer("ak26m")
        let ctx = container.mainContext
        let p = try await importM3U(ctx)
        p.channels.first { $0.name == "Alpha" }?.isFavorite = true
        try ctx.save()
        var cfg = B03QAPanel(); cfg.m3u = B03QA.m3u(B03QA.v1); cfg.m3uDelay = 1.5
        mock.handler = cfg.handler()
        let task = Task { @MainActor in try await PlaylistImporter(modelContext: ctx).refresh(p) }
        try await Task.sleep(nanoseconds: 400_000_000)
        try await PlaylistImporter(modelContext: ctx).delete(p)
        let result = await task.result
        var resultText = "ok"
        if case .failure(let e) = result { resultText = e.localizedDescription }
        let favTab = try ctx.fetch(FetchDescriptor<Channel>(predicate: #Predicate { $0.isFavorite == true })).count
        let ctxChannels = try ctx.fetchCount(FetchDescriptor<Channel>())
        B03QA.log("AK-26|m3u|aktualisieren=\(resultText)|\(B03QA.dbSummary(url))|kontextSender=\(ctxChannels)|favoritenTab=\(favTab)|hasChanges=\(ctx.hasChanges)")
        XCTAssertEqual(resultText, "ok", "endet ohne Meldung")
        XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZPLAYLIST"), 0)
        XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZCHANNEL"), 0, "keine verwaisten Sender")
        XCTAssertEqual(favTab, 0)
        try? ctx.save()
        XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZCHANNEL"), 0, "auch nach weiterem Speichern")
    }

    @MainActor func testAK26_LoeschenWaehrendAktualisieren_Xtream() async throws {
        let (container, url) = try fileContainer("ak26x")
        let ctx = container.mainContext
        let p = try await importXtream(ctx, pass: "qa-pass-b03-ak26")
        p.channels.first?.isFavorite = true
        try ctx.save()
        let pid = p.id
        var cfg = B03QAPanel(); cfg.streamsDelay = 1.5
        mock.handler = cfg.handler()
        let task = Task { @MainActor in try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).refresh(p) }
        try await Task.sleep(nanoseconds: 600_000_000)
        try await PlaylistImporter(modelContext: ctx).delete(p)
        let result = await task.result
        var resultText = "ok"
        if case .failure(let e) = result { resultText = e.localizedDescription }
        let favTab = try ctx.fetch(FetchDescriptor<Channel>(predicate: #Predicate { $0.isFavorite == true })).count
        let secret = try XtreamCredentialStore.standard.load(for: pid)
        B03QA.log("AK-26|xtream|aktualisieren=\(resultText)|\(B03QA.dbSummary(url))|favoritenTab=\(favTab)|schluesselbund=\(secret != nil)")
        XCTAssertEqual(resultText, "ok")
        XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZCHANNEL"), 0)
        XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZPLAYLIST"), 0)
        XCTAssertEqual(favTab, 0)
        XCTAssertNil(secret, "kein wieder angelegter Schlüsselbund-Eintrag")
    }

    /// AK-35 ⚠: Altbestand wird aktualisiert und währenddessen gelöscht → Schlüsselbund-Eintrag entsteht nach dem Löschen.
    @MainActor func testAK35_AltbestandAktualisierenUndLoeschenOhneVerwaistenEintrag() async throws {
        let (container, url) = try fileContainer("ak35")
        let ctx = container.mainContext
        var cfg = B03QAPanel(); cfg.streamsDelay = 1.5
        mock.handler = cfg.handler()
        let pass = "qa-pass-b03-ak35"
        let api = URL(string: "http://\(mock.hostPort)/player_api.php?username=qa-user&password=\(pass)")!
        let p = Playlist(name: "QA Alt", sourceURL: api, lastRefreshed: Date(), isXtream: true, xtreamOutput: "mpegts")
        ctx.insert(p)
        ctx.insert(Channel(name: "Kanal Int", streamURL: URL(string: "http://\(mock.hostPort)/live/qa-user/\(pass)/101.ts")!, playlist: p, playlistID: p.id))
        p.channelCount = 1
        try ctx.save()
        let pid = p.id
        let task = Task { @MainActor in try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).refresh(p) }
        try await Task.sleep(nanoseconds: 600_000_000)
        try await PlaylistImporter(modelContext: ctx).delete(p)
        let afterDelete = try XtreamCredentialStore.standard.load(for: pid)
        _ = await task.result
        let afterRefresh = try XtreamCredentialStore.standard.load(for: pid)
        B03QA.log("AK-35|nachLoeschen=\(afterDelete != nil)|nachAktualisieren=\(afterRefresh != nil)|\(B03QA.dbSummary(url))")
        XCTAssertNil(afterDelete)
        XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZPLAYLIST"), 0)
        // BUG-08 behoben: Das Aktualisieren legt den Eintrag nur an, solange die Playlist existiert.
        XCTAssertNil(afterRefresh, "kein verwaister Schlüsselbund-Eintrag")
    }

    // MARK: - AK-29 ⚠ · gehaltener Sender nach Aktualisieren (Adressbildung)

    @MainActor func testAK29_GehaltenerSenderNachAktualisierenMitZugangsdaten() async throws {
        let (container, _) = try fileContainer("ak29")
        let ctx = container.mainContext
        let x = try await importXtream(ctx, pass: "qa-pass-b03-ak29", output: .hls)
        let held = try XCTUnwrap(x.channels.first { $0.name == "Kanal Int" })
        let before = try StreamURLResolver.playableURL(for: held)
        try await refresh(x, ctx)
        var after = "-"
        do { after = try StreamURLResolver.playableURL(for: held).absoluteString } catch { after = "Fehler: \(error.localizedDescription)" }
        let masked = after.replacingOccurrences(of: mock.hostPort, with: "<mock>")
        B03QA.log("AK-29|vorher=\(before.absoluteString.replacingOccurrences(of: mock.hostPort, with: "<mock>"))|nachher=\(masked)|playlistNil=\(held.playlist == nil)")
        XCTAssertTrue(before.absoluteString.contains("qa-pass-b03-ak29"))
        // BUG-05 behoben: Der Resolver schlägt die Playlist über die ID nach, nicht über die ersetzte Beziehung.
        XCTAssertEqual(after, "http://\(mock.hostPort)/live/qa-user/qa-pass-b03-ak29/101.m3u8", "mit Benutzername und Passwort")
    }

    // MARK: - EC-03 · Speichern scheitert nach dem Ersetzen

    /// EC-03: Das abschließende `save()` des Aktualisierens scheitert. Provoziert über einen Schreibkonflikt: Ein zweiter
    /// Container auf derselben Datei ändert dieselbe Playlist, während der Kontext der Ansicht den alten Stand hält.
    /// (Eine Schreibsperre über eine zweite SQLite-Verbindung taugt nicht: Core Data wartet dann auf dem Main-Thread
    /// unbegrenzt – ausprobiert, Lauf nach 5 min abgebrochen.)
    @MainActor func testEC03_SpeichernScheitertNachDemErsetzen() async throws {
        let (container, url) = try fileContainer("ec03")
        let ctx = container.mainContext
        let p = try await importM3U(ctx)
        p.channels.first { $0.name == "Alpha" }?.isFavorite = true
        try ctx.save()
        let idsBefore = Set(p.channels.map(\.id))
        do {
            let other = try AppPersistence.diskContainer(at: url, schema: AppSchema.schema)
            let o = try XCTUnwrap(try other.mainContext.fetch(FetchDescriptor<Playlist>()).first)
            o.name = "QA Konflikt"
            o.lastRefreshed = Date(timeIntervalSince1970: 0)
            for ch in o.channels { ch.group = "Konflikt" }
            try other.mainContext.save()
        }
        var cfg = B03QAPanel()
        cfg.m3u = B03QA.m3u([("Nur Neu", nil, nil, "\(B03QA.dead)/n.m3u8")])
        mock.handler = cfg.handler()
        var message = "KEIN FEHLER"
        do { try await refresh(p, ctx) } catch { message = error.localizedDescription }
        let dbAfterFailure = B03QA.dbSummary(url)
        let hasChanges = ctx.hasChanges
        B03QA.log("EC-03|meldung=\(message.replacingOccurrences(of: url.deletingLastPathComponent().path, with: "<tmp>").prefix(300))|hasChanges=\(hasChanges)|kontextSender=\(p.channels.map(\.name))|db=\(dbAfterFailure)")
        guard message != "KEIN FEHLER" else {
            throw XCTSkip("Speichern ist trotz Schreibkonflikt gelungen (db=\(dbAfterFailure)) – EC-03 so nicht provozierbar")
        }
        XCTAssertTrue(dbAfterFailure.contains("ZCHANNEL=7"), "Datenbank noch alt")
        // Nächstes Speichern aus einem anderen Anlass (z. B. Stern in der Senderliste: ChannelRowView speichert sofort)
        var second = "ok"
        do { try ctx.save() } catch { second = error.localizedDescription }
        let dbLater = B03QA.dbSummary(url)
        let idsLater = Set(try ctx.fetch(FetchDescriptor<Channel>()).map(\.id))
        B03QA.log("EC-03|nachFolgendemSpeichern=\(second.prefix(120))|db=\(dbLater)|alteIDsUebrig=\(idsBefore.intersection(idsLater).count)")
        XCTAssertTrue(hasChanges, "Ist: gelöschte und neue Sender bleiben ungespeichert im Kontext")
    }
}
