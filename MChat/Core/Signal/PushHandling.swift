import Foundation

/// Push é apenas um GATILHO: o servidor envia uma notificação SEM conteúdo,
/// e o app (aqui) busca e decifra localmente. O texto nunca trafega pelo
/// APNs — a Apple e o APNs veem apenas "há algo para buscar".
///
/// Em produção isto roda numa Notification Service Extension: o payload
/// chega vazio (`mutable-content: 1`, `alert` genérico ou ausente), a
/// extensão chama `handleTrigger`, e só então monta a notificação local
/// com o texto já decifrado no aparelho.
final class PushTriggerHandler {
    private let signal: SignalProtocolManager
    private let localStore: LocalMessageStore
    private let localUserId: String

    init(signal: SignalProtocolManager, localStore: LocalMessageStore, localUserId: String) {
        self.signal = signal
        self.localStore = localStore
        self.localUserId = localUserId
    }

    /// Chamado ao receber o push vazio. Retorna quantas mensagens novas
    /// foram decifradas e gravadas localmente (para montar a notificação).
    @discardableResult
    func handleTrigger() async throws -> Int {
        let decrypted = try await signal.fetchAndDecrypt()
        for msg in decrypted {
            let convo = Self.conversationId(localUserId, msg.senderUserId)
            try localStore.append(LocalMessageStore.StoredMessage(
                id: UUID(), conversationId: convo, senderId: msg.senderUserId,
                isMine: false, text: String(decoding: msg.plaintext, as: UTF8.self),
                sentAt: msg.receivedAt))
        }
        return decrypted.count
    }

    /// Id de conversa determinístico e LOCAL (par ordenado). Nunca enviado
    /// ao servidor — existe só para agrupar mensagens no banco do aparelho.
    static func conversationId(_ a: String, _ b: String) -> String {
        [a, b].sorted().joined(separator: "|")
    }

    /// Validação defensiva: o payload de push não pode conter conteúdo.
    static func isEmptyTrigger(_ payload: [String: Any]) -> Bool {
        guard let aps = payload["aps"] as? [String: Any] else { return false }
        // Aceita apenas content-available/mutable-content; recusa alert com corpo.
        if let alert = aps["alert"] as? [String: Any],
           (alert["body"] != nil || alert["title"] != nil) { return false }
        if let alert = aps["alert"] as? String, !alert.isEmpty { return false }
        return true
    }
}
