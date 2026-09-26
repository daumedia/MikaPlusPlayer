import XCTest
import SwiftData
import UniformTypeIdentifiers
import Darwin
@testable import MikaPlusPlayer

/// B02 · M3U-Import — Import aus einer Datei über den echten Pfad (`PlaylistImporter.importFromFile`).
/// AK-16 … AK-19, AK-25 (Datei), EC-07 … EC-09, EC-19. Nur Dateien in eigenen Temp-Ordnern.
final class B02DateiImportTests: B02TestCase {

    // MARK: AK-16

    /// AK-16: lesbare Datei → Playlist ohne Quelladresse und ohne Aktualisierungszeitpunkt; Name = Dateiname ohne letzte
    /// Endung, eingegebener Name exakt.
    @MainActor func testAK16_DateiImportNameUndOhneQuelladresse() async throws {
        let c = try B02.memory()
        let dir = try tempDir("ak16")
        let cases: [(file: String, name: String?, expected: String)] = [
            ("liste.v2.m3u", nil, "liste.v2"),
            ("Sender & Ümlaut (Kopie).M3U8", nil, "Sender & Ümlaut (Kopie)"),
            (".m3u", nil, ".m3u"),
            (".versteckt.m3u", nil, ".versteckt"),
            ("liste.m3u", "   ", "   "),
            ("liste.m3u", "  Eigener Name  ", "  Eigener Name  ")
        ]
        for tc in cases {
            let url = dir.appendingPathComponent(tc.file)
            try B02.zweiSenderData.write(to: url)
            let p = try await B02.importFile(url, name: tc.name, c.mainContext).get()
            B02.log("AK-16|datei=\(tc.file.debugDescription)|eingabe=\(tc.name?.debugDescription ?? "nil")|\(B02.describe(p))")
            XCTAssertEqual(p.name, tc.expected, tc.file)
            XCTAssertNil(p.sourceURL)
            XCTAssertNil(p.lastRefreshed)
            XCTAssertFalse(p.isRemote)
            XCTAssertEqual(p.channelCount, 2)
        }
    }

    // MARK: AK-17

    /// AK-17: der Inhalt entscheidet, nicht die Endung; `.txt` ohne `#EXTINF` → „keine gültigen Sender".
    @MainActor func testAK17_InhaltStattEndung() async throws {
        let c = try B02.memory()
        let dir = try tempDir("ak17")
        for file in ["liste.txt", "daten.csv", "quelltext.swift", "bild.png", "ohne-endung", "liste.json"] {
            let url = dir.appendingPathComponent(file)
            try B02.zweiSenderData.write(to: url)
            let r = await B02.importFile(url, c.mainContext)
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier) ?? "-"
            B02.log("AK-17|\(file)|typ=\(type)|ergebnis=\(B02.message(r) ?? "OK")|sender=\((try? r.get())?.channelCount ?? 0)")
            XCTAssertNil(B02.message(r), file)
        }
        let notes = dir.appendingPathComponent("notizen.txt")
        try Data("Einkaufsliste\nhttp://example.invalid/a.ts\n".utf8).write(to: notes)
        let r = await B02.importFile(notes, c.mainContext)
        XCTAssertEqual(B02.message(r), "Die Playlist enthält keine gültigen Sender.")
    }

    // MARK: AK-18 / EC-19

    /// AK-18: nicht lesbare Dateien → „Auf die ausgewählte Datei kann nicht zugegriffen werden."; Symlink (auch Kette) auf
    /// lesbare Datei wird gelesen, Name vom Symlink. EC-19: Named Pipe mit spätem Schreiber → sofort Meldung, keine Blockade.
    @MainActor func testAK18_EC19_NichtLesbareDateienUndSymlinks() async throws {
        let c = try B02.memory()
        let dir = try tempDir("ak18")
        let fm = FileManager.default
        let denied = "Auf die ausgewählte Datei kann nicht zugegriffen werden."

        let ok = dir.appendingPathComponent("ziel.m3u"); try B02.zweiSenderData.write(to: ok)
        let noRead = dir.appendingPathComponent("rechte-000.m3u"); try B02.zweiSenderData.write(to: noRead)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: noRead.path)
        let lockedDir = dir.appendingPathComponent("ordner-000", isDirectory: true)
        try fm.createDirectory(at: lockedDir, withIntermediateDirectories: true)
        let inLocked = lockedDir.appendingPathComponent("drin.m3u"); try B02.zweiSenderData.write(to: inLocked)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedDir.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDir.path)
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: noRead.path)
        }
        let deleted = dir.appendingPathComponent("geloescht.m3u"); try B02.zweiSenderData.write(to: deleted); try fm.removeItem(at: deleted)
        let folder = dir.appendingPathComponent("ordner.m3u", isDirectory: true); try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let dangling = dir.appendingPathComponent("ins-leere.m3u"); try fm.createSymbolicLink(atPath: dangling.path, withDestinationPath: dir.appendingPathComponent("gibt-es-nicht.m3u").path)
        let link = dir.appendingPathComponent("verweis.m3u"); try fm.createSymbolicLink(atPath: link.path, withDestinationPath: ok.path)
        let chain = dir.appendingPathComponent("kette.m3u"); try fm.createSymbolicLink(atPath: chain.path, withDestinationPath: link.path)

        for (label, url) in [("Rechte 000", noRead), ("Ordner 000", inLocked), ("gelöscht", deleted), ("Ordner", folder), ("Symlink ins Leere", dangling)] {
            let r = await B02.importFile(url, c.mainContext)
            B02.log("AK-18|\(label)|meldung=\(B02.message(r) ?? "OK")")
            XCTAssertEqual(B02.message(r), denied, label)
        }
        for (label, url, name) in [("Symlink", link, "verweis"), ("Symlink-Kette", chain, "kette")] {
            let r = await B02.importFile(url, c.mainContext)
            B02.log("AK-18|\(label)|ergebnis=\(B02.message(r) ?? "OK")|name=\((try? r.get())?.name ?? "-")")
            XCTAssertEqual((try? r.get())?.name, name, label)
        }

        // EC-19: Named Pipe; ein Schreiber öffnet sie erst nach 3 s (damit der Test nie endlos hängt)
        let fifo = dir.appendingPathComponent("pipe.m3u")
        XCTAssertEqual(mkfifo(fifo.path, 0o644), 0)
        let writer = Thread {
            Thread.sleep(forTimeInterval: 3)
            let fd = open(fifo.path, O_WRONLY | O_NONBLOCK)
            if fd >= 0 { _ = B02.zweiSender.withCString { write(fd, $0, strlen($0)) }; close(fd) }
        }
        writer.start()
        let watchdog = MainThreadWatchdog(); watchdog.start()
        let t = Date()
        let r = await B02.importFile(fifo, c.mainContext)
        let elapsed = Date().timeIntervalSince(t)
        try await Task.sleep(nanoseconds: 200_000_000)
        let gap = watchdog.stop()
        B02.log("EC-19|namedPipe|meldung=\(B02.message(r) ?? "OK")|dauer=\(B02.f2(elapsed))s|maxMainThreadBlockade=\(B02.f2(gap))s")
        XCTAssertEqual(B02.message(r), denied)
        XCTAssertLessThan(elapsed, 2)
        XCTAssertEqual(B02.count(Playlist.self, c.mainContext), 2)
    }

    // MARK: AK-19 (macOS-Anteil)

    /// AK-19 (macOS-Anteil): Eine security-scoped Adresse (Lesezeichen mit `.withSecurityScope`) wird gelesen; Zugriff
    /// lässt sich danach erneut anfordern. Der iOS-Teil (Dateien-Dialog außerhalb des Containers) ist hier nicht ausführbar.
    @MainActor func testAK19_SecurityScopedAdresseMacOS() async throws {
        let c = try B02.memory()
        let dir = try tempDir("ak19")
        let file = dir.appendingPathComponent("scope.m3u")
        try B02.zweiSenderData.write(to: file)
        let bookmark = try file.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        var stale = false
        let scoped = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        let p = try await B02.importFile(scoped, c.mainContext).get()
        let again = scoped.startAccessingSecurityScopedResource()
        if again { scoped.stopAccessingSecurityScopedResource() }
        let sandbox = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] ?? "nil"
        B02.log("AK-19|macOS|name=\(p.name)|sender=\(p.channelCount)|startAccessingNachImport=\(again)|sandbox=\(sandbox)")
        XCTAssertEqual(p.channelCount, 2)
    }

    // MARK: AK-25 / EC-07 … EC-09 (Datei)

    /// AK-25: UTF-8 mit/ohne BOM und Latin-1 werden richtig gelesen. EC-07: ein ungültiges Byte kippt die ganze Datei nach
    /// Latin-1. EC-08: Windows-1252 `…`/`€`. EC-09: UTF-16 mit BOM → „keine gültigen Sender".
    @MainActor func testAK25_EC07_EC08_EC09_KodierungUeberDatei() async throws {
        let c = try B02.memory()
        let dir = try tempDir("ak25")
        let text = "#EXTM3U\n#EXTINF:-1 group-title=\"Österreich\",ORF Eins Ä\nhttp://h/a.ts\n"
        func write(_ name: String, _ data: Data) throws -> URL {
            let u = dir.appendingPathComponent(name); try data.write(to: u); return u
        }
        func scalars(_ s: String) -> String { s.unicodeScalars.filter { $0.value > 0x7E || $0.value < 0x20 }.map { String(format: "U+%04X", $0.value) }.joined(separator: ",") }

        for (label, data) in [
            ("utf8", Data(text.utf8)),
            ("utf8-bom", Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)),
            ("utf8-bom-direkt-extinf", Data([0xEF, 0xBB, 0xBF]) + Data("#EXTINF:-1 group-title=\"Österreich\",ORF Eins Ä\nhttp://h/a.ts\n".utf8)),
            ("latin1", try XCTUnwrap(text.data(using: .isoLatin1)))
        ] {
            let p = try await B02.importFile(try write(label + ".m3u", data), c.mainContext).get()
            let ch = try XCTUnwrap(p.channels.first)
            B02.log("AK-25|datei|\(label)|name=\(ch.name.debugDescription)|gruppe=\(ch.group ?? "nil")|skalare=\(scalars(ch.name))")
            XCTAssertEqual(ch.name, "ORF Eins Ä", label)
            XCTAssertEqual(ch.group, "Österreich", label)
        }

        // EC-07: überwiegend UTF-8, ein ungültiges Byte
        var mixed = Data("#EXTINF:-1 group-title=\"Österreich\",Ärger TV\nhttp://h/a.ts\n#EXTINF:-1,Kaputt ".utf8)
        mixed.append(0xFF)
        mixed.append(Data("\nhttp://h/b.ts\n".utf8))
        let p7 = try await B02.importFile(try write("ec07.m3u", mixed), c.mainContext).get()
        let aerger = try XCTUnwrap(p7.channels.first { $0.streamURL.absoluteString.hasSuffix("a.ts") })
        B02.log("EC-07|name=\(aerger.name.debugDescription)|skalare=\(scalars(aerger.name))|gruppe=\(aerger.group ?? "nil")")
        XCTAssertEqual(aerger.name, "Ã\u{84}rger TV")
        XCTAssertEqual(aerger.group, "Ã\u{96}sterreich")

        // EC-08: Windows-1252 — 0x85 (…) wird U+0085 (Zeilentrenner), 0x80 (€) wird U+0080
        var cp1252 = Data("#EXTINF:-1,Mehr".utf8); cp1252.append(0x85); cp1252.append(Data("Sender\nhttp://h/a.ts\n#EXTINF:-1,Preis ".utf8))
        cp1252.append(0x80); cp1252.append(Data(" TV\nhttp://h/b.ts\n".utf8))
        let r8 = await B02.importFile(try write("ec08.m3u", cp1252), c.mainContext)
        let p8 = try r8.get()
        B02.log("EC-08|sender=\(p8.channels.map { $0.name.debugDescription })|skalare=\(p8.channels.map { scalars($0.name) })")
        XCTAssertEqual(p8.channelCount, 1, "Sender mit … geht verloren")
        XCTAssertEqual(p8.channels.first?.name, "Preis \u{80} TV")

        // EC-09: UTF-16 mit BOM (LE und BE)
        for (label, enc) in [("utf16le", String.Encoding.utf16LittleEndian), ("utf16be", String.Encoding.utf16BigEndian)] {
            var d = Data(enc == .utf16LittleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF])
            d.append(try XCTUnwrap(text.data(using: enc)))
            let r = await B02.importFile(try write(label + ".m3u", d), c.mainContext)
            B02.log("EC-09|\(label)|bytes=\(d.count)|meldung=\(B02.message(r) ?? "OK")")
            XCTAssertEqual(B02.message(r), "Die Playlist enthält keine gültigen Sender.", label)
        }
    }

    /// EC-09 über URL: UTF-16 mit `charset=utf-16` in der Antwort → „keine gültigen Sender".
    @MainActor func testEC09_UTF16UeberURL() async throws {
        let c = try B02.memory()
        var d = Data([0xFF, 0xFE])
        d.append(try XCTUnwrap(B02.zweiSender.data(using: .utf16LittleEndian)))
        let body = d
        server.handler = { _ in B02Server.ok(body, type: "audio/x-mpegurl; charset=utf-16") }
        let r = await B02.importURL(server.url("/utf16.m3u"), c.mainContext)
        B02.log("EC-09|url|meldung=\(B02.message(r) ?? "OK")")
        XCTAssertEqual(B02.message(r), "Die Playlist enthält keine gültigen Sender.")
    }

    // MARK: EC-10 (Datei)

    /// EC-10: relative Adressen in einer lokalen Datei, neben der die Stream-Datei tatsächlich liegt → trotzdem verworfen.
    @MainActor func testEC10_RelativeAdresseNebenDerDatei() async throws {
        let c = try B02.memory()
        let dir = try tempDir("ec10")
        try Data("x".utf8).write(to: dir.appendingPathComponent("stream.ts"))
        let url = dir.appendingPathComponent("relativ.m3u")
        try Data("#EXTINF:-1,Relativ\nstream.ts\n#EXTINF:-1,Absolut\n\(dir.appendingPathComponent("stream.ts").absoluteString)\n".utf8).write(to: url)
        let p = try await B02.importFile(url, c.mainContext).get()
        B02.log("EC-10|datei|\(B02.describe(p))")
        XCTAssertEqual(p.channels.map(\.name), ["Absolut"])
    }
}
