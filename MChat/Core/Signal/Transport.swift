import Foundation

/// Envelope que trafega pela rede. O corpo já está cifrado ponta-a-ponta
/// (Signal); com sealed sender, nem o remetente é visível ao servidor.
struct SealedEnvelope: Codable, Equatable {
    /// Destinatário — o servidor precisa dele para ENTREGAR, mas não o
    /// persiste como metadado de relacionamento (só enfileira e apaga).
    let recipient: String
    let deviceId: UInt32
    /// Bytes opacos: UnidentifiedSenderMessage (sealed sender) OU o
    /// CiphertextMessage serializado. O servidor os trata como blob.
    let ciphertext: Data
    /// Tipo do CiphertextMessage (prekey vs whisper), necessário para o
    /// destinatário decifrar. Não revela conteúdo.
    let contentHint: UInt8
    let timestamp: Date
    /// SEMPRE nil sob sealed sender (o remetente vai cifrado dentro de
    /// `ciphertext`). Preenchido apenas no modo identificado (sem
    /// certificado — usado em testes locais). Em produção, com sealed
    /// sender ativo, este campo nunca carrega metadado de relacionamento.
    let senderHint: String?
}

/// Bundle de chaves PÚBLICAS que o servidor guarda e entrega para iniciar
/// sessões. Nada aqui é secreto.
struct PublicPreKeyBundle: Codable {
    let registrationId: UInt32
    let deviceId: UInt32
    let identityKey: Data
    let signedPreKeyId: UInt32
    let signedPreKeyPublic: Data
    let signedPreKeySignature: Data
    let preKeyId: UInt32?
    let preKeyPublic: Data?
    let kyberPreKeyId: UInt32
    let kyberPreKeyPublic: Data
    let kyberPreKeySignature: Data
}

/// Contrato do transporte. O `SignalProtocolManager` fala só com isto —
/// trocar servidor real, fake de teste ou mix network não muda o cliente.
protocol MessageTransport {
    func publishBundle(_ bundle: PublicPreKeyBundle, for userId: String) async throws
    func fetchBundle(for userId: String, deviceId: UInt32) async throws -> PublicPreKeyBundle
    /// Repõe one-time pre-keys quando o servidor sinaliza estoque baixo.
    func replenishPreKeys(_ preKeys: [PublicSinglePreKey], for userId: String) async throws
    func send(_ envelope: SealedEnvelope) async throws
    /// Busca e REMOVE do servidor os envelopes enfileirados (entregou, apagou).
    func drainInbox(for userId: String, deviceId: UInt32) async throws -> [SealedEnvelope]
    /// Quantas one-time pre-keys ainda restam no servidor (para reposição).
    func remainingPreKeyCount(for userId: String, deviceId: UInt32) async throws -> Int
}

struct PublicSinglePreKey: Codable {
    let id: UInt32
    let publicKey: Data
}
