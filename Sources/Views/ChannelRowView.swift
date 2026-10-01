import SwiftUI
import SwiftData

/// Inhalt einer Sender-Card: Logo, Name, Gruppe und Favoriten-Stern.
/// Der Card-Rahmen wird vom Aufrufer via `.playerCard()` gesetzt.
struct ChannelRowView: View {
    @Environment(\.modelContext) private var modelContext
    #if os(macOS)
    @Environment(MultiviewSession.self) private var multiview
    @Environment(\.openWindow) private var openWindow
    #endif
    @Bindable var channel: Channel
    /// Der Stern ließ sich nicht speichern (B05 · BUG-02).
    @State private var starNotSaved = false

    var body: some View {
        HStack(spacing: 12) {
            logo
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    // B05 · BUG-04: VoiceOver sagt an, ob der Sender Favorit ist. Am Namen, nicht am Stapel: Die Karte
                    // (`NavigationLink`) fasst ihre Teile zu einem Element zusammen und übernähme den Wert sonst je Teil.
                    .accessibilityValue(channel.isFavorite ? "Favorit" : "")
                if let group = channel.group, !group.isEmpty {
                    PlayerBadge(systemImage: nil, text: group)
                }
            }
            Spacer(minLength: 8)
            #if os(macOS)
            multiviewButton
            #endif
            favoriteButton
        }
        .alert("Favorit nicht gespeichert", isPresented: $starNotSaved) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(PlaylistStoreError.starNotSaved.errorDescription ?? "")
        }
    }

    private var logo: some View {
        ChannelLogoView(url: channel.logoURL)
            .frame(width: 48, height: 48)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var favoriteButton: some View {
        Button {
            // Review R-01: über `FavoriteEdits`, damit ein Stern während des Aktualisierens nicht verloren geht.
            // B05 · BUG-02: Scheitert das Speichern, ist der Stern schon zurückgesetzt; hier nur die Meldung.
            do {
                try FavoriteEdits.toggle(channel, in: modelContext)
            } catch {
                starNotSaved = true
            }
        } label: {
            Image(systemName: channel.isFavorite ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(channel.isFavorite ? Color.playerAccent : Color.secondary)
        }
        .buttonStyle(.plain)
        // B05 · BUG-04: deutsche Aktion je Zustand statt des Symbolnamens „Favourite“.
        .accessibilityLabel(channel.isFavorite ? "Favorit entfernen" : "Favorit hinzufügen")
    }

    #if os(macOS)
    /// Fügt den Sender zum Multiview hinzu und öffnet das Multiview-Fenster.
    /// B08 · BUG-03: Bei vollem Multiview ist der Knopf abgeblendet, aber nicht deaktiviert, und bewirkt nichts. Ein
    /// deaktivierter Knopf nähme den Klick nicht an – er fiele an die Karte (`NavigationLink`) durch und öffnete den Player.
    private var multiviewButton: some View {
        Button {
            guard multiview.canAddMore else { return }
            multiview.add(channel)
            openWindow(id: "multiview")
        } label: {
            Image(systemName: "rectangle.split.2x2")
                .font(.title3)
                .foregroundStyle(multiview.canAddMore ? Color.secondary : Color.secondary.opacity(0.3))
        }
        .buttonStyle(.plain)
        .help(multiview.canAddMore ? "Zu Multiview hinzufügen" : "Multiview voll (max. 4)")
    }
    #endif
}

/// Logofeld einer Senderkarte (Senderliste und Favoriten-Tab) über den gemeinsamen `ChannelLogoLoader`
/// (B04 · BUG-04 bis BUG-07): Ladeindikator nur, solange eine Anfrage läuft; ohne Adresse, bei fremdem Schema und bei
/// jedem Fehler das graue TV-Symbol. Wird die Karte weggescrollt oder die Liste verlassen, endet die Anfrage; beim
/// erneuten Erscheinen wird neu geladen (sofern das Bild nicht im Arbeitsspeicher liegt).
struct ChannelLogoView: View {
    enum Phase {
        case loading
        case image(CGImage)
        case placeholder
    }

    let url: URL?
    private let loader: ChannelLogoLoader
    @State private var phase: Phase
    /// Adresse, zu der `phase` gehört.
    @State private var phaseURL: URL?

    init(url: URL?, loader: ChannelLogoLoader = .shared) {
        self.url = url
        self.loader = loader
        _phase = State(initialValue: Self.immediatePhase(url, loader) ?? .loading)
        _phaseURL = State(initialValue: url)
    }

    var body: some View {
        Group {
            switch phase {
            case .image(let image):
                Image(decorative: image, scale: 1).resizable().scaledToFit().padding(4)
            case .placeholder:
                Image(systemName: "tv")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
            }
        }
        .task(id: url) { await load() }
    }

    /// Ohne Anfrage bekannt: Platzhalter (keine bzw. fremde Adresse) oder Bild aus dem Arbeitsspeicher.
    private static func immediatePhase(_ url: URL?, _ loader: ChannelLogoLoader) -> Phase? {
        guard let url, ChannelLogoLoader.accepts(url) else { return .placeholder }
        return loader.cachedImage(for: url).map(Phase.image)
    }

    private func load() async {
        if let known = Self.immediatePhase(url, loader) {
            phase = known
            phaseURL = url
            return
        }
        guard let url else { return }
        // Schon angezeigt (z. B. wieder in den sichtbaren Bereich gescrollt): nicht erneut anfragen.
        if case .image = phase, phaseURL == url { return }
        phase = .loading
        phaseURL = url
        let image = await loader.image(for: url)
        // Abgebrochen (weggescrollt, Liste verlassen): Ladeindikator lassen, beim nächsten Erscheinen wird neu geladen.
        guard !Task.isCancelled else { return }
        phase = image.map(Phase.image) ?? .placeholder
    }
}
