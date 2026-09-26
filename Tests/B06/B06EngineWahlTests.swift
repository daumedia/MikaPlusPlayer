import XCTest
import SwiftData
@testable import MikaPlusPlayer

/// B06 · AK-02, AK-03, AK-04 (Resolver-Teil), EC-14, EC-15, AK-35 (Schema/Ziel) — Engine-Wahl und abspielbare Adresse.
/// Ohne Wiedergabe: es wird nur die Engine erzeugt, nichts geladen.
@MainActor
final class B06EngineWahlTests: XCTestCase {

    private func engineName(_ e: any PlaybackEngine) -> String { String(describing: type(of: e)) }

    // MARK: AK-02 · 25 Adressen

    func testAK02_EC15_EngineNurNachLetzterEndung() {
        let b = "http://127.0.0.1:9"
        let cases: [(String, String)] = [
            ("\(b)/a.ts", "VLC"), ("\(b)/a.TS", "VLC"), ("\(b)/a.mpegts", "VLC"), ("\(b)/a.mts", "VLC"), ("\(b)/a.m2ts", "VLC"),
            ("\(b)/a.ts?token=abc", "VLC"), ("\(b)/a.ts#frag", "VLC"), ("\(b)/a.m3u8.ts", "VLC"), ("file:///tmp/a.ts", "VLC"),
            ("\(b)/a.m3u8", "AVKit"), ("\(b)/a.M3U8", "AVKit"), ("\(b)/a.m3u", "AVKit"), ("\(b)/a.ts.m3u8", "AVKit"),
            ("\(b)/a.m3u8?token=abc", "AVKit"),
            ("\(b)/a.mp4", "AVKit"), ("\(b)/a.mkv", "AVKit"), ("\(b)/live/u/p/101", "AVKit"), ("\(b)/play.php?file=a.ts", "AVKit"),
            ("\(b)/a.ts%20", "AVKit"), ("rtmp://127.0.0.1/live/a", "AVKit"), ("rtsp://127.0.0.1/a", "AVKit"),
            ("udp://@239.0.0.1:1234", "AVKit"), ("\(b)/get?type=m3u8", "AVKit"), ("\(b)/a.", "AVKit"), ("\(b)/stream.ts/", "VLC"),
        ]
        XCTAssertEqual(cases.count, 25)
        var abweichend: [String] = []
        for (address, expected) in cases {
            guard let url = URL(string: address) else { XCTFail("URL(string:) nil: \(address)"); continue }
            let e = PlaybackEngineFactory.engine(for: url)
            let got = engineName(e).contains("VLC") ? "VLC" : "AVKit"
            B06QA.log("AK-02|\(address)|pathExtension=\(url.pathExtension)|StreamType=\(StreamType(url: url))|engine=\(engineName(e))|PiP=\(e.supportsPictureInPicture)")
            if got != expected { abweichend.append("\(address): \(got) statt \(expected)") }
        }
        XCTAssertEqual(abweichend, [])
    }

    // MARK: AK-03 · Xtream mit Schlüsselbund, M3U unverändert, Altbestand

    func testAK03_EC14_AbspielbareAdresseUndEngine() throws {
        let container = try B06QA.inMemoryContainer()
        let ctx = container.mainContext
        let store = XtreamCredentialStore(service: "lu.daumedia.MikaPlusPlayer.xtream.tests.b06.\(UUID().uuidString)")
        defer { try? store.deleteAll() }
        let host = "http://127.0.0.1:18916"

        func add(_ p: Playlist, _ name: String, _ stored: String) -> Channel {
            let c = Channel(name: name, streamURL: URL(string: stored)!, playlist: p, playlistID: p.id)
            ctx.insert(c)
            return c
        }
        let x = Playlist(name: "X", sourceURL: URL(string: "\(host)/player_api.php"), isXtream: true, xtreamOutput: "mpegts")
        ctx.insert(x)
        try store.save(XtreamSecret(host: host, username: B06QA.user, password: B06QA.pass), for: x.id)
        let ts = add(x, "TS", "\(host)/live/101.ts")
        let hls = add(x, "HLS", "\(host)/live/102.m3u8")

        let sp = Playlist(name: "S", sourceURL: URL(string: "\(host)/player_api.php"), isXtream: true, xtreamOutput: "hls")
        ctx.insert(sp)
        try store.save(XtreamSecret(host: host, username: "qa user", password: "a/b#c?d.m3u8"), for: sp.id)
        let special = add(sp, "Sonderzeichen", "\(host)/live/106.ts")

        let legacy = Playlist(name: "L", sourceURL: URL(string: "\(host)/player_api.php?username=qa-user&password=qa-pass-b06"), isXtream: true)
        ctx.insert(legacy)
        let leg = add(legacy, "Altbestand", "\(host)/live/qa-user/qa-pass-b06/105.ts")

        let m3u = Playlist(name: "M", sourceURL: URL(string: "\(host)/list.m3u"))
        ctx.insert(m3u)
        let m = add(m3u, "M3U", "http://u:pw@127.0.0.1:18916/a.ts?token=geheim")

        let expected: [(Channel, String, String)] = [
            (ts, "\(host)/live/qa-user/qa-pass-b06/101.ts", "VLC"),
            (hls, "\(host)/live/qa-user/qa-pass-b06/102.m3u8", "AVKit"),
            (special, "\(host)/live/qa%20user/a%2Fb%23c%3Fd.m3u8/106.ts", "VLC"),
            (leg, "\(host)/live/qa-user/qa-pass-b06/105.ts", "VLC"),
            (m, "http://u:pw@127.0.0.1:18916/a.ts?token=geheim", "VLC"),
        ]
        for (c, address, engine) in expected {
            let url = try StreamURLResolver.playableURL(for: c, store: store)
            let e = PlaybackEngineFactory.engine(for: url)
            B06QA.log("AK-03|\(c.name)|gespeichert=\(c.streamURL.absoluteString)|abspielbar=\(url.absoluteString)|engine=\(engineName(e))")
            XCTAssertEqual(url.absoluteString, address, c.name)
            XCTAssertEqual(engineName(e).contains("VLC") ? "VLC" : "AVKit", engine, c.name)
        }
    }

    // MARK: AK-04 · fehlende Zugangsdaten, ungültige Adresse (Resolver)

    func testAK04_ResolverMeldungenOhneZugangsdaten() throws {
        let container = try B06QA.inMemoryContainer()
        let ctx = container.mainContext
        let store = XtreamCredentialStore(service: "lu.daumedia.MikaPlusPlayer.xtream.tests.b06.\(UUID().uuidString)")
        defer { try? store.deleteAll() }
        let host = "http://127.0.0.1:18916"
        let missing = Playlist(name: "Y", sourceURL: URL(string: "\(host)/player_api.php"), isXtream: true, xtreamOutput: "mpegts")
        ctx.insert(missing)
        let miss = Channel(name: "Fehlt", streamURL: URL(string: "\(host)/live/104.ts")!, playlist: missing, playlistID: missing.id)
        ctx.insert(miss)
        let x = Playlist(name: "X", sourceURL: URL(string: "\(host)/player_api.php"), isXtream: true, xtreamOutput: "mpegts")
        ctx.insert(x)
        try store.save(XtreamSecret(host: host, username: B06QA.user, password: B06QA.pass), for: x.id)
        let bad = Channel(name: "Ungültig", streamURL: URL(string: "\(host)/stream/103.ts")!, playlist: x, playlistID: x.id)
        ctx.insert(bad)

        for (c, text) in [(miss, "Die Zugangsdaten dieser Xtream-Playlist fehlen auf diesem Gerät. Bitte die Playlist löschen und neu importieren."),
                          (bad, "Die Stream-Adresse ist ungültig.")] {
            XCTAssertThrowsError(try StreamURLResolver.playableURL(for: c, store: store)) { error in
                let msg = error.localizedDescription
                B06QA.log("AK-04|\(c.name)|meldung=\(msg)")
                XCTAssertEqual(msg, text)
                XCTAssertFalse(msg.contains(B06QA.pass))
                XCTAssertFalse(msg.contains(B06QA.user))
                XCTAssertFalse(msg.contains("127.0.0.1"))
            }
        }
    }

    // MARK: Angriff 1/2 · Host aus der Datenbank lenkt Zugangsdaten nicht um; fremde Playlist bekommt keine

    /// Die gespeicherte Adresse nennt einen fremden Host (z. B. manipulierte Datenbank). Die Zugangsdaten gehen trotzdem nur
    /// an den Host aus dem Schlüsselbund. Ein Sender einer anderen Playlist (ohne Eintrag) bekommt keine fremden Zugangsdaten.
    func testAngriff_FremderHostUndFremdePlaylistID() throws {
        let container = try B06QA.inMemoryContainer()
        let ctx = container.mainContext
        let store = XtreamCredentialStore(service: "lu.daumedia.MikaPlusPlayer.xtream.tests.b06.\(UUID().uuidString)")
        defer { try? store.deleteAll() }
        let a = Playlist(name: "A", sourceURL: URL(string: "http://127.0.0.1:18916/player_api.php"), isXtream: true)
        ctx.insert(a)
        try store.save(XtreamSecret(host: "http://127.0.0.1:18916", username: B06QA.user, password: B06QA.pass), for: a.id)
        let evil = Channel(name: "Umgelenkt", streamURL: URL(string: "http://evil.example/live/../../x/live/101.ts")!, playlist: a, playlistID: a.id)
        ctx.insert(evil)
        let b = Playlist(name: "B", sourceURL: URL(string: "http://evil.example/player_api.php"), isXtream: true)
        ctx.insert(b)
        // Sender aus B, der die ID von A als denormalisierte playlistID trägt
        let foreign = Channel(name: "Fremd", streamURL: URL(string: "http://evil.example/live/102.ts")!, playlist: b, playlistID: a.id)
        ctx.insert(foreign)

        let url = try StreamURLResolver.playableURL(for: evil, store: store)
        B06QA.log("ANGRIFF-1|gespeichert=\(evil.streamURL.absoluteString)|abspielbar=\(url.absoluteString)|host=\(url.host ?? "-")")
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertThrowsError(try StreamURLResolver.playableURL(for: foreign, store: store)) { error in
            B06QA.log("ANGRIFF-1|fremde playlistID|meldung=\(error.localizedDescription)")
            XCTAssertEqual(error as? StreamURLResolver.ResolveError, .missingCredentials)
        }
    }

    // MARK: Angriff 7 · Eingaben in der Adresse

    func testAngriff7_EingabenInStreamAdresse() {
        let long = "http://127.0.0.1:9/" + String(repeating: "a", count: 10_000) + ".ts"
        let cases = [
            long,
            "http://127.0.0.1:9/%F0%9F%93%BA.ts",
            "http://127.0.0.1:9/';%20drop%20table%20--.m3u8",
            "http://127.0.0.1:9/%3Cscript%3Ealert(1)%3C/script%3E.ts",
            "file:///../../etc/passwd.ts",
            "file:///etc/hosts",
            "javascript:alert(1)",
            "data:video/mp2t;base64,AAAA",
        ]
        for c in cases {
            guard let url = URL(string: c) else { B06QA.log("ANGRIFF-7|URL(string:)=nil|\(c.prefix(60))"); continue }
            let e = PlaybackEngineFactory.engine(for: url)
            B06QA.log("ANGRIFF-7|\(c.count > 80 ? String(c.prefix(40)) + "…(\(c.count) Zeichen)" : c)|scheme=\(url.scheme ?? "-")|engine=\(engineName(e))")
        }
        XCTAssertTrue(engineName(PlaybackEngineFactory.engine(for: URL(string: long)!)).contains("VLC"))
        XCTAssertTrue(engineName(PlaybackEngineFactory.engine(for: URL(string: "file:///../../etc/passwd.ts")!)).contains("VLC"),
                      "Ist: Schema wird nicht eingegrenzt (FB-03)")
    }
}
