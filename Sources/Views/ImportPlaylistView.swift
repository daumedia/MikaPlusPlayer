import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Sheet zum Importieren einer Playlist per Xtream-Codes-Login, URL oder
/// lokaler Datei.
struct ImportPlaylistView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum Source: String, CaseIterable, Identifiable {
        case xtream = "Xtream"
        case url = "URL"
        case file = "Datei"
        var id: String { rawValue }
    }

    @State private var source: Source = .xtream
    @State private var urlString = ""
    @State private var name = ""
    @State private var isImporting = false
    @State private var showingFileImporter = false
    @State private var errorMessage: String?
    /// Laufender Import (alle Reiter); „Abbrechen" und das Schließen des Sheets brechen ihn ab
    /// (B01 · BUG-11, B02 · BUG-08).
    @State private var importTask: Task<Void, Never>?

    // Xtream-Codes-Felder
    @State private var xtreamHost = ""
    @State private var xtreamUser = ""
    @State private var xtreamPassword = ""
    // MPEG-TS als Standard: viele Panels (z. B. Telecasty) blockieren den
    // HLS-Endpunkt (HTTP 407) und liefern nur rohes .ts (-> VLCKit nötig).
    @State private var xtreamOutput: XtreamOutput = .mpegts

    /// Erlaubte Dateitypen für den fileImporter (.m3u/.m3u8; Inhalt entscheidet, nicht die Endung).
    private var allowedTypes: [UTType] {
        var types: [UTType] = []
        if let m3u = UTType(filenameExtension: "m3u") { types.append(m3u) }
        if let m3u8 = UTType(filenameExtension: "m3u8") { types.append(m3u8) }
        types.append(.plainText)
        return types
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Quelle", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Section("Name (optional)") {
                    TextField("z. B. Mein IPTV-Anbieter", text: $name)
                }

                switch source {
                case .xtream:
                    Section {
                        TextField("Host (z. B. http://dein-anbieter.tld)", text: $xtreamHost)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                            .autocorrectionDisabled()
                        TextField("Benutzername", text: $xtreamUser)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                        SecureField("Passwort", text: $xtreamPassword)
                    } header: {
                        Text("Xtream-Codes-Zugang")
                    } footer: {
                        // B01 · BUG-02: ohne https gehen die Zugangsdaten im Klartext übers Netz.
                        if !xtreamCredentials.usesHTTPS {
                            Text("Ohne „https://“ gehen Benutzername und Passwort unverschlüsselt über das Netz.")
                        }
                    }
                    Section {
                        Picker("Format", selection: $xtreamOutput) {
                            ForEach(XtreamOutput.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Stream-Format")
                    } footer: {
                        Text(xtreamOutput.hint)
                    }
                    Section {
                        Button {
                            startXtreamImport()
                        } label: {
                            Label("Anmelden & importieren", systemImage: "person.badge.key")
                        }
                        .disabled(!xtreamCredentials.isComplete || isImporting)
                    }
                case .url:
                    Section("Playlist-URL") {
                        TextField("https://… .m3u8", text: $urlString)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                            .autocorrectionDisabled()
                        Button {
                            startURLImport()
                        } label: {
                            Label("Von URL importieren", systemImage: "arrow.down.circle")
                        }
                        .disabled(urlString.isEmpty || isImporting)
                    }
                case .file:
                    Section("Lokale Datei") {
                        Button {
                            showingFileImporter = true
                        } label: {
                            Label("Datei auswählen (.m3u/.m3u8)", systemImage: "folder")
                        }
                        .disabled(isImporting)
                    }
                }

                if isImporting {
                    HStack {
                        ProgressView()
                        Text("Importiere…").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Playlist importieren")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        importTask?.cancel()
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: allowedTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileResult(result)
            }
            .alert("Fehler", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(.playerAccent)
        // iOS: auch Wegwischen des Sheets bricht einen laufenden Import ab (B01 · BUG-11, B02 · BUG-08).
        .onDisappear { importTask?.cancel() }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    // MARK: - Aktionen

    private var xtreamCredentials: XtreamCredentials {
        XtreamCredentials(host: xtreamHost, username: xtreamUser, password: xtreamPassword)
    }

    /// Startet den Xtream-Import.
    private func startXtreamImport() {
        guard !isImporting else { return }
        guard xtreamCredentials.isComplete else {
            errorMessage = "Bitte Host, Benutzername und Passwort ausfüllen."
            return
        }
        let credentials = xtreamCredentials, output = xtreamOutput, name = name
        startImport { try await $0.importFromXtream(credentials, output: output, name: name) }
    }

    /// Startet den Import per URL (B02 · BUG-08, BUG-09: wie beim Xtream-Reiter).
    private func startURLImport() {
        let address = urlString, name = name
        startImport { try await $0.importFromURL(address, name: name) }
    }

    private func handleFileResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let name = name.isEmpty ? nil : name
            startImport { try await $0.importFromFile(url, name: name) }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// Gemeinsamer Ablauf aller Reiter: `isImporting` wird **vor** dem Start der Aufgabe gesetzt, damit ein zweiter
    /// Klick vor dem Neuzeichnen keinen zweiten Import auslöst (B01 · BUG-09, B02 · BUG-09). Die Aufgabe ist an das
    /// Sheet gebunden: Nach „Abbrechen" wird nichts gespeichert und kein Fehler mehr angezeigt (B01 · BUG-11,
    /// B02 · BUG-08).
    private func startImport(_ operation: @escaping @MainActor (PlaylistImporter) async throws -> Void) {
        guard !isImporting else { return }
        isImporting = true
        let importer = PlaylistImporter(modelContext: modelContext)
        importTask = Task {
            defer { isImporting = false }
            do {
                try await operation(importer)
                guard !Task.isCancelled else { return }
                dismiss()
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
