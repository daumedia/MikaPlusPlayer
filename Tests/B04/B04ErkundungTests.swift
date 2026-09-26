import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B04 · Erkundung des Fensteraufbaus (Accessibility-Baum, Suchfeld, Ladeindikatoren). Schreibt nur Protokollzeilen;
/// Grundlage für die Hilfen in `B04Support.swift`.
final class B04ErkundungTests: B04TestCase {

    func testErkundung_AccessibilityBaumDerSenderliste() throws {
        let (c, _) = try fileContainer("erkundung")
        let ctx = c.mainContext
        let pl = try B04QA.seed(ctx, name: "QA Erkundung", items: [
            .init("Alpha Eins", "Sport", logo: "\(host.base)/nocache/a.png"),
            .init("Beta Zwei", " Sport", logo: "\(host.base)/404/b.png"),
            .init("Gamma Drei", "News"),
            .init("Delta Vier", nil, logo: "\(host.base)/hang/d.png"),
        ])
        let w = window(c)
        B04QA.log("ERK|vorPush|\(w.sizeText)")
        w.open(pl, wait: 3)
        B04QA.log("ERK|nachPush|\(w.sizeText)|titel=\(w.window.title)|toolbarItems=\(w.window.toolbar?.items.map { "\(type(of: $0)):\($0.itemIdentifier.rawValue)" } ?? [])")
        B04QA.log("ERK|suchfeld=\(w.searchField.map { "\($0.placeholderString ?? "-")" } ?? "nil")|spinner=\(w.spinnerCount)")
        let lines = B04AX.describe(w.hosting)
        for l in lines { B04QA.log("ERK|AX|\(l)") }
        B04QA.log("ERK|chips=\(w.chips.map(\.title))|karten=\(w.cardNames)|kopf=\(w.header ?? "-")")
        B04QA.log("ERK|views=\(Set(B04AX.views(w.hosting, of: NSView.self).map { String(describing: type(of: $0)) }).sorted())")
        w.shot("erkundung-01")
        XCTAssertTrue(w.pressChip("Sport"))
        B04QA.log("ERK|nachSport|karten=\(w.cardNames)|busy=\(w.busyRows)|chips=\(w.chips.map { "\($0.title)" })")
        _ = w.type("gamma")
        B04QA.log("ERK|nachSuche|karten=\(w.cardNames)|texte=\(w.staticTexts)")
        w.shot("erkundung-02")
        B04QA.log("ERK|anfragen=\(host.requests.map(\.target))")
    }
}
