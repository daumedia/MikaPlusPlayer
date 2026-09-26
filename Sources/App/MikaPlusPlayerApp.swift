import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

@main
struct MikaPlusPlayerApp: App {
    /// Gemeinsamer SwiftData-Container für beide Plattformen.
    let modelContainer: ModelContainer
    /// B09 · BUG-13: Hinweis, falls die Datenbank beim Start beiseitegelegt werden musste.
    @State private var storeNotice: StoreNoticeCenter

    init() {
        // B01 · BUG-04: app-eigener Speicherort, Übernahme der alten default.store; Test-Host im Speicher.
        // B09 · BUG-13: versioniertes Schema mit Migrationsplan; nicht zu öffnende Datei wird beiseitegelegt
        //               statt fatalError.
        // B01 · BUG-01/BUG-03: danach Zugangsdaten aus Altbeständen in den Schlüsselbund, alten HTTP-Cache leeren.
        let launch = AppPersistence.openAppStore()
        modelContainer = launch.container
        _storeNotice = State(initialValue: StoreNoticeCenter(notice: launch.outcome.notice))
    }

    #if os(macOS)
    /// Sparkle-Auto-Updater (nur macOS).
    @State private var updater = SparkleUpdater()
    /// Geteilte Multiview-Session (nur macOS): erreicht Haupt- und Multiview-Fenster.
    @State private var multiview = MultiviewSession()
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .storeRecoveryAlert(storeNotice)
                // B02 · BUG-06: „Öffnen mit"/Doppelklick bzw. iOS „Öffnen in" importiert die Datei – im offenen
                // Fenster, statt je Ereignis ein leeres Fenster zu erzeugen.
                .playlistDocumentHandler()
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            #if os(macOS)
                .environment(multiview)
            #endif
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen …") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
            // B03 · BUG-09: der Weg, alle gespeicherten Daten zu entfernen.
            CommandGroup(after: .appSettings) {
                Button("Alle Daten entfernen …") {
                    confirmAndEraseAllData()
                }
            }
        }
        #endif

        // Eigenständiges Multiview-Fenster (mehrere Streams gleichzeitig).
        // Dieselbe `multiview`-Instanz wie das Hauptfenster – so wirken die
        // „⊞"-Buttons der Senderliste live auf dieses Fenster.
        #if os(macOS)
        Window("Multiview", id: "multiview") {
            MultiviewScreen()
                .environment(multiview)
        }
        .modelContainer(modelContainer)
        .handlesExternalEvents(matching: [])
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 720)
        #endif
    }

    #if os(macOS)
    /// Rückfrage als Warnung mit zerstörender Standardtaste; danach `AppDataReset` (B03 · BUG-09).
    @MainActor
    private func confirmAndEraseAllData() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppDataReset.confirmationTitle
        alert.informativeText = AppDataReset.confirmationMessage
        alert.addButton(withTitle: "Alle Daten entfernen").hasDestructiveAction = true
        alert.addButton(withTitle: "Abbrechen")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let container = modelContainer
        Task { @MainActor in
            do {
                try await AppDataReset.eraseAll(context: container.mainContext, targets: .app(container: container))
            } catch {
                let failure = NSAlert(error: error)
                failure.runModal()
            }
        }
    }
    #endif
}
