import SwiftUI
import SwiftData

/// Übersicht aller importierten Playlists. Einstieg in den Import und in die
/// jeweilige Senderliste. Stil angelehnt an die Mika+ Familie.
struct PlaylistsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]

    @State private var showingImport = false
    /// Laufende Aktualisierungen dieses Fensters, je Playlist ein Indikator (B03 · BUG-03).
    @State private var refreshingIDs: Set<UUID> = []
    /// Playlists, deren Löschen läuft: sofort ausgeblendet (B03 · BUG-01).
    @State private var deletingIDs: Set<UUID> = []
    @State private var errorMessage: String?
    #if os(iOS)
    @State private var confirmingErase = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlayerTheme.sectionSpacing) {
                PlayerHeader(subline: "MIKA+PLAYER · PLAYLISTS", title: "Playlists") {
                    #if os(iOS)
                    // B03 · BUG-09: iOS hat keine Menüleiste – „Alle Daten entfernen …" hier.
                    Menu {
                        Button(role: .destructive) { confirmingErase = true } label: {
                            Label("Alle Daten entfernen …", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Weitere Aktionen")
                    #endif
                    Button { showingImport = true } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.playerAccent)
                }

                if visiblePlaylists.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: PlayerTheme.rowSpacing) {
                        ForEach(visiblePlaylists) { playlist in
                            NavigationLink(value: playlist) {
                                PlaylistRow(
                                    playlist: playlist,
                                    isRefreshing: refreshingIDs.contains(playlist.id)
                                )
                                .playerCard()
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if playlist.isRemote {
                                    Button {
                                        startRefresh(playlist)
                                    } label: {
                                        Label("Aktualisieren", systemImage: "arrow.clockwise")
                                    }
                                    // B03 · BUG-04: gesperrt, solange diese Playlist aktualisiert wird.
                                    .disabled(refreshingIDs.contains(playlist.id))
                                }
                                Button(role: .destructive) {
                                    delete(playlist)
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, PlayerTheme.contentHPadding)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Color.playerBackground.ignoresSafeArea())
        .navigationTitle("Playlists")
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .navigationDestination(for: Playlist.self) { playlist in
            ChannelListView(playlist: playlist)
        }
        .sheet(isPresented: $showingImport) {
            ImportPlaylistView()
        }
        .alert("Fehler", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        #if os(iOS)
        .confirmationDialog(AppDataReset.confirmationTitle, isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Alle Daten entfernen", role: .destructive) { eraseAll() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(AppDataReset.confirmationMessage)
        }
        #endif
    }

    private var visiblePlaylists: [Playlist] {
        deletingIDs.isEmpty ? playlists : playlists.filter { !deletingIDs.contains($0.id) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.and.film")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Keine Playlists")
                .font(.headline)
            Text("Importiere eine M3U/M3U8-Playlist per URL oder Datei, um loszulegen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Playlist importieren") { showingImport = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.playerAccent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, PlayerTheme.contentHPadding)
        .padding(.top, 60)
    }

    // MARK: - Aktionen

    /// Zentraler Löschweg (B03 · BUG-01, -05 … -08): läuft abseits des Main-Actors; die Karte verschwindet sofort.
    /// Scheitert etwas, erscheint die Karte wieder bzw. ein Hinweis – nichts wird verschluckt (BUG-08).
    private func delete(_ playlist: Playlist) {
        let id = playlist.id
        guard !deletingIDs.contains(id) else { return }
        deletingIDs.insert(id)
        let importer = PlaylistImporter(modelContext: modelContext)
        Task {
            defer { deletingIDs.remove(id) }
            do {
                try await importer.delete(playlist)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Markiert die Playlist **vor** dem Start der Aufgabe als laufend (wie `isImporting` im Import-Sheet), damit eine
    /// zweite Wahl vor dem Neuzeichnen schon gesperrt ist (B03 · BUG-03, BUG-04).
    private func startRefresh(_ playlist: Playlist) {
        let id = playlist.id
        guard !refreshingIDs.contains(id) else { return }
        refreshingIDs.insert(id)
        let importer = PlaylistImporter(modelContext: modelContext)
        Task {
            defer { refreshingIDs.remove(id) }
            do {
                try await importer.refresh(playlist)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    #if os(iOS)
    private func eraseAll() {
        let context = modelContext
        Task {
            do {
                try await AppDataReset.eraseAll(context: context, targets: .app(container: context.container))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    #endif
}

/// Eine Card-Zeile in der Playlist-Liste.
private struct PlaylistRow: View {
    let playlist: Playlist
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: playlist.isRemote ? "globe" : "doc")
                .font(.title3)
                .foregroundStyle(Color.playerAccent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                PlayerBadge(systemImage: "tv", text: "\(playlist.channelCount) Sender")
            }
            Spacer()
            if isRefreshing {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
