import Foundation

/// Conversa 1:1 ou em grupo. O conteúdo trafega cifrado ponta-a-ponta
/// via protocolo Signal; estes modelos guardam apenas metadados locais
/// e o texto já decifrado no dispositivo.
struct Conversation: Codable, Identifiable, Hashable {
    let id: UUID
    var participantIDs: [UUID]
    var title: String
    var lastMessagePreview: String?
    var lastActivityAt: Date
    var unreadCount: Int
}

enum MessageContent: Codable, Hashable {
    case text(String)
    case attachment(fileName: String, mimeType: String)
    case callEvent(CallEvent)
}

struct ChatMessage: Codable, Identifiable, Hashable {
    let id: UUID
    let conversationID: UUID
    let senderID: UUID
    var content: MessageContent
    let sentAt: Date
    var deliveredAt: Date?
    var readAt: Date?
}

/// Evento de ligação registrado na conversa (perdida, concluída, etc.).
struct CallEvent: Codable, Hashable {
    enum Outcome: String, Codable {
        case completed, missed, declined
    }
    var outcome: Outcome
    var duration: TimeInterval
}
