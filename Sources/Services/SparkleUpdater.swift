#if os(macOS)
import Foundation
@preconcurrency import Sparkle

/// Dünner Wrapper um Sparkles `SPUStandardUpdaterController` – analog zu den
/// anderen Mika+ Apps. Nur macOS (Sparkle ist macOS-only, DMG-Distribution).
///
/// B09 · Durchlauf 2 (2026-10-02): Spiegelt die vier Werte, die das Update-Menü zeigt (BF-18, AK-31), und startet
/// Sparkle im Test-Host nicht (BF-49, Entwurf Entscheidung 8). Die beiden Einstellungen gehören Sparkle: Der Wrapper
/// liest sie nur über den Spiegel und schreibt sie ausschließlich auf eine Nutzeraktion im Menü (Entscheidung 7) –
/// keine eigenen Vorgaben, nichts beim Start.
@MainActor
@Observable
final class SparkleUpdater {
    /// Ob aktuell nach Updates gesucht werden kann (für den Menü-Button).
    ///
    /// B09 · BUG-18: gespeicherte, beobachtete Eigenschaft. Sparkles Werte sind nur per KVO beobachtbar; eine
    /// berechnete Durchreiche über `@ObservationIgnored`-Speicher registriert in SwiftUI keine Abhängigkeit, der
    /// Menüeintrag konnte deshalb veralten. Die Werte werden per KVO hierher gespiegelt.
    private(set) var canCheckForUpdates = false
    /// Sparkle-Einstellung „automatisch nach Updates suchen“ (`SUEnableAutomaticChecks`).
    private(set) var automaticallyChecksForUpdates = false
    /// Sparkle-Einstellung „Updates automatisch laden und installieren“; Sparkle meldet sie falsch, solange
    /// automatisches Installieren nicht erlaubt ist (der gespeicherte Wert bleibt erhalten).
    private(set) var automaticallyDownloadsUpdates = false
    /// Ob Sparkle automatisches Installieren erlaubt (ohne `SUAllowsAutomaticUpdates`: nur bei automatischer Prüfung).
    private(set) var allowsAutomaticUpdates = false
    /// Sparkle ist gestartet; im Test-Host nicht (BF-49). Dann ist das Menü inaktiv und es wird nichts geschrieben.
    let isRunning: Bool

    /// Schlüsselpfade der gespiegelten Werte (in der App `SPUUpdater`, in Tests eine Attrappe).
    struct KeyPaths<Source: NSObject> {
        let canCheckForUpdates: KeyPath<Source, Bool>
        let automaticallyChecksForUpdates: ReferenceWritableKeyPath<Source, Bool>
        let automaticallyDownloadsUpdates: ReferenceWritableKeyPath<Source, Bool>
        let allowsAutomaticUpdates: KeyPath<Source, Bool>
    }

    @ObservationIgnored private let checkAction: () -> Void
    @ObservationIgnored private let writeAutomaticChecks: (Bool) -> Void
    @ObservationIgnored private let writeAutomaticDownloads: (Bool) -> Void
    /// Enden mit dem Wrapper (NSKeyValueObservation beendet die Beobachtung beim Freigeben selbst).
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    /// Hält den Controller am Leben (Sparkle-Updater läuft, solange er existiert).
    @ObservationIgnored private let owner: AnyObject?

    convenience init() {
        // Im Test-Host wird der Controller angelegt, aber nicht gestartet: keine Feed-Abfrage, kein Zeitplan,
        // keine Schreibvorgänge (B09 · BF-49). Debug startet mit der Vorgabe „automatische Prüfung aus“
        // (Info.plist SUEnableAutomaticChecks aus MIKA_SPARKLE_AUTOMATIC_CHECKS), Release mit „an“.
        let start = !AppEnvironment.isRunningTests
        let controller = SPUStandardUpdaterController(
            startingUpdater: start,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.init(source: controller.updater, keyPaths: KeyPaths(
            canCheckForUpdates: \.canCheckForUpdates,
            automaticallyChecksForUpdates: \.automaticallyChecksForUpdates,
            automaticallyDownloadsUpdates: \.automaticallyDownloadsUpdates,
            allowsAutomaticUpdates: \.allowsAutomaticUpdates), isRunning: start, owner: controller) {
            controller.checkForUpdates(nil)
        }
    }

    /// - Parameters:
    ///   - source: KVO-fähiges Objekt (in der App `SPUUpdater`)
    ///   - keyPaths: seine vier Werte
    ///   - isRunning: ob der Updater gestartet ist
    ///   - owner: wird gehalten, solange dieser Wrapper lebt
    ///   - check: löst die manuelle Prüfung aus
    init<Source: NSObject>(source: Source, keyPaths: KeyPaths<Source>, isRunning: Bool = true,
                           owner: AnyObject? = nil, check: @escaping () -> Void) {
        self.owner = owner
        self.isRunning = isRunning
        self.checkAction = check
        self.writeAutomaticChecks = { source[keyPath: keyPaths.automaticallyChecksForUpdates] = $0 }
        self.writeAutomaticDownloads = { source[keyPath: keyPaths.automaticallyDownloadsUpdates] = $0 }
        canCheckForUpdates = source[keyPath: keyPaths.canCheckForUpdates]
        automaticallyChecksForUpdates = source[keyPath: keyPaths.automaticallyChecksForUpdates]
        automaticallyDownloadsUpdates = source[keyPath: keyPaths.automaticallyDownloadsUpdates]
        allowsAutomaticUpdates = source[keyPath: keyPaths.allowsAutomaticUpdates]
        observations = [
            mirror(source, keyPaths.canCheckForUpdates, into: .canCheckForUpdates),
            mirror(source, keyPaths.automaticallyChecksForUpdates, into: .automaticallyChecksForUpdates),
            mirror(source, keyPaths.automaticallyDownloadsUpdates, into: .automaticallyDownloadsUpdates),
            mirror(source, keyPaths.allowsAutomaticUpdates, into: .allowsAutomaticUpdates),
        ]
    }

    /// Die gespiegelten Werte.
    private enum Field {
        case canCheckForUpdates, automaticallyChecksForUpdates, automaticallyDownloadsUpdates, allowsAutomaticUpdates
    }

    /// Beobachtet einen Wert der Quelle per KVO und überträgt Änderungen auf dem Main-Actor in den Spiegel.
    private func mirror<Source: NSObject>(_ source: Source, _ keyPath: KeyPath<Source, Bool>,
                                          into field: Field) -> NSKeyValueObservation {
        source.observe(keyPath, options: [.new]) { [weak self] _, change in
            guard let value = change.newValue else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.apply(value, to: field) }
            } else {
                Task { @MainActor in self?.apply(value, to: field) }
            }
        }
    }

    /// Schreibt nur bei einer echten Änderung (sonst bekäme SwiftUI unnötige Änderungsmeldungen).
    private func apply(_ value: Bool, to field: Field) {
        switch field {
        case .canCheckForUpdates:
            if canCheckForUpdates != value { canCheckForUpdates = value }
        case .automaticallyChecksForUpdates:
            if automaticallyChecksForUpdates != value { automaticallyChecksForUpdates = value }
        case .automaticallyDownloadsUpdates:
            if automaticallyDownloadsUpdates != value { automaticallyDownloadsUpdates = value }
        case .allowsAutomaticUpdates:
            if allowsAutomaticUpdates != value { allowsAutomaticUpdates = value }
        }
    }

    /// Manueller Update-Check (zeigt Sparkles UI mit Fortschritt/Release-Notes).
    func checkForUpdates() {
        checkAction()
    }

    /// Nutzeraktion im Menü: setzt Sparkles Einstellung; der Spiegel folgt über die Beobachtung.
    func setAutomaticallyChecksForUpdates(_ value: Bool) {
        guard isRunning else { return }
        writeAutomaticChecks(value)
    }

    /// Nutzeraktion im Menü: setzt Sparkles Einstellung; der Spiegel folgt über die Beobachtung.
    func setAutomaticallyDownloadsUpdates(_ value: Bool) {
        guard isRunning else { return }
        writeAutomaticDownloads(value)
    }

    /// Zustand der drei Menüeinträge (design.md, *Zustände des Update-Menüs*).
    var menuState: UpdateMenuState {
        UpdateMenuState(
            checkEnabled: isRunning && canCheckForUpdates,
            automaticChecksOn: automaticallyChecksForUpdates,
            automaticChecksEnabled: isRunning,
            automaticDownloadsOn: allowsAutomaticUpdates && automaticallyDownloadsUpdates,
            automaticDownloadsEnabled: isRunning && allowsAutomaticUpdates)
    }
}

/// Was die drei Update-Einträge im App-Menü zeigen.
struct UpdateMenuState: Equatable {
    /// „Nach Updates suchen …“ aktiv
    var checkEnabled: Bool
    /// Häkchen „Automatisch nach Updates suchen“
    var automaticChecksOn: Bool
    var automaticChecksEnabled: Bool
    /// Häkchen „Updates automatisch installieren“
    var automaticDownloadsOn: Bool
    var automaticDownloadsEnabled: Bool
}
#endif
