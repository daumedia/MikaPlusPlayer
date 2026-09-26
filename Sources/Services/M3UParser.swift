import Foundation

/// Plattformunabhängiges, kontextfreies Ergebnis des Parsers.
/// Bewusst KEIN SwiftData-`@Model`, damit der Parser ohne `ModelContext`
/// testbar bleibt und nicht an einen Thread/Actor gebunden ist.
struct ParsedChannel: Equatable, Sendable {
    var name: String
    var streamURL: URL
    var logoURL: URL?
    var group: String?
    var tvgID: String?
}

/// Parser für M3U/M3U8-Playlists im Extended-M3U-Format.
///
/// Beispielzeile:
/// `#EXTINF:-1 tvg-id="ard.de" tvg-logo="http://logo.png" group-title="News",Das Erste, HD`
/// `http://example.com/stream.m3u8`
///
/// Wichtig: Der Anzeigename ist alles nach dem **ersten Komma außerhalb von
/// Anführungszeichen** – im Beispiel also `Das Erste, HD` (inkl. des zweiten Kommas).
///
/// Listen sind unvertraute Eingaben (B02 · BUG-03, BUG-05): Name, Gruppe und tvg-ID werden gekürzt,
/// überlange Adressen verworfen, und übernommen werden nur Stream-Adressen mit einem Wiedergabe-Schema
/// und Logo-Adressen über HTTP(S).
struct M3UParser: Sendable {
    struct Limits: Sendable {
        /// Längere Namen, Gruppen und tvg-IDs werden gekürzt (wie `XtreamClient.Limits`).
        var maxTextLength = 512
        /// Längere Stream-Adressen: Eintrag wird verworfen.
        var maxStreamURLLength = 4_096
        /// Längere Logo-Adressen werden verworfen (der Sender bleibt).
        var maxLogoURLLength = 2_048
        /// Höchstzahl Einträge; der Parser hört danach auf. `nil` = ohne Grenze (nur für Messungen).
        var maxChannels: Int?

        static let standard = Limits()
    }

    /// Schemata, die eine Wiedergabe-Engine (AVKit, VLCKit) als Stream öffnet. Alles andere (`file:`, `smb:`,
    /// `javascript:`, `data:`, `vlc:`, `ftp:` …) wird verworfen.
    static let streamSchemes: Set<String> = ["http", "https", "rtsp", "rtsps", "rtmp", "rtmps", "rtp", "udp", "mms", "mmsh"]
    /// Logos lädt die Senderliste nur über HTTP(S).
    static let logoSchemes: Set<String> = ["http", "https"]

    var limits: Limits = .standard

    func parse(_ text: String) -> [ParsedChannel] {
        var channels: [ParsedChannel] = []
        // Pending-Metadaten aus dem zuletzt gelesenen #EXTINF-Tag.
        var pending: PendingChannel?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            if let maximum = limits.maxChannels, channels.count > maximum { break }
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTINF:") {
                pending = parseExtInf(line)
            } else if line.hasPrefix("#") {
                // Andere Direktiven (#EXTM3U, #EXTGRP, #EXTVLCOPT, ...) ignorieren.
                // #EXTGRP kann eine Gruppe nachreichen, falls group-title fehlt.
                if line.hasPrefix("#EXTGRP:"), pending != nil, pending?.group == nil {
                    let grp = String(line.dropFirst("#EXTGRP:".count))
                        .trimmingCharacters(in: .whitespaces)
                    if !grp.isEmpty { pending?.group = grp }
                }
                continue
            } else {
                // URL-Zeile: schließt den zuletzt gelesenen #EXTINF-Eintrag ab.
                guard let meta = pending else { continue }
                pending = nil
                guard line.utf8.count <= limits.maxStreamURLLength,
                      let url = URL(string: line),
                      let scheme = url.scheme?.lowercased(), Self.streamSchemes.contains(scheme) else { continue }
                channels.append(
                    ParsedChannel(
                        name: clipped(meta.name.isEmpty ? url.lastPathComponent : meta.name),
                        streamURL: url,
                        logoURL: meta.logo.flatMap(logoURL),
                        group: meta.group.map(clipped),
                        tvgID: meta.tvgID.map(clipped)
                    )
                )
            }
        }
        return channels
    }

    private func clipped(_ text: String) -> String {
        text.count > limits.maxTextLength ? String(text.prefix(limits.maxTextLength)) : text
    }

    private func logoURL(_ raw: String) -> URL? {
        guard raw.utf8.count <= limits.maxLogoURLLength,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), Self.logoSchemes.contains(scheme) else { return nil }
        return url
    }

    // MARK: - #EXTINF-Zerlegung

    private struct PendingChannel {
        var name: String = ""
        var logo: String?
        var group: String?
        var tvgID: String?
    }

    /// Zerlegt eine #EXTINF-Zeile in Attribute + Anzeigename.
    private func parseExtInf(_ line: String) -> PendingChannel {
        var result = PendingChannel()

        // Body nach "#EXTINF:" (enthält Duration, Attribute, Komma, Name).
        let body = String(line.dropFirst("#EXTINF:".count))

        // 1) Anzeigename = alles nach dem ersten Komma AUSSERHALB von Quotes.
        if let commaIndex = firstUnquotedComma(in: body) {
            let attrPart = String(body[body.startIndex..<commaIndex])
            let namePart = String(body[body.index(after: commaIndex)...])
            result.name = namePart.trimmingCharacters(in: .whitespaces)
            applyAttributes(from: attrPart, to: &result)
        } else {
            // Kein Komma -> nur Attribute, kein Name.
            applyAttributes(from: body, to: &result)
        }

        return result
    }

    /// Findet den Index des ersten Kommas, das nicht innerhalb von "..." steht.
    private func firstUnquotedComma(in s: String) -> String.Index? {
        var insideQuotes = false
        var idx = s.startIndex
        while idx < s.endIndex {
            let ch = s[idx]
            if ch == "\"" {
                insideQuotes.toggle()
            } else if ch == ",", !insideQuotes {
                return idx
            }
            idx = s.index(after: idx)
        }
        return nil
    }

    /// Liest `key="value"`-Attribute aus dem Bereich vor dem Anzeigenamen.
    private func applyAttributes(from attrPart: String, to result: inout PendingChannel) {
        for (key, value) in keyValueAttributes(in: attrPart) {
            switch key.lowercased() {
            case "tvg-id":    result.tvgID = value.isEmpty ? nil : value
            case "tvg-logo":  result.logo = value.isEmpty ? nil : value
            case "group-title": result.group = value.isEmpty ? nil : value
            default: break
            }
        }
    }

    /// Extrahiert alle `key="value"`-Paare. Werte dürfen Kommas, Leerzeichen
    /// und Sonderzeichen enthalten – nur das schließende `"` beendet den Wert.
    private func keyValueAttributes(in s: String) -> [(String, String)] {
        var pairs: [(String, String)] = []
        let scalars = Array(s)
        var i = 0
        while i < scalars.count {
            // Key-Start suchen (Buchstabe, Ziffer oder '-').
            guard scalars[i].isLetter || scalars[i].isNumber else { i += 1; continue }
            let keyStart = i
            while i < scalars.count, isKeyChar(scalars[i]) { i += 1 }
            let key = String(scalars[keyStart..<i])

            // Optionaler Whitespace + '=' + '"'
            while i < scalars.count, scalars[i] == " " { i += 1 }
            guard i < scalars.count, scalars[i] == "=" else { continue }
            i += 1
            while i < scalars.count, scalars[i] == " " { i += 1 }
            guard i < scalars.count, scalars[i] == "\"" else { continue }
            i += 1 // öffnendes Quote überspringen

            let valStart = i
            while i < scalars.count, scalars[i] != "\"" { i += 1 }
            let value = String(scalars[valStart..<min(i, scalars.count)])
            if i < scalars.count { i += 1 } // schließendes Quote überspringen

            pairs.append((key, value))
        }
        return pairs
    }

    private func isKeyChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "-" || c == "_"
    }
}
