import CoreGraphics
import Foundation
// Listet sichtbare Bild-in-Bild-Systemfenster (nur Metadaten) und Fenster eines Prozesses (Argument: PID).
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let pid = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? -1 : -1
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
    let opid = w[kCGWindowOwnerPID as String] as? Int ?? 0
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let wd = b["Width"] as? Double ?? 0, ht = b["Height"] as? Double ?? 0
    let isPip = owner.lowercased().contains("bild-in-bild") || owner.lowercased().contains("picture in picture")
    if (isPip && wd > 80) || opid == pid {
        print("\(isPip ? "PIP" : "APP") id=\(w[kCGWindowNumber as String] ?? 0) owner=\(owner) pid=\(opid) layer=\(w[kCGWindowLayer as String] ?? 0) \(Int(wd))x\(Int(ht)) name='\(w[kCGWindowName as String] ?? "")'")
    }
}
