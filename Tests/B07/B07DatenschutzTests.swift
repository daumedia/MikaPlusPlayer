import XCTest
import SwiftUI
import SwiftData
import AVFoundation
import AVKit
import AppKit
import MediaPlayer
import OSLog
@testable import MikaPlusPlayer

/// B07 · Multiview (AK-12, EC-11), Ablehnung (AK-18) und Datenschutz (AK-19, AK-20, AK-22, AK-23, AK-24) – macOS.
@MainActor
final class B07DatenschutzTests: B07TestCase {

    private func waitPlaying(_ probe: @escaping () -> AVKitPlaybackEngine?) async -> AVKitPlaybackEngine? {
        guard await B07Engine.wait(25, { probe()?.state == .playing }) != nil, let e = probe() else { return nil }
        _ = await B07Engine.wait(15) { B07Engine.pipController(e)?.isPictureInPicturePossible == true }
        return e
    }

    private func startPiP(_ w: NSWindow, _ e: AVKitPlaybackEngine) async -> Bool {
        await showControls(w)
        if let b = pipButton(w) { B07UI.click(b, in: w) }
        if await B07Engine.wait(4, { e.isPictureInPictureActive }) == nil, let b = pipButton(w) { B07UI.press(b) }
        return await B07Engine.wait(10) { e.isPictureInPictureActive && !B07PiPWindows.current().isEmpty } != nil
    }

    // MARK: AK-12 / EC-11 · Multiview

    func testAK12_EC11_Multiview_KeinKnopfKeineTasteKeinAutoStart_ControllerJeKachel() async throws {
        let session = MultiviewSession()
        let c1 = channel("QA MV 1", "/livehls/mv1/index.m3u8")
        let c2 = channel("QA MV 2", "/livehls/mv2/index.m3u8")
        let c3 = channel("QA MV TS", "/tslive/mv3.ts")
        session.add(c1); session.add(c2); session.add(c3)
        for s in session.slots { s.engine.setMuted(true) }
        let w = B07UI.window(MultiviewScreen().environment(session).modelContainer(container),
                             size: CGSize(width: 900, height: 520), title: "B07-Multiview")
        windows.append(w)
        try await activate(w)
        let ok = await B07Engine.wait(25) { session.slots.prefix(2).allSatisfy { $0.engine.state == .playing } }
        await B07QA.spin(2)
        let buttons = B07UI.elements(w).filter { B07UI.role($0) == "AXButton" }.map(B07UI.label)
        let avkit = session.slots.filter { $0.engine is AVKitPlaybackEngine }.count
        let ctrls = B07Registry.liveControllers
        #if os(iOS)
        let auto = ctrls.map { $0.canStartPictureInPictureAutomaticallyFromInline }
        #else
        let auto: [Bool] = []
        #endif
        B07QA.log("AK-12|spielt=\(ok != nil)|knöpfe=\(buttons)|AVKit-Kacheln=\(avkit)|PiP-Controller=\(ctrls.count) aktiv=\(ctrls.map(\.isPictureInPictureActive)) auto(iOS)=\(auto)")
        B07QA.shot(w, "AK-12-multiview-ohne-pip-knopf")
        XCTAssertNotNil(ok)
        XCTAssertFalse(buttons.contains { $0.lowercased().contains("pip") || $0.contains("Minimise Video") }, "kein Bild-in-Bild-Knopf")
        XCTAssertEqual(ctrls.count, avkit, "EC-11: je AVKit-Kachel ein (ungenutzter) Controller")
        XCTAssertTrue(ctrls.allSatisfy { !$0.isPictureInPictureActive })
        // Taste P: im Multiview nicht belegt → läuft ins Leere (Beep-Wächter fängt den Systembeep ab)
        let hits = await press(w, .char("p"))
        await B07QA.spin(2)
        B07QA.log("AK-12|P im Multiview → unbehandelt=\(hits)|pipfenster=\(B07PiPWindows.current().count)")
        XCTAssertTrue(B07PiPWindows.current().isEmpty, "P startet kein Bild-in-Bild")
        XCTAssertFalse(hits.isEmpty, "P ist im Multiview nicht belegt (ohne Beep-Wächter: Systembeep)")
        // aufräumen: erst Fenster weg (onDisappear leert die Session), nicht umgekehrt
        B07UI.close(w); windows.removeAll()
        await B07QA.spin(1)
        session.clear()
    }

    // MARK: AK-18 · Ablehnung durch das System

    func testAK18_StartAbgelehnt_KeineMeldungKnopfBleibtOeffnen() async throws {
        let c = channel("QA Ablehnung", "/livehls/ak18/index.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        guard let e = await waitPlaying({ self.lastEngine }) else { return XCTFail("spielt nicht") }
        await showControls(w)
        let before = pipButton(w).map(B07UI.label) ?? "-"
        // a) Ablehnung, wie das System sie meldet: Delegate-Aufruf failedToStart… am echten Controller
        guard let ctrl = B07Engine.pipController(e), let del = B07Registry.liveDelegates.last else { return XCTFail("kein Controller") }
        let err = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.operationNotAllowed.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "QA: Start abgelehnt"])
        let sel = NSSelectorFromString("pictureInPictureController:failedToStartPictureInPictureWithError:")
        XCTAssertTrue(del.responds(to: sel))
        _ = del.perform(sel, with: ctrl, with: err)
        await B07QA.spin(1.5)
        await showControls(w)
        let after = pipButton(w).map(B07UI.label) ?? "-"
        let texts = B07UI.elements(w).map(B07UI.label).filter { !$0.isEmpty }
        let sheets = NSApp.windows.filter { $0.isVisible && ($0.isSheet || $0 is NSPanel) }.map { $0.title }
        B07QA.log("AK-18a|failedToStart gemeldet|aktiv=\(e.isPictureInPictureActive)|knopf vorher='\(before)' nachher='\(after)'|texte=\(texts)|sheets/panels=\(sheets)")
        XCTAssertFalse(e.isPictureInPictureActive)
        XCTAssertEqual(after, before, "Knopf zeigt weiter „Bild-in-Bild öffnen“")
        XCTAssertFalse(texts.contains { $0.contains("QA: Start abgelehnt") || $0.localizedCaseInsensitiveContains("fehl") }, "keine Meldung")
        // b) Start nicht möglich, weil das Fenster verkleinert ist (Layer nicht sichtbar)
        w.miniaturize(nil)
        _ = await B07Engine.wait(5) { !(ctrl.isPictureInPicturePossible) }
        let possible = ctrl.isPictureInPicturePossible
        e.togglePictureInPicture()   // dieselbe Aktion wie Knopf und P
        await B07QA.spin(3)
        B07QA.log("AK-18b|Fenster im Dock: possible=\(possible)|nach Umschalten aktiv=\(e.isPictureInPictureActive)|pipfenster=\(B07PiPWindows.current().count)|panels=\(NSApp.windows.filter { $0.isVisible && $0 is NSPanel }.count)")
        w.deminiaturize(nil)
        await B07QA.spin(1)
    }

    // MARK: AK-19 / AK-20 / AK-22 · Sichtbarkeit

    func testAK19_AK20_AK22_NurBild_UeberAllenFenstern_KeineJetztLaeuftAngaben() async throws {
        let c = channel("QA Geheimsender", "/live/\(B07QA.user)/\(B07QA.pass)/201.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        guard let e = await waitPlaying({ self.lastEngine }) else { return XCTFail("spielt nicht") }
        guard await startPiP(w, e) else { return XCTFail("PiP startet nicht") }
        await B07QA.spin(2)
        let pip = B07PiPWindows.current()
        let own = B07PiPWindows.all().filter { $0.ownerPID == Int(getpid()) && $0.bounds.width > 100 }
        let item = B07Engine.avPlayer(e)?.currentItem
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        let state = MPNowPlayingInfoCenter.default().playbackState
        let texts = B07UI.elements(w).map(B07UI.label).filter { !$0.isEmpty }
        B07QA.log("AK-19|pipfenster=\(pip)|eigene=\(own)")
        B07QA.log("AK-19|AVPlayerItem.externalMetadata=n/a(macOS) asset.metadata=\(item?.asset.commonMetadata.count ?? -1)|nowPlayingInfo=\(String(describing: info))|playbackState=\(state.rawValue)|app-texte=\(texts)")
        XCTAssertEqual(pip.count, 1)
        if let p = pip.first {
            XCTAssertGreaterThan(p.layer, 0, "AK-20: liegt über normalen Fenstern (Ebene \(p.layer) > 0)")
            XCTAssertFalse(p.name.contains("Geheimsender") || p.name.contains(B07QA.pass) || p.name.contains("127.0.0.1"))
            let captured = await B07QA.requestWindowShot(p.id, "AK-19-20-pip-fenster-ohne-metadaten")
            B07QA.log("AK-20|Aufnahme des Systemfensters per screencapture: \(captured)")
        }
        XCTAssertNil(info, "AK-22: App setzt keine „Jetzt läuft“-Angaben")
        XCTAssertFalse(texts.contains { $0.contains(B07QA.pass) || $0.contains("127.0.0.1") || $0.contains("/live/") }, "Platzhalter ohne Adresse")
        B07QA.shot(w, "AK-19-platzhalter-app")
    }

    // MARK: AK-23 · Systemprotokoll

    func testAK23_KeinProtokollVonSenderAdresseZugangsdaten() async throws {
        let t0 = Date()
        B07QA.log("AK-23|pid=\(getpid())|start=\(ISO8601DateFormatter().string(from: t0))")
        let c = channel("QA Protokollsender", "/live/\(B07QA.user)/\(B07QA.pass)/301.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        guard let e = await waitPlaying({ self.lastEngine }) else { return XCTFail("spielt nicht") }
        guard await startPiP(w, e) else { return XCTFail("PiP startet nicht") }
        await B07QA.spin(2)
        e.stopPictureInPicture()
        _ = await B07Engine.wait(8) { !e.isPictureInPictureActive }
        // Fehlschlag melden lassen (wie AK-18)
        if let ctrl = B07Engine.pipController(e), let del = B07Registry.liveDelegates.last {
            _ = del.perform(NSSelectorFromString("pictureInPictureController:failedToStartPictureInPictureWithError:"),
                            with: ctrl, with: NSError(domain: "QA", code: 1))
        }
        await B07QA.spin(1)
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(at: store.position(date: t0)).compactMap { $0 as? OSLogEntryLog }
        let needles = [B07QA.pass, B07QA.user, "QA Protokollsender", "/live/", "301.m3u8"]
        var hits: [String] = []
        for en in entries {
            let m = en.composedMessage
            if needles.contains(where: { m.contains($0) }) { hits.append("\(en.subsystem)|\(en.category)|\(m.prefix(200))") }
        }
        let pipLines = entries.filter { $0.composedMessage.localizedCaseInsensitiveContains("pictureinpicture") || $0.subsystem.contains("avkit") || $0.category.localizedCaseInsensitiveContains("pip") }
        B07QA.log("AK-23|OSLogStore Einträge seit Start=\(entries.count)|Treffer=\(hits.count)|PiP-/AVKit-Zeilen=\(pipLines.count)")
        for h in hits.prefix(20) { B07QA.log("AK-23|TREFFER|\(h)") }
        for l in pipLines.prefix(15) { B07QA.log("AK-23|pip-zeile|\(l.subsystem)|\(l.category)|\(l.composedMessage.prefix(160))") }
        B07QA.log("AK-23|ende=\(ISO8601DateFormatter().string(from: Date()))")
        let appHits = hits.filter { $0.hasPrefix("lu.daumedia") }
        let pipHits = hits.filter { $0.hasPrefix("com.apple.avkit") || $0.localizedCaseInsensitiveContains("pictureinpicture") }
        let networkHits = hits.filter { $0.hasPrefix("com.apple.network") || $0.hasPrefix("com.apple.CFNetwork") }
        B07QA.log("AK-23|app=\(appHits.count) pip/avkit=\(pipHits.count) netzwerk=\(networkHits.count) sonstige=\(hits.count - appHits.count - pipHits.count - networkHits.count)")
        XCTAssertEqual(appHits, [], "App-eigene Protokollzeilen ohne Sender, Adresse, Zugangsdaten")
        XCTAssertEqual(pipHits, [], "Bild-in-Bild-Zeilen (AVKit) ohne Sender, Adresse, Zugangsdaten")
        XCTAssertEqual(hits.count, appHits.count + pipHits.count + networkHits.count, "keine weiteren Quellen")
        // Hinweis (kein B07-Kriterium): libnetwork schreibt beim Verbindungsaufbau jeder Wiedergabe die volle Stream-Adresse
        // samt Zugangsdaten – am Test-Host ungeschwärzt (vgl. BF-43).
    }

    // MARK: AK-24 · Nichts gespeichert

    func testAK24_NachPiPNichtsGespeichert_NeueEngineInaktiv() async throws {
        let fm = FileManager.default
        let bid = Bundle.main.bundleIdentifier ?? "?"
        let lib = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let dirs = [lib.appendingPathComponent("Application Support/\(bid)"), lib.appendingPathComponent("Caches/\(bid)"),
                    lib.appendingPathComponent("Preferences"), lib.appendingPathComponent("Saved Application State/\(bid).savedState")]
        func snapshot() -> [String: Date] {
            var out: [String: Date] = [:]
            for d in dirs {
                guard let en = fm.enumerator(at: d, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
                for case let u as URL in en {
                    if d.lastPathComponent == "Preferences" && !u.lastPathComponent.hasPrefix(bid) { continue }
                    out[u.path] = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                }
            }
            return out
        }
        UserDefaults.standard.synchronize()
        let defaultsBefore = UserDefaults.standard.persistentDomain(forName: bid) ?? [:]
        let filesBefore = snapshot()
        let c = channel("QA Speichern", "/livehls/ak24/index.m3u8")
        try container.mainContext.save()
        let w = playerWindow(c)
        try await activate(w)
        guard let e = await waitPlaying({ self.lastEngine }) else { return XCTFail("spielt nicht") }
        guard await startPiP(w, e) else { return XCTFail("PiP startet nicht") }
        await B07QA.spin(2)
        e.stopPictureInPicture()
        _ = await B07Engine.wait(8) { !e.isPictureInPictureActive }
        await B07QA.spin(1)
        UserDefaults.standard.synchronize()
        let defaultsAfter = UserDefaults.standard.persistentDomain(forName: bid) ?? [:]
        let filesAfter = snapshot()
        let newKeys = Set(defaultsAfter.keys).subtracting(defaultsBefore.keys)
        let changedFiles = filesAfter.filter { filesBefore[$0.key] != $0.value }.map(\.key).sorted()
        let dbChanges = container.mainContext.hasChanges
        let fetched = try container.mainContext.fetch(FetchDescriptor<Channel>())
        B07QA.log("AK-24|domain=\(bid)|neue Einstellungen=\(newKeys.sorted())|geänderte/neue Dateien=\(changedFiles)|db.hasChanges=\(dbChanges)|kanäle=\(fetched.map { "\($0.name) fav=\($0.isFavorite)" })")
        XCTAssertEqual(newKeys.filter { $0.localizedCaseInsensitiveContains("pip") || $0.localizedCaseInsensitiveContains("picture") }, [])
        XCTAssertFalse(dbChanges, "keine Änderung an der Datenbank")
        // „Neustart“: neue Ansicht, neue Engine
        B07UI.close(w); windows.removeAll()
        await B07QA.spin(1)
        let w2 = playerWindow(c)
        _ = w2
        guard let e2 = await waitPlaying({ B07Registry.engines.last(where: { $0 !== e }) }) else { return XCTFail("zweite Engine spielt nicht") }
        B07QA.log("AK-24|neue Engine: \(B07Engine.detail(e2))")
        XCTAssertFalse(e2.isPictureInPictureActive, "Bild-in-Bild ist nach Neustart aus")
    }
}
