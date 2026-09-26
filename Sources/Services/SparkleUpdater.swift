#if os(macOS)
import Foundation
@preconcurrency import Sparkle

/// Dünner Wrapper um Sparkles `SPUStandardUpdaterController` – analog zu den
/// anderen Mika+ Apps. Nur macOS (Sparkle ist macOS-only, DMG-Distribution).
@MainActor
@Observable
final class SparkleUpdater {
    /// Ob aktuell nach Updates gesucht werden kann (für den Menü-Button).
    ///
    /// B09 · BUG-18: gespeicherte, beobachtete Eigenschaft. Sparkles `canCheckForUpdates` ist nur per KVO
    /// beobachtbar; eine berechnete Durchreiche über `@ObservationIgnored`-Speicher registriert in SwiftUI
    /// keine Abhängigkeit, der Menüeintrag konnte deshalb veralten. Der Wert wird per KVO hierher gespiegelt.
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let checkAction: () -> Void
    /// Endet mit dem Wrapper (NSKeyValueObservation beendet die Beobachtung beim Freigeben selbst).
    @ObservationIgnored private var observation: NSKeyValueObservation?
    /// Hält den Controller am Leben (Sparkle-Updater läuft, solange er existiert).
    @ObservationIgnored private let owner: AnyObject?

    convenience init() {
        // startingUpdater: true -> startet den geplanten Update-Check automatisch.
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.init(source: controller.updater, canCheckForUpdates: \.canCheckForUpdates, owner: controller) {
            controller.checkForUpdates(nil)
        }
    }

    /// - Parameters:
    ///   - source: KVO-fähiges Objekt (in der App `SPUUpdater`)
    ///   - keyPath: seine Eigenschaft „kann prüfen"
    ///   - owner: wird gehalten, solange dieser Wrapper lebt
    ///   - check: löst die manuelle Prüfung aus
    init<Source: NSObject>(source: Source, canCheckForUpdates keyPath: KeyPath<Source, Bool>,
                           owner: AnyObject? = nil, check: @escaping () -> Void) {
        self.owner = owner
        self.checkAction = check
        self.canCheckForUpdates = source[keyPath: keyPath]
        observation = source.observe(keyPath, options: [.new]) { [weak self] _, change in
            guard let value = change.newValue else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.apply(value) }
            } else {
                Task { @MainActor in self?.apply(value) }
            }
        }
    }

    private func apply(_ value: Bool) {
        if canCheckForUpdates != value {
            canCheckForUpdates = value
        }
    }

    /// Manueller Update-Check (zeigt Sparkles UI mit Fortschritt/Release-Notes).
    func checkForUpdates() {
        checkAction()
    }
}
#endif
