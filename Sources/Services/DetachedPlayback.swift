import Foundation
import Observation

/// Wiedergabe, deren Player verlassen wurde, während Bild-in-Bild lief (B06 · BUG-02).
///
/// Verlässt der Nutzer den Player, endet die Wiedergabe samt Verbindung – außer Bild-in-Bild ist aktiv. Dann
/// übernimmt diese Stelle die Engine: Sie läuft im schwebenden Fenster weiter, bis Bild-in-Bild endet (Fenster
/// geschlossen, „Zurück zur App", System), und wird dann mit `stop()` beendet. Vorher hing eine solche Engine nur
/// noch an SwiftUI-Zustand bzw. an schwachen Referenzen (B07 · BUG-01/BUG-02).
///
/// Einzige app-weite Stelle, die eine laufende Wiedergabe ohne Player kennt. B07 · BUG-01: Startet ein Player eine
/// Wiedergabe, endet die übernommene (`stopAll()`); „Zurück zur App" im schwebenden Fenster stellt keinen Player
/// wieder her, sondern beendet sie (`holds(_:)`, Delegate in `AVKitPlaybackEngine`).
@MainActor
final class DetachedPlayback {
    static let shared = DetachedPlayback()

    /// Engines, die gerade ohne Player im Bild-in-Bild-Fenster laufen.
    private(set) var engines: [any PlaybackEngine] = []

    /// Übernimmt eine Engine, deren Player verlassen wird. Läuft kein Bild-in-Bild, wird sie sofort beendet.
    func adopt(_ engine: any PlaybackEngine) {
        guard engine.isPictureInPictureActive else {
            engine.stop()
            return
        }
        guard !engines.contains(where: { $0 === engine }) else { return }
        engines.append(engine)
        watch(engine)
    }

    /// Ob diese Engine gerade ohne Player läuft (B07 · BUG-01: „Zurück zur App" hat dann keinen Player).
    func holds(_ engine: AnyObject) -> Bool {
        engines.contains { $0 === engine }
    }

    /// Beendet alle übernommenen Wiedergaben – samt Bild-in-Bild-Fenster. Ruft `PlayerView` auf, bevor sie eine
    /// Wiedergabe startet oder fortsetzt: nie zwei Streams zugleich (B07 · BUG-01).
    func stopAll() {
        let running = engines
        engines.removeAll()
        running.forEach { $0.stop() }
    }

    private func watch(_ engine: any PlaybackEngine) {
        let id = ObjectIdentifier(engine)
        withObservationTracking {
            _ = engine.isPictureInPictureActive
        } onChange: { [weak self] in
            // `onChange` kommt vor der Änderung – erst danach auf dem Hauptthread neu prüfen.
            Task { @MainActor [weak self] in self?.recheck(id) }
        }
    }

    private func recheck(_ id: ObjectIdentifier) {
        guard let index = engines.firstIndex(where: { ObjectIdentifier($0) == id }) else { return }
        let engine = engines[index]
        if engine.isPictureInPictureActive {
            watch(engine)
        } else {
            engines.remove(at: index)
            engine.stop()
        }
    }
}
