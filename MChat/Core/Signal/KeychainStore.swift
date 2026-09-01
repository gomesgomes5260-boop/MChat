import Foundation
import Security
import CryptoKit

/// Segredos que NUNCA saem do aparelho.
///
/// - `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: item indisponível
///   antes do primeiro desbloqueio e jamais migrado para outro aparelho
///   (fica fora de backup iCloud/iTunes).
/// - `kSecAttrSynchronizable` ausente/false: sem sincronização via
///   iCloud Keychain.
enum KeychainStore {
    private static let service = "app.mchat.e2ee"

    enum KeychainError: Error { case unexpectedStatus(OSStatus) }

    static func data(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        return result as? Data
    }

    static func set(_ data: Data, forKey key: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemCopyMatching(base as CFDictionary, nil)
        if status == errSecSuccess {
            let update = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
            guard update == errSecSuccess else { throw KeychainError.unexpectedStatus(update) }
        } else {
            let add = SecItemAdd(base.merging(attributes) { $1 } as CFDictionary, nil)
            guard add == errSecSuccess else { throw KeychainError.unexpectedStatus(add) }
        }
    }

    /// Chave-mestra AES-256 do banco local cifrado; criada no primeiro uso.
    static func databaseKey() throws -> SymmetricKey {
        let keyName = "local-db-master-key"
        if let existing = try data(forKey: keyName) {
            return SymmetricKey(data: existing)
        }
        let key = SymmetricKey(size: .bits256)
        try set(key.withUnsafeBytes { Data($0) }, forKey: keyName)
        return key
    }
}
