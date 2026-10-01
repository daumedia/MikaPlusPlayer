import XCTest
import SwiftUI
import SwiftData
import AppKit
import Darwin
@testable import MikaPlusPlayer

/// B04 · Senderliste — Ergänzungen der QA (Durchlauf 1, Fortsetzung 2026-09-26):
/// - AK-31/AK-33: das **tatsächliche** SQL der echten `ChannelListView` (Core-Data-Ausgabe `CoreData: sql:` auf stderr).
///   Läuft nur mit dem Startargument `-com.apple.CoreData.SQLDebug 1` (eigene xctestrun-Kopie), sonst übersprungen.
/// - AK-13/FB-11: Kontrast aus der Akzentfarbe des Codes (hell und dunkel aufgelöst) und aus der gerenderten Aufnahme.
/// - Angriff 4: Logo-Adressen im Systemprotokoll des eigenen Prozesses.
final class B04ErgaenzungTests: B04TestCase {

    // MARK: - AK-31 / AK-33 (echtes SQL)

    func testAK31_AK33_EchtesSQLDerSenderliste() throws {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-com.apple.CoreData.SQLDebug"), i + 1 < args.count, args[i + 1] != "0" else {
            throw XCTSkip("nur mit Startargument -com.apple.CoreData.SQLDebug 1 (eigene xctestrun-Kopie, siehe qa-report.md)")
        }
        let (c, _) = try fileContainer("sql")
        let pl = try B04QA.seed(c.mainContext, name: "QA SQL", items: [
            .init("Alpha Sport", "Sport"), .init("Beta News", "News"), .init("Gamma Sport", "Sport"),
        ])
        let capture = B04Stderr()
        capture.start()
        let w = window(c)
        w.open(pl, wait: 1.5)
        let nachOeffnen = capture.text
        XCTAssertTrue(w.pressChip("Sport"))
        let nachChip = capture.text
        XCTAssertTrue(w.type("alpha", wait: 1.0))
        let nachSucheMitChip = capture.text
        XCTAssertTrue(w.pressChip("Sport"))   // abwählen: nur Suche
        B04QA.spin(0.5)
        let alles = capture.stop()

        func selects(_ text: String) -> [String] {
            text.components(separatedBy: "\n")
                .filter { $0.contains("CoreData: sql: SELECT") && $0.contains("FROM ZCHANNEL") }
                .map { $0.replacingOccurrences(of: "CoreData: sql: ", with: "").trimmingCharacters(in: .whitespaces) }
        }
        let sqlOeffnen = selects(nachOeffnen)
        let sqlChip = selects(String(nachChip.dropFirst(nachOeffnen.count)))
        let sqlSucheChip = selects(String(nachSucheMitChip.dropFirst(nachChip.count)))
        let sqlSuche = selects(String(alles.dropFirst(nachSucheMitChip.count)))
        let zeiten = alles.components(separatedBy: "\n").filter { $0.contains("fetch execution time") }
        for (label, zeilen) in [("oeffnen", sqlOeffnen), ("chip", sqlChip), ("sucheUndChip", sqlSucheChip), ("suche", sqlSuche)] {
            for z in Set(zeilen) { B04QA.log("AK-31|sql|\(label)|\(z)") }
        }
        let belege = [("Öffnen", sqlOeffnen), ("Chip „Sport“", sqlChip), ("Chip + Suche „alpha“", sqlSucheChip),
                      ("nur Suche „alpha“", sqlSuche)]
            .map { "\($0.0):\n    " + Array(Set($0.1)).sorted().joined(separator: "\n    ") }
        B04QA.evidence("AK-31-33-sql.txt", "Echtes SQL der ChannelListView (CoreData SQLDebug, stderr des Test-Hosts)\n  "
                       + belege.joined(separator: "\n  ") + "\n  Ausführungszeiten: " + zeiten.suffix(8).joined(separator: " · "))

        // AK-31: Filter und Sortierung in SQL. Seit B04 · BUG-12/-13 (Build 2026-09-29): über die indizierte Beziehung
        // (`t0.ZPLAYLIST = ?`), die Trefferliste nur als Kennungen (`SELECT 0, t0.Z_PK`), im Hintergrund.
        let geordnet = "ORDER BY t0.ZNAME COLLATE NSCollateLocaleSensitive"
        let beziehung = "t0.ZPLAYLIST IS NOT NULL AND  t0.ZPLAYLIST = ?"
        XCTAssertTrue(sqlOeffnen.contains { $0.hasPrefix("SELECT 0, t0.Z_PK FROM ZCHANNEL t0 WHERE") && $0.contains(beziehung) && $0.contains(geordnet) },
                      "Öffnen: Kennungen mit Filter über die Beziehung und Sortierung in SQLite")
        XCTAssertFalse((sqlOeffnen + sqlChip + sqlSucheChip + sqlSuche).contains { $0.contains("ZPLAYLISTID = ?") },
                       "die unindizierte Kopie playlistID filtert nicht mehr")
        XCTAssertTrue(sqlChip.contains { $0.contains(beziehung) && $0.contains("t0.ZGROUP = ?") && $0.contains(geordnet) }, "Chip: ZGROUP in SQL")
        XCTAssertTrue(sqlSucheChip.contains { $0.contains("NSCoreDataStringSearch( t0.ZNAME, ?, 417, 1)")
                          && $0.contains("t0.ZGROUP = ?") && $0.contains(geordnet) }, "Suche + Chip in SQL")
        XCTAssertTrue(sqlSuche.contains { $0.contains("NSCoreDataStringSearch( t0.ZNAME, ?, 417, 1)")
                          && !$0.contains("ZGROUP = ?") }, "nur Suche in SQL")
        // Karten holen nur ihren eigenen Sender (sichtbarer Bereich), nicht die ganze Liste
        let einzeln = (sqlOeffnen + sqlChip).filter { $0.contains("WHERE  t0.Z_PK = ?  LIMIT 1") }
        B04QA.log("AK-31|kartenAbfragen=\(einzeln.count)")
        XCTAssertFalse(einzeln.isEmpty, "Karten holen ihren Sender einzeln")

        // AK-33: Die Chip-Berechnung (ohne ORDER BY) läuft im Hintergrund (BUG-14, Teil Main-Thread: behoben, Blockade in
        // B04LeistungTests). SwiftData liest dabei weiter alle Spalten, obwohl nur `group` angefordert ist.
        let chipAbfrage = sqlOeffnen.filter { $0.contains(beziehung) && !$0.contains("ORDER BY") }
        B04QA.log("AK-33|chipAbfrage=\(chipAbfrage)")
        XCTAssertFalse(chipAbfrage.isEmpty, "Chip-Berechnung als eigene Abfrage ohne Sortierung")
        XCTExpectFailure("BUG-14 (Teil Spalten) · SwiftData liest trotz propertiesToFetch alle Spalten – ohne Schemaänderung nicht lösbar (spec OF-08)") {
            XCTAssertFalse(chipAbfrage.contains { $0.contains("ZSTREAMURL") }, "nur die Spalte ZGROUP wird gelesen")
        }
    }

    // MARK: - AK-13 / FB-11 (Kontrast aus Code und Aufnahme, hell und dunkel)

    func testAK13_KontrastGewaehlterChipHellUndDunkel() throws {
        // Aus dem Code: die dynamische Akzentfarbe je Erscheinungsbild auflösen
        func aufgeloest(_ name: NSAppearance.Name) -> NSColor {
            var out = NSColor.black
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                out = NSColor(Color.playerAccent).usingColorSpace(.sRGB) ?? .black
            }
            return out
        }
        func schrift(_ name: NSAppearance.Name) -> NSColor {
            var out = NSColor.white
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                out = NSColor(Color.playerOnAccent).usingColorSpace(.sRGB) ?? .white
            }
            return out
        }
        let hell = aufgeloest(.aqua), dunkel = aufgeloest(.darkAqua)
        let schriftHell = schrift(.aqua), schriftDunkel = schrift(.darkAqua)
        func rgb(_ c: NSColor) -> String {
            String(format: "(%.0f, %.0f, %.0f)", c.redComponent * 255, c.greenComponent * 255, c.blueComponent * 255)
        }
        // Seit B04 · BUG-10 (Build 2026-09-29): Schrift `playerOnAccent` statt Weiß.
        let kHell = B04Shot.contrast(schriftHell, hell), kDunkel = B04Shot.contrast(schriftDunkel, dunkel)
        let weissHell = B04Shot.contrast(.white, hell), weissDunkel = B04Shot.contrast(.white, dunkel)
        B04QA.log("AK-13|akzentAusCode|hell=\(rgb(hell)) schrift=\(rgb(schriftHell)) kontrast=\(String(format: "%.2f", kHell)) (weiß \(String(format: "%.2f", weissHell)))|dunkel=\(rgb(dunkel)) schrift=\(rgb(schriftDunkel)) kontrast=\(String(format: "%.2f", kDunkel)) (weiß \(String(format: "%.2f", weissDunkel)))")

        // Aus der Aufnahme: gewählter Chip in beiden Erscheinungsbildern
        let (c, _) = try fileContainer("ak13k")
        let pl = try B04QA.seed(c.mainContext, name: "QA Kontrast", items: [
            .init("Alpha Sport", "Sport"), .init("Beta News", "News"),
        ])
        var gerendert: [String] = []
        var gerenderteKontraste: [Double] = []
        for (name, label) in [(NSAppearance.Name.aqua, "hell"), (NSAppearance.Name.darkAqua, "dunkel")] {
            let w = window(c, size: CGSize(width: 700, height: 420), appearance: name)
            w.open(pl, wait: 1.5)
            XCTAssertTrue(w.pressChip("Sport", wait: 1.0))
            w.shot("BUILD-AK-13-chip-\(label)")
            let chip = try XCTUnwrap(w.chips.first { $0.title == "Sport" })
            let r = w.inWindow(chip.frame)
            let (flaeche, schrift) = B04Shot.fillAndText(w.window, in: r)
            let k = B04Shot.contrast(flaeche, schrift)
            gerenderteKontraste.append(k)
            gerendert.append("\(label): Fläche \(rgb(flaeche)), Schrift \(rgb(schrift)), \(String(format: "%.2f", k)) : 1")
            B04QA.log("AK-13|gerendert|\(gerendert.last!)")
            w.close()
        }
        B04QA.evidence("BUILD-AK-13-kontrast.txt",
                       "Akzentfarbe aus PlayerTheme (aufgelöst): hell \(rgb(hell)) → Schrift \(rgb(schriftHell)) \(String(format: "%.2f", kHell)) : 1, "
                       + "dunkel \(rgb(dunkel)) → Schrift \(rgb(schriftDunkel)) \(String(format: "%.2f", kDunkel)) : 1 (15-pt-Text medium, WCAG AA 4,5 : 1)\n  "
                       + "Gerendert (Fensteraufnahme, gewählter Chip „Sport“): " + gerendert.joined(separator: " · "))
        XCTAssertEqual(rgb(hell), "(239, 68, 68)", "Akzent unverändert")
        XCTAssertEqual(rgb(dunkel), "(248, 113, 113)", "Akzent unverändert")
        XCTAssertGreaterThanOrEqual(min(kHell, kDunkel), 4.5, "Schrift auf Akzent erreicht 4,5 : 1 (aus dem Code)")
        XCTAssertEqual(gerenderteKontraste.count, 2)
        XCTAssertGreaterThanOrEqual(gerenderteKontraste.min() ?? 0, 4.5, "gerendert in beiden Modi mindestens 4,5 : 1")
    }

    // MARK: - Angriff 4 (Logo-Adressen im Systemprotokoll)

    func testAngriff4_LogoAdressenImSystemprotokoll() throws {
        let marke = "qab04log\(UInt32.random(in: 100_000...999_999))"
        let (c, _) = try fileContainer("angriff4b")
        let pl = try B04QA.seed(c.mainContext, name: "QA Protokoll Logos", items: [
            .init("L1 geschlossener Port", "Logos", logo: "http://127.0.0.1:9/\(marke)-port.png"),
            .init("L2 unbekannter Host", "Logos", logo: "http://\(marke).invalid/logo.png"),
            .init("L3 404", "Logos", logo: "\(host.base)/404/\(marke)-404.png"),
            .init("L4 Bild", "Logos", logo: "\(host.base)/nocache/\(marke)-ok.png"),
        ])
        let w = window(c, size: CGSize(width: 900, height: 500))
        w.open(pl, wait: 6.0)
        w.back(wait: 1.0)
        B04QA.spin(2.0)
        let prozess = ProcessInfo.processInfo.processName
        let zeilen = Self.shell("/usr/bin/log", ["show", "--style", "compact", "--info", "--debug", "--last", "3m",
                                                 "--predicate", "process == \"\(prozess)\" AND eventMessage CONTAINS \"\(marke)\""])
            .split(separator: "\n").filter { $0.contains(marke) }.map(String.init)
        let gesamt = Self.shell("/usr/bin/log", ["show", "--style", "compact", "--info", "--debug", "--last", "3m",
                                                 "--predicate", "process == \"\(prozess)\""]).split(separator: "\n").count
        let gekuerzt = zeilen.prefix(6).map { z -> String in
            let s = z.replacingOccurrences(of: "\(host.port)", with: "<port>")
            return String(s.prefix(260))
        }
        B04QA.log("ANGRIFF-4|logos|prozess=\(prozess)|zeilenDesProzesses=\(gesamt)|mitLogoAdresse=\(zeilen.count)")
        for z in gekuerzt { B04QA.log("ANGRIFF-4|logos|zeile|\(z)") }
        B04QA.evidence("angriff-4-logoadressen.txt",
                       "log show --info --debug --last 3m --predicate 'process == \"\(prozess)\"': \(gesamt) Zeilen, davon "
                       + "\(zeilen.count) mit einer Logo-Adresse (Marke \(marke)).\n  " + gekuerzt.joined(separator: "\n  "))
        // Kein Soll-Kriterium der Spec; Ergebnis steht im Bericht (Hinweis, Schwärzung am Test-Host aus)
        XCTAssertGreaterThan(gesamt, 0, "Systemprotokoll des Prozesses lesbar")
    }

    // MARK: - EC-11 (Daten für den iOS-Simulator)

    /// Legt die Datenbank für `B04iOSOberflaecheUITests` an (nur mit `TEST_RUNNER_B04_IOS_STORE=<Pfad>`).
    /// Die Datei wird danach in den App-Container des Simulators kopiert; keine Logo-Adressen, keine Netzanfragen.
    func testEC11_DatenbankFuerIOSSimulatorErzeugen() throws {
        guard let pfad = B04QA.env("B04_IOS_STORE"), !pfad.isEmpty else {
            throw XCTSkip("nur mit TEST_RUNNER_B04_IOS_STORE (Vorbereitung der iOS-Prüfung)")
        }
        let url = URL(fileURLWithPath: pfad)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: pfad + suffix) }
        var items: [B04QA.Item] = []
        for (g, gruppe) in ["Kino", "News", "Sport"].enumerated() {
            for k in 0..<10 {
                items.append(.init("\(gruppe) Kanal \(k)", gruppe, stream: "\(B04QA.dead)/live/\(g * 10 + k).m3u8"))
            }
        }
        do {
            let container = try AppPersistence.diskContainer(at: url, schema: AppSchema.schema)
            try B04QA.seed(container.mainContext, name: "QA iOS", items: items)
        }
        B04QA.spin(0.5)
        XCTAssertEqual(B04QA.int(pfad, "select count(*) from ZCHANNEL"), 30)
        B04QA.log("EC-11|datenbank=\(pfad)|sender=30")
    }

    // MARK: - Hilfen

    static func shell(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "FEHLER: \(error)" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Leitet stderr des Test-Prozesses vorübergehend in eine Pipe um (für `CoreData: sql:`-Zeilen).
final class B04Stderr: @unchecked Sendable {
    private let pipe = Pipe()
    private var saved: Int32 = -1
    private let lock = NSLock()
    private var buffer = Data()

    func start() {
        fflush(stderr)
        saved = dup(STDERR_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard let self, !d.isEmpty else { return }
            self.lock.withLock { self.buffer.append(d) }
        }
    }

    var text: String {
        fflush(stderr)
        B04QA.spin(0.2)
        return lock.withLock { String(decoding: buffer, as: UTF8.self) }
    }

    @discardableResult
    func stop() -> String {
        let t = text
        dup2(saved, STDERR_FILENO)
        close(saved)
        pipe.fileHandleForReading.readabilityHandler = nil
        try? pipe.fileHandleForWriting.close()
        return t
    }
}

extension B04Shot {
    /// Häufigste Farbe (Fläche) und die davon am stärksten abweichende helle Farbe (Schrift) in einem Bereich.
    @MainActor
    static func fillAndText(_ w: NSWindow, in region: NSRect) -> (NSColor, NSColor) {
        guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber),
                                                [.boundsIgnoreFraming, .bestResolution]) else { return (.black, .black) }
        let scale = CGFloat(img.width) / w.frame.width
        let rep = NSBitmapImageRep(cgImage: img)
        // Ränder der Kapsel meiden: mittlere 60 % der Breite, mittlere 70 % der Höhe
        let inner = region.insetBy(dx: region.width * 0.2, dy: region.height * 0.15)
        var counts: [UInt32: Int] = [:]
        var colors: [UInt32: NSColor] = [:]
        for y in Int(inner.minY * scale)..<Int(inner.maxY * scale) {
            for x in Int(inner.minX * scale)..<Int(inner.maxX * scale) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let key = UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255)
                counts[key, default: 0] += 1
                colors[key] = c
            }
        }
        guard let fillKey = counts.max(by: { $0.value < $1.value })?.key, let fill = colors[fillKey] else { return (.black, .black) }
        let text = colors.values.max { contrast($0, fill) < contrast($1, fill) } ?? fill
        return (fill, text)
    }
}
