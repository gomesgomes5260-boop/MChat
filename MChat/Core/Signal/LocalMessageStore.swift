import Foundation
import CryptoKit

/// Histórico de mensagens persistido SOMENTE no aparelho, cifrado em repouso.
///
/// - Cada registro é selado com AES-GCM usando a chave-mestra do Keychain
///   (`KeychainStore.databaseKey()`), que nunca sai do dispositivo.
/// - O arquivo é marcado como excluído de backup (iCloud/iTunes) e protegido
///   por `.completeUntilFirstUserAuthentication`.
/// - Não há qualquer caminho de escrita para o servidor: este tipo não
///   conhece transporte.
///
/// Em produção o backing pode ser SQLCipher; aqui usamos um arquivo append
/// de registros AES-GCM para manter a lógica testável sem dependência nativa.
final class LocalMessageStore {
    struct StoredMessage: Codable, Equatable {
        let id: UUID
        let conversationId: String   // par ordenado local, nunca enviado
        let senderId: String
        let isMine: Bool
        let text: String
        let sentAt: Date
    }

    private let fileURL: URL
    private let key: SymmetricKey
    private var cache: [StoredMessage]

    init(fileURL: URL, key: SymmetricKey) throws {
        self.fileURL = fileURL
        self.key = key
        self.cache = []
        try excludeFromBackup()
        try load()
    }

    /// Inicializador de teste com chave e diretório temporários.
    convenience init(directory: URL, key: SymmetricKey) throws {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try self.init(fileURL: directory.appendingPathComponent("messages.enc"), key: key)
    }

    func append(_ message: StoredMessage) throws {
        cache.append(message)
        try persist()
    }

    func messages(in conversationId: String) -> [StoredMessage] {
        cache.filter { $0.conversationId == conversationId }.sorted { $0.sentAt < $1.sentAt }
    }

    var count: Int { cache.count }

    /// Apaga tudo (ex.: logout/pânico). Sem backup, isto é irreversível.
    func wipe() throws {
        cache = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: Cifra em repouso

    private func persist() throws {
        let plaintext = try JSONEncoder().encode(cache)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw ServiceError.network("Falha ao selar o banco local")
        }
        try combined.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let combined = try Data(contentsOf: fileURL)
        let box = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(box, using: key)
        cache = try JSONDecoder().decode([StoredMessage].self, from: plaintext)
    }

    private func excludeFromBackup() throws {
        // Marca o diretório-pai como fora de backup.
        var dir = fileURL.deletingLastPathComponent()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
    }
}
