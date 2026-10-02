import XCTest
import AVFoundation
@testable import MikaPlusPlayer

/// B06 · Zustände und Fehler beider Engines gegen den lokalen Mock (stumme Medien, Engines vor dem Laden stumm).
/// AK-05, AK-06, AK-07, AK-09, AK-10, AK-11, AK-12, AK-31 (Engine-Texte), AK-32 (Payload), AK-35 (Version), EC-01…EC-04, EC-09.
/// Lange Beobachtungen (40–140 s) nur mit Umgebungsvariable `B06_LANGSAM=1` (xcodebuild: `TEST_RUNNER_B06_LANGSAM=1`).
@MainActor
final class B06EngineZustandTests: B06TestCase {

    private var langsam: Bool { ProcessInfo.processInfo.environment["B06_LANGSAM"] == "1" }

    private func start(_ cases: [(String, String)], forceAVKit: Set<String> = []) -> [(String, any PlaybackEngine)] {
        var items: [(String, any PlaybackEngine)] = []
        for (i, c) in cases.enumerated() {
            let url = c.1.hasPrefix("/") ? mock.url(c.1) : URL(string: c.1)!
            let e: any PlaybackEngine
            if forceAVKit.contains(c.0) {
                e = AVKitPlaybackEngine()
                e.setMuted(true)
                engines.append(e)
            } else {
                e = mutedEngine(for: url)
            }
            host(e, index: i)
            B06QA.log("\(c.0)|load|\(type(of: e))|\(url.absoluteString)")
            e.load(url)
            items.append((c.0, e))
        }
        return items
    }

    /// Beobachtet alle Engines parallel; Rückgabe je Label: Zeitpunkt des ersten Wechsels in jeden Zustand.
    private func observe(_ items: [(String, any PlaybackEngine)], seconds: TimeInterval) async -> [String: [String: TimeInterval]] {
        var first: [String: [String: TimeInterval]] = [:]
        var last: [String: String] = [:]
        var lastRaw: [String: String] = [:]
        let t0 = Date()
        while true {
            let t = Date().timeIntervalSince(t0)
            for (label, e) in items {
                if let v = B06Engine.vlcPlayer(e) {
                    let r = B06Engine.vlcState(v)
                    if lastRaw[label] != r {
                        lastRaw[label] = r
                        B06QA.log("\(label)|t=\(B06QA.f1(t))s|vlcRoh=\(r)")
                    }
                }
                let s = B06Engine.name(e.state)
                if last[label] != s {
                    last[label] = s
                    let key = s.hasPrefix("failed") ? "failed" : s
                    if first[label]?[key] == nil { first[label, default: [:]][key] = t }
                    B06QA.log("\(label)|t=\(B06QA.f1(t))s|state=\(s)|\(B06Engine.detail(e))")
                }
            }
            if t >= seconds { break }
            await B06QA.spin(0.05)
        }
        return first
    }

    private func failureText(_ e: any PlaybackEngine) -> String? {
        if case .failed(let m) = e.state { return m }
        return nil
    }

    // MARK: AK-05 · AVKit spielt

    func testAK05_EC02_AVKitSpieltHLSVodLiveMP4() async throws {
        let items = start([
            ("hls-vod", "/hls/vod.m3u8"),
            ("hls-live", "/livehls/ak05/index.m3u8"),
            ("mp4", "/clip.mp4"),
            ("hls-als-m3u", "/livehls/ak05m3u/index.m3u"),
        ])
        let first = await observe(items, seconds: 9)
        for (label, e) in items {
            let t = first[label]?["playing"]
            B06QA.log("AK-05|\(label)|playingNach=\(t.map(B06QA.f1) ?? "-")s|ende=\(B06Engine.name(e.state))")
            XCTAssertNotNil(t, label)
            XCTAssertLessThan(t ?? 99, 3.0, label)
            XCTAssertEqual(e.state, .playing, label)
        }
        let playlistFetches = mock.requests(containing: "/livehls/ak05/index.m3u8").map(\.time)
        let gaps = zip(playlistFetches.dropFirst(), playlistFetches).map { $0.timeIntervalSince($1) }
        let segs = mock.requests(containing: "/livehls/ak05/seg").count
        B06QA.log("AK-05|live|playlistAbrufe=\(playlistFetches.count)|abstaende=\(gaps.map(B06QA.f1))|segmente=\(segs)|UA=\(mock.requests(containing: "/livehls/ak05/").first?.userAgent ?? "-")")
        XCTAssertGreaterThanOrEqual(playlistFetches.count, 3, "Live-Playlist wird wiederholt geladen")
        XCTAssertGreaterThanOrEqual(segs, 3)
    }

    // MARK: AK-06 / AK-31 / EC-01 / EC-02 / EC-03 · AVKit-Fehler (schnell)

    func testAK06_AK31_EC01_EC02_EC03_AVKitFehlertexte() async throws {
        let x = "/live/\(B06QA.user)/\(B06QA.pass)"
        let items = start([
            ("404-m3u8", "/404/a.m3u8"),
            ("403-m3u8", "/403/a.m3u8"),
            ("401-m3u8", "/401/a.m3u8"),
            ("port-zu", "http://127.0.0.1:1/a.m3u8"),
            ("dns", "http://b06-qa.invalid/a.m3u8"),
            ("html-m3u8", "/html/a.m3u8"),
            ("html-mp4", "/html/a.mp4"),
            ("ts-live-ohne-endung", "/tslive/ec01"),
            ("m3u-senderliste", "/m3uplaylist/list.m3u"),
            ("xtream-404-m3u8", "\(x)/404/101.m3u8"),
            ("ts-datei-avkit", "/static/src.ts"),
            ("ts-live-avkit", "/tslive/ec03.ts"),
        ], forceAVKit: ["ts-datei-avkit", "ts-live-avkit"])
        let first = await observe(items, seconds: 8)
        let expected: [String: String] = [
            "404-m3u8": "The requested URL was not found on this server.",
            "403-m3u8": "You do not have permission to access the requested resource.",
            "401-m3u8": "The operation couldn’t be completed. (NSURLErrorDomain error -1013.)",
            "port-zu": "Could not connect to the server.",
            "dns": "A server with the specified hostname could not be found.",
            "html-m3u8": "unsupported URL",
            "html-mp4": "Operation Stopped",
            "ts-live-ohne-endung": "Operation Stopped",
            "m3u-senderliste": "The operation couldn’t be completed. (CoreMediaErrorDomain error -12646.)",
            "xtream-404-m3u8": "The requested URL was not found on this server.",
            "ts-live-avkit": "Operation Stopped",
        ]
        var abweichend: [String] = []
        for (label, e) in items {
            let text = failureText(e)
            let t = first[label]?["failed"]
            B06QA.log("AK-06|\(label)|fehlerNach=\(t.map(B06QA.f1) ?? "-")s|text=\(text ?? "-")|zustand=\(B06Engine.name(e.state))")
            if label == "ts-datei-avkit" {
                XCTAssertEqual(e.state, .playing, "EC-03: abgeschlossene TS-Datei mit Byte-Range spielt über AVKit")
                continue
            }
            if SystemSprache.englisch(text) != expected[label] { abweichend.append("\(label): \(text ?? B06Engine.name(e.state))") } // B09 · OF-01: englisch oder deutsch
            XCTAssertLessThan(t ?? 99, 2.0, "\(label): Fehler schnell sichtbar")
            // AK-31: kein Host, Benutzer, Passwort, keine Adresse im Text
            for secret in [B06QA.pass, B06QA.user, "127.0.0.1", "b06-qa.invalid", "/live/"] {
                XCTAssertFalse((text ?? "").contains(secret), "AK-31 \(label) enthält \(secret)")
            }
        }
        XCTAssertEqual(abweichend, [], "Texte weichen von AK-06 ab")
    }

    // MARK: AK-06 / EC-09 · AVKit Hänger und Abbruch (lang)

    func testAK06_EC09_AVKitHaengerUndAbbruch_langsam() async throws {
        guard langsam else { throw XCTSkip("nur mit B06_LANGSAM=1 (≈ 130 s)") }
        let items = start([
            ("haenger-m3u8", "/hang/a.m3u8"),
            ("haenger-mp4", "/hang/a.mp4"),
            ("live-abbruch-10s", "/abort/10/livehls/ec09/index.m3u8"),
        ])
        let first = await observe(items, seconds: 130)
        for (label, e) in items {
            B06QA.log("AK-06-lang|\(label)|zeiten=\(first[label] ?? [:])|text=\(failureText(e) ?? "-")")
        }
        XCTAssertEqual(failureText(items[0].1), "resource unavailable")
        XCTAssertEqual(failureText(items[1].1), "The operation could not be completed")
        XCTAssertEqual(failureText(items[2].1), "The network connection was lost.")
        XCTAssertEqual(first["haenger-m3u8"]?["failed"] ?? 0, 40, accuracy: 8)
        XCTAssertEqual(first["haenger-mp4"]?["failed"] ?? 0, 120, accuracy: 10)
        XCTAssertEqual((first["live-abbruch-10s"]?["failed"] ?? 0) - 10, 31, accuracy: 10)
    }

    // MARK: AK-07 · verzögerter Start (lang)

    func testAK07_LiveHLSVerzoegertUm25s_langsam() async throws {
        guard langsam else { throw XCTSkip("nur mit B06_LANGSAM=1 (≈ 45 s)") }
        let items = start([("delay25", "/delay/25/livehls/ak07/index.m3u8")])
        let first = await observe(items, seconds: 45)
        let fetches = mock.requests(containing: "ak07/index.m3u8").map { B06QA.f1($0.time.timeIntervalSince(mock.requests.first!.time)) }
        let zustand = B06Engine.name(items[0].1.state)
        B06QA.log("AK-07|zeiten=\(first["delay25"] ?? [:])|endzustand=\(zustand)|playlistAbrufe(s ab erster Anfrage)=\(fetches)")
        // Belegt wird der **neue Abruf nach ≈ 20 s**. Ob der Stream danach spielt, ist ein Wettlauf zwischen der
        // Antwort des Servers und der Aufgabefrist von AVFoundation: 2026-09-16 und 11:35 → `playing` nach 20,07 s,
        // unter Last (drei parallele Builds) → `failed("resource unavailable")` nach 20,05 s (QA 2026-09-26).
        XCTAssertGreaterThanOrEqual(fetches.count, 2, "AVKit startet einen neuen Abruf")
        XCTAssertEqual(Double(fetches[1]) ?? 0, 20, accuracy: 3, "neuer Abruf nach ≈ 20 s")
        if zustand == "playing" {
            XCTAssertGreaterThan(first["delay25"]?["playing"] ?? 0, 15)
        } else {
            B06QA.log("AK-07|Hinweis: Antwort kam nach der Aufgabefrist – Endzustand \(zustand)")
        }
    }

    // MARK: AK-09 / AK-32 / AK-35 · VLC spielt

    func testAK09_AK32_AK35_VLCSpieltAlleEndungen() async throws {
        let x = "/live/\(B06QA.user)/\(B06QA.pass)"
        let items = start([
            ("ts", "/tslive/ak09.ts"), ("mpegts", "/tslive/ak09.mpegts"), ("mts", "/tslive/ak09.mts"),
            ("m2ts", "/tslive/ak09.m2ts"), ("TS", "/tslive/ak09b.TS"), ("xtream-ts", "\(x)/101.ts"),
        ])
        let first = await observe(items, seconds: 10)
        for (label, e) in items {
            let v = B06Engine.vlcPlayer(e)
            B06QA.log("AK-09|\(label)|engine=\(type(of: e))|playingNach=\(first[label]?["playing"].map(B06QA.f1) ?? "-")s|vlc=\(v.map(B06Engine.vlcState) ?? "-")")
            XCTAssertTrue(String(describing: type(of: e)).contains("VLC"), label)
            XCTAssertEqual(e.state, .playing, label)
            XCTAssertLessThan(first[label]?["playing"] ?? 99, 2.0, label)
            XCTAssertEqual(v.map(B06Engine.vlcIsPlaying), true, "\(label): VLC isPlaying (Rohzustand \(v.map(B06Engine.vlcState) ?? "-"))")
        }
        let now = Date()
        for c in mock.connections where c.path.contains("ak09") || c.path.contains("/live/") {
            let last5 = c.bytes(from: now.addingTimeInterval(-5), to: now)
            B06QA.log("AK-09|verbindung \(c.id)|\(c.path.replacingOccurrences(of: B06QA.pass, with: "<pass>"))|bytes=\(c.bytesSent)|letzte5s=\(last5)|rate/s=\(Int(mock.media.tsRate))")
            XCTAssertGreaterThan(last5, Int(mock.media.tsRate * 2), "Daten fließen in Echtzeit")
        }
        let xr = mock.requests(containing: "/live/")
        for r in xr {
            B06QA.log("AK-32|\(r.method) \(r.target.replacingOccurrences(of: B06QA.pass, with: "<pass>"))|UA=\(r.userAgent)|Range=\(r.range)|Kopfzeilen=\(r.headers.keys.sorted())")
        }
        XCTAssertEqual(xr.count, 1, "AK-32: bei .ts einmal je Öffnen")
        XCTAssertEqual(xr.first?.target, "\(x)/101.ts")
        XCTAssertEqual(xr.first?.userAgent, "VLC/3.0.21 LibVLC/3.0.21", "AK-35: eingebettete libVLC-Version")
        XCTAssertEqual(xr.first?.range, "bytes=0-")
    }

    // MARK: AK-10 · VLC: HTTP-Fehler und Host weg (behoben in Build B06 · BUG-01)

    func testAK10_VLCHTTPFehlerUndHostWegZeigenMeldung() async throws {
        let seconds: TimeInterval = langsam ? 60 : 8
        let items = start([
            ("401-ts", "/401/ak10.ts"), ("403-ts", "/403/ak10.ts"), ("404-ts", "/404/ak10.ts"),
            ("port-zu-ts", "http://127.0.0.1:1/ak10.ts"), ("dns-ts", "http://b06-qa.invalid/ak10.ts"),
            ("xtream-404-ts", "/live/\(B06QA.user)/\(B06QA.pass)/404/ak10.ts"),
        ])
        let first = await observe(items, seconds: seconds)
        var summary: [String] = []
        for (label, e) in items {
            let v = B06Engine.vlcPlayer(e)
            let path = label.hasPrefix("xtream") ? "/live/\(B06QA.user)/\(B06QA.pass)/404/ak10.ts" : "/\(label.prefix(3))/ak10.ts"
            let reqs = label.contains("port") || label.contains("dns") ? -1 : mock.requests.filter { $0.path == path }.count
            summary.append("\(label):\(B06Engine.name(e.state))/vlc=\(v.map(B06Engine.vlcState) ?? "-")/anfragen=\(reqs)")
            B06QA.log("AK-10|\(label)|nach \(Int(seconds))s|zustand=\(B06Engine.name(e.state))|zeiten=\(first[label] ?? [:])|vlcRoh=\(v.map(B06Engine.vlcState) ?? "-")|anfragen=\(reqs)")
            // Behoben: VLC-Fehler enden in der Fehleransicht mit deutscher Meldung, schnell und dauerhaft
            XCTAssertEqual(failureText(e), VLCPlaybackEngine.Failure.cannotOpen.message, label)
            XCTAssertLessThan(first[label]?["failed"] ?? 99, 3.0, "\(label): Meldung nach < 3 s")
            XCTAssertNil(first[label]?["playing"], "\(label): nie „läuft“")
            for secret in [B06QA.pass, B06QA.user, "127.0.0.1", "b06-qa.invalid", "/live/", "ak10"] {
                XCTAssertFalse((failureText(e) ?? "").contains(secret), "AK-31 \(label) enthält \(secret)")
            }
        }
        B06QA.log("AK-10|zusammenfassung|\(summary)")
        let offen = mock.connections.filter { $0.path.contains("ak10") && $0.closed == nil }.map(\.path)
        XCTAssertEqual(offen, [], "nach der Meldung keine offene Verbindung")
    }

    // MARK: AK-11 · VLC: keine Daten, HTML, verzögert (behoben in Build B06 · BUG-01)

    /// Schnell mit kurzen Fristen (Laden 5 s); mit `B06_LANGSAM=1` mit den Standardfristen (40 s / 30 s).
    func testAK11_VLCHaengerHTMLVerzoegertMeldenSich() async throws {
        if !langsam { VLCPlaybackEngine.limitsForNewEngines = .init(load: 5, stall: 5) }
        let loadLimit = VLCPlaybackEngine.limitsForNewEngines.load
        let seconds: TimeInterval = langsam ? 60 : 12
        let items = start([
            ("haenger-ts", "/hang/ak11.ts"), ("html-ts", "/html/ak11.ts"), ("verzoegert30-ts", "/delay/30/tslive/ak11.ts"),
        ])
        let first = await observe(items, seconds: seconds)
        let now = Date()
        for (label, e) in items {
            let v = B06Engine.vlcPlayer(e)
            let bytes = mock.connections.filter { $0.path.contains("ak11") && $0.path.contains(label.prefix(4)) }.map(\.bytesSent)
            B06QA.log("AK-11|\(label)|nach \(Int(seconds))s|zustand=\(B06Engine.name(e.state))|zeiten=\(first[label] ?? [:])|vlcRoh=\(v.map(B06Engine.vlcState) ?? "-")|gesendeteBytes=\(bytes)|frist=\(Int(loadLimit))s")
        }
        _ = now
        // Hänger: Ladekreis bis zur Frist, dann „antwortet nicht“ – nie „läuft“
        XCTAssertNil(first["haenger-ts"]?["playing"], "Hänger gilt nicht mehr als „läuft“")
        XCTAssertEqual(failureText(items[0].1), VLCPlaybackEngine.Failure.noResponse.message)
        XCTAssertEqual(first["haenger-ts"]?["failed"] ?? 0, loadLimit, accuracy: 1.5, "Meldung nach der Ladefrist")
        // HTML statt Video: kein Bild, Meldung sofort
        XCTAssertNil(first["html-ts"]?["playing"])
        XCTAssertEqual(failureText(items[1].1), VLCPlaybackEngine.Failure.unplayable.message)
        XCTAssertLessThan(first["html-ts"]?["failed"] ?? 99, 3.0)
        if langsam {
            // Verzögerter Start (30 s) liegt innerhalb der Ladefrist (40 s): spielt danach
            XCTAssertEqual(items[2].1.state, .playing, "verzögerter Stream spielt nach 30 s")
            XCTAssertEqual(first["verzoegert30-ts"]?["playing"] ?? 0, 30, accuracy: 5)
        } else {
            XCTAssertEqual(failureText(items[2].1), VLCPlaybackEngine.Failure.noResponse.message, "mit 5 s Frist: antwortet nicht")
        }
        let offen = mock.connections.filter { $0.path.contains("ak11") && $0.closed == nil && !$0.path.contains("verzoegert") }
        XCTAssertEqual(offen.filter { $0.path.contains("hang") || $0.path.contains("html") }.map(\.path), [], "nach der Meldung keine offene Verbindung")
    }

    // MARK: AK-12 ⚠ · VLC: Abbruch mitten im Stream / EC-04 Dateiende

    func testAK12_EC04_VLCAbbruchUndDateiende() async throws {
        let items = start([("abbruch-5s", "/abort/5/tslive/ak12.ts"), ("datei-8s", "/static/short.ts")])
        let first = await observe(items, seconds: 22)
        for (label, e) in items {
            let v = B06Engine.vlcPlayer(e)
            B06QA.log("AK-12|\(label)|zustand=\(B06Engine.name(e.state))|zeiten=\(first[label] ?? [:])|vlcRoh=\(v.map(B06Engine.vlcState) ?? "-")|verbindungen=\(mock.connections.filter { $0.path.contains(label.hasPrefix("abbruch") ? "ak12" : "short") }.map { "\($0.id):\($0.closeReason ?? "offen")" })")
        }
        let abort = items[0].1
        // Behoben (BUG-01): Abbruch mitten im Stream → „Verbindung unterbrochen“, kurz nach dem Ende der Daten
        XCTAssertEqual(failureText(abort), VLCPlaybackEngine.Failure.interrupted.message)
        XCTAssertNotNil(first["abbruch-5s"]?["playing"], "lief vorher")
        XCTAssertEqual(first["abbruch-5s"]?["failed"] ?? 0, 6, accuracy: 3, "Meldung kurz nach dem Abbruch (5 s)")
        // EC-04 (VLC-Dateiende): bleibt „läuft“ (Standbild) wie das MP4-Ende bei AVKit
        XCTAssertEqual(items[1].1.state, .playing, "EC-04: Ende einer TS-Datei über HTTP bleibt .playing")
        XCTAssertNil(first["datei-8s"]?["idle"])
        XCTAssertNil(first["datei-8s"]?["failed"])
    }

    // MARK: EC-04 · MP4 bis zum Ende (AVKit)

    func testEC04_MP4BisZumEndeBleibtLaeuft() async throws {
        let items = start([("mp4-ende", "/clip.mp4")])
        _ = await observe(items, seconds: 14)
        let e = items[0].1
        let p = B06Engine.avPlayer(e)
        B06QA.log("EC-04|zustand=\(B06Engine.name(e.state))|isPaused=\(e.isPaused)|rate=\(p?.rate ?? -1)|zeit=\(p.map { CMTimeGetSeconds($0.currentTime()) } ?? -1)")
        XCTAssertEqual(e.state, .playing)
        XCTAssertFalse(e.isPaused, "Knopf zeigt weiter ❚❚")
        XCTAssertEqual(p?.rate, 0)
    }

    // MARK: AK-35 / Angriff 7 · file:// und lokale Dateien gehen ungeprüft an libVLC

    /// Eine Playlist kann `file://`-Adressen enthalten: libVLC 3.0.21 öffnet sie im Prozess der App, ohne Prüfung von
    /// Schema, Host oder Inhalt. Beide Dateien sind selbst erzeugt und harmlos (stummes Testvideo bzw. Textdatei) –
    /// **kein präpariertes Material, kein Exploit**.
    func testAK35_Angriff7_FileSchemaUndLokaleDatei() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("b06-qa-file-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appendingPathComponent("lokal.ts")
        try mock.media.shortTS.write(to: video)
        let text = dir.appendingPathComponent("text.ts")
        try Data("Das ist kein Transportstrom, sondern Text.\n".utf8).write(to: text)

        let items = start([("file-video", video.absoluteString), ("file-text", text.absoluteString)])
        for (label, e) in items {
            B06QA.log("AK-35|\(label)|engine=\(type(of: e))")
            XCTAssertTrue(String(describing: type(of: e)).contains("VLC"), "\(label): file:// mit .ts geht an VLC")
        }
        let first = await observe(items, seconds: 12)
        for (label, e) in items {
            let v = B06Engine.vlcPlayer(e)
            B06QA.log("AK-35|\(label)|zustand=\(B06Engine.name(e.state))|zeiten=\(first[label] ?? [:])|vlcRoh=\(v.map(B06Engine.vlcState) ?? "-")|spielt=\(v.map(B06Engine.vlcIsPlaying) ?? false)")
        }
        XCTAssertEqual(items[0].1.state, .playing, "libVLC spielt die lokale Datei aus der Playlist")
        // Behoben (BUG-01): eine unbrauchbare Datei endet in einer Meldung; Schema/Ziel bleiben offen (BUG-03)
        XCTAssertNotNil(failureText(items[1].1), "unbrauchbare Datei erzeugt eine Meldung")
        B06QA.log("AK-35|Prüfungen im Code: nur pathExtension (PlaybackEngine.swift:13-19); kein Schema-, Host- oder Größenfilter; libVLC-Version laut User-Agent VLC/3.0.21 LibVLC/3.0.21")
    }
}
