import Foundation

/// Camada OPCIONAL de mix network (estilo Loopix/Nym), plugável como
/// decorator sobre qualquer `MessageTransport`. Desligada por padrão.
///
/// Quando ativada, ela:
///  - adiciona atraso aleatório (defesa contra correlação de tempo);
///  - intercala tráfego de cobertura (mensagens falsas indistinguíveis);
///  - encaminharia o envelope por múltiplos mixes (aqui, o hop final é o
///    transporte embrulhado — os hops reais entram quando você plugar um
///    provedor de mixnet de verdade).
///
/// O restante do app não muda: `SignalProtocolManager` recebe um
/// `MessageTransport` e não sabe se há mixnet embaixo.
actor MixNetworkTransport: MessageTransport {
    private let base: MessageTransport
    private let config: Config

    struct Config {
        var enabled: Bool = false
        var maxJitter: TimeInterval = 0.5      // atraso aleatório por hop
        var coverTrafficRate: Double = 0.0     // 0…1: chance de tráfego falso por envio
        static let disabled = Config()
    }

    init(base: MessageTransport, config: Config = .disabled) {
        self.base = base
        self.config = config
    }

    private func mixDelay() async {
        guard config.enabled, config.maxJitter > 0 else { return }
        let ns = UInt64(Double.random(in: 0...config.maxJitter) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: ns)
    }

    func send(_ envelope: SealedEnvelope) async throws {
        await mixDelay()
        if config.enabled, Double.random(in: 0...1) < config.coverTrafficRate {
            // Tráfego de cobertura: um envelope falso, descartado no destino.
            let decoy = SealedEnvelope(recipient: envelope.recipient, deviceId: envelope.deviceId,
                                       ciphertext: Data((0..<envelope.ciphertext.count).map { _ in .random(in: 0...255) }),
                                       contentHint: 0xFF, timestamp: Date(), senderHint: nil)
            try? await base.send(decoy)
        }
        try await base.send(envelope)
    }

    // Demais operações passam direto (com jitter quando ativo).
    func publishBundle(_ bundle: PublicPreKeyBundle, for userId: String) async throws {
        await mixDelay(); try await base.publishBundle(bundle, for: userId)
    }
    func fetchBundle(for userId: String, deviceId: UInt32) async throws -> PublicPreKeyBundle {
        await mixDelay(); return try await base.fetchBundle(for: userId, deviceId: deviceId)
    }
    func replenishPreKeys(_ preKeys: [PublicSinglePreKey], for userId: String) async throws {
        await mixDelay(); try await base.replenishPreKeys(preKeys, for: userId)
    }
    func drainInbox(for userId: String, deviceId: UInt32) async throws -> [SealedEnvelope] {
        await mixDelay()
        // Descarta tráfego de cobertura (contentHint 0xFF) antes de entregar.
        return try await base.drainInbox(for: userId, deviceId: deviceId).filter { $0.contentHint != 0xFF }
    }
    func remainingPreKeyCount(for userId: String, deviceId: UInt32) async throws -> Int {
        try await base.remainingPreKeyCount(for: userId, deviceId: deviceId)
    }
}
