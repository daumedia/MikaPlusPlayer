import SwiftUI

#if os(macOS)

/// Multiview-Fenster: mehrere Streams gleichzeitig, umschaltbar zwischen Fokus-Layout
/// (ein großer Haupt-Player + kleine Kacheln oben rechts, „wie bei Reacts") und Raster.
/// Das native Fenster-Vollbild (grüner Button / Menü „Vollbild") funktioniert hier
/// out of the box, weil es ein eigenständiges Fenster ist.
///
/// B08 · BUG-01/BUG-02: Jede Kachel ist über `ForEach(session.slots)` an ihren Slot gebunden (Identität = `Slot.id`)
/// und bleibt bei Fokuswechsel, Layoutwechsel und Entfernen dieselbe Ansicht – nur Lage und Größe ändern sich
/// (`MultiviewArrangement`). Es gibt keinen Zugriff über einen Index mehr, der beim Schrumpfen der Liste ins Leere
/// greifen könnte, und die Zeichenfläche einer Engine wandert nie zwischen zwei Kacheln.
struct MultiviewScreen: View {
    @Environment(MultiviewSession.self) private var session

    /// B08 · BUG-10: kleinste Inhaltsgröße des Fensters. Im Fokus-Layout passen alle kleinen Kacheln samt Abständen
    /// untereinander, darüber die Leiste des großen Streams mit seinem X.
    static let minimumContentSize = CGSize(
        width: 640,
        height: MultiviewMetrics.smallTileTopInset
            + CGFloat(MultiviewSession.maxSlots - 1) * MultiviewMetrics.smallTileSize.height
            + CGFloat(MultiviewSession.maxSlots - 2) * MultiviewMetrics.smallTileSpacing
            + MultiviewMetrics.smallTileTrailingInset)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if session.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .frame(minWidth: Self.minimumContentSize.width, minHeight: Self.minimumContentSize.height)
        .navigationTitle("Multiview")
        .toolbar {
            ToolbarItem(placement: .principal) { layoutPicker }
        }
        // Beim Schließen des Fensters alle Engines stoppen, sonst läuft Audio weiter.
        .onDisappear { session.clear() }
    }

    // MARK: - Kacheln (Fokus-Layout und Raster in einer Anordnung)

    private var content: some View {
        let focusedID = session.slots.indices.contains(session.focusedIndex) ? session.slots[session.focusedIndex].id : nil
        let layout = session.layout
        return MultiviewArrangement(layout: layout) {
            ForEach(session.slots) { slot in
                let isFocused = slot.id == focusedID
                // Im Fokus-Layout stehen alle nicht fokussierten Streams als kleine Kacheln über dem großen.
                let isSmall = layout == .focus && !isFocused
                MultiviewTile(
                    slot: slot,
                    isFocused: isFocused,
                    showsConnectionHint: session.otherStreamIsPlaying(onProviderOf: slot),
                    onFocus: { focus(slot.id) },
                    onClose: { session.remove(slot.id) }
                )
                // Dieselben Modifier in jedem Zustand (nur die Werte wechseln), damit die Kachel ihre Identität behält.
                .clipShape(TileClip(cornerRadius: isSmall ? PlayerTheme.cardRadius : nil))
                .shadow(color: isSmall ? Color(.sRGBLinear, white: 0, opacity: 0.33) : .clear, radius: isSmall ? 8 : 0)
                .layoutValue(key: MultiviewArrangement.IsMainTile.self, value: layout == .focus && isFocused)
                .zIndex(isSmall ? 1 : 0)
            }
        }
    }

    /// Fokus über die Identität des Slots, nicht über einen beim Zeichnen gemerkten Index.
    private func focus(_ slotID: UUID) {
        guard let index = session.slots.firstIndex(where: { $0.id == slotID }) else { return }
        session.setFocus(index)
    }

    // MARK: - Leerer Zustand & Toolbar

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Kein Stream im Multiview", systemImage: "rectangle.split.2x2")
        } description: {
            Text("Füge in der Senderliste mit dem ⊞-Button Sender hinzu, um sie hier gleichzeitig zu sehen.")
        }
    }

    private var layoutPicker: some View {
        Picker("Layout", selection: Binding(
            get: { session.layout },
            set: { session.layout = $0 }
        )) {
            ForEach(MultiviewLayout.allCases) { layout in
                Text(layout.label).tag(layout)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // B08 · BUG-01: Mit weniger als zwei Streams bleibt der Weg zurück zu „Fokus" offen, wenn „Raster" gewählt ist.
        .disabled(session.slots.count < 2 && session.layout == .focus)
    }
}

/// Ordnet die Kacheln an: im Fokus-Layout die markierte Hauptkachel über die ganze Fläche und alle übrigen als
/// 240 × 135 pt große Kacheln übereinander oben rechts; im Raster alle gleich groß (1 = voll, 2 = nebeneinander,
/// 3–4 = 2 × 2). Die Lage folgt der Reihenfolge der Slots, nicht einem Index – die Kacheln selbst bleiben dieselben.
struct MultiviewArrangement: Layout {
    /// Markiert im Fokus-Layout die große Kachel.
    struct IsMainTile: LayoutValueKey {
        static let defaultValue = false
    }

    var layout: MultiviewLayout

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        switch layout {
        case .focus:
            var y = bounds.minY + MultiviewMetrics.smallTileTopInset
            let x = bounds.maxX - MultiviewMetrics.smallTileTrailingInset - MultiviewMetrics.smallTileSize.width
            for subview in subviews {
                if subview[IsMainTile.self] {
                    subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
                } else {
                    subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(MultiviewMetrics.smallTileSize))
                    y += MultiviewMetrics.smallTileSize.height + MultiviewMetrics.smallTileSpacing
                }
            }
        case .grid:
            let count = subviews.count
            guard count > 0 else { return }
            let columns = count <= 1 ? 1 : 2
            let rows = (count + columns - 1) / columns
            let width = (bounds.width - CGFloat(columns - 1) * MultiviewMetrics.gridSpacing) / CGFloat(columns)
            let height = (bounds.height - CGFloat(rows - 1) * MultiviewMetrics.gridSpacing) / CGFloat(rows)
            for (position, subview) in subviews.enumerated() {
                let row = position / columns, column = position % columns
                let origin = CGPoint(x: bounds.minX + CGFloat(column) * (width + MultiviewMetrics.gridSpacing),
                                     y: bounds.minY + CGFloat(row) * (height + MultiviewMetrics.gridSpacing))
                subview.place(at: origin, proposal: ProposedViewSize(width: width, height: height))
            }
        }
    }
}

/// Maße des Multiview-Fensters (Kacheln, Abstände, Leiste mit dem X).
enum MultiviewMetrics {
    /// Innenabstand der Leiste einer Kachel (Etikett links, X rechts).
    static let chromePadding: CGFloat = 8
    /// Kantenlänge des runden X-Knopfs.
    static let closeButtonSize: CGFloat = 30
    static let smallTileSize = CGSize(width: 240, height: 135)
    static let smallTileSpacing: CGFloat = 8
    static let smallTileTrailingInset: CGFloat = 16
    /// B08 · BUG-04: Die kleinen Kacheln beginnen unterhalb der Leiste des großen Streams, damit dessen X frei liegt
    /// (vorher 16 pt vom oberen Rand – die erste kleine Kachel lag über dem X).
    static let smallTileTopInset: CGFloat = chromePadding + closeButtonSize + 8
    static let gridSpacing: CGFloat = 4
}

/// Beschneidet kleine Kacheln rund; ohne Radius bleibt die Kachel unbeschnitten, die Videofläche reicht dann wie
/// bisher unter die Titelleiste. Eine Form statt eines bedingten Modifiers, damit die Kachel ihre Identität behält.
private struct TileClip: Shape {
    var cornerRadius: CGFloat?

    func path(in rect: CGRect) -> Path {
        guard let cornerRadius else { return Path(rect.insetBy(dx: -10_000, dy: -10_000)) }
        return Path(roundedRect: rect, cornerRadius: cornerRadius)
    }
}

#endif
