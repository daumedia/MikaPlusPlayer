import XCTest
@testable import MikaPlusPlayer

/// B02 · M3U-Import — Parser (AK-20 … AK-24, AK-26 Parser-Teil, EC-01 … EC-14). Reine Funktion, ohne Datenbank und Netz.
final class B02ParserTests: XCTestCase {
    private let parser = M3UParser()

    private func parse(_ s: String) -> [ParsedChannel] { parser.parse(s) }

    private func show(_ list: [ParsedChannel]) -> String {
        list.map { "{\($0.name.debugDescription) url=\($0.streamURL.absoluteString.prefix(80)) gruppe=\($0.group?.debugDescription ?? "nil") tvg=\($0.tvgID?.debugDescription ?? "nil") logo=\($0.logoURL?.absoluteString.prefix(60) ?? "nil")}" }
            .joined(separator: " ")
    }

    // MARK: AK-20

    /// AK-20: `#EXTINF:` + nächste Zeile, die weder leer ist noch mit `#` beginnt; Adresse mit Schema; `#EXTM3U` nicht nötig;
    /// Leerzeilen, Kommentare, `#EXTVLCOPT`, `#KODIPROP` stören nicht; Leerzeichen/Tabs am Zeilenrand werden ignoriert.
    func testAK20_EintragAusExtinfUndAdresszeile() {
        let ohneKopf = parse("#EXTINF:-1,Ohne Kopf\nhttp://h/a.m3u8\n")
        XCTAssertEqual(ohneKopf.map(\.name), ["Ohne Kopf"])

        let dazwischen = parse("""
        #EXTM3U x-tvg-url="http://epg.example/e.xml"
        #EXTINF:-1 tvg-id="a",Mit Zwischenzeilen

        # ein Kommentar
        #EXTVLCOPT:http-user-agent=QA/1.0
        #KODIPROP:inputstream.adaptive.license_type=clearkey

        http://h/a.ts
        """)
        XCTAssertEqual(dazwischen.map(\.name), ["Mit Zwischenzeilen"])
        XCTAssertEqual(dazwischen.first?.streamURL.absoluteString, "http://h/a.ts")

        let rand = parse(" \t#EXTINF:-1,Rand\t \n \t http://h/rand.ts \t\n")
        XCTAssertEqual(rand.map(\.name), ["Rand"])
        XCTAssertEqual(rand.first?.streamURL.absoluteString, "http://h/rand.ts")

        let mitteKopf = parse("#EXTINF:-1,Eins\nhttp://h/1.ts\n#EXTM3U\n#EXTINF:-1,Zwei\nhttp://h/2.ts\n")
        XCTAssertEqual(mitteKopf.map(\.name), ["Eins", "Zwei"])

        let ohneSchema = parse("#EXTINF:-1,Ohne Schema\nh/a.ts\n")
        XCTAssertEqual(ohneSchema.count, 0, "Adresse ohne Schema wird verworfen")
        B02.log("AK-20|ohneKopf=\(ohneKopf.count)|dazwischen=\(show(dazwischen))|rand=\(show(rand))|kopfInDerMitte=\(mitteKopf.count)|ohneSchema=\(ohneSchema.count)")
    }

    // MARK: AK-21

    /// AK-21: Name = Text nach dem ersten Komma außerhalb von `"…"`, getrimmt; leer oder ohne Komma → letzter Pfadabschnitt.
    func testAK21_NameQuoteSicherUndErsatzname() {
        let a = parse("#EXTINF:-1 tvg-id=\"ard.de\" tvg-logo=\"http://x/logo.png\" group-title=\"News, Politik\",Das Erste, HD\nhttp://h/a.m3u8")
        XCTAssertEqual(a.first?.name, "Das Erste, HD")
        XCTAssertEqual(a.first?.group, "News, Politik")
        let logoKomma = parse("#EXTINF:-1 tvg-logo=\"http://x/l.png?a=1,2\",Name\nhttp://h/a.ts")
        XCTAssertEqual(logoKomma.first?.name, "Name")
        XCTAssertEqual(logoKomma.first?.logoURL?.absoluteString, "http://x/l.png?a=1,2")
        let quotes = parse("#EXTINF:-1,Sender \"Eins\", HD\nhttp://h/a.ts")
        XCTAssertEqual(quotes.first?.name, "Sender \"Eins\", HD")
        let leer = parse("#EXTINF:-1 tvg-id=\"x\",\nhttp://h/stream-name.ts")
        XCTAssertEqual(leer.first?.name, "stream-name.ts")
        let nurLeerzeichen = parse("#EXTINF:-1,    \nhttp://h/pfad/letzter.m3u8")
        XCTAssertEqual(nurLeerzeichen.first?.name, "letzter.m3u8")
        let ohneKomma = parse("#EXTINF:-1 tvg-id=\"x\"\nhttp://h/ohne-komma.ts")
        XCTAssertEqual(ohneKomma.first?.name, "ohne-komma.ts")
        B02.log("AK-21|\(show(a + logoKomma + quotes + leer + nurLeerzeichen + ohneKomma))")
    }

    // MARK: AK-22

    /// AK-22 (a)–(f): nur `tvg-id`, `tvg-logo`, `group-title`, Schlüssel ohne Beachtung der Großschreibung; Wert in `"…"`,
    /// Leerzeichen um `=` und Tabs erlaubt; letzter Wert gewinnt, leerer Wert fehlt; Rand-Leerzeichen bleiben; ohne
    /// Anführungszeichen oder mit Hochkommas nicht gelesen; Attribute nach dem Komma gehören zum Namen.
    func testAK22_AttributRegeln() {
        let gross = parse("#EXTINF:-1 TVG-ID=\"up\" Tvg-Logo=\"http://x/u.png\" GROUP-TITLE=\"GRUPPE\" tvg-name=\"Anderer\" tvg-chno=\"5\",Gross\nhttp://h/a.ts")
        XCTAssertEqual(gross.first?.tvgID, "up")
        XCTAssertEqual(gross.first?.logoURL?.absoluteString, "http://x/u.png")
        XCTAssertEqual(gross.first?.group, "GRUPPE")
        XCTAssertEqual(gross.first?.name, "Gross", "tvg-name wird nicht gelesen")

        let leerzeichen = parse("#EXTINF:-1 tvg-id = \"sp\"   group-title =\"G\",Sp\nhttp://h/a.ts")
        XCTAssertEqual(leerzeichen.first?.tvgID, "sp")
        XCTAssertEqual(leerzeichen.first?.group, "G")
        let tabs = parse("#EXTINF:-1\ttvg-id=\"tab\"\tgroup-title=\"TabG\",Tab\nhttp://h/a.ts")
        XCTAssertEqual(tabs.first?.tvgID, "tab")
        XCTAssertEqual(tabs.first?.group, "TabG")

        let doppelt = parse("#EXTINF:-1 group-title=\"Erste\" group-title=\"Zweite\",Doppelt\nhttp://h/a.ts")
        XCTAssertEqual(doppelt.first?.group, "Zweite")
        let leer = parse("#EXTINF:-1 tvg-id=\"\" tvg-logo=\"\" group-title=\"\",Leer\nhttp://h/a.ts")
        XCTAssertNil(leer.first?.tvgID)
        XCTAssertNil(leer.first?.logoURL)
        XCTAssertNil(leer.first?.group)

        let rand = parse("#EXTINF:-1 tvg-id=\" id \" group-title=\" News \",Rand\nhttp://h/a.ts")
        XCTAssertEqual(rand.first?.group, " News ")
        XCTAssertEqual(rand.first?.tvgID, " id ")

        let ohneQuotes = parse("#EXTINF:-1 tvg-id=noquote group-title=News,NoQuote\nhttp://h/a.ts")
        XCTAssertNil(ohneQuotes.first?.tvgID)
        XCTAssertNil(ohneQuotes.first?.group)
        let hochkomma = parse("#EXTINF:-1 group-title='News',Hoch\nhttp://h/a.ts")
        XCTAssertNil(hochkomma.first?.group)

        let nachKomma = parse("#EXTINF:-1,Name group-title=\"Nach Komma\"\nhttp://h/a.ts")
        XCTAssertEqual(nachKomma.first?.name, "Name group-title=\"Nach Komma\"")
        XCTAssertNil(nachKomma.first?.group)
        B02.log("AK-22|\(show(gross + leerzeichen + tabs + doppelt + leer + rand + ohneQuotes + hochkomma + nachKomma))")
    }

    // MARK: AK-23

    /// AK-23: `#EXTGRP:` zwischen `#EXTINF` und Adresse, falls `group-title` fehlt; erste gilt, leere ignoriert; davor,
    /// kleingeschrieben oder für Folgesender ohne Wirkung.
    func testAK23_ExtgrpRegeln() {
        XCTAssertEqual(parse("#EXTINF:-1,A\n#EXTGRP:Sport\nhttp://h/a.ts").first?.group, "Sport")
        XCTAssertEqual(parse("#EXTINF:-1 group-title=\"Titel\",A\n#EXTGRP:Sport\nhttp://h/a.ts").first?.group, "Titel")
        XCTAssertEqual(parse("#EXTINF:-1,A\n#EXTGRP:Erste\n#EXTGRP:Zweite\nhttp://h/a.ts").first?.group, "Erste")
        XCTAssertNil(parse("#EXTINF:-1,A\n#EXTGRP:\nhttp://h/a.ts").first?.group)
        XCTAssertEqual(parse("#EXTINF:-1,A\n#EXTGRP:   \n#EXTGRP:Danach\nhttp://h/a.ts").first?.group, "Danach", "leere wird übersprungen")
        XCTAssertNil(parse("#EXTGRP:Vorher\n#EXTINF:-1,A\nhttp://h/a.ts").first?.group)
        XCTAssertNil(parse("#EXTINF:-1,A\n#extgrp:klein\nhttp://h/a.ts").first?.group)
        let folge = parse("#EXTINF:-1,A\nhttp://h/a.ts\n#EXTGRP:Spaet\n#EXTINF:-1,B\nhttp://h/b.ts")
        XCTAssertEqual(folge.map { $0.group ?? "nil" }, ["nil", "nil"])
        B02.log("AK-23|folge=\(show(folge))")
    }

    // MARK: AK-24

    /// AK-24: LF, CRLF, CR und gemischt ergeben dieselben Sender.
    func testAK24_Zeilenenden() {
        let base = ["#EXTM3U", "#EXTINF:-1 group-title=\"G\",A", "http://h/a.ts", "#EXTINF:-1,B", "http://h/b.ts"]
        let lf = parse(base.joined(separator: "\n"))
        let crlf = parse(base.joined(separator: "\r\n"))
        let cr = parse(base.joined(separator: "\r"))
        let mixed = parse("#EXTM3U\r\n#EXTINF:-1 group-title=\"G\",A\rhttp://h/a.ts\n#EXTINF:-1,B\r\nhttp://h/b.ts\r")
        XCTAssertEqual(lf.count, 2)
        XCTAssertEqual(lf, crlf)
        XCTAssertEqual(lf, cr)
        XCTAssertEqual(lf, mixed)
        B02.log("AK-24|LF=\(lf.count)|CRLF=\(crlf.count)|CR=\(cr.count)|gemischt=\(mixed.count)")
    }

    // MARK: AK-26 (Parser)

    /// AK-26 (Parser-Teil): leer, HTML, JSON, nur Adressen → keine Sender; ungültige Einträge in einer gültigen Liste fallen still weg.
    func testAK26_KeineGueltigenEintraegeUndStillesVerwerfen() {
        XCTAssertEqual(parse("").count, 0)
        XCTAssertEqual(parse("<!doctype html><html><body>Login</body></html>").count, 0)
        XCTAssertEqual(parse("{\"user_info\":{\"auth\":0}}").count, 0)
        XCTAssertEqual(parse("http://h/a.ts\nhttp://h/b.ts\n").count, 0)
        let gemischt = parse("#EXTINF:-1,Kaputt\nkein url\n#EXTINF:-1,Gut\nhttp://h/ok.m3u8\n#EXTINF:-1,Relativ\n/live/1.ts\n#EXTINF:-1,Auch gut\nhttp://h/ok2.ts")
        XCTAssertEqual(gemischt.map(\.name), ["Gut", "Auch gut"])
    }

    // MARK: Edge Cases

    /// EC-01: einfache M3U nur aus Adresszeilen → 0 Sender (Meldung im Import: `B02URLImportTests.testAK26_…`).
    func testEC01_EinfacheM3UOhneExtinf() {
        XCTAssertEqual(parse("#EXTM3U\nhttp://h/a.ts\nhttp://h/b.m3u8\n").count, 0)
    }

    /// EC-02: `#extinf:` kleingeschrieben oder `#EXTINF -1,…` ohne Doppelpunkt → wie Kommentar übersprungen.
    func testEC02_ExtinfKleinOderOhneDoppelpunkt() {
        XCTAssertEqual(parse("#extinf:-1,klein\nhttp://h/a.ts").count, 0)
        XCTAssertEqual(parse("#EXTINF -1,ohne\nhttp://h/a.ts").count, 0)
    }

    /// EC-03: ungültige Adresszeile verbraucht den Eintrag; zwei `#EXTINF` → der zweite; zwei Adressen → nur die erste;
    /// `#EXTINF` am Ende ohne Adresse → verworfen.
    func testEC03_VerbrauchteUndDoppelteEintraege() {
        XCTAssertEqual(parse("#EXTINF:-1,Kaputt\nkein url\nhttp://h/b.ts").count, 0, "direkt folgende gültige Adresse fällt weg")
        XCTAssertEqual(parse("#EXTINF:-1,Erster\n#EXTINF:-1,Zweiter\nhttp://h/a.ts").map(\.name), ["Zweiter"])
        let zweiAdressen = parse("#EXTINF:-1,A\nhttp://h/a.ts\nhttp://h/b.ts")
        XCTAssertEqual(zweiAdressen.map(\.streamURL.absoluteString), ["http://h/a.ts"])
        XCTAssertEqual(parse("#EXTINF:-1,A\nhttp://h/a.ts\n#EXTINF:-1,Ende").map(\.name), ["A"])
    }

    /// EC-04: ungerade Zahl `"` vor dem Namen → kein Namenskomma; Gruppe „News,Das Erste"; fehlendes schließendes `"` frisst
    /// das nächste Attribut.
    func testEC04_UnbalancierteAnfuehrungszeichen() {
        let offen = parse("#EXTINF:-1 group-title=\"News,Das Erste\nhttp://h/a.ts")
        XCTAssertEqual(offen.first?.name, "a.ts")
        XCTAssertEqual(offen.first?.group, "News,Das Erste")
        let frisst = parse("#EXTINF:-1 tvg-id=\"abc group-title=\"News\",Name\nhttp://h/a.ts")
        XCTAssertEqual(frisst.first?.name, "a.ts")
        XCTAssertEqual(frisst.first?.tvgID, "abc group-title=")
        XCTAssertNil(frisst.first?.group)
        B02.log("EC-04|\(show(offen + frisst))")
    }

    /// EC-05: einfache Hochkommas mit Komma im Wert → Name „X',Name", keine Gruppe.
    func testEC05_HochkommasMitKomma() {
        let r = parse("#EXTINF:-1 group-title='Grp, X',Name\nhttp://h/a.ts")
        XCTAssertEqual(r.first?.name, "X',Name")
        XCTAssertNil(r.first?.group)
    }

    /// EC-06: U+2028, U+0085, VT teilen die Zeile → Sender geht verloren; NUL, ESC-Sequenz und U+202E bleiben im Namen.
    func testEC06_SteuerzeichenImNamen() {
        for (label, sep) in [("U+2028", "\u{2028}"), ("U+0085", "\u{0085}"), ("VT", "\u{0B}"), ("FF", "\u{0C}")] {
            let r = parse("#EXTINF:-1,Vor\(sep)Nach\nhttp://h/a.ts")
            B02.log("EC-06|\(label)|anzahl=\(r.count)|\(show(r))")
            XCTAssertEqual(r.count, 0, label)
        }
        XCTAssertEqual(parse("#EXTINF:-1,Vor\u{0}Nach\nhttp://h/a.ts").first?.name, "Vor\u{0}Nach")
        XCTAssertEqual(parse("#EXTINF:-1,Vor\u{1B}[31mRot\nhttp://h/a.ts").first?.name, "Vor\u{1B}[31mRot")
        XCTAssertEqual(parse("#EXTINF:-1,abc\u{202E}gnp.exe\nhttp://h/a.ts").first?.name, "abc\u{202E}gnp.exe")
    }

    /// EC-10: relative Adressen verworfen; `C:\Videos\a.ts` mit Schema „C"; `localhost:8080/…` mit Schema „localhost".
    func testEC10_RelativeUndSchemaaehnlicheAdressen() {
        for rel in ["stream.m3u8", "/live/1.ts", "../live/1.ts", "//cdn.example/1.ts", "127.0.0.1:8080/live/1.ts"] {
            XCTAssertEqual(parse("#EXTINF:-1,R\n\(rel)").count, 0, rel)
        }
        let win = parse("#EXTINF:-1,Win\nC:\\Videos\\a.ts")
        XCTAssertEqual(win.first?.streamURL.absoluteString, "C:%5CVideos%5Ca.ts")
        XCTAssertEqual(win.first?.streamURL.scheme, "C")
        let lh = parse("#EXTINF:-1,LH\nlocalhost:8080/live/1.ts")
        XCTAssertEqual(lh.first?.streamURL.scheme, "localhost")
        B02.log("EC-10|\(show(win + lh))")
    }

    /// EC-11: Logo-Adresse mit Leerzeichen → prozentkodiert relativ; relative Logo-Pfade bleiben relativ.
    func testEC11_LogoAdressen() {
        let leer = parse("#EXTINF:-1 tvg-logo=\"kein url mit leer zeichen\",Logo\nhttp://h/a.ts")
        XCTAssertEqual(leer.first?.logoURL?.absoluteString, "kein%20url%20mit%20leer%20zeichen")
        XCTAssertNil(leer.first?.logoURL?.scheme)
        let rel = parse("#EXTINF:-1 tvg-logo=\"logos/a.png\",Rel\nhttp://h/a.ts")
        XCTAssertEqual(rel.first?.logoURL?.absoluteString, "logos/a.png")
    }

    /// EC-12: derselbe Sender zweimal → zwei Sender.
    func testEC12_DoppelterSender() {
        XCTAssertEqual(parse("#EXTINF:-1,A\nhttp://h/a.ts\n#EXTINF:-1,A\nhttp://h/a.ts").count, 2)
    }

    /// EC-13 (FB-03): sehr lange Zeilen werden ungekürzt übernommen; Laufzeit je Fall.
    func testEC13_SehrLangeZeilenUngekuerzt() {
        func timed(_ label: String, _ s: String) -> [ParsedChannel] {
            let t = Date()
            let r = parse(s)
            B02.evidence("AK-37-EC-13-grenzen.txt", "EC-13|\(label)|eingabeBytes=\(s.utf8.count)|anzahl=\(r.count)|dauer=\(B02.f2(Date().timeIntervalSince(t)))s|name=\(r.first?.name.count ?? -1)|logo=\(r.first?.logoURL?.absoluteString.count ?? -1)|gruppe=\(r.first?.group?.count ?? -1)|url=\(r.first?.streamURL.absoluteString.count ?? -1)|build=\(B02.buildConfiguration)")
            return r
        }
        let mb = 1_000_000
        let a = timed("Name 1 MB + Logo 5 MB", "#EXTINF:-1 tvg-logo=\"http://x/\(String(repeating: "l", count: 5 * mb)).png\",\(String(repeating: "N", count: mb))\nhttp://h/a.ts")
        XCTAssertEqual(a.first?.name.count, mb)
        XCTAssertEqual(a.first?.logoURL?.absoluteString.count, 5 * mb + 13)
        let b = timed("Stream-Adresse 2 MB", "#EXTINF:-1,Lang\nhttp://h/\(String(repeating: "u", count: 2 * mb))")
        XCTAssertEqual(b.first?.streamURL.absoluteString.count, 2 * mb + 9)
        let c = timed("Gruppe 1 MB", "#EXTINF:-1 group-title=\"\(String(repeating: "g", count: mb))\",G\nhttp://h/a.ts")
        XCTAssertEqual(c.first?.group?.count, mb)
        let d = timed("1 MB Anführungszeichen", "#EXTINF:-1 \(String(repeating: "\"", count: mb)),Q\nhttp://h/a.ts")
        XCTAssertEqual(d.count, 1)
        let e = timed("500.000 × a=", "#EXTINF:-1 \(String(repeating: "a=", count: 500_000)),A\nhttp://h/a.ts")
        XCTAssertEqual(e.count, 1)
    }

    /// EC-14 (FB-03): 300.000 Einträge ≈ 46 MB — nur der Parser; Laufzeit und Speicherzuwachs.
    func testEC14_DreihunderttausendEintraegeParser() {
        let data = B02.grosseListe(300_000)
        let before = B02.footprintMB()
        let t0 = Date()
        let text = String(data: data, encoding: .utf8) ?? ""
        let t1 = Date()
        let r = parse(text)
        let t2 = Date()
        let after = B02.footprintMB()
        B02.evidence("AK-37-EC-13-grenzen.txt", "EC-14|bytes=\(data.count)|anzahl=\(r.count)|dekodieren=\(B02.f2(t1.timeIntervalSince(t0)))s|parser=\(B02.f2(t2.timeIntervalSince(t1)))s|speicherVorher=\(Int(before))MB|nachher=\(Int(after))MB|build=\(B02.buildConfiguration)")
        XCTAssertEqual(r.count, 300_000)
    }

    /// AK-40 (Parser-Anteil): 17.000 Einträge nur parsen.
    func testAK40_ParserAllein17000() {
        let text = String(decoding: B02.grosseListe(17_000), as: UTF8.self)
        var times: [String] = []
        for _ in 0..<3 {
            let t = Date()
            XCTAssertEqual(parse(text).count, 17_000)
            times.append(B02.f2(Date().timeIntervalSince(t)))
        }
        B02.evidence("AK-40-messung.txt", "AK-40|parserAllein|sender=17000|bytes=\(text.utf8.count)|dauer=\(times.joined(separator: ","))s|build=\(B02.buildConfiguration)")
    }
}
