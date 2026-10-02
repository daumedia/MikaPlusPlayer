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
    /// Review R-10: einmalige Umstellungen beim Start laufen im Hintergrund.
    @State private var maintenance: LaunchMaintenance

    init() {
        // B01 · BUG-04: app-eigener Speicherort, Übernahme der alten default.store; Test-Host im Speicher.
        // B09 · BUG-13: versioniertes Schema mit Migrationsplan; nicht zu öffnende Datei wird beiseitegelegt
        //               statt fatalError.
        // B01 · BUG-01/BUG-03: danach Zugangsdaten aus Altbeständen in den Schlüsselbund, alten HTTP-Cache leeren –
        //               seit Review R-10 im Hintergrund; das Fenster erscheint sofort und zeigt solange einen Hinweis.
        let launch = AppPersistence.openAppStore()
        modelContainer = launch.container
        _storeNotice = State(initialValue: StoreNoticeCenter(notice: launch.outcome.notice))
        _maintenance = State(initialValue: launch.maintenance)
    }

    #if os(macOS)
    /// Sparkle-Auto-Updater (nur macOS); im Test-Host angelegt, aber nicht gestartet (B09 · BF-49).
    @State private var updater = SparkleUpdater()
    /// Geteilte Multiview-Session (nur macOS): erreicht Haupt- und Multiview-Fenster.
    @State private var multiview = MultiviewSession()
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .launchMaintenanceCover(maintenance)
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
            // B09 · BF-18 / AK-31: drei Update-Einträge als eigene Ansicht (Zustand im eigenen Rumpf beobachtet).
            CommandGroup(after: .appInfo) {
                UpdateMenu(updater: updater)
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
    /// Läuft noch die Umstellung beim Start, wartet das Entfernen hinter ihr (gleicher Actor, Review R-10).
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

/// Deckt die App ab, solange die Umstellungen beim Start laufen (Review R-10): Die Oberfläche ist gesperrt, und dauert
/// es länger als einen Augenblick, erscheint ein Hinweis mit Fortschrittsanzeige. Im Normalfall (nichts umzustellen)
/// sind es Millisekunden – dann erscheint der Hinweis nicht. Als Überlagerung, nicht als Weiche um `ContentView`: Eine
/// Weiche an der Wurzel des Fensters hielt im Test Kontextmenüs anderer Fenster offen, solange eine Aktualisierung lief.
struct LaunchMaintenanceCover: ViewModifier {
    let maintenance: LaunchMaintenance
    @State private var showsHint = false

    func body(content: Content) -> some View {
        content
            .disabled(maintenance.isRunning)
            .accessibilityHidden(maintenance.isRunning)
            .overlay {
                if maintenance.isRunning {
                    ZStack {
                        Color.playerBackground
                        if showsHint {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Gespeicherte Playlists werden aktualisiert …")
                                    .font(.headline)
                                Text("Das geschieht einmalig nach einem Update und kann bei großen Senderlisten einige Sekunden dauern.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(32)
                        }
                    }
                    .task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        showsHint = true
                    }
                }
            }
    }
}

extension View {
    func launchMaintenanceCover(_ maintenance: LaunchMaintenance) -> some View {
        modifier(LaunchMaintenanceCover(maintenance: maintenance))
    }
}
