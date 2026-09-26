import SwiftUI
import SwiftData

/// Importiert Playlist-Dateien, die das System der App übergibt (B02 · BUG-06): „Öffnen mit" und Doppelklick
/// unter macOS, „Öffnen in"/Teilen unter iOS. Derselbe Weg wie der Datei-Reiter des Import-Sheets
/// (`PlaylistImporter.importFromFile`: Größengrenze, Hintergrund, keine Kopie der Datei).
///
/// Die Datei wird an Ort und Stelle gelesen (`LSSupportsOpeningDocumentsInPlace = YES`, iOS mit security-scoped
/// Zugriff). Legt iOS doch eine Kopie in `Documents/Inbox` ab (ältere Wege wie „Kopieren nach …"), wird diese nach dem
/// Import entfernt, damit keine Liste doppelt auf dem Gerät bleibt.
private struct PlaylistDocumentHandler: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                guard url.isFileURL else { return }
                importFile(url)
            }
            .alert("Import fehlgeschlagen", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func importFile(_ url: URL) {
        let importer = PlaylistImporter(modelContext: modelContext)
        Task {
            defer { Self.removeInboxCopy(url) }
            do {
                try await importer.importFromFile(url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Entfernt nur Kopien im eigenen `Documents/Inbox` (iOS), nie die Datei des Nutzers.
    private static func removeInboxCopy(_ url: URL) {
        #if os(iOS)
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true).standardizedFileURL.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(inbox) else { return }
        try? FileManager.default.removeItem(at: url)
        #endif
    }
}

extension View {
    func playlistDocumentHandler() -> some View {
        modifier(PlaylistDocumentHandler())
    }
}
