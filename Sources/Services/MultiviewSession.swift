import Foundation
import SwiftUI

#if os(macOS)

/// Layout-Modi für das Multiview-Fenster.
enum MultiviewLayout: String, CaseIterable, Identifiable {
    /// Ein großer Haupt-Player, die übrigen als kleine Kacheln oben rechts (PiP).
    case focus
    /// Gleich große Kacheln (1 = voll, 2 = nebeneinander, 3–4 = 2×2).
    case grid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .focus: return "Fokus"
        case .grid:  return "Raster"
        }
    }
}

/// Geteilter Zustand des Multiview-Fensters (macOS-only).
///
/// Hält bis zu `maxSlots` Streams, jeder mit eigener `PlaybackEngine`. Setzt den
/// Audio-Fokus durch: **immer nur der fokussierte Stream hat Ton**, alle anderen
/// sind stumm. Wird auf App-Ebene als `@State` erzeugt und per `.environment(_:)`
/// an Haupt- **und** Multiview-Fenster gehängt – so erreicht der „⊞"-Button in der
/// Senderliste dieselbe Instanz wie das Multiview-Fenster.
@MainActor
@Observable
final class MultiviewSession {
    /// Obergrenze gleichzeitiger Streams (2×2-Raster).
    static let maxSlots = 4

    /// Ein Multiview-Platz: Sender + die dafür erzeugte Engine.
    struct Slot: Identifiable {
        let id = UUID()
        let channel: Channel
        let engine: any PlaybackEngine
        /// Playlist des Senders beim Hinzufügen – zum Beenden, wenn sie gelöscht wird (B03 · BUG-05).
        var playlistID: UUID?
    }

    private(set) var slots: [Slot] = []
    /// Index des Streams mit Ton (und im Fokus-Layout des großen Haupt-Players).
    private(set) var focusedIndex = 0
    var layout: MultiviewLayout = .focus

    var isEmpty: Bool { slots.isEmpty }
    var canAddMore: Bool { slots.count < Self.maxSlots }

    @ObservationIgnored private var deletionObserver: NSObjectProtocol?

    init() {
        // B03 · BUG-05: Wird die Playlist eines Streams gelöscht, endet dessen Wiedergabe samt Verbindung.
        deletionObserver = NotificationCenter.default.addObserver(forName: PlaylistEvents.willDelete, object: nil,
                                                                  queue: .main) { [weak self] note in
            let ids = PlaylistEvents.ids(in: note)
            MainActor.assumeIsolated { self?.removeSlots(ofPlaylists: ids) }
        }
    }

    deinit {
        if let deletionObserver { NotificationCenter.default.removeObserver(deletionObserver) }
    }

    /// Beendet und entfernt alle Streams der genannten Playlists.
    func removeSlots(ofPlaylists ids: Set<UUID>) {
        let doomed = slots.filter { $0.playlistID.map(ids.contains) ?? false }
        guard !doomed.isEmpty else { return }
        let focusedID = slots.indices.contains(focusedIndex) ? slots[focusedIndex].id : nil
        for slot in doomed { slot.engine.stop() }
        slots.removeAll { slot in doomed.contains { $0.id == slot.id } }
        focusedIndex = slots.firstIndex { $0.id == focusedID } ?? 0
        enforceAudioFocus()
    }

    /// Fügt einen Sender hinzu, erzeugt sofort dessen Engine und startet die Wiedergabe.
    /// Der erste Stream wird fokussiert (mit Ton), alle weiteren starten stumm.
    /// Lässt sich keine abspielbare Adresse bilden (Xtream-Zugangsdaten fehlen), wird nichts hinzugefügt.
    func add(_ channel: Channel) {
        guard canAddMore else { return }
        // B01 · BUG-01: Xtream-Adressen erst hier mit Zugangsdaten aus dem Schlüsselbund.
        guard let url = try? StreamURLResolver.playableURL(for: channel) else { return }
        let engine = PlaybackEngineFactory.engine(for: url)
        let isFirst = slots.isEmpty
        engine.load(url)
        // Sollwert sofort setzen – bei VLC greift er, sobald der Audiokanal nach
        // `.playing` existiert (der Delegate ruft `applyAudio()` erneut).
        engine.setMuted(!isFirst)
        slots.append(Slot(channel: channel, engine: engine, playlistID: channel.playlistID ?? channel.playlist?.id))
        if isFirst { focusedIndex = 0 }
        enforceAudioFocus()
    }

    /// Entfernt einen Slot. Stoppt die Engine **explizit** (pause), bevor die Referenz
    /// fällt – die Engines haben keinen `deinit`/`stop`, sonst liefe Audio weiter.
    func remove(_ slotID: UUID) {
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else { return }
        slots[index].engine.pause()
        slots.remove(at: index)
        // Fokus dem gleichen Stream nachführen: Entfernen VOR dem fokussierten
        // verschiebt diesen um eine Position nach unten.
        if index < focusedIndex { focusedIndex -= 1 }
        focusedIndex = min(focusedIndex, max(0, slots.count - 1))
        enforceAudioFocus()
    }

    /// Macht den Stream an `index` zum fokussierten (großen) Stream mit Ton.
    func setFocus(_ index: Int) {
        guard slots.indices.contains(index) else { return }
        focusedIndex = index
        enforceAudioFocus()
    }

    /// Stoppt alle Engines und leert die Session (z. B. beim Schließen des Fensters).
    func clear() {
        slots.forEach { $0.engine.pause() }
        slots.removeAll()
        focusedIndex = 0
    }

    /// Stellt sicher, dass nur der fokussierte Stream Ton hat.
    private func enforceAudioFocus() {
        for (index, slot) in slots.enumerated() {
            slot.engine.setMuted(index != focusedIndex)
        }
    }
}

#endif
