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
            if text != expected[label] { abweichend.append("\(label): \(text ?? B06Engine.name(e.state))") }
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

    // MARK: AK-10 ⚠ · VLC: HTTP-Fehler und Host weg

    func testAK10_VLCHTTPFehlerUndHostWegOhneMeldung() async throws {
        let seconds: TimeInterval = langsam ? 60 : 15
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
            // Ist: nie .failed – die Ansicht zeigt für .idle/.loading den Ladekreis
            XCTAssertNil(failureText(e), label)
            XCTAssertTrue([.idle, .loading].contains(e.state), "\(label): Ladekreis-Zustand")
        }
        B06QA.log("AK-10|zusammenfassung|\(summary)")
        XCTExpectFailure("BUG-01 · VLC-Fehler (401/403/404/Host weg) erreichen die Oberfläche nie – FB-01") {
            for (label, e) in items { XCTAssertNotNil(failureText(e), "\(label) sollte .failed melden") }
        }
    }

    // MARK: AK-11 ⚠ · VLC: keine Daten, HTML, verzögert

    func testAK11_VLCHaengerHTMLVerzoegertGiltAlsLaeuft() async throws {
        let seconds: TimeInterval = langsam ? 200 : 15
        let items = start([
            ("haenger-ts", "/hang/ak11.ts"), ("html-ts", "/html/ak11.ts"), ("verzoegert30-ts", "/delay/30/tslive/ak11.ts"),
        ])
        let first = await observe(items, seconds: seconds)
        let now = Date()
        for (label, e) in items {
            let v = B06Engine.vlcPlayer(e)
            let bytes = mock.connections.filter { $0.path.contains("ak11") && $0.path.contains(label.prefix(4)) }.map(\.bytesSent)
            B06QA.log("AK-11|\(label)|nach \(Int(seconds))s|zustand=\(B06Engine.name(e.state))|zeiten=\(first[label] ?? [:])|vlcRoh=\(v.map(B06Engine.vlcState) ?? "-")|gesendeteBytes=\(bytes)")
            XCTAssertNil(failureText(e), label)
        }
        _ = now
        XCTAssertEqual(items[0].1.state, .playing, "Hänger gilt als „läuft“")
        XCTAssertLessThan(first["haenger-ts"]?["playing"] ?? 99, 1.0)
        XCTExpectFailure("BUG-01 · VLC ohne Daten/HTML/verzögert gilt als „läuft“ bzw. lädt endlos, ohne Meldung – FB-01") {
            for (label, e) in items where label != "verzoegert30-ts" || langsam {
                XCTAssertNotNil(failureText(e), "\(label) sollte .failed melden oder eine Zeitgrenze haben")
            }
        }
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
        XCTAssertEqual(abort.state, .playing, "Ist: Standbild gilt weiter als „läuft“")
        XCTAssertNil(first["abbruch-5s"]?["failed"])
        // EC-04 (VLC-Dateiende): Spec „gelesen: ended → idle → Ladekreis“; ausgeführt: bleibt „läuft“ (Standbild)
        XCTAssertEqual(items[1].1.state, .playing, "EC-04 Ist: Ende einer TS-Datei über HTTP bleibt .playing")
        XCTAssertNil(first["datei-8s"]?["idle"])
        XCTExpectFailure("BUG-01 · Abbruch eines laufenden TS-Streams bleibt „läuft“ (Standbild, keine Meldung) – FB-01") {
            XCTAssertNotEqual(abort.state, .playing)
        }
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
        XCTAssertNil(failureText(items[1].1), "Ist: unbrauchbare Datei erzeugt keine Meldung (FB-01)")
        B06QA.log("AK-35|Prüfungen im Code: nur pathExtension (PlaybackEngine.swift:13-19); kein Schema-, Host- oder Größenfilter; libVLC-Version laut User-Agent VLC/3.0.21 LibVLC/3.0.21")
    }
}
