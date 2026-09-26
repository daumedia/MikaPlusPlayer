import Foundation

/// Bremst wiederholte Fehlanmeldungen je Panel (B01 · BUG-07).
///
/// Viele Panels sperren IP-Adresse oder Konto nach mehreren Fehlversuchen. Nach
/// `freeAttempts` abgelehnten Anmeldungen in Folge sperrt die App weitere Versuche
/// gegen dasselbe Panel (Host und Port): zuerst `baseLock` Sekunden, mit jedem weiteren
/// Fehlschlag doppelt so lange, höchstens `maxLock`. Eine erfolgreiche Anmeldung setzt
/// den Zähler zurück. Gesperrte Versuche erreichen das Panel nicht.
final class XtreamLoginThrottle: @unchecked Sendable {
    static let shared = XtreamLoginThrottle()

    let freeAttempts: Int
    let baseLock: TimeInterval
    let maxLock: TimeInterval
    private let now: @Sendable () -> Date

    private struct Entry {
        var failures = 0
        var lockedUntil: Date?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    init(freeAttempts: Int = 3, baseLock: TimeInterval = 30, maxLock: TimeInterval = 300,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.freeAttempts = freeAttempts
        self.baseLock = baseLock
        self.maxLock = maxLock
        self.now = now
    }

    /// Schlüssel eines Panels: Schema, Host und Port, kleingeschrieben.
    static func key(for base: URL) -> String {
        let scheme = base.scheme?.lowercased() ?? "http"
        let port = base.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(base.host?.lowercased() ?? ""):\(port)"
    }

    /// Verbleibende Sperrzeit in Sekunden, `nil`, wenn ein Versuch erlaubt ist.
    func remainingLock(for key: String) -> TimeInterval? {
        lock.withLock {
            guard let until = entries[key]?.lockedUntil else { return nil }
            let remaining = until.timeIntervalSince(now())
            return remaining > 0 ? remaining : nil
        }
    }

    func recordFailure(for key: String) {
        lock.withLock {
            var entry = entries[key] ?? Entry()
            entry.failures += 1
            if entry.failures >= freeAttempts {
                let exponent = Double(entry.failures - freeAttempts)
                let duration = min(baseLock * pow(2, exponent), maxLock)
                entry.lockedUntil = now().addingTimeInterval(duration)
            }
            entries[key] = entry
        }
    }

    func recordSuccess(for key: String) {
        lock.withLock { _ = entries.removeValue(forKey: key) }
    }
}
