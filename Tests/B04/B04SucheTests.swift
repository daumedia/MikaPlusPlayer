import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B04 · Senderliste — Suche und Sortierung (QA Durchlauf 1).
/// Die Semantik wird am Spiegel der Abfrage (`B04QA.resultsDescriptor`) über 41 Namen und 46 Suchbegriffe geprüft und
/// in `testAK07_…Oberflaeche` gegen die echte `ChannelListView` gehalten.
final class B04SucheTests: B04TestCase {

    static let namen = [
        "ARD", "ard alpha", "ZDFneo", "BR München HD", "MÜNCHEN TV", "Straße TV", "Strasse 2",
        "Écran Plus", "ecran basic", "Sport 2", "Sport 10", "1LIVE", "3sat", "Ärger TV", "Zebra",
        "arte", "#Hash TV", " Leerzeichen vorn", "100% Hits", "under_score", "Stern*Kanal",
        "Frage?TV", "Back\\slash", "O'Reilly TV", "Quote \"TV\"", "ＡＲＤ Fullwidth", "İstanbul TV",
        "istanbul 2", "Ελληνικά", "Первый канал", "قناة الاولى", "😀 Emoji TV", "ﬁlm ligature",
        "film normal", "Œuvre", "oeuvre", "Ølstrup", "Å TV", "Łódź TV", "lodz tv", "Sport  2",
    ]

    /// Reihenfolge, die `SortDescriptor(\.name, comparator: .localized)` in SQLite ergibt (Ist-Stand).
    static let erwarteteReihenfolge = [
        " Leerzeichen vorn", "#Hash TV", "😀 Emoji TV", "100% Hits", "1LIVE", "3sat", "Å TV", "ARD", "ard alpha",
        "ＡＲＤ Fullwidth", "Ärger TV", "arte", "Back\\slash", "BR München HD", "ecran basic", "Écran Plus",
        "ﬁlm ligature", "film normal", "Frage?TV", "istanbul 2", "İstanbul TV", "lodz tv", "Łódź TV", "MÜNCHEN TV",
        "O'Reilly TV", "oeuvre", "Œuvre", "Ølstrup", "Quote \"TV\"", "Sport  2", "Sport 10", "Sport 2",
        "Stern*Kanal", "Strasse 2", "Straße TV", "under_score", "ZDFneo", "Zebra", "Ελληνικά", "Первый канал",
        "قناة الاولى",
    ]

    @MainActor
    private func semantikPlaylist(_ label: String) throws -> (ModelContainer, Playlist, Playlist) {
        let (c, _) = try fileContainer(label)
        let ctx = c.mainContext
        let pl = try B04QA.seed(ctx, name: "QA Semantik", items: Self.namen.map { B04QA.Item($0) })
        let andere = try B04QA.seed(ctx, name: "QA Andere", items: [B04QA.Item("ARD in anderer Playlist")])
        return (c, pl, andere)
    }

    // MARK: - AK-06

    func testAK06_SucheProZeichenNurImNamenUndNurInDerOffenenPlaylist() throws {
        let (c, _) = try fileContainer("ak06")
        let ctx = c.mainContext
        let pl = try B04QA.seed(ctx, name: "QA Suche", items: [
            .init("Alpha", "Nachrichten", tvg: "zeta.id"),
            .init("Beta", "Sport", tvg: "beta.id"),
            .init("Gamma Sport", "News"),
        ])
        try B04QA.seed(ctx, name: "QA Fremd", items: [.init("Alpha Fremd", "Nachrichten")])
        let w = window(c, size: CGSize(width: 900, height: 820))
        w.open(pl, wait: 1.5)

        // Buchstabe für Buchstabe, ohne Bestätigung
        var verlauf: [String] = []
        for text in ["G", "Ga", "Gam", "Gamma S"] {
            XCTAssertTrue(w.type(text, wait: 0.6))
            verlauf.append("\(text)=\(w.cardNames.count)")
        }
        B04QA.log("AK-06|verlauf=\(verlauf)")
        XCTAssertEqual(verlauf, ["G=1", "Ga=1", "Gam=1", "Gamma S=1"])

        XCTAssertTrue(w.type("alpha", wait: 0.8))
        B04QA.log("AK-06|alpha=\(w.cardNames)")
        XCTAssertEqual(w.cardNames, ["Alpha, Nachrichten"], "nur die geöffnete Playlist")

        // Gruppe und tvg-ID werden nicht durchsucht
        XCTAssertTrue(w.type("Nachrichten", wait: 0.8))
        let gruppeTreffer = w.cardNames
        XCTAssertTrue(w.type("zeta", wait: 0.8))
        let tvgTreffer = w.cardNames
        B04QA.log("AK-06|gruppeAlsSuche=\(gruppeTreffer)|tvgIDAlsSuche=\(tvgTreffer)|texte=\(w.staticTexts.suffix(2))")
        XCTAssertEqual(gruppeTreffer.count, 0, "Gruppenname findet nichts")
        XCTAssertEqual(tvgTreffer.count, 0, "tvg-ID findet nichts")

        // Sport kommt in Name und Gruppe vor: nur der Name zählt
        XCTAssertTrue(w.type("Sport", wait: 0.8))
        B04QA.log("AK-06|sport=\(w.cardNames)")
        XCTAssertEqual(w.cardNames, ["Gamma Sport, News"])
    }

    // MARK: - AK-07 (Datenebene)

    func testAK07_SucheSemantikUeber41NamenUnd46Begriffe() throws {
        let (c, pl, _) = try semantikPlaylist("ak07")
        let ctx = c.mainContext
        var begriffe = ["", "ard", "ARD", "Ard", "münchen", "munchen", "MUNCHEN", "muenchen", "strasse", "straße",
                        "STRASSE", "ecran", "ÉCRAN", " ard", "ard ", " ", "  ", "%", "_", "*", "?", "\\", "'", "\"",
                        "ＡＲＤ", "istanbul", "İstanbul", "ελλ", "ΕΛΛ", "первый", "😀", "fi", "ﬁ", "film", "oe", "œ",
                        "ø", "o", "lodz", "łódź", "10", "sport 2", "sport  2", "#", "hits", "zdf"]
        begriffe.append(String(repeating: "a", count: 10_000))
        var protokoll: [String] = []
        var treffer: [String: [String]] = [:]
        for b in begriffe {
            let namen = B04QA.results(ctx, pl.id, b)
            treffer[b] = namen
            let label = b.count > 40 ? "<\(b.count) Zeichen>" : b.debugDescription
            protokoll.append("\(label) → \(namen.count): \(namen.prefix(6).map { $0.debugDescription }.joined(separator: ", "))")
        }
        for p in protokoll { B04QA.log("AK-07|\(p)") }
        B04QA.evidence("AK-07-suchmatrix.txt", "41 Namen, \(begriffe.count) Begriffe\n" + protokoll.joined(separator: "\n"))

        // (a) Groß-/Kleinschreibung
        for b in ["ard", "ARD", "Ard"] {
            XCTAssertEqual(Set(treffer[b] ?? []), ["ARD", "ard alpha", "ＡＲＤ Fullwidth"], b)
        }
        // (b) Akzente, Umlaute, punktloses i
        for b in ["münchen", "munchen", "MUNCHEN"] {
            XCTAssertEqual(Set(treffer[b] ?? []), ["BR München HD", "MÜNCHEN TV"], b)
        }
        for b in ["ecran", "ÉCRAN"] { XCTAssertEqual(Set(treffer[b] ?? []), ["ecran basic", "Écran Plus"], b) }
        for b in ["istanbul", "İstanbul"] { XCTAssertEqual(Set(treffer[b] ?? []), ["istanbul 2", "İstanbul TV"], b) }
        // (c) ß = ss
        for b in ["strasse", "straße", "STRASSE"] {
            XCTAssertEqual(Set(treffer[b] ?? []), ["Strasse 2", "Straße TV"], b)
        }
        // (d) Ligatur und Vollbreite
        for b in ["fi", "ﬁ", "film"] { XCTAssertEqual(Set(treffer[b] ?? []), ["ﬁlm ligature", "film normal"], b) }
        XCTAssertEqual(Set(treffer["ＡＲＤ"] ?? []), ["ARD", "ard alpha", "ＡＲＤ Fullwidth"])
        // (e) Umschreibungen und eigene Buchstaben bleiben verschieden
        XCTAssertEqual(treffer["muenchen"], [])
        XCTAssertEqual(treffer["oe"], ["oeuvre"])
        XCTAssertEqual(treffer["œ"], ["Œuvre"])
        XCTAssertEqual(treffer["lodz"], ["lodz tv"])
        XCTAssertEqual(treffer["łódź"], ["Łódź TV"])
        XCTAssertFalse((treffer["o"] ?? []).contains("Ølstrup"), "„o“ findet „Ølstrup“ nicht (eigener Buchstabe)")
        XCTAssertTrue((treffer["o"] ?? []).contains("Łódź TV"), "„o“ findet „Łódź TV“ (ó ist ein o mit Akzent)")
        // (f) Griechisch, Kyrillisch
        for b in ["ελλ", "ΕΛΛ"] { XCTAssertEqual(treffer[b], ["Ελληνικά"], b) }
        XCTAssertEqual(treffer["первый"], ["Первый канал"])
        XCTAssertEqual(treffer["😀"], ["😀 Emoji TV"])
    }

    // MARK: - AK-07 (Gegenprobe in der echten Ansicht)

    func testAK07_SucheSemantikOberflaecheGegenSpiegel() throws {
        let (c, pl, _) = try semantikPlaylist("ak07ui")
        let ctx = c.mainContext
        let w = window(c, size: CGSize(width: 900, height: 900))
        w.open(pl, wait: 2.0)
        let begriffe = ["ard", "ＡＲＤ", "munchen", "MUNCHEN", "strasse", "straße", "ecran", "istanbul", "ΕΛΛ",
                        "fi", "oe", "lodz", "muenchen", "sport 2"]
        var abweichungen: [String] = []
        for b in begriffe {
            XCTAssertTrue(w.type(b, wait: 0.7))
            let sichtbar = Set(w.cardNames.map { $0.split(separator: ",").first.map(String.init) ?? $0 })
            let spiegel = Set(B04QA.results(ctx, pl.id, b))
            B04QA.log("AK-07|ui|\(b.debugDescription)|sichtbar=\(sichtbar.sorted())|spiegel=\(spiegel.sorted())")
            if sichtbar != spiegel { abweichungen.append("\(b): sichtbar \(sichtbar.sorted()) ≠ Spiegel \(spiegel.sorted())") }
        }
        XCTAssertEqual(abweichungen, [], "echte Ansicht und Spiegel der Abfrage stimmen überein")
    }

    // MARK: - AK-08

    func testAK08_SuchtextWirdWoertlichGenommen() throws {
        let (c, pl, _) = try semantikPlaylist("ak08")
        let ctx = c.mainContext
        let w = window(c, size: CGSize(width: 900, height: 900))
        w.open(pl, wait: 2.0)

        func sichtbar(_ text: String) -> [String] {
            XCTAssertTrue(w.type(text, wait: 0.7))
            return w.cardNames
        }

        // (a) Leerzeichen am Rand bleiben stehen
        let vorn = sichtbar(" ard")
        let hinten = sichtbar("ard ")
        let nurLeerzeichen = B04QA.results(ctx, pl.id, " ")
        B04QA.log("AK-08|a| ard=\(vorn)|ard =\(hinten)|einLeerzeichen=\(nurLeerzeichen.count)")
        XCTAssertEqual(vorn, [], "„ ard“ findet nichts")
        XCTAssertEqual(Set(hinten), ["ard alpha", "ＡＲＤ Fullwidth"], "„ard “ nur mit folgendem Leerzeichen")
        XCTAssertEqual(nurLeerzeichen.count, Self.namen.filter { $0.contains(" ") }.count, "ein Leerzeichen findet jeden Namen mit Leerzeichen")

        // (b) keine Platzhalter
        for (zeichen, erwartet) in [("%", "100% Hits"), ("_", "under_score"), ("*", "Stern*Kanal"),
                                    ("?", "Frage?TV"), ("\\", "Back\\slash"), ("'", "O'Reilly TV"),
                                    ("\"", "Quote \"TV\"")] {
            let t = sichtbar(zeichen)
            B04QA.log("AK-08|b|\(zeichen.debugDescription)=\(t)")
            XCTAssertEqual(t.count, 1, "„\(zeichen)“ ist kein Platzhalter")
            XCTAssertTrue(t.first?.hasPrefix(erwartet) ?? false, "„\(zeichen)“ → \(erwartet)")
        }

        // (c) doppelte Leerzeichen zählen
        let einfach = sichtbar("sport 2")
        let doppelt = sichtbar("sport  2")
        B04QA.log("AK-08|c|sport 2=\(einfach)|sport  2=\(doppelt)")
        XCTAssertEqual(einfach, ["Sport 2"])
        XCTAssertEqual(doppelt, ["Sport  2"])

        // (d) 10.000 Zeichen
        let lang = sichtbar(String(repeating: "a", count: 10_000))
        B04QA.log("AK-08|d|10000Zeichen=\(lang.count)|texte=\(w.staticTexts.suffix(2))")
        XCTAssertEqual(lang, [], "kein Treffer, kein Fehler")
        XCTAssertTrue(w.staticTexts.contains { $0.hasPrefix("No Results") }, "Suchansicht erscheint")
    }

    // MARK: - AK-09

    func testAK09_SortierungNachNamenSprachgerechtAberOhneZahlen() throws {
        let (c, pl, _) = try semantikPlaylist("ak09")
        let ctx = c.mainContext
        let reihenfolge = B04QA.results(ctx, pl.id)
        B04QA.log("AK-09|reihenfolge=\(reihenfolge.map { $0.debugDescription }.joined(separator: " "))")
        B04QA.evidence("AK-09-sortierung.txt", reihenfolge.joined(separator: " | "))
        XCTAssertEqual(reihenfolge, Self.erwarteteReihenfolge, "Reihenfolge wie in der Spec beschrieben")
        XCTAssertEqual(reihenfolge, Self.namen.sorted { $0.localizedCompare($1) == .orderedAscending },
                       "entspricht localizedCompare der Systemsprache")

        // Oberfläche: die ersten sichtbaren Karten in derselben Reihenfolge; mit Suche ebenso
        let w = window(c, size: CGSize(width: 900, height: 900))
        w.open(pl, wait: 2.0)
        let sichtbar = w.cardNames
        B04QA.log("AK-09|ui|erste=\(sichtbar)")
        XCTAssertEqual(Array(reihenfolge.prefix(sichtbar.count)), sichtbar)
        XCTAssertTrue(w.type("sport", wait: 0.8))
        B04QA.log("AK-09|ui|mitSuche=\(w.cardNames)")
        XCTAssertEqual(w.cardNames, ["Sport  2", "Sport 10", "Sport 2"], "auch mit Suche nach Namen sortiert")

        // Einzelne Merkmale der Reihenfolge
        func vor(_ a: String, _ b: String) -> Bool {
            (reihenfolge.firstIndex(of: a) ?? -1) < (reihenfolge.firstIndex(of: b) ?? -1)
        }
        XCTAssertTrue(vor(" Leerzeichen vorn", "#Hash TV"), "Leerzeichen zuerst")
        XCTAssertTrue(vor("😀 Emoji TV", "100% Hits"), "Emoji vor Ziffern")
        XCTAssertTrue(vor("3sat", "ARD"), "Ziffern vor Buchstaben")
        XCTAssertTrue(vor("Ärger TV", "arte"), "Umlaut beim Grundbuchstaben")
        XCTAssertTrue(vor("Zebra", "Ελληνικά") && vor("Ελληνικά", "Первый канал") && vor("Первый канал", "قناة الاولى"),
                      "Griechisch, Kyrillisch, Arabisch am Ende")

        // ⚠ Zahlen werden als Text sortiert (BUG-08, offene Frage OF-01)
        XCTExpectFailure("BUG-08 · Zahlen in Sendernamen werden als Text sortiert (OF-01)") {
            XCTAssertTrue(vor("Sport 2", "Sport 10"), "Sender-Nummern numerisch sortiert")
            XCTAssertTrue(vor("1LIVE", "100% Hits"), "1LIVE vor 100% Hits")
        }
    }
}
