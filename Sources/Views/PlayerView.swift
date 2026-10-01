import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Wiedergabe-Ansicht. Wählt über die `PlaybackEngineFactory` die passende
/// Engine (AVKit für HLS, VLCKit für rohe TS-Streams) und zeigt je nach
/// Status Player, Ladeanzeige oder einen Fehler-Fallback. Unterstützt Vollbild.
struct PlayerView: View {
    let channel: Channel

    /// Die aktuell verwendete Engine. Über `any PlaybackEngine` typisiert,
    /// damit der View engine-unabhängig bleibt.
    @State private var engine: (any PlaybackEngine)?
    /// Adresse ließ sich nicht bilden (z. B. Xtream-Zugangsdaten fehlen im Schlüsselbund).
    @State private var resolveError: String?
    @State private var isFullscreen = false
    @State private var showControls = true
    @State private var autoHideTask: Task<Void, Never>?
    /// macOS: true, wenn der Mauszeiger nahe dem oberen Rand schwebt.
    @State private var topHover = false
    /// Fokus für die Tastatur-Steuerung (Leertaste, M, ↑/↓ usw.).
    @FocusState private var keyboardFocused: Bool
    /// Kurzzeitig eingeblendetes Feedback (HUD) bei Tastatur-/Button-Aktionen.
    @State private var hud: HUDKind?
    @State private var hudTask: Task<Void, Never>?
    /// B06 · BUG-02: wahr, solange der Player im Navigationsstapel liegt – auch in einem gerade verdeckten Tab.
    /// Wird er falsch, hat der Nutzer den Player verlassen („Zurück").
    @Environment(\.isPresented) private var isPresented
    /// B07 · BUG-01: sichtbarer Tab des Fensters (nur in `ContentView`) und der Tab, in dem dieser Player liegt.
    @Environment(ShellTabs.self) private var shellTabs: ShellTabs?
    @State private var ownTab: ShellTabs.Tab?
    #if os(macOS)
    /// B06 · BUG-06: das Fenster, in dem dieser Player liegt.
    @State private var hostWindow = PlayerHostWindow()
    #endif

    /// Schrittweite der Lautstärke-Tasten (5 %).
    private let volumeStep = 0.05

    /// Art des HUD-Feedbacks.
    private enum HUDKind: Equatable {
        case playPause(Bool)   // isPaused
        case mute(Bool)        // isMuted
        case volume(Double)    // 0…1
        /// Kurze Erklärung mit Symbol, z. B. warum es kein Bild-in-Bild gibt (B07 · BUG-04).
        case notice(symbol: String, text: String)
    }

    var body: some View {
        ZStack {
            Color.black

            if let engine {
                engine.makePlayerView()
                stateOverlay(engine)
                controlsOverlay
                hudOverlay
            } else if let resolveError {
                failureView(resolveError)
            } else {
                loadingIndicator
            }
        }
        #if os(macOS)
        .background(PlayerWindowReader { attach(to: $0) })
        #endif
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
        .focusable()
        .focusEffectDisabled()
        .focused($keyboardFocused)
        #if os(iOS)
        // B06 · BUG-08: am iPad nimmt sonst die Tab-Leiste den Tastaturfokus.
        .defaultFocus($keyboardFocused, true)
        #endif
        .onKeyPress { handleKey($0) }
        #if os(macOS)
        .onContinuousHover { handleHover($0) }
        #endif
        .ignoresSafeArea(edges: isFullscreen ? .all : [])
        .navigationTitle(isFullscreen ? "" : channel.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isFullscreen ? .hidden : .visible, for: .navigationBar)
        // B06 · BUG-09: Leiste über der schwarzen Fläche dunkel, damit der Sendername auch im hellen
        // Erscheinungsbild lesbar ist.
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(isFullscreen ? .hidden : .visible, for: .tabBar)
        .statusBarHidden(isFullscreen)
        .persistentSystemOverlays(isFullscreen ? .hidden : .automatic)
        #elseif os(macOS)
        // Obere Fenster-Toolbar/Titelleiste im Vollbild ausblenden – erscheint
        // wieder, sobald der Mauszeiger nahe den oberen Rand kommt.
        .toolbar(macToolbarVisibility, for: .windowToolbar)
        // B06 · BUG-06: Vollbild des eigenen Fensters mitführen – auch über den grünen Knopf, das Menü oder einen
        // Tabwechsel.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            windowFullscreenChanged(note, entered: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            windowFullscreenChanged(note, entered: false)
        }
        // B06 · BUG-02: Fenster schließen (⌘W) ist ebenfalls Verlassen.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            guard hostWindow.contains(note) else { return }
            leavePlayer()
        }
        #endif
        .onAppear {
            if ownTab == nil { ownTab = shellTabs?.selected }
            startIfNeeded()
            scheduleAutoHide()
            keyboardFocused = true
            #if os(iOS)
            refocusAfterPush()
            #endif
        }
        .onChange(of: isPresented) { _, presented in
            // B06 · BUG-02: „Zurück" – Wiedergabe und Verbindung beenden.
            if !presented { leavePlayer() }
        }
        .onReceive(NotificationCenter.default.publisher(for: PlaylistEvents.willDelete)) { note in
            handlePlaylistDeletion(PlaylistEvents.ids(in: note))
        }
        .onDisappear {
            autoHideTask?.cancel()
            hudTask?.cancel()
            leaveFullscreenOnDisappear()
            if stillInStack {
                // Noch im Stapel, z. B. Tabwechsel (AK-27): nur anhalten, dieselbe Engine setzt bei der Rückkehr fort.
                // Bei aktivem PiP NICHT pausieren – sonst würgt der Ansichtswechsel die schwebende Wiedergabe ab.
                if engine?.isPictureInPictureActive != true {
                    engine?.pause()
                }
            } else {
                // B06 · BUG-02: Player verlassen (bzw. nie im Stapel, z. B. als Wurzel eines Fensters).
                leavePlayer()
            }
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private func stateOverlay(_ engine: any PlaybackEngine) -> some View {
        switch engine.state {
        case .loading, .idle:
            loadingIndicator
        case .failed(let message):
            failureView(message)
        case .playing:
            EmptyView()
        }
    }

    /// Steuerungs-Overlay mit Vollbild-Umschalter (per Tap bzw. Hover sichtbar).
    @ViewBuilder
    private var controlsOverlay: some View {
        if controlsVisible, case .playing = engine?.state {
            VStack {
                HStack(spacing: 12) {
                    Spacer()
                    if engine?.supportsPictureInPicture == true {
                        Button(action: togglePiP) {
                            controlIcon(engine?.isPictureInPictureActive == true
                                        ? "pip.exit" : "pip.enter")
                        }
                        .buttonStyle(.plain)
                        .help("Bild-in-Bild")
                    }
                    Button(action: toggleFullscreen) {
                        controlIcon(isFullscreen
                                    ? "arrow.down.right.and.arrow.up.left"
                                    : "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.plain)
                }
                .padding(isFullscreen ? 24 : 12)
                Spacer()
                bottomControls
            }
            .transition(.opacity)
        }
    }

    /// Untere Leiste: Play/Pause und Stumm (Tastatur-Pendants: Leertaste / M).
    @ViewBuilder
    private var bottomControls: some View {
        HStack(spacing: 20) {
            Button(action: togglePlay) {
                controlIcon(engine?.isPaused == true ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.plain)
            Button(action: toggleMute) {
                controlIcon(engine?.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.plain)
            #if os(iOS)
            // B07 · BUG-05: Am iPad liegt das Bild-in-Bild-Fenster oft über dem Knopf oben rechts. Solange es offen
            // ist, beendet es ein zweiter Knopf unten links – ohne das Fenster erst zu verschieben.
            if engine?.isPictureInPictureActive == true {
                Button(action: togglePiP) {
                    Label("Bild-in-Bild beenden", systemImage: "pip.exit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.5), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            #endif
            Spacer()
        }
        .padding(isFullscreen ? 24 : 12)
    }

    /// Ladeanzeige: groß und weiß auf der schwarzen Fläche (Design-System „Laden (Video)").
    /// B06 · BUG-09: `.tint(.white)` färbt den kreisförmigen Indikator am Mac nicht (grau). Das dunkle
    /// Farbschema lässt ihn unabhängig vom Erscheinungsbild der App gleich zeichnen, `brightness(1)` macht ihn
    /// dann weiß und lässt die Deckkraft des Systems stehen.
    private var loadingIndicator: some View {
        ProgressView()
            .controlSize(.large)
            .tint(.white)
            .environment(\.colorScheme, .dark)
            .brightness(1)
    }

    private func controlIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .padding(12)
            .background(.black.opacity(0.5), in: Circle())
    }

    /// Zentrales, kurz eingeblendetes Feedback bei Tastatur-/Button-Aktionen.
    @ViewBuilder
    private var hudOverlay: some View {
        if let hud {
            Group {
                switch hud {
                case .playPause(let paused):
                    Image(systemName: paused ? "pause.fill" : "play.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                case .mute(let muted):
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                case .volume(let value):
                    volumeHUD(value)
                case .notice(let symbol, let text):
                    VStack(spacing: 10) {
                        Image(systemName: symbol)
                            .font(.system(size: 32, weight: .bold))
                            .accessibilityHidden(true)   // sonst liest VoiceOver den englischen Symbolnamen
                        Text(text)
                            .font(.callout.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: 260)
                }
            }
            .padding(28)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func volumeHUD(_ value: Double) -> some View {
        VStack(spacing: 10) {
            Image(systemName: volumeSymbol(value))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .frame(width: 140)
                .tint(.playerAccent)
            Text("\(Int((value * 100).rounded())) %")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    private func volumeSymbol(_ value: Double) -> String {
        if value <= 0 { return "speaker.slash.fill" }
        if value < 0.34 { return "speaker.wave.1.fill" }
        if value < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    @ViewBuilder
    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Wiedergabe fehlgeschlagen", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
            if showsMissingVLCKitHint {
                Text("Hinweis: Rohe MPEG-TS-Streams (.ts) benötigen VLCKit – siehe README.")
                    .font(.footnote)
            }
        } actions: {
            Button {
                retry()
            } label: {
                // B04 · Review R-1: Schrift `playerOnAccent` statt Weiß auf dem Akzent
                Text("Erneut versuchen").playerOnAccentLabel()
            }
            .buttonStyle(.borderedProminent)
            .tint(.playerAccent)
        }
        .background(.ultraThinMaterial)
    }

    /// B06 · BUG-04: Der README-Hinweis gilt nur für einen Build ohne VLCKit (README „Ohne VLCKit"). Mit VLCKit
    /// hat ein Fehler eine andere Ursache, und Endnutzer haben keine README.
    private var showsMissingVLCKitHint: Bool {
        #if canImport(VLCKitSPM) || canImport(MobileVLCKit) || canImport(VLCKit)
        return false
        #else
        return StreamType(url: channel.streamURL) == .transportStream
        #endif
    }

    /// Abspielbare Adresse – bei Xtream mit Zugangsdaten aus dem Schlüsselbund (B01 · BUG-01).
    private func playableURL() -> URL? {
        do {
            let url = try StreamURLResolver.playableURL(for: channel)
            resolveError = nil
            return url
        } catch {
            resolveError = error.localizedDescription
            return nil
        }
    }

    private func retry() {
        guard let url = playableURL() else { return }
        if let engine {
            engine.load(url)
        } else {
            startIfNeeded()
        }
    }

    // MARK: - Steuerung

    /// Ob die eigene Steuerung (Vollbild-Button) sichtbar ist.
    private var controlsVisible: Bool {
        #if os(macOS)
        return showControls || (isFullscreen && topHover)
        #else
        return showControls
        #endif
    }

    #if os(macOS)
    /// Sichtbarkeit der nativen Fenster-Toolbar: normal automatisch, im Vollbild
    /// nur beim Hover am oberen Rand.
    private var macToolbarVisibility: Visibility {
        guard isFullscreen else { return .automatic }
        return topHover ? .visible : .hidden
    }

    private func handleHover(_ phase: HoverPhase) {
        let near: Bool
        switch phase {
        case .active(let location): near = location.y < 90
        case .ended: near = false
        @unknown default: near = false
        }
        if near != topHover {
            withAnimation(.easeInOut(duration: 0.2)) { topHover = near }
        }
    }
    #endif

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
        if showControls { scheduleAutoHide() }
        #if os(iOS)
        // B06 · BUG-08: ein Tipp aufs Bild holt den Tastaturfokus zurück (iPad).
        keyboardFocused = true
        #endif
    }

    /// Blendet die Steuerung nach kurzer Inaktivität automatisch aus.
    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showControls = false }
        }
    }

    private func toggleFullscreen() {
        let target = !isFullscreen
        withAnimation(.easeInOut(duration: 0.25)) { isFullscreen = target }
        applyFullscreenSideEffects(target)
        showControls = true
        scheduleAutoHide()
        // macOS: Beim nativen Fullscreen-Wechsel wechselt das Key-Window – Fokus halten.
        keyboardFocused = true
    }

    // MARK: - Tastatur & Aktionen

    /// Wertet einen Tastendruck aus. `.handled` unterdrückt u. a. den macOS-Systembeep.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .space:
            togglePlay(); return .handled
        case .upArrow:
            changeVolume(volumeStep); return .handled
        case .downArrow:
            changeVolume(-volumeStep); return .handled
        case .escape:
            if isFullscreen { toggleFullscreen(); return .handled }
            return .ignored
        default:
            break
        }
        switch press.characters.lowercased() {
        case "m":
            toggleMute(); return .handled
        case "f":
            toggleFullscreen(); return .handled
        case "p":
            togglePiP(); return .handled
        case "+", "=":
            changeVolume(volumeStep); return .handled
        case "-":
            changeVolume(-volumeStep); return .handled
        default:
            return .ignored
        }
    }

    private func togglePlay() {
        guard let engine else { return }
        engine.togglePlayPause()
        flashControls()
        showHUD(.playPause(engine.isPaused))
    }

    private func toggleMute() {
        guard let engine else { return }
        engine.toggleMute()
        flashControls()
        showHUD(.mute(engine.isMuted))
    }

    private func togglePiP() {
        if let engine, !engine.supportsPictureInPicture, PlaybackEngineFactory.deviceSupportsPictureInPicture {
            // B07 · BUG-04: Das Gerät kann Bild-in-Bild, dieser Sender (MPEG-TS über VLC) nicht – kurz sagen, warum.
            showHUD(.notice(symbol: "pip", text: "Bild-in-Bild gibt es nur mit HLS, nicht mit MPEG-TS."), seconds: 3)
        } else {
            engine?.togglePictureInPicture()
        }
        flashControls()
    }

    private func changeVolume(_ delta: Double) {
        guard let engine else { return }
        engine.setVolume(engine.volume + delta)
        showHUD(.volume(engine.volume))
    }

    /// Blendet die Steuerung kurz ein und startet den Auto-Hide neu.
    private func flashControls() {
        withAnimation(.easeInOut(duration: 0.2)) { showControls = true }
        scheduleAutoHide()
    }

    /// Zeigt das HUD-Feedback und blendet es nach kurzer Zeit wieder aus.
    private func showHUD(_ kind: HUDKind, seconds: Double = 0.9) {
        withAnimation(.easeInOut(duration: 0.15)) { hud = kind }
        hudTask?.cancel()
        hudTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { hud = nil }
        }
    }

    // MARK: - Plattform-spezifisches Vollbild

    private func applyFullscreenSideEffects(_ fullscreen: Bool) {
        #if os(iOS)
        // Auf dem iPhone Querformat anfordern (iPad/Info.plist erlauben Rotation ohnehin).
        guard UIDevice.current.userInterfaceIdiom == .phone,
              let scene = activeWindowScene else { return }
        let mask: UIInterfaceOrientationMask = fullscreen ? .landscapeRight : .portrait
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        #elseif os(macOS)
        // B06 · BUG-06: natives Vollbild immer des Fensters, in dem dieser Player liegt – nicht des Schlüsselfensters.
        guard let window = hostWindow.window else { return }
        if window.styleMask.contains(.fullScreen) != fullscreen { window.toggleFullScreen(nil) }
        #endif
    }

    /// Beim Verschwinden (Verlassen, Tabwechsel) das Vollbild beenden und den Zustand mitführen (BUG-06).
    private func leaveFullscreenOnDisappear() {
        guard isFullscreen else { return }
        applyFullscreenSideEffects(false)
        isFullscreen = false
    }

    #if os(macOS)
    /// Merkt sich das Fenster des Players und übernimmt dessen Vollbild-Zustand (BUG-06).
    private func attach(to window: NSWindow) {
        hostWindow.window = window
        let windowFullscreen = window.styleMask.contains(.fullScreen)
        if windowFullscreen != isFullscreen { isFullscreen = windowFullscreen }
    }

    /// Das Fenster des Players hat das Vollbild betreten bzw. verlassen – egal, wodurch (BUG-06).
    private func windowFullscreenChanged(_ note: Notification, entered: Bool) {
        guard hostWindow.contains(note), isFullscreen != entered else { return }
        withAnimation(.easeInOut(duration: 0.25)) { isFullscreen = entered }
        showControls = true
        scheduleAutoHide()
        keyboardFocused = true
    }
    #endif

    #if os(iOS)
    /// B06 · BUG-08: Am iPad übernimmt nach dem Einblenden des Players die Tab-Leiste den Fokus; den Fokus deshalb
    /// nach dem Übergang erneut anfordern.
    private func refocusAfterPush() {
        Task { @MainActor in
            for delay in [0.35, 1.0] {
                try? await Task.sleep(for: .seconds(delay))
                keyboardFocused = true
            }
        }
    }
    #endif

    #if os(iOS)
    private var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
    #endif

    // MARK: - Wiedergabe

    /// B03 · BUG-05: Die Playlist des Senders wird gelöscht → Wiedergabe und Verbindung (bei Xtream mit
    /// Zugangsdaten im Pfad) beenden und das statt eines Engine-Fehlers anzeigen. „Erneut versuchen" meldet danach
    /// dasselbe, ohne den Anbieter anzufragen.
    private func handlePlaylistDeletion(_ ids: Set<UUID>) {
        guard let playlistID = channel.playlistID ?? channel.playlist?.id, ids.contains(playlistID) else { return }
        engine?.stop()
        engine = nil
        resolveError = StreamURLResolver.ResolveError.playlistDeleted.localizedDescription
    }

    /// Liegt der Player beim Verschwinden noch im Stapel (Tabwechsel)? In `ContentView` entscheidet der sichtbare
    /// Tab: Ist der eigene Tab weiter sichtbar, wurde der Player verlassen – auch wenn `isPresented` am Mac (tiefer
    /// Stapel) noch wahr meldet (B07 · BUG-01). Ohne `ShellTabs` (eigene Fenster, Tests) gilt `isPresented`.
    private var stillInStack: Bool {
        if let shellTabs, let ownTab { return shellTabs.selected != ownTab }
        return isPresented
    }

    /// B06 · BUG-02: Der Nutzer verlässt den Player. Wiedergabe und Verbindung enden (AVKit: Element frei,
    /// VLC: stoppen und Player abbauen) – außer Bild-in-Bild läuft: dann spielt das schwebende Fenster weiter, bis
    /// Bild-in-Bild endet, und die Wiedergabe endet dann ebenfalls (`DetachedPlayback`).
    private func leavePlayer() {
        guard let current = engine else { return }
        engine = nil
        DetachedPlayback.shared.adopt(current)
    }

    private func startIfNeeded() {
        // B07 · BUG-01: Eine Wiedergabe, die nach „Zurück" im Bild-in-Bild-Fenster weiterläuft, endet, sobald ein
        // Player startet oder fortsetzt – nie zwei Streams zugleich.
        DetachedPlayback.shared.stopAll()
        if engine == nil {
            guard let url = playableURL() else { return }
            let newEngine = PlaybackEngineFactory.engine(for: url)
            engine = newEngine
            newEngine.load(url)
            // Nur der Einzel-Player startet automatisch PiP beim App-Wechsel (iOS).
            newEngine.setAutomaticPictureInPicture(true)
        } else {
            engine?.play()
        }
    }
}

#if os(macOS)
/// Schwache Referenz auf das Fenster eines Players (B06 · BUG-06). Bleibt über einen Tabwechsel erhalten, in dem
/// die Ansicht kurz ohne Fenster ist.
final class PlayerHostWindow {
    weak var window: NSWindow?

    func contains(_ note: Notification) -> Bool {
        guard let window, let other = note.object as? NSWindow else { return false }
        return other === window
    }
}

/// Meldet das Fenster, in dem die Ansicht liegt (B06 · BUG-06).
private struct PlayerWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowReportingView {
        let view = WindowReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowReportingView, context: Context) {
        nsView.onWindow = onWindow
    }

    final class WindowReportingView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Nicht während eines SwiftUI-Updates Zustand ändern.
            DispatchQueue.main.async { [weak self] in self?.onWindow?(window) }
        }
    }
}
#endif
