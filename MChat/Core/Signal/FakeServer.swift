import Foundation

/// Servidor de teste em memória — modela EXATAMENTE o que um servidor
/// real teria direito de ver, para que os testes provem as garantias:
///
///  - Guarda bundles de chaves PÚBLICAS e filas de envelopes cifrados.
///  - Ao entregar, REMOVE o envelope (sem histórico no servidor).
///  - NÃO registra "quem falou com quem": `accessLog` guarda só o mínimo
///    do art. 15 do Marco Civil (IP + timestamp de acesso), com retenção
///    de 6 meses e descarte automático — nunca o par remetente/destinatário.
///  - Não tem como ler `ciphertext`: é blob opaco.
actor FakeSignalServer: MessageTransport {
    struct AccessRecord: Equatable { let ip: String; let at: Date }

    private var bundles: [String: PublicPreKeyBundle] = [:]           // "user.device"
    private var oneTimePreKeys: [String: [PublicSinglePreKey]] = [:]  // "user.device"
    private var inboxes: [String: [SealedEnvelope]] = [:]             // "user.device"
    /// Registro de acesso do art. 15 — SEM par de conversa.
    private(set) var accessLog: [AccessRecord] = []
    private let retention: TimeInterval = 60 * 60 * 24 * 180          // 6 meses

    /// IP simulado do "cliente" da requisição atual (injeção de teste).
    var currentIP = "203.0.113.10"

    private func addr(_ user: String, _ device: UInt32) -> String { "\(user).\(device)" }

    /// Único dado de acesso persistido — art. 15. Descarta o que passou de 6 meses.
    private func logAccess() {
        accessLog.append(AccessRecord(ip: currentIP, at: Date()))
        let cutoff = Date().addingTimeInterval(-retention)
        accessLog.removeAll { $0.at < cutoff }
    }

    func publishBundle(_ bundle: PublicPreKeyBundle, for userId: String) async throws {
        logAccess()
        bundles[addr(userId, bundle.deviceId)] = bundle
    }

    func fetchBundle(for userId: String, deviceId: UInt32) async throws -> PublicPreKeyBundle {
        logAccess()
        let key = addr(userId, deviceId)
        guard var bundle = bundles[key] else { throw ServiceError.notFound }
        // Consome uma one-time pre-key (como o servidor real faz).
        if var pool = oneTimePreKeys[key], let otp = pool.first {
            pool.removeFirst()
            oneTimePreKeys[key] = pool
            bundle = PublicPreKeyBundle(
                registrationId: bundle.registrationId, deviceId: bundle.deviceId,
                identityKey: bundle.identityKey, signedPreKeyId: bundle.signedPreKeyId,
                signedPreKeyPublic: bundle.signedPreKeyPublic,
                signedPreKeySignature: bundle.signedPreKeySignature,
                preKeyId: otp.id, preKeyPublic: otp.publicKey,
                kyberPreKeyId: bundle.kyberPreKeyId, kyberPreKeyPublic: bundle.kyberPreKeyPublic,
                kyberPreKeySignature: bundle.kyberPreKeySignature)
        }
        return bundle
    }

    func replenishPreKeys(_ preKeys: [PublicSinglePreKey], for userId: String) async throws {
        logAccess()
        // deviceId do bundle publicado por este usuário.
        guard let dev = bundles.keys.first(where: { $0.hasPrefix(userId + ".") })?
                .split(separator: ".").last.flatMap({ UInt32($0) }) else { return }
        oneTimePreKeys[addr(userId, dev), default: []].append(contentsOf: preKeys)
    }

    func send(_ envelope: SealedEnvelope) async throws {
        logAccess()
        // O servidor enfileira pelo DESTINATÁRIO. Não há campo de remetente:
        // com sealed sender ele está cifrado dentro de `ciphertext`.
        inboxes[addr(envelope.recipient, envelope.deviceId), default: []].append(envelope)
    }

    func drainInbox(for userId: String, deviceId: UInt32) async throws -> [SealedEnvelope] {
        logAccess()
        let key = addr(userId, deviceId)
        let pending = inboxes[key] ?? []
        inboxes[key] = []          // entregou → apaga (sem histórico no servidor)
        return pending
    }

    func remainingPreKeyCount(for userId: String, deviceId: UInt32) async throws -> Int {
        oneTimePreKeys[addr(userId, deviceId)]?.count ?? 0
    }

    // Utilidades de inspeção para os testes.
    func inboxIsEmpty(for userId: String, deviceId: UInt32) -> Bool {
        (inboxes[addr(userId, deviceId)] ?? []).isEmpty
    }
    func accessLogCount() -> Int { accessLog.count }
    func setCurrentIP(_ ip: String) { currentIP = ip }
}
