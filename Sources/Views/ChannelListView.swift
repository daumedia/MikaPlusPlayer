import SwiftUI
import SwiftData

/// Senderliste einer Playlist mit Suche und horizontalen Gruppen-Filter-Chips.
///
/// Filter und Sortierung laufen in der Datenbank (AK-31), aber **nicht auf dem Main-Thread** (B04 · BUG-13, BUG-14):
/// Trefferliste und Gruppen holt `ChannelListQuery` in einem eigenen Kontext im Hintergrund – die Trefferliste nur als
/// Kennungen, gefiltert über die indizierte Beziehung zur Playlist (BUG-12). Nur kleine Listen (bis `synchronousLimit`)
/// werden beim ersten Erscheinen sofort geladen. Die Karten holen ihren Sender erst, wenn sie sichtbar werden. Die Suche
/// ist entprellt, Chips wirken sofort.
struct ChannelListView: View {
    @Environment(\.modelContext) private var modelContext
    let playlist: Playlist

    @State private var searchText = ""
    @State private var selectedGroup: String?
    @State private var groups = ChannelListQuery.Groups()
    /// Kennungen der angezeigten Sender, in Anzeigereihenfolge.
    @State private var results: [PersistentIdentifier] = []
    /// Zu welcher Abfrage `results` gehört; `nil`, solange noch nichts geladen ist.
    @State private var shown: ResultsKey?
    /// Erhöht sich, wenn die Sender der Playlist ersetzt wurden (Aktualisieren, B04 · BUG-02).
    @State private var generation = 0
    /// Identität der Kartenliste; wechselt, wenn eine große Trefferliste ersetzt wird (siehe `rebuildThreshold`).
    @State private var listEpoch = 0
    /// Zu welcher `generation` die Gruppen geladen sind.
    @State private var groupsGeneration: Int?
    /// B03 · BUG-05: Die Playlist wurde gelöscht, während die Liste offen war.
    @State private var playlistDeleted = false

    /// Wartezeit nach der letzten Eingabe, bevor gesucht wird (B04 · BUG-13, EC-12).
    static let searchDebounce: Duration = .milliseconds(150)
    /// Ab so vielen Treffern (alt oder neu) wird die Kartenliste neu aufgebaut statt abgeglichen: SwiftUI gleicht sonst
    /// bis zu 17.000 Kennungen mit der vorigen Liste ab (B04 · BUG-13). Kleinere Listen werden abgeglichen, sichtbare
    /// Karten, die bleiben, also wiederverwendet.
    static let rebuildThreshold = 2_000
    /// Bis zu so vielen Sendern lädt die Liste beim ersten Erscheinen sofort (wenige Millisekunden), damit schon das erste
    /// Bild die Karten zeigt; größere Listen laden im Hintergrund.
    static let synchronousLimit = 2_000

    private struct ResultsKey: Equatable {
        var search: String
        var group: String?
        /// Gespeicherte Gruppenwerte des gewählten Chips (B04 · BUG-01)
        var groupValues: [String]?
        var generation: Int
    }

    private var requestedKey: ResultsKey {
        ResultsKey(search: searchText, group: selectedGroup,
                   groupValues: selectedGroup.map { groups.values[$0] ?? [$0] }, generation: generation)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlayerTheme.sectionSpacing) {
                if playlistDeleted {
                    deletedState
                } else {
                    PlayerHeader(
                        subline: "MIKA+PLAYER · \(playlist.channelCount) SENDER",
                        title: playlist.name
                    )

                    if let shown {
                        ChannelResultsList(
                            ids: results,
                            searchText: shown.search,
                            group: shown.group,
                            showAllGroups: { selectedGroup = nil }
                        )
                        .id(listEpoch)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Color.playerBackground.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { if !playlistDeleted { groupFilterBar } }
        .navigationTitle(playlistDeleted ? "Playlist gelöscht" : playlist.name)
        .onReceive(NotificationCenter.default.publisher(for: PlaylistEvents.willDelete)) { note in
            if PlaylistEvents.ids(in: note).contains(playlist.id) { playlistDeleted = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: PlaylistEvents.didReplaceChannels)) { note in
            if PlaylistEvents.ids(in: note).contains(playlist.id) { generation += 1 }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(for: Channel.self) { channel in
            PlayerView(channel: channel)
        }
        .searchable(text: $searchText, prompt: "Sender suchen")
        .onAppear { loadSmallListImmediately() }
        .task(id: generation) { await loadGroups() }
        .task(id: requestedKey) { await loadResults(requestedKey) }
    }

    private var deletedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Playlist gelöscht").font(.headline)
            Text("Diese Playlist wurde gelöscht. Ihre Sender sind nicht mehr verfügbar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, PlayerTheme.contentHPadding)
        .padding(.top, 60)
    }

    // MARK: - Laden

    /// Kleine Listen beim ersten Erscheinen sofort laden (Gruppen und Treffer, zusammen wenige Millisekunden). Große Listen
    /// und jede spätere Änderung laufen über die Hintergrund-Aufgaben unten.
    private func loadSmallListImmediately() {
        guard shown == nil, !playlistDeleted, playlist.channelCount <= Self.synchronousLimit else { return }
        let container = modelContext.container
        let owner = playlist.persistentModelID
        if groupsGeneration == nil, let loaded = try? ChannelListQuery.groups(in: container, playlist: owner) {
            groups = loaded
            groupsGeneration = generation
        }
        let key = requestedKey
        if let ids = try? ChannelListQuery.identifiers(in: container, playlist: owner, search: key.search,
                                                       groupValues: key.groupValues) {
            results = ids
            shown = key
        }
    }

    /// Gruppen-Chips, neu nach jedem Aktualisieren der Playlist (B04 · BUG-02, BUG-14). Eine gewählte Gruppe, die es
    /// danach nicht mehr gibt, wird aufgehoben.
    private func loadGroups() async {
        guard !playlistDeleted, groupsGeneration != generation else { return }
        let stand = generation
        let container = modelContext.container
        let owner = playlist.persistentModelID
        // Scheitert die Abfrage, bleibt der bisherige Stand stehen (keine leere Leiste als falsche Aussage).
        let loaded = await Task.detached(priority: .userInitiated) {
            try? ChannelListQuery.groups(in: container, playlist: owner)
        }.value
        guard !Task.isCancelled, let loaded else { return }
        if groups != loaded { groups = loaded }
        groupsGeneration = stand
        if let selected = selectedGroup, !loaded.chips.contains(selected) {
            selectedGroup = nil
        }
    }

    /// Trefferliste zur Abfrage `key`. Änderungen am Suchtext warten `searchDebounce` ab; eine neue Eingabe bricht
    /// das Warten ab (`.task(id:)`), ein veraltetes Ergebnis wird verworfen.
    private func loadResults(_ key: ResultsKey) async {
        // Schon angezeigt (z. B. sofort geladen oder zurück aus dem Player): nichts zu tun.
        guard !playlistDeleted, shown != key else { return }
        if let shown, shown.search != key.search {
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled else { return }
        }
        let container = modelContext.container
        let owner = playlist.persistentModelID
        // Scheitert die Abfrage, bleibt die bisherige Liste stehen – nie „Diese Playlist enthält keine Sender.“ als
        // Folge eines Lesefehlers.
        let ids = await Task.detached(priority: .userInitiated) {
            try? ChannelListQuery.identifiers(in: container, playlist: owner, search: key.search, groupValues: key.groupValues)
        }.value
        guard !Task.isCancelled, let ids else { return }
        if results != ids {
            if results.count > Self.rebuildThreshold || ids.count > Self.rebuildThreshold { listEpoch += 1 }
            results = ids
        }
        if shown != key { shown = key }
    }

    // MARK: - Gruppen-Filter

    /// Ab so vielen Chips baut die Leiste nur die sichtbaren auf (B04 · BUG-13): 300 Gruppen blockierten das Öffnen
    /// sonst rund 0,2–0,3 s (gemessen, Debug wie Release). Darunter stehen alle Chips sofort bereit.
    static let lazyChipThreshold = 40

    @ViewBuilder
    private var groupFilterBar: some View {
        if groups.chips.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                Group {
                    if groups.chips.count > Self.lazyChipThreshold {
                        LazyHStack(spacing: 8) { chipButtons }
                    } else {
                        HStack(spacing: 8) { chipButtons }
                    }
                }
                .padding(.horizontal, PlayerTheme.contentHPadding)
                .padding(.vertical, 10)
            }
            // Nur so hoch wie die Chips: Ein `LazyHStack` würde sonst die ganze Höhe beanspruchen.
            .fixedSize(horizontal: false, vertical: true)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var chipButtons: some View {
        GroupChip(title: "Alle", isSelected: selectedGroup == nil) {
            selectedGroup = nil
        }
        ForEach(groups.chips, id: \.self) { group in
            GroupChip(title: group, isSelected: selectedGroup == group) {
                selectedGroup = (selectedGroup == group) ? nil : group
            }
        }
    }
}

/// Senderkarten zu einer fertigen Trefferliste (Kennungen), mit den Leerzuständen.
private struct ChannelResultsList: View {
    let ids: [PersistentIdentifier]
    let searchText: String
    let group: String?
    let showAllGroups: () -> Void

    var body: some View {
        if ids.isEmpty {
            if !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .padding(.top, 40)
            } else if let group {
                emptyGroupState(group)
            } else {
                emptyState
            }
        } else {
            LazyVStack(spacing: PlayerTheme.rowSpacing) {
                ForEach(ids, id: \.self) { id in
                    ChannelCard(id: id)
                }
            }
            .padding(.horizontal, PlayerTheme.contentHPadding)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tv.slash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Keine Sender").font(.headline)
            Text("Diese Playlist enthält keine Sender.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    /// B04 · BUG-03: Ein gewählter Chip ohne Treffer sagt nichts über die ganze Playlist.
    private func emptyGroupState(_ group: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Keine Sender in dieser Gruppe").font(.headline)
            Text("In der Gruppe „\(group)“ sind keine Sender.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Alle Sender zeigen", action: showAllGroups)
                .buttonStyle(.borderedProminent)
                .tint(.playerAccent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, PlayerTheme.contentHPadding)
        .padding(.top, 60)
    }
}

/// Eine Senderkarte zu einer Kennung. Der Sender wird erst geholt, wenn die Karte aufgebaut wird (sichtbarer Bereich).
/// Gibt es ihn nicht mehr (z. B. zwischen Aktualisieren und neuer Trefferliste), bleibt die Karte leer.
private struct ChannelCard: View {
    @Environment(\.modelContext) private var modelContext
    let id: PersistentIdentifier

    var body: some View {
        if let channel = ChannelListQuery.channel(id, in: modelContext) {
            NavigationLink(value: channel) {
                ChannelRowView(channel: channel).playerCard()
            }
            .buttonStyle(.plain)
        }
    }
}

/// Ein anklickbarer Filter-Chip im Mika+ Capsule-Stil.
private struct GroupChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(
                        isSelected ? Color.playerAccent : Color.secondary.opacity(0.16)
                    )
                )
                // B04 · BUG-10: Schrift auf dem Akzent mit mindestens 4,5 : 1, Auswahl auch für VoiceOver.
                .foregroundStyle(isSelected ? Color.playerOnAccent : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
