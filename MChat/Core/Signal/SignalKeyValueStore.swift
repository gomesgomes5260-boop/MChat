import Foundation

/// Armazenamento chave-valor usado pelos stores do protocolo Signal
/// (identidade, sessões, pré-chaves) e pelo histórico de mensagens.
/// Implementações: `EncryptedFileKVStore` (app, cifrado em disco) e
/// `InMemoryKVStore` (testes).
protocol SignalKeyValueStore: AnyObject {
    func data(forKey key: String) throws -> Data?
    func set(_ data: Data, forKey key: String) throws
    func removeValue(forKey key: String) throws
    func keys(withPrefix prefix: String) throws -> [String]
}

/// Backing em memória — para testes de unidade.
final class InMemoryKVStore: SignalKeyValueStore {
    private var storage: [String: Data] = [:]

    func data(forKey key: String) throws -> Data? { storage[key] }
    func set(_ data: Data, forKey key: String) throws { storage[key] = data }
    func removeValue(forKey key: String) throws { storage[key] = nil }
    func keys(withPrefix prefix: String) throws -> [String] {
        storage.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }
}
