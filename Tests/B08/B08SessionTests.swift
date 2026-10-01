import XCTest
import SwiftUI
import SwiftData
import AppKit
import AVFoundation
@testable import MikaPlusPlayer

/// B08 · `MultiviewSession` mit echten Engines (AVKit für HLS, VLC für MPEG-TS) gegen den stummen Mock.
/// Ton-Fokus am Engine-Flag **und** am eigentlichen Player (AVPlayer.isMuted, VLC audio.muted). Kein Ton: Medien ohne
/// Tonspur, jede Engine sofort auf Lautstärke 0.
@MainActor
final class B08SessionTests: B08TestCase {

    private func muted(_ s: MultiviewSession) -> [Bool] { s.slots.map(\.engine.isMuted) }
    private func inner(_ s: MultiviewSession) -> [Bool?] { s.slots.map { B08Engine.innerMuted($0.engine) } }

    /// Wartet, bis alle Engines spielen und ihr innerer Stummzustand lesbar ist.
    private func waitPlaying(_ s: MultiviewSession, _ timeout: TimeInterval = 10) async -> Bool {
        await B08QA.wait(timeout) { s.slots.allSatisfy { $0.engine.state == .playing && B08Engine.innerMuted($0.engine) != nil } } != nil
    }

    // MARK: AK-03 · EC-01 · EC-03 — erster mit Ton, weitere stumm, AVKit und VLC gemischt

    func testAK03_EC01_EC03_ErsterMitTonWeitereStummGemischt() async throws {
        let s = session()
        add(s, channel("A HLS", "/livehls/a03/index.m3u8"))
        B08QA.log("AK-03|nach 1|\(B08Engine.describe(s))")
        XCTAssertEqual(muted(s), [false], "erster Stream fokussiert und mit Ton")
        add(s, channel("B TS", "/tslive/b03.ts"))
        // EC-03: VLC übernimmt den Sollwert sofort (Audiokanal schon vor dem Start vorhanden)?
        let vlcDirekt = B08Engine.vlcPlayer(s.slots[1].engine).map { B08Engine.vlcAudio($0).muted }
        B08QA.log("EC-03|VLC direkt nach add (vor Wiedergabe)|audio.muted=\(String(describing: vlcDirekt))|state=\(B08Engine.name(s.slots[1].engine.state))")
        add(s, channel("C HLS", "/livehls/c03/index.m3u8"))
        add(s, channel("D TS", "/tslive/d03.ts"))
        XCTAssertEqual(s.focusedIndex, 0, "Fokus bleibt beim ersten")
        XCTAssertEqual(muted(s), [false, true, true, true])
        XCTAssertEqual(s.slots.map { B08Engine.kind($0.engine) }, ["AVKit", "VLC", "AVKit", "VLC"], "EC-01: Engines gemischt")
        let ok = await waitPlaying(s)
        B08QA.log("AK-03|nach Start|\(B08Engine.describe(s))")
        XCTAssertTrue(ok, "alle vier spielen")
        XCTAssertEqual(inner(s), [false, true, true, true], "Stummzustand am eigentlichen Player (AVPlayer/VLC-Audiokanal)")
        XCTAssertEqual(vlcDirekt ?? nil, true, "EC-03: VLC-Audiokanal übernimmt den Wert schon vor dem Start")
        // Nichts ist hörbar: Engine-Lautstärke 0 und keine Tonspur
        XCTAssertTrue(s.slots.allSatisfy { $0.engine.volume == 0 })
    }

    // MARK: AK-04 — vier ist die Grenze, der fünfte erzeugt keine Verbindung

    func testAK04_FuenfterSenderKommtNichtHinzuKeineVerbindung() async throws {
        let s = session()
        for i in 1...4 { add(s, channel("T\(i)", "/tslive/ak04-\(i).ts")) }
        XCTAssertFalse(s.canAddMore)
        let before = s.slots.map(\.id)
        add(s, channel("Fünfter", "/tslive/ak04-fuenf.ts"))
        await B08QA.spin(3)
        let fifth = server.requests(containing: "ak04-fuenf")
        B08QA.log("AK-04|slots=\(s.slots.count)|ids gleich=\(s.slots.map(\.id) == before)|anfragen fuenfter=\(fifth.count)|\(server.summary("ak04"))")
        XCTAssertEqual(s.slots.count, 4)
        XCTAssertEqual(s.slots.map(\.id), before)
        XCTAssertEqual(fifth.count, 0, "keine Verbindung für den fünften")
        XCTAssertEqual(server.openStreamConnections(containing: "ak04").count, 4)
    }

    // MARK: AK-06 ⚠ — derselbe Sender zweimal (OF-01)

    func testAK06_GleicherSenderZweimalZweiKachelnZweiVerbindungen() async throws {
        let s = session()
        let c = channel("Doppelt", "/tslive/ak06.ts")
        add(s, c)
        add(s, c)
        await B08QA.spin(3)
        B08QA.log("AK-06|slots=\(s.slots.map(\.channel.name))|ids verschieden=\(s.slots[0].id != s.slots[1].id)|gleiche Engine=\(s.slots[0].engine === s.slots[1].engine)|\(server.summary("ak06"))")
        XCTAssertEqual(s.slots.count, 2)
        XCTAssertFalse(s.slots[0].engine === s.slots[1].engine)
        XCTAssertEqual(server.openStreamConnections(containing: "ak06").count, 2, "zwei Verbindungen für denselben Sender")
        XCTExpectFailure("BUG-08 · derselbe Sender kommt ohne Hinweis doppelt ins Multiview (wartet auf OF-01)") {
            XCTAssertEqual(s.slots.count, 1, "erwartet (nach Entscheidung OF-01): kein zweites Hinzufügen bzw. ein Hinweis")
        }
    }

    // MARK: AK-07 ⚠ — Xtream ohne Zugangsdaten: keine Kachel, keine Meldung (OF-02)

    func testAK07_OhneZugangsdatenKeineKachelKeineAnfrage() async throws {
        let container = try B08QA.inMemoryContainer()
        let p = try await importXtream(container.mainContext, output: .mpegts)
        let chans = p.channels.sorted { $0.name < $1.name }
        try XtreamCredentialStore.standard.delete(for: p.id)
        server.configure()
        let before = server.requests(containing: "/live/").count
        let s = session()
        add(s, chans[0])
        await B08QA.spin(1.5)
        let after = server.requests(containing: "/live/").count
        B08QA.log("AK-07|slots=\(s.slots.count)|liveAnfragen vorher/nachher=\(before)/\(after)|resolver=\(String(describing: try? StreamURLResolver.playableURL(for: chans[0])))")
        XCTAssertEqual(s.slots.count, 0)
        XCTAssertEqual(after, before, "keine Anfrage an den Anbieter")
        XCTAssertThrowsError(try StreamURLResolver.playableURL(for: chans[0]))
        XCTExpectFailure("BUG-09 · ⊞ ohne Zugangsdaten bleibt ohne Meldung (wartet auf OF-02)") {
            XCTFail("MultiviewSession.add meldet nichts (try? verschluckt missingCredentials); kein Weg, eine Meldung zu zeigen")
        }
    }

    // MARK: AK-14 · AK-17 · EC-02 — Fokus setzen, Entfernen vor/auf/nach dem Fokus

    func testAK14_AK17_EC02_FokusWandertUndEntfernenFuehrtNach() async throws {
        let s = session()
        let names = ["R1", "R2", "R3", "R4"]
        let paths = ["/livehls/r1/index.m3u8", "/tslive/r2.ts", "/livehls/r3/index.m3u8", "/tslive/r4.ts"]
        for (n, p) in zip(names, paths) { add(s, channel(n, p)) }
        _ = await waitPlaying(s)
        s.setFocus(2)
        B08QA.log("AK-14|setFocus(2)|\(B08Engine.describe(s))")
        XCTAssertEqual(s.focusedIndex, 2)
        XCTAssertEqual(muted(s), [true, true, false, true])
        XCTAssertEqual(inner(s), [true, true, false, true], "am eigentlichen Player")
        s.setFocus(2)
        XCTAssertEqual(muted(s), [true, true, false, true], "erneuter Fokus auf den fokussierten: keine Änderung")
        s.setFocus(9); s.setFocus(-1)
        XCTAssertEqual(s.focusedIndex, 2, "ungültige Indizes ändern nichts")

        // vor dem Fokus entfernen: Fokus bleibt beim selben Stream (R3)
        s.remove(s.slots[0].id)
        B08QA.log("AK-17|remove vor Fokus|\(B08Engine.describe(s))")
        XCTAssertEqual(s.slots[s.focusedIndex].channel.name, "R3")
        XCTAssertEqual(muted(s), [true, false, true])
        // den fokussierten entfernen: Nachfolger (R4) bekommt den Ton
        s.remove(s.slots[s.focusedIndex].id)
        B08QA.log("AK-17|remove Fokus|\(B08Engine.describe(s))")
        XCTAssertEqual(s.slots.map(\.channel.name), ["R2", "R4"])
        XCTAssertEqual(s.slots[s.focusedIndex].channel.name, "R4")
        XCTAssertEqual(muted(s), [true, false])
        XCTAssertEqual(inner(s), [true, false])
        // letzter in der Reihe fokussiert und entfernt: der davor bekommt den Ton
        s.remove(s.slots[1].id)
        XCTAssertEqual(s.slots.map(\.channel.name), ["R2"])
        XCTAssertEqual(muted(s), [false])
        await B08QA.spin(0.5)
        XCTAssertEqual(inner(s), [false])
        // nach dem Fokus entfernen: nichts ändert sich
        add(s, channel("R5", "/livehls/r5/index.m3u8"))
        add(s, channel("R6", "/tslive/r6.ts"))
        s.remove(s.slots[2].id)
        XCTAssertEqual(s.focusedIndex, 0)
        XCTAssertEqual(muted(s), [false, true])
        // immer genau einer mit Ton
        XCTAssertEqual(muted(s).filter { !$0 }.count, 1)
        // nach dem Leeren hat der nächste Ton
        s.clear()
        add(s, channel("R7", "/tslive/r7.ts"))
        XCTAssertEqual(s.focusedIndex, 0)
        XCTAssertEqual(muted(s), [false])
        // EC-02: fokussierter Stream ohne Tonspur ist „mit Ton" fokussiert, alle anderen stumm – zu hören ist nichts
        add(s, channel("R8", "/livehls/r8/index.m3u8"))
        _ = await waitPlaying(s)
        XCTAssertEqual(inner(s), [false, true])
        B08QA.log("EC-02|\(B08Engine.describe(s))|Medien ohne Tonspur, Lautstärke \(s.slots.map(\.engine.volume))")
        // unbekannte ID
        let snapshot = s.slots.map(\.id)
        s.remove(UUID())
        XCTAssertEqual(s.slots.map(\.id), snapshot)
    }

    // MARK: AK-19 · EC-05 — Entfernen gibt die Engine frei, die Verbindung endet (auch beim Laden)

    func testAK19_EC05_EntfernenGibtFreiUndSchliesstVerbindung() async throws {
        let s = session()
        let specs: [(String, String)] = [("VLC spielt", "/tslive/ak19-vlc.ts"), ("AVKit spielt", "/livehls/ak19-av/index.m3u8"),
                                          ("VLC lädt", "/hang/ak19-vlc-hang.ts"), ("AVKit lädt", "/hang/ak19-av-hang/index.m3u8")]
        var weaks: [B08Weak] = []
        for (n, p) in specs {
            add(s, channel(n, p))
            weaks.append(B08Weak(s.slots.last!.engine, n))
        }
        await B08QA.spin(5)
        B08QA.log("AK-19|vorher|\(B08Engine.describe(s))|\(server.summary("ak19"))")
        XCTAssertEqual(s.slots.map { B08Engine.name($0.engine.state) }.prefix(2), ["playing", "playing"])
        let openBefore = server.openConnections(containing: "ak19").count
        XCTAssertGreaterThanOrEqual(openBefore, 4)
        for id in s.slots.map(\.id) { s.remove(id) }
        await B08QA.spin(0.2)
        let alive = weaks.filter(\.alive).map(\.label)
        B08QA.log("AK-19|direkt nach remove|lebt=\(alive)")
        XCTAssertEqual(alive, [], "Engines sofort freigegeben")
        let removedAt = Date()
        var closedAt: [String: TimeInterval] = [:]
        while Date().timeIntervalSince(removedAt) < 8 {
            for (_, p) in specs where closedAt[p] == nil {
                let key = String(p.split(separator: "/").dropFirst().joined(separator: "/").prefix(18))
                if server.openStreamConnections(containing: key).isEmpty { closedAt[p] = Date().timeIntervalSince(removedAt) }
            }
            if closedAt.count == specs.count { break }
            await B08QA.spin(0.2)
        }
        await B08QA.spin(5)
        // HLS: gibt es nach dem Entfernen (ab 1 s) noch Abrufe?
        let hlsLate = server.requests(containing: "ak19-av/").filter { $0.time > removedAt.addingTimeInterval(1) }
        let idle = server.openConnections(containing: "ak19")
        B08QA.log("AK-19|Stream-Verbindungen zu nach s|\(specs.map { "\($0.0)=\(closedAt[$0.1].map(B08QA.f1) ?? "offen")" })|HLS-Abrufe nach >1 s=\(hlsLate.count)|leere Keep-alive-Verbindungen 5 s danach=\(idle.count) \(idle.map { "#\($0.id)\($0.path)" })")
        XCTAssertEqual(server.openStreamConnections(containing: "ak19").count, 0, "alle Stream-Verbindungen zu")
        XCTAssertLessThanOrEqual(closedAt[specs[0].1] ?? 99, 2.0, "MPEG-TS nach ≤ 2 s zu")
        XCTAssertLessThanOrEqual(closedAt.values.max() ?? 99, 2.0, "auch ladende Kacheln")
        XCTAssertEqual(hlsLate.count, 0, "HLS-Abrufe enden")
        // Beobachtung (Hinweis, kein Kriterium): wie lange bleibt die leere HLS-Keep-alive-Verbindung offen?
        let idleClosed = await B08QA.wait(40, step: 0.5) { self.server.openConnections(containing: "ak19").isEmpty }
        B08QA.log("AK-19|leere Keep-alive-Verbindung zu nach \(idleClosed.map { B08QA.f1($0 + 6) } ?? "> 46") s ab Entfernen")
    }

    // MARK: EC-04 — pausierte, aber gehaltene Engine hält ihre Verbindung

    func testEC04_PauseOhneFreigabeHaeltVerbindung() async throws {
        let vlc = VLCPlaybackEngine()
        vlc.setMuted(true); vlc.setVolume(0)
        vlc.load(server.url("/tslive/ec04-vlc.ts"))
        let av = AVKitPlaybackEngine()
        av.setMuted(true); av.setVolume(0)
        av.load(server.url("/livehls/ec04-av/index.m3u8"))
        _ = await B08QA.wait(10) { vlc.state == .playing && av.state == .playing }
        vlc.pause(); av.pause()
        let t = Date()
        await B08QA.spin(8)
        let playlistAbrufe = server.requests(containing: "ec04-av/index.m3u8").filter { $0.time > t }.count
        let vlcOpen = server.openStreamConnections(containing: "ec04-vlc").count
        B08QA.log("EC-04|8 s pausiert, Engine gehalten|VLC offen=\(vlcOpen)|HLS-Playlistabrufe=\(playlistAbrufe)|\(server.summary("ec04"))")
        XCTAssertEqual(vlcOpen, 1, "VLC hält die Verbindung trotz Pause")
        XCTAssertGreaterThan(playlistAbrufe, 0, "AVKit ruft die HLS-Playlist weiter ab")
        vlc.setMuted(true)
        B08Registry.stopAll()
        withExtendedLifetime((vlc, av)) {}
    }

    // MARK: AK-20 (Session-Teil) — clear() gibt alles frei

    func testAK20_ClearGibtAlleEnginesUndVerbindungenFrei() async throws {
        let s = session()
        var weaks: [B08Weak] = []
        for (i, p) in ["/tslive/ak20a.ts", "/livehls/ak20b/index.m3u8", "/tslive/ak20c.ts", "/hang/ak20d.ts"].enumerated() {
            add(s, channel("K\(i)", p)); weaks.append(B08Weak(s.slots.last!.engine, "K\(i)"))
        }
        await B08QA.spin(4)
        s.layout = .grid
        s.clear()
        XCTAssertTrue(s.isEmpty)
        XCTAssertEqual(s.focusedIndex, 0)
        XCTAssertEqual(s.layout, .grid, "clear() lässt das Layout stehen")
        await B08QA.spin(0.2)
        XCTAssertEqual(weaks.filter(\.alive).count, 0)
        let clearedAt = Date()
        let closed = await B08QA.wait(4) { self.server.openStreamConnections(containing: "ak20").isEmpty }
        await B08QA.spin(4)
        let hlsLate = server.requests(containing: "ak20b").filter { $0.time > clearedAt.addingTimeInterval(1) }.count
        B08QA.log("AK-20|clear|Stream-Verbindungen zu nach=\(closed.map(B08QA.f1) ?? "offen") s|HLS-Abrufe nach >1 s=\(hlsLate)|\(server.summary("ak20"))")
        XCTAssertNotNil(closed)
        XCTAssertLessThanOrEqual(closed ?? 99, 3.0)
        XCTAssertEqual(hlsLate, 0)
    }

    // MARK: AK-25 · AK-26 ⚠ — Fehler je Kachel

    func testAK25_AK26_FehlerJeKachel() async throws {
        let s1 = session()
        add(s1, channel("404 HLS", "/404/ak25/index.m3u8"))
        add(s1, Channel(name: "Port zu HLS", streamURL: URL(string: "http://127.0.0.1:9/ak25/index.m3u8")!))
        add(s1, channel("OK TS", "/tslive/ak25ok.ts"))
        let okAV = await B08QA.wait(12) {
            if case .failed = s1.slots[0].engine.state, case .failed = s1.slots[1].engine.state { return true }
            return false
        }
        B08QA.log("AK-25|AVKit|nach \(okAV.map(B08QA.f1) ?? "-") s|\(B08Engine.describe(s1))")
        guard case .failed(let m404) = s1.slots[0].engine.state, case .failed(let mPort) = s1.slots[1].engine.state else {
            return XCTFail("AVKit-Kacheln zeigen keinen Fehler: \(B08Engine.describe(s1))")
        }
        XCTAssertTrue(m404.contains("not found") || m404.contains("nicht gefunden"), m404)
        XCTAssertTrue(mPort.lowercased().contains("connect") || mPort.contains("Verbindung"), mPort)
        // Seit B06 · BUG-01 gilt VLC erst mit dem ersten Bild als „spielt“ (≈ 0,3 s), nicht schon beim Puffern
        let okTS = await B08QA.wait(5) { s1.slots[2].engine.state == .playing }
        XCTAssertNotNil(okTS, "die anderen Kacheln laufen weiter")
        XCTAssertEqual(s1.slots[2].engine.state, .playing, "die anderen Kacheln laufen weiter")
        for m in [m404, mPort] {
            XCTAssertFalse(m.contains("127.0.0.1") || m.contains("/ak25") || m.contains(B08QA.pass), "AK-32: keine Adresse in der Meldung: \(m)")
        }
        s1.clear()

        // VLC: 404, Port zu, Abbruch während der Wiedergabe, Server antwortet nie; AVKit: Segmente ab 6 s 404
        let s2 = session()
        add(s2, channel("404 TS", "/404/ak26.ts"))
        add(s2, Channel(name: "Port zu TS", streamURL: URL(string: "http://127.0.0.1:9/ak26.ts")!))
        add(s2, channel("Abbruch TS", "/abort/5/tslive/ak26abort.ts"))
        add(s2, channel("Hängt TS", "/hang/ak26hang.ts"))
        var verlauf: [String] = []
        for t in [3.0, 8.0, 16.0, 25.0] {
            await B08QA.spin(t == 3 ? 3 : (t == 8 ? 5 : (t == 16 ? 8 : 9)))
            let line = "t=\(Int(t))s|\(B08Engine.describe(s2))"
            verlauf.append(line)
            B08QA.log("AK-26|VLC|\(line)")
        }
        let states = s2.slots.map { B08Engine.name($0.engine.state) }
        let failedCount = s2.slots.filter { if case .failed = $0.engine.state { return true } else { return false } }.count
        // Seit B08 · BUG-07 (Build 2026-09-28): AVKit-Kacheln haben eine Frist ohne Fortschritt (Standard 30 s, hier
        // verkürzt auf 5 s, damit das Beobachtungsfenster von 20 s bleibt; mit Standardfrist: B08ReparaturTests).
        MultiviewSession.stallLimitForNewTiles = 5
        defer { MultiviewSession.stallLimitForNewTiles = 30 }
        let s3 = session()
        add(s3, channel("Segmente 404 HLS", "/seg404/6/ak26seg/index.m3u8"))
        await B08QA.spin(20)
        B08QA.log("AK-26|AVKit Segmente 404 ab 6 s|\(B08Engine.describe(s3))|seg404=\(server.requests(containing: "ak26seg").filter { $0.status == 404 }.count)")
        let segState = B08Engine.name(s3.slots[0].engine.state)
        // VLC-Teil durch B06 · BUG-01 behoben (Build 2026-09-27): 404, Port zu und Abbruch melden sich; der Hänger zeigt
        // bis zur Ladefrist von 40 s die Ladeanzeige (nach 25 s also noch `loading`, nicht mehr „spielt“).
        XCTAssertEqual(failedCount, 3, "404, Port zu und Abbruch zeigen „Wiedergabe fehlgeschlagen“ – ist: \(states)")
        XCTAssertTrue(states[0].hasPrefix("failed"), "404 TS: \(states[0])")
        XCTAssertTrue(states[1].hasPrefix("failed"), "Port zu TS: \(states[1])")
        XCTAssertTrue(states[2].hasPrefix("failed"), "Abbruch während der Wiedergabe: \(states[2])")
        XCTAssertEqual(states[3], "loading", "Server antwortet nie: Ladeanzeige bis zur Frist, nicht „spielt“")
        XCTAssertEqual(s3.slots[0].engine.state, .failed(AVKitPlaybackEngine.interruptedMessage),
                       "HLS mit 404-Segmenten meldet sich nach der Frist – ist: \(segState)")
    }

    // MARK: AK-30 ⚠ · AK-31 ⚠ — N Kacheln = N Verbindungen mit Zugangsdaten; Anbieterlimit 1

    func testAK30_NKachelnNVerbindungenMitZugangsdaten() async throws {
        let container = try B08QA.inMemoryContainer()
        let p = try await importXtream(container.mainContext, output: .mpegts)
        let chans = p.channels.sorted { $0.name < $1.name }
        XCTAssertEqual(chans.count, 4)
        XCTAssertFalse(chans[0].streamURL.absoluteString.contains(B08QA.pass), "gespeicherte Adresse ohne Passwort (B01)")
        let s = session()
        var counts: [Int] = []
        for c in chans {
            add(s, c)
            await B08QA.spin(2.5)
            counts.append(server.openStreamConnections(containing: "/live/").count)
        }
        let paths = Set(server.requests(containing: "/live/").map { server.redact($0.path) })
        let uas = Set(server.requests(containing: "/live/").map { $0.headers["user-agent"] ?? "-" })
        B08QA.log("AK-30|offene Verbindungen nach 1…4 Kacheln=\(counts)|pfade=\(paths.sorted())|user-agent=\(uas)")
        XCTAssertEqual(counts, [1, 2, 3, 4])
        XCTAssertTrue(paths.allSatisfy { $0.hasPrefix("/live/qa-user/<pass>/") }, "jede Verbindung mit Benutzername und Passwort im Pfad")
        XCTExpectFailure("BUG-06 · keine Rücksicht auf das Verbindungslimit, kein Hinweis (FB-06)") {
            XCTAssertLessThanOrEqual(counts.last ?? 0, 1, "Anbieter meldet max_connections=1 – die App öffnet trotzdem 4")
        }
    }

    /// Seit B06 · BUG-01 (Build 2026-09-27) melden sich die abgelehnten Kacheln; offen bleibt die Rücksicht auf das Limit (AK-30).
    func testAK31_AnbieterlimitEinsDreiKachelnMeldenAblehnung() async throws {
        let container = try B08QA.inMemoryContainer()
        let p = try await importXtream(container.mainContext, output: .mpegts)
        let chans = p.channels.sorted { $0.name < $1.name }
        server.configure(connectionLimit: 1)
        let s = session()
        let t0 = Date()
        for c in chans { add(s, c) }
        await B08QA.spin(15)
        let reqs = server.requests(containing: "/live/")
        var perStream: [String: [Int]] = [:]
        for r in reqs { perStream[String(r.path.split(separator: "/").last ?? ""), default: []].append(r.status) }
        let spans: [String: String] = perStream.mapValues { _ in "" }
        _ = spans
        let firstAttempts = Dictionary(grouping: reqs.filter { $0.status == 403 }) { String($0.path.split(separator: "/").last ?? "") }
            .mapValues { rs -> String in
                let ts = rs.map { $0.time.timeIntervalSince(t0) }.sorted()
                return "\(rs.count)× in \(Int(((ts.last ?? 0) - (ts.first ?? 0)) * 1000)) ms"
            }
        B08QA.log("AK-31|limit 1|\(B08Engine.describe(s))|status je Stream=\(perStream.sorted { $0.key < $1.key })|403-Versuche=\(firstAttempts.sorted { $0.key < $1.key })|\(server.summary("/live/"))")
        let states = s.slots.map { B08Engine.name($0.engine.state) }
        XCTAssertEqual(states.first, "playing", "die erste Kachel spielt")
        XCTAssertEqual(reqs.filter { $0.status == 403 }.count >= 3, true)
        XCTAssertTrue(s.slots.dropFirst().allSatisfy { $0.engine.state == .failed(VLCPlaybackEngine.Failure.cannotOpen.message) },
                      "drei Kacheln melden die Ablehnung – ist: \(states)")
    }

    // MARK: AK-27 ⚠ · AK-28 ⚠ · EC-14 · Angriff 8 — Löschen und Aktualisieren der Playlist bei laufenden Kacheln

    func testAK27_EC14_Angriff8_LoeschenLaesstKachelnMitZugangsdatenLaufen() async throws {
        let (container, storeURL) = try B08QA.fileContainer("ak27")
        let ctx = container.mainContext
        let p = try await importXtream(ctx, output: .mpegts, name: "QA Löschen")
        let pid = p.id
        let chans = p.channels.sorted { $0.name < $1.name }
        let s = session()
        add(s, chans[0]); add(s, chans[1])
        _ = await B08QA.wait(10) { s.slots.allSatisfy { $0.engine.state == .playing } }
        XCTAssertNotNil(try XtreamCredentialStore.standard.load(for: pid))
        let openBefore = server.openStreamConnections(containing: "/live/qa-user/\(B08QA.pass)/").count
        try await PlaylistImporter(modelContext: ctx).delete(p)
        await B08QA.spin(4)
        let pl = B08.sqliteCount(storeURL.path, "select count(*) from ZPLAYLIST") ?? -1
        let ch = B08.sqliteCount(storeURL.path, "select count(*) from ZCHANNEL") ?? -1
        let key = try XtreamCredentialStore.standard.load(for: pid)
        let openAfter = server.openStreamConnections(containing: "/live/qa-user/\(B08QA.pass)/")
        let bytesBefore = openAfter.map(\.bytesSent).reduce(0, +)
        await B08QA.spin(2)
        let bytesAfter = server.openStreamConnections(containing: "/live/qa-user/\(B08QA.pass)/").map(\.bytesSent).reduce(0, +)
        // EC-14: Fokus wechseln, Namen lesen
        s.setFocus(1)
        let names = s.slots.map(\.channel.name)
        B08QA.log("AK-27|nach Löschen|sqlite ZPLAYLIST=\(pl) ZCHANNEL=\(ch)|schlüsselbund=\(key == nil ? "leer" : "vorhanden")|offen vorher/nachher=\(openBefore)/\(openAfter.count)|bytes +\(bytesAfter - bytesBefore) in 2 s|\(B08Engine.describe(s))|namen=\(names)")
        XCTAssertEqual(pl, 0); XCTAssertEqual(ch, 0)
        XCTAssertNil(key, "Schlüsselbund-Eintrag entfernt")
        // Seit B03 · BUG-05: Das Löschen der Playlist beendet ihre Kacheln samt Verbindungen; EC-14 (Fokus, Namen) ohne
        // Absturz auf der leeren Session.
        XCTAssertEqual(openAfter.count, 0, "keine Verbindung mit Zugangsdaten mehr")
        XCTAssertEqual(bytesAfter, bytesBefore, "es wird nicht weiter gestreamt")
        XCTAssertTrue(s.isEmpty)
        XCTAssertEqual(names, [])
    }

    func testAK28_AktualisierenAlteAdresseUndZweiteKachel() async throws {
        let container = try B08QA.inMemoryContainer()
        let ctx = container.mainContext
        let p = try await importXtream(ctx, output: .mpegts, name: "QA Aktualisieren")
        let old = try XCTUnwrap(p.channels.first { $0.name == "QA Kanal 1" })
        let s = session()
        add(s, old)
        _ = await B08QA.wait(8) { s.slots.first?.engine.state == .playing }
        server.configure(streamIDs: [201, 202, 203, 204])
        try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).refresh(p)
        await B08QA.spin(1)
        let fresh = try XCTUnwrap(p.channels.first { $0.name == "QA Kanal 1" })
        add(s, fresh)
        await B08QA.spin(3)
        let open = server.openStreamConnections(containing: "/live/").map { server.redact($0.path) }.sorted()
        B08QA.log("AK-28|nach Aktualisieren|slots=\(s.slots.map(\.channel.name))|offen=\(open)|alteAdresse=\(old.streamURL.lastPathComponent) neu=\(fresh.streamURL.lastPathComponent)")
        XCTAssertEqual(s.slots.map(\.channel.name), ["QA Kanal 1", "QA Kanal 1"], "derselbe Sender zweimal")
        XCTAssertEqual(open, ["/live/qa-user/<pass>/101.ts", "/live/qa-user/<pass>/201.ts"], "alte Adresse läuft weiter, neue kommt dazu")
        XCTExpectFailure("BUG-05 · nach dem Aktualisieren spielt die Kachel die alte Adresse (FB-05)") {
            XCTAssertFalse(open.contains("/live/qa-user/<pass>/101.ts"))
        }
    }

    // MARK: AK-24 · AK-34 — nichts gespeichert

    func testAK24_AK34_NichtsInDatenbankEinstellungenSchluesselbund() async throws {
        let (container, storeURL) = try B08QA.fileContainer("ak34")
        let ctx = container.mainContext
        let pl = Playlist(name: "QA M3U", sourceURL: server.url("/list.m3u"), lastRefreshed: Date())
        ctx.insert(pl)
        let c1 = Channel(name: "AK34 A", streamURL: server.url("/tslive/ak34a.ts"), playlist: pl)
        let c2 = Channel(name: "AK34 B", streamURL: server.url("/livehls/ak34b/index.m3u8"), playlist: pl)
        ctx.insert(c1); ctx.insert(c2)
        try ctx.save()
        let defaultsBefore = Set(UserDefaults.standard.dictionaryRepresentation().keys)
        let storeBefore = try Data(contentsOf: storeURL)
        let walBefore = (try? Data(contentsOf: URL(fileURLWithPath: storeURL.path + "-wal"))) ?? Data()
        let s = session()
        add(s, c1); add(s, c2)
        s.setFocus(1); s.layout = .grid; s.layout = .focus
        await B08QA.spin(3)
        s.remove(s.slots[0].id)
        s.clear()
        let defaultsAfter = Set(UserDefaults.standard.dictionaryRepresentation().keys)
        let neu = defaultsAfter.subtracting(defaultsBefore)
        let storeAfter = try Data(contentsOf: storeURL)
        let walAfter = (try? Data(contentsOf: URL(fileURLWithPath: storeURL.path + "-wal"))) ?? Data()
        B08QA.log("AK-34|hasChanges=\(ctx.hasChanges)|store gleich=\(storeBefore == storeAfter)|wal gleich=\(walBefore == walAfter)|neue Einstellungen=\(neu.sorted())")
        XCTAssertFalse(ctx.hasChanges)
        XCTAssertEqual(storeBefore, storeAfter)
        XCTAssertEqual(walBefore, walAfter)
        XCTAssertTrue(neu.filter { !$0.hasPrefix("NSWindow") && !$0.hasPrefix("NS") && !$0.hasPrefix("Apple") && !$0.hasPrefix("com.apple") }.isEmpty,
                      "keine eigenen Einstellungen: \(neu)")
        // AK-24: eine neue Session (wie nach dem Neustart) ist leer und steht auf „Fokus"
        let fresh = MultiviewSession()
        XCTAssertTrue(fresh.isEmpty); XCTAssertEqual(fresh.layout, .focus); XCTAssertEqual(fresh.focusedIndex, 0)
    }

    // MARK: Angriff 1 · fremde IDs, fremde Session, manipulierte Playlist-Zuordnung

    func testAngriff1_FremdeIDsUndFremdeZuordnung() async throws {
        let a = session(), b = session()
        add(a, channel("A1", "/hang/ang1a.ts"))
        add(b, channel("B1", "/hang/ang1b.ts"))
        let aID = a.slots[0].id
        b.remove(aID)                      // Slot-ID der anderen Session
        b.setFocus(5)                      // Index außerhalb
        a.remove(UUID())                   // erfundene ID
        XCTAssertEqual(a.slots.count, 1); XCTAssertEqual(b.slots.count, 1)
        // Xtream-Sender, dessen Playlist-Zuordnung auf eine andere Playlist (ohne Schlüsselbund-Eintrag) zeigt
        let container = try B08QA.inMemoryContainer()
        let ctx = container.mainContext
        let px = try await importXtream(ctx, output: .mpegts, name: "Echt")
        let fremd = Playlist(name: "Fremd", sourceURL: server.url("/player_api.php"), isXtream: true, xtreamOutput: "mpegts")
        ctx.insert(fremd)
        let c = try XCTUnwrap(px.channels.first)
        let before = server.requests(containing: "/live/").count
        c.playlist = fremd                 // Zuordnung manipuliert
        add(a, c)
        await B08QA.spin(1)
        B08QA.log("Angriff1|fremde IDs ohne Wirkung|a=\(a.slots.count) b=\(b.slots.count)|manipulierte Zuordnung: slots=\(a.slots.count) liveAnfragen +\(server.requests(containing: "/live/").count - before)")
        XCTAssertEqual(a.slots.count, 1, "fremde Playlist ohne Zugangsdaten → keine Kachel")
        XCTAssertEqual(server.requests(containing: "/live/").count, before, "keine Anfrage mit fremden Zugangsdaten")
    }

    // MARK: Angriff 3 · Wiederholversuche — 10× derselbe Sender, 5× Öffnen/Schließen

    func testAngriff3_ZehnMalHinzufuegenUndFuenfZyklen() async throws {
        let s = session()
        let c = channel("Spam", "/tslive/ang3.ts")
        for _ in 0..<10 { add(s, c) }
        await B08QA.spin(2)
        let open10 = server.openStreamConnections(containing: "ang3").count
        let slots10 = s.slots.count
        XCTAssertEqual(s.slots.count, 4)
        XCTAssertEqual(open10, 4, "höchstens vier Verbindungen, auch bei 10 Klicks")
        var afterCycles: [Int] = []
        for _ in 0..<5 {
            s.clear()
            _ = await B08QA.wait(4) { self.server.openStreamConnections(containing: "ang3").isEmpty }
            afterCycles.append(server.openStreamConnections(containing: "ang3").count)
            for _ in 0..<4 { add(s, c) }
            await B08QA.spin(1)
        }
        s.clear()
        _ = await B08QA.wait(4) { self.server.openStreamConnections(containing: "ang3").isEmpty }
        B08QA.log("Angriff3|10× add → slots=\(slots10) offen=\(open10)|offen nach je clear=\(afterCycles)|am Ende offen=\(server.openStreamConnections(containing: "ang3").count)|verbindungen gesamt=\(server.connections.filter { $0.path.contains("ang3") }.count)")
        XCTAssertEqual(afterCycles, [0, 0, 0, 0, 0], "Verbindungen sammeln sich nicht an")
        XCTAssertEqual(server.openStreamConnections(containing: "ang3").count, 0)
    }

    // MARK: Angriff 5 · tatsächlicher Payload am Mock

    func testAngriff5_PayloadDerKachelnAmAnbieter() async throws {
        let container = try B08QA.inMemoryContainer()
        let ts = try await importXtream(container.mainContext, output: .mpegts, name: "TS")
        let s = session()
        add(s, ts.channels.sorted { $0.name < $1.name }[0])
        let hls = try await importXtream(container.mainContext, output: .hls, name: "HLS")
        add(s, hls.channels.sorted { $0.name < $1.name }[1])
        await B08QA.spin(5)
        let live = server.requests(containing: "/live/")
        for r in live.prefix(4) {
            let hdr = r.headers.keys.sorted().map { "\($0): \($0 == "host" ? "127.0.0.1:<port>" : server.redact(r.headers[$0] ?? ""))" }.joined(separator: " · ")
            B08QA.log("Angriff5|\(r.method) \(server.redact(r.target))|\(hdr)")
            B08QA.appendEvidence("angriff5-payload.txt", "\(r.method) \(server.redact(r.target)) HTTP/1.1 | \(hdr)")
        }
        let allHeaders = live.flatMap { $0.headers.keys }
        XCTAssertFalse(allHeaders.contains("cookie")); XCTAssertFalse(allHeaders.contains("authorization"))
        XCTAssertTrue(live.allSatisfy { $0.path.hasPrefix("/live/qa-user/") }, "Zugangsdaten im Pfad (Xtream-Protokoll)")
        XCTAssertEqual(Set(live.map { $0.headers["host"] ?? "" }), [server.hostPort], "nur an den Host der Playlist")
    }

    // MARK: Angriff 7 · Eingaben — Sendernamen und Adressen

    func testAngriff7_EingabenSendernamenUndAdressen() async throws {
        let s = session()
        let names = ["", "x", String(repeating: "Ä", count: 10_000), "📺🎉 Sport 🇱🇺", "'; drop table ZCHANNEL; --",
                     "<script>alert(1)</script>", "../../etc/passwd"]
        for n in names.prefix(4) { add(s, channel(n, "/hang/ang7-\(n.count).ts")) }
        XCTAssertEqual(s.slots.count, 4)
        let w = track(B08UI.window(MultiviewScreen().environment(s), size: CGSize(width: 900, height: 560)))
        s.layout = .grid
        await B08QA.spin(1)
        B08UI.shot(w, "angriff7-namen-raster")
        await safeClear(s)
        for n in names.suffix(3) { add(s, channel(n, "/hang/ang7-\(n.count).ts")) }
        add(s, Channel(name: "Datei", streamURL: URL(string: "file:///etc/passwd")!))
        await B08QA.spin(4)
        B08UI.shot(w, "angriff7-sonderzeichen-dateiadresse")
        let labels = B08UI.labels(w)
        B08QA.log("Angriff7|\(B08Engine.describe(s).replacingOccurrences(of: String(repeating: "Ä", count: 10_000), with: "Ä×10000"))|labels=\(labels.map { $0.count > 80 ? String($0.prefix(40)) + "…(\($0.count))" : $0 })")
        XCTAssertEqual(s.slots.count, 4)
        XCTAssertFalse(labels.contains { $0.contains("/etc/passwd") && !$0.hasPrefix("../../") }, "Dateiadresse nicht angezeigt")
        await safeClear(s)
    }
}

/// SQLite-Nachzählung auf Test-Datenbanken (nur eigene Temp-Dateien).
enum B08 {
    static func sqliteCount(_ path: String, _ sql: String) -> Int? { B01.sqliteCount(path, sql) }
}
