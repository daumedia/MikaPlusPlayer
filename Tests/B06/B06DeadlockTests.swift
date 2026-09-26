import XCTest
import AppKit
@testable import MikaPlusPlayer

/// B06 · Reproduktion des libVLC-Deadlocks beim Sender-Wechsel (BUG-07 der QA vom 2026-09-26).
///
/// **Reproduktion im Gesamtlauf (2026-09-26, zweimal in zwei Läufen):** `testAK09` erzeugt sechs VLC-Engines und
/// spielt 10 s, `tearDown` stoppt und gibt sie frei, `testAK10` erzeugt sofort sechs neue – dabei hängt der Prozess.
/// Dieser Test versucht dasselbe in Runden; mit 12 × 4 und 8 × 6 Engines (auch mit `stop` und Fenstern) trat der
/// Hänger **nicht** auf. Beobachtet am 2026-09-26 im Gesamtlauf: Beim Erzeugen eines neuen `VLCMediaPlayer` hängt der **Hauptthread**
/// unbegrenzt in `config_GetFloat` → `pthread_rwlock`, während verworfene Player in
/// `-[VLCMediaPlayer dealloc]` → `libvlc_media_player_destroy` → `pthread_join` festsitzen
/// (Sample: `features/B06-wiedergabe/qa/BUG-07-libvlc-deadlock-sample.txt`).
///
/// Der Test hängt im Fehlerfall selbst; deshalb läuft er **nur** mit `B06_DEADLOCK=1`
/// (`xcodebuild … TEST_RUNNER_B06_DEADLOCK=1`) und hat einen Wachhund, der ein Sample schreibt und den
/// Prozess beendet. Kein Ton: Engines vor dem Laden stumm, Medien ohne Tonspur.
@MainActor
final class B06DeadlockTests: B06TestCase {

    private static let fortschritt = Fortschritt()

    final class Fortschritt: @unchecked Sendable {
        private let lock = NSLock()
        private var wert = 0
        private var marke = ""
        func tick(_ m: String) { lock.lock(); wert += 1; marke = m; lock.unlock() }
        var stand: (Int, String) { lock.lock(); defer { lock.unlock() }; return (wert, marke) }
    }

    /// Wachhund: schreibt bei Stillstand ein Sample in den QA-Ordner und beendet den Prozess.
    private func wachhund(sekunden: Double = 60) {
        let ziel = B06QA.qaFolder.appendingPathComponent("BUG-07-deadlock-sample-lauf.txt").path
        Thread.detachNewThread {
            var letzter = Self.fortschritt.stand.0
            var still = 0.0
            while true {
                Thread.sleep(forTimeInterval: 5)
                let (wert, marke) = Self.fortschritt.stand
                if wert != letzter {
                    letzter = wert
                    still = 0
                    continue
                }
                still += 5
                if still >= sekunden {
                    print("B06QA|WACHHUND|kein Fortschritt seit \(Int(still)) s bei '\(marke)' – Sample nach \(ziel)")
                    fflush(stdout)
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
                    p.arguments = ["\(getpid())", "2", "-file", ziel]
                    try? p.run()
                    p.waitUntilExit()
                    print("B06QA|WACHHUND|Sample geschrieben, Prozess wird beendet (Exit 70)")
                    fflush(stdout)
                    exit(70)
                }
            }
        }
    }

    func testBUG07_SenderWechselDeadlockInLibVLC() async throws {
        guard ProcessInfo.processInfo.environment["B06_DEADLOCK"] == "1" else {
            throw XCTSkip("nur mit B06_DEADLOCK=1 – der Test kann im Fehlerfall den Prozess aufhängen")
        }
        wachhund()
        let runden = Int(ProcessInfo.processInfo.environment["B06_DEADLOCK_RUNDEN"] ?? "12") ?? 12
        let gleichzeitig = Int(ProcessInfo.processInfo.environment["B06_DEADLOCK_PARALLEL"] ?? "4") ?? 4
        let mitStop = ProcessInfo.processInfo.environment["B06_DEADLOCK_STOP"] == "1"
        let mitFenstern = ProcessInfo.processInfo.environment["B06_DEADLOCK_FENSTER"] == "1"
        B06QA.log("BUG-07|Start: \(runden) Runden mit je \(gleichzeitig) VLC-Engines (erzeugen, laden, verwerfen)|stop=\(mitStop)|fenster=\(mitFenstern)")
        for runde in 1...runden {
            Self.fortschritt.tick("Runde \(runde) erzeugen")
            var gruppe: [any PlaybackEngine] = []
            var fenster: [NSWindow] = []
            for i in 0..<gleichzeitig {
                let url = mock.url("/tslive/dl\(runde)-\(i).ts")
                let e = PlaybackEngineFactory.engine(for: url)      // hier hängt der Hauptthread im Fehlerfall
                e.setMuted(true)
                if mitFenstern {
                    let w = B06UI.window(e.makePlayerView(), size: CGSize(width: 160, height: 90),
                                         origin: CGPoint(x: 40 + CGFloat(i) * 170, y: 60), title: "B06-DL \(i)")
                    fenster.append(w)
                }
                e.load(url)
                gruppe.append(e)
            }
            Self.fortschritt.tick("Runde \(runde) geladen")
            await B06QA.spin(1.5)
            let zustaende = gruppe.map { B06Engine.name($0.state) }
            for e in gruppe { e.pause() }                           // wie `onDisappear`
            if mitStop {                                            // wie das Aufräumen der QA (stop auf allen Playern)
                for e in gruppe { if let v = B06Engine.vlcPlayer(e) { _ = v.perform(NSSelectorFromString("stop")) } }
            }
            for w in fenster { B06UI.close(w) }
            fenster.removeAll()
            gruppe.removeAll()                                      // Referenzen fallen lassen → dealloc
            Self.fortschritt.tick("Runde \(runde) verworfen")
            await B06QA.spin(0.5)
            B06QA.log("BUG-07|Runde \(runde) ok|zustände=\(zustaende)|offeneVerbindungen=\(mock.connections.filter { $0.closed == nil }.count)")
        }
        B06QA.log("BUG-07|alle \(runden) Runden ohne Hänger durchgelaufen (kein Deadlock in diesem Lauf)")
    }
}
