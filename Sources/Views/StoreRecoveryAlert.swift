import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Hält den Hinweis aus dem Start, bis der Nutzer ihn bestätigt (B09 · BUG-13).
@MainActor
@Observable
final class StoreNoticeCenter {
    var notice: AppPersistence.StoreNotice?

    init(notice: AppPersistence.StoreNotice?) {
        self.notice = notice
    }
}

/// Meldet, dass die Datenbank beim Start beiseitegelegt und neu angelegt wurde.
private struct StoreRecoveryAlert: ViewModifier {
    let center: StoreNoticeCenter

    func body(content: Content) -> some View {
        content.alert(
            center.notice?.title ?? "",
            isPresented: Binding(
                get: { center.notice != nil },
                set: { if !$0 { center.notice = nil } }
            ),
            presenting: center.notice
        ) { notice in
            #if os(macOS)
            if let folder = notice.folder {
                Button("Im Finder zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                    center.notice = nil
                }
            }
            #endif
            Button("OK", role: .cancel) { center.notice = nil }
        } message: { notice in
            Text(notice.message)
        }
    }
}

extension View {
    func storeRecoveryAlert(_ center: StoreNoticeCenter) -> some View {
        modifier(StoreRecoveryAlert(center: center))
    }
}
