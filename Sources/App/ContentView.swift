import SwiftUI
import SwiftData

/// Wurzel-Ansicht: TabView mit zwei Tabs, jeder mit eigenem NavigationStack.
struct ContentView: View {
    /// Sichtbarer Tab dieses Fensters – der Player unterscheidet damit „Zurück" von einem Tabwechsel (B07 · BUG-01).
    @State private var tabs = ShellTabs()

    var body: some View {
        TabView(selection: $tabs.selected) {
            NavigationStack {
                PlaylistsView()
            }
            .tabItem {
                Label("Playlists", systemImage: "list.and.film")
            }
            .tag(ShellTabs.Tab.playlists)

            NavigationStack {
                FavoritesView()
            }
            .tabItem {
                Label("Favoriten", systemImage: "star.fill")
            }
            .tag(ShellTabs.Tab.favorites)
        }
        .environment(tabs)
        .tint(.playerAccent)
        #if os(iOS)
        .toolbarBackground(.visible, for: .tabBar)
        #endif
    }
}

/// Welcher Tab eines Hauptfensters sichtbar ist (B07 · BUG-01).
///
/// Verschwindet der Player, muss er wissen, ob er verlassen wurde („Zurück") oder nur verdeckt ist (Tabwechsel,
/// B06 AK-27). `@Environment(\.isPresented)` meldet das am Mac nicht verlässlich: Liegt der Player tiefer im Stapel
/// (Playlists → Senderliste → Player), ist es beim Verschwinden nach „Zurück" noch wahr. Der Tab dagegen stimmt:
/// Ist der eigene Tab beim Verschwinden weiter sichtbar, hat der Nutzer den Player verlassen.
@MainActor @Observable
final class ShellTabs {
    enum Tab: Hashable { case playlists, favorites }
    var selected: Tab = .playlists
}

#Preview {
    ContentView()
        .modelContainer(for: [Playlist.self, Channel.self], inMemory: true)
}
