import Foundation
import Security

/// Schlüsselbund-Ablage der Zugangsdaten, ein Eintrag je Playlist (B01 · BUG-01, B02 · BUG-01).
///
/// Eintrag: generisches Passwort, `service` = Dienstname, `account` = `Playlist.id`,
/// Inhalt = `XtreamSecret` (Xtream-Playlists) bzw. `M3USecret` (M3U-Adressen mit Zugangsdaten) als JSON.
/// Der Name stammt aus B01; die Ablage gilt heute für alle Importwege.
///
/// **Zugriffsklasse `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:**
/// - *AfterFirstUnlock*, weil Import und Aktualisieren großer Listen über eine Bildschirmsperre
///   hinweg laufen können (iOS, Hintergrund-Audio aktiv) und dann nicht am gesperrten Gerät scheitern sollen.
/// - *ThisDeviceOnly*, damit das Passwort weder über iCloud-Schlüsselbund noch über ein Backup auf ein
///   anderes Gerät wandert. Folge: Nach einer Wiederherstellung auf einem neuen Gerät müssen
///   Xtream-Playlists neu importiert werden.
/// - Nicht synchronisiert (`kSecAttrSynchronizable` bleibt aus).
///
/// macOS: Die Mac-App ist ad-hoc signiert und hat keine Schlüsselbund-Zugriffsgruppe, der
/// Data-Protection-Schlüsselbund steht ihr daher nicht zur Verfügung (`errSecMissingEntitlement`).
/// Der Eintrag landet im Anmelde-Schlüsselbund; die Zugriffsklasse wird dort nicht ausgewertet.
/// Schutz vor anderen Prozessen gibt die Zugriffsliste des Eintrags, die nur dieser App vertraut.
struct XtreamCredentialStore: Sendable {
    let service: String

    /// Dienst der App. Läuft die App als Test-Host, bekommt jeder Lauf einen eigenen Dienstnamen,
    /// damit Tests nie Einträge des Nutzers lesen oder verändern.
    static let standard = XtreamCredentialStore(
        service: AppEnvironment.isRunningTests
            ? "lu.daumedia.MikaPlusPlayer.xtream.tests.\(UUID().uuidString)"
            : "lu.daumedia.MikaPlusPlayer.xtream"
    )

    enum KeychainError: LocalizedError {
        case status(OSStatus)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .status(let status):
                return "Der Schlüsselbund hat den Zugriff auf die Zugangsdaten verweigert (Code \(status))."
            case .invalidData:
                return "Die gespeicherten Zugangsdaten sind beschädigt. Bitte die Playlist neu importieren."
            }
        }
    }

    func save(_ secret: XtreamSecret, for playlistID: UUID) throws {
        try store(secret, for: playlistID, label: "Mika+Player – Xtream-Zugang")
    }

    func load(for playlistID: UUID) throws -> XtreamSecret? {
        try value(XtreamSecret.self, for: playlistID)
    }

    /// Zugangsdaten einer M3U-Playlist (B02 · BUG-01).
    func saveM3U(_ secret: M3USecret, for playlistID: UUID) throws {
        try store(secret, for: playlistID, label: "Mika+Player – Playlist-Zugang")
    }

    func loadM3U(for playlistID: UUID) throws -> M3USecret? {
        try value(M3USecret.self, for: playlistID)
    }

    private func store<Value: Encodable>(_ value: Value, for playlistID: UUID, label: String) throws {
        let data = try JSONEncoder().encode(value)
        let query = itemQuery(for: playlistID)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            attributes[kSecAttrLabel as String] = label
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    private func value<Value: Decodable>(_ type: Value.Type, for playlistID: UUID) throws -> Value? {
        var query = itemQuery(for: playlistID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data,
              let secret = try? JSONDecoder().decode(Value.self, from: data) else {
            throw KeychainError.invalidData
        }
        return secret
    }

    func delete(for playlistID: UUID) throws {
        let status = SecItemDelete(itemQuery(for: playlistID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }

    /// Löscht alle Einträge dieses Dienstes: Tests mit eigenem Dienstnamen und „Alle Daten entfernen" (B03 · BUG-09).
    func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        for _ in 0..<10_000 {
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecItemNotFound { return }
            guard status == errSecSuccess else { throw KeychainError.status(status) }
        }
    }

    private func itemQuery(for playlistID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: playlistID.uuidString
        ]
    }
}
