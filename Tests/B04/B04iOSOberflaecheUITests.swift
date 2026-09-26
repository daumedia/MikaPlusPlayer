#if os(iOS)
import XCTest

/// B04 · Senderliste auf iOS (AK-01, AK-02, AK-03, AK-04, AK-10, AK-13, AK-22, EC-11) — QA Durchlauf 1, 2026-09-26.
///
/// Läuft nur in einem iOS-UI-Test-Target. Das Projekt hat keins; die QA hat es in ihrer Kopie angelegt
/// (`project.yml`: `bundle.ui-testing`, `platform: iOS`, `TEST_TARGET_NAME: MikaPlusPlayer`, nur diese Datei).
/// Im macOS-Test-Target ist die Datei wegen `#if os(iOS)` leer.
///
/// Daten: `B04ErgaenzungTests.testEC11_DatenbankFuerIOSSimulatorErzeugen` legt eine Datenbank an („QA iOS“,
/// 30 Sender, Gruppen Kino/News/Sport, keine Logo-Adressen, Streams auf den geschlossenen Port 9), die vor dem Start
/// nach `<Daten-Container>/Library/Application Support/<Bundle-ID>/MikaPlusPlayer.store` kopiert wird.
/// Nur Tippen, keine Tastatureingabe (kein Tastaturklick-Ton), keine Wiedergabe mit Ton.
final class B04iOSOberflaecheUITests: XCTestCase {

    private var qaDir: String? { ProcessInfo.processInfo.environment["B04_QA_DIR"] }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let att = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        att.name = name
        att.lifetime = .keepAlways
        add(att)
        if let dir = qaDir { try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")) }
    }

    private func log(_ s: String) {
        print("B04QA|\(s)")
        if let dir = qaDir {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("EC-11-ios.txt")
            let line = Data("\(ISO8601DateFormatter().string(from: Date())) [iOS-Simulator] \(s)\n".utf8)
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line); try? h.close() }
            else { try? line.write(to: url) }
        }
    }

    func testAK01_EC11_SenderlisteAufIOS() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launch()
        let karte = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'QA iOS'")).firstMatch
        XCTAssertTrue(karte.waitForExistence(timeout: 60), "Playlist-Karte in der Übersicht")
        shot(app, "EC-11-ios-uebersicht")
        karte.tap()

        let kopf = app.staticTexts["MIKA+PLAYER · 30 SENDER"]
        XCTAssertTrue(kopf.waitForExistence(timeout: 30), "AK-01: Kopfzeile in Akzentschrift")
        sleep(2)
        shot(app, "EC-11-ios-senderliste")
        let fenster = app.windows.firstMatch.frame
        let navBars = app.navigationBars.allElementsBoundByIndex.map { "\($0.identifier)@\(Int($0.frame.minY))-\(Int($0.frame.maxY))" }
        let suche = app.searchFields.firstMatch
        let sucheInfo = suche.exists ? "\(suche.placeholderValue ?? suche.label)@y=\(Int(suche.frame.minY))..\(Int(suche.frame.maxY))" : "nicht gefunden"
        let chips = ["Alle", "Kino", "News", "Sport"].map { name -> String in
            let b = app.buttons[name]
            return b.exists ? "\(name)@y=\(Int(b.frame.minY))" : "\(name)=fehlt"
        }
        let titel = app.staticTexts["QA iOS"].exists
        let alleButtons = app.buttons.allElementsBoundByIndex.map(\.label)
        log("EC-11|bildschirm=\(Int(fenster.width))x\(Int(fenster.height))|navigationsleisten=\(navBars)|suchfeld=\(sucheInfo)|chips=\(chips)|titelImInhalt=\(titel)")
        log("EC-11|buttons=\(alleButtons.prefix(40))")
        XCTAssertTrue(app.navigationBars["QA iOS"].exists, "AK-01: Playlistname als Titel der Navigationsleiste")
        XCTAssertTrue(titel, "AK-01: Playlistname groß im Inhalt")
        // Das Suchfeld ist beim Öffnen nicht vorhanden; erst Herunterziehen der Liste blendet es ein
        let sofortSichtbar = suche.exists
        // Senkrechte Liste an der Kopfzeile herunterziehen (die erste ScrollView ist die waagerechte Chip-Leiste),
        // danach einmal hinauf- und wieder zurückscrollen
        kopf.swipeDown()
        var nachZiehen = app.searchFields.firstMatch.waitForExistence(timeout: 3)
        if !nachZiehen {
            let fenster = app.windows.firstMatch
            fenster.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                .press(forDuration: 0.05, thenDragTo: fenster.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
            nachZiehen = app.searchFields.firstMatch.waitForExistence(timeout: 3)
        }
        if !nachZiehen {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Kino Kanal 3'")).firstMatch.swipeUp()
            sleep(1)
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Kino Kanal'")).firstMatch.swipeDown()
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Kino Kanal'")).firstMatch.swipeDown()
            nachZiehen = app.searchFields.firstMatch.waitForExistence(timeout: 3)
        }
        let sucheNachher = app.searchFields.firstMatch
        let nachherInfo = nachZiehen ? "\(sucheNachher.placeholderValue ?? sucheNachher.label)@y=\(Int(sucheNachher.frame.minY))..\(Int(sucheNachher.frame.maxY))" : "nicht gefunden"
        log("AK-01|ios|suchfeldBeimOeffnen=\(sofortSichtbar)|nachHerunterziehen=\(nachherInfo)|navigationsleisten=\(app.navigationBars.allElementsBoundByIndex.map { "\($0.identifier)@\(Int($0.frame.minY))-\(Int($0.frame.maxY))" })")
        shot(app, "EC-11-ios-suchfeld-nach-herunterziehen")
        XCTAssertTrue(nachZiehen, "AK-01: Suchfeld „Sender suchen“ (nach Herunterziehen)")
        if nachZiehen { XCTAssertEqual(sucheNachher.placeholderValue, "Sender suchen") }
        XCTExpectFailure("Hinweis H-1 · Suchfeld auf iOS beim Öffnen der Liste verborgen (erst nach Herunterziehen; kein Spec-Kriterium)") {
            XCTAssertTrue(sofortSichtbar, "Suchfeld beim Öffnen sichtbar")
        }
        XCTAssertTrue(chips.allSatisfy { !$0.hasSuffix("=fehlt") }, "AK-10: Chip-Leiste")
        // EC-11: kein ⊞-Button (nur macOS)
        let multiview = alleButtons.filter { $0.localizedCaseInsensitiveContains("multiview") || $0.contains("rectangle.split") }
        log("EC-11|multiviewButtons=\(multiview)")
        XCTAssertEqual(multiview, [], "EC-11: kein ⊞-Button auf iOS")

        // AK-02 / AK-13: Chip wählen — Kopfzeile bleibt bei der Gesamtzahl
        app.buttons["Sport"].tap()
        sleep(2)
        let sportKarten = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sport Kanal'")).count
        let kinoKarten = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Kino Kanal'")).count
        log("AK-13|ios|chipSport|sportKarten=\(sportKarten)|kinoKarten=\(kinoKarten)|kopf=\(kopf.exists)")
        shot(app, "EC-11-ios-chip-sport")
        XCTAssertGreaterThan(sportKarten, 0)
        XCTAssertEqual(kinoKarten, 0, "nur Sender der Gruppe")
        XCTAssertTrue(kopf.exists, "AK-02: Kopfzeile zeigt weiter 30 Sender")

        // AK-22: Sender ohne Logo-Adresse → Ladeindikator statt Platzhalter
        let indikatoren = app.activityIndicators.count
        log("AK-22|ios|ladeindikatoren=\(indikatoren)")

        // AK-04: Karte antippen öffnet den Player im selben Stapel (Stream auf Port 9: keine Wiedergabe, kein Ton)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sport Kanal 0'")).firstMatch.tap()
        let playerTitel = app.navigationBars["Sport Kanal 0"]
        let geoeffnet = playerTitel.waitForExistence(timeout: 15) || app.staticTexts["Sport Kanal 0"].waitForExistence(timeout: 5)
        sleep(2)
        log("AK-04|ios|playerGeoeffnet=\(geoeffnet)|texte=\(app.staticTexts.allElementsBoundByIndex.prefix(8).map(\.label))")
        shot(app, "EC-11-ios-player")
        XCTAssertTrue(geoeffnet, "AK-04: Player des angetippten Senders")
        app.terminate()
    }
}
#endif
