import Foundation

/// B09 · OF-01 (2026-10-01): Die App deklariert sich als deutschsprachig (Entwicklungssprache `de`,
/// `CFBundleLocalizations [de]`). Texte, die vom System kommen – Fehlermeldungen von Foundation/URLSession,
/// Bedienungshilfe-Namen von Symbolen und Systemansichten, Systemmenüs –, erscheinen seitdem deutsch.
///
/// Tests nehmen den englischen **oder** den deutschen Wortlaut an (Muster aus `B04NacharbeitTests`). Die deutschen
/// Fassungen sind am Test-Host beobachtet (Bau B09 Durchlauf 2, 2026-10-02), nicht erfunden.
enum SystemSprache {
    /// Systemtexte englisch → deutsch, wie sie unter `de` erscheinen.
    static let deutsch: [String: String] = [
        // Foundation / URLSession (NSURLErrorDomain)
        "Could not connect to the server.": "Verbindung zum Server konnte nicht hergestellt werden.",
        "A server with the specified hostname could not be found.": "Es wurde kein Server mit dem angegebenen Hostnamen gefunden.",
        "The request timed out.": "Zeitüberschreitung bei der Anforderung.",
        "too many HTTP redirects": "Zu viele HTTP-Umleitungen",
        "You do not have permission to access the requested resource.": "Du bist nicht berechtigt, auf die angeforderte Ressource zuzugreifen.",
        "unsupported URL": "URL nicht unterstützt",
        "unknown error": "Unbekannter Fehler",
        "The requested URL was not found on this server.": "Die angeforderte URL wurde auf diesem Server nicht gefunden.",
        "The operation couldn’t be completed. (NSURLErrorDomain error -1013.)": "Der Vorgang konnte nicht abgeschlossen werden. (NSURLErrorDomain-Fehler -1013.)",
        // Foundation (NSCocoaErrorDomain), AVFoundation
        "The data couldn’t be read because it isn’t in the correct format.": "Die Daten konnten nicht gelesen werden, da sie nicht das korrekte Format haben.",
        "Operation Stopped": "Vorgang gestoppt",
        "The operation couldn’t be completed. (CoreMediaErrorDomain error -12646.)": "Der Vorgang konnte nicht abgeschlossen werden. (CoreMediaErrorDomain-Fehler -12646.)",
        // SwiftUI ContentUnavailableView.search
        "Check the spelling or try a new search.": "Überprüfe die Schreibweise oder starte eine neue Suche.",
    ]

    /// Kurze Namen (Bedienungshilfe-Namen von SF-Symbolen, Systemmenüs) englisch → deutsch. Nur als ganzer Name
    /// vergleichen, nie als Teilzeichenkette („Laut“ steckt in „Lautstärke“).
    static let namen: [String: String] = [
        "Add": "Hinzufügen",                                         // plus
        "Rectangle Split Two By Two": "In Zwei Mal Zwei Geteiltes Rechteck", // rectangle.split.2x2
        "Volume High": "Laut",                                       // speaker.wave.2.fill
        "Mute": "Ton Aus",                                           // speaker.slash.fill
        "Window": "Fenster",                                         // Menü „Fenster“
    ]

    /// Englischer Name zu einem (englischen oder deutschen) Bedienungshilfe-Namen; unbekannte Namen unverändert.
    static func englischerName(_ name: String) -> String {
        namen.first { $0.value == name }?.key ?? name
    }

    /// Englischer und deutscher Bedienungshilfe-Name.
    static func namensVarianten(_ englisch: String) -> [String] {
        [englisch] + (namen[englisch].map { [$0] } ?? [])
    }

    /// Leerzustand der Suche (`ContentUnavailableView.search`): „No Results for “x”“ bzw. „Keine Ergebnisse für „x““.
    static func istSuchLeerzustand(_ text: String, suchtext: String? = nil) -> Bool {
        guard let suchtext else { return text.hasPrefix("No Results") || text.hasPrefix("Keine Ergebnisse") }
        return text == "No Results for “\(suchtext)”" || text == "Keine Ergebnisse für „\(suchtext)“"
    }

    /// Ersetzt bekannte deutsche Systemtexte durch die englischen, damit Vergleiche mit dem (englisch formulierten)
    /// Erwartungswert in beiden Sprachen gelten.
    static func englisch(_ text: String) -> String {
        var result = text
        for (en, de) in deutsch where result.contains(de) {
            result = result.replacingOccurrences(of: de, with: en)
        }
        return result
    }

    static func englisch(_ text: String?) -> String? {
        text.map { englisch($0) }
    }

    /// Englischer und deutscher Wortlaut eines Systemtexts (für `contains`-Prüfungen und Suchen nach Namen).
    static func varianten(_ englisch: String) -> [String] {
        [englisch] + (deutsch[englisch].map { [$0] } ?? [])
    }
}
