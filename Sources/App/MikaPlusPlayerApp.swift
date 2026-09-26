import SwiftUI
import SwiftData

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
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 720)
        #endif
    }
}
