#if os(macOS)
import SwiftUI

/// Die Update-Einträge im App-Menü, direkt nach „Über Mika+Player“ (B09 · AK-01, AK-31).
///
/// Eigene Ansicht statt Inhalt im Menü-Block der App (B09 · BF-18, Entwurf Entscheidung 6): SwiftUI bildet
/// Abhängigkeiten nur für den Rumpf einer Ansicht; der Rumpf der App wurde für das Menü nicht zuverlässig neu
/// ausgewertet, der Eintrag konnte veralten. Deshalb liest diese Ansicht den Zustand in ihrem eigenen Rumpf.
/// Die Schalter zeigen nur Sparkles Werte und schreiben sie auf Klick (Entscheidung 7).
struct UpdateMenu: View {
    let updater: SparkleUpdater

    var body: some View {
        let state = updater.menuState
        Button("Nach Updates suchen …") {
            updater.checkForUpdates()
        }
        .disabled(!state.checkEnabled)
        Toggle("Automatisch nach Updates suchen", isOn: Binding(
            get: { state.automaticChecksOn },
            set: { updater.setAutomaticallyChecksForUpdates($0) }))
        .disabled(!state.automaticChecksEnabled)
        // Ohne automatische Prüfung wirkt automatisches Installieren nicht: ausgegraut ohne Häkchen; der gespeicherte
        // Wert kehrt zurück, sobald die Prüfung wieder an ist (design.md, OF-12).
        Toggle("Updates automatisch installieren", isOn: Binding(
            get: { state.automaticDownloadsOn },
            set: { updater.setAutomaticallyDownloadsUpdates($0) }))
        .disabled(!state.automaticDownloadsEnabled)
    }
}
#endif
