import Foundation

enum WithdrawalStatus: String, Codable, CaseIterable {
    case pending   = "pending"
    case approved  = "approved"
    case completed = "completed"
    case cancelled = "cancelled"

    var displayName: String {
        switch self {
        case .pending:   return "Pendente"
        case .approved:  return "Aprovado"
        case .completed: return "Concluído"
        case .cancelled: return "Cancelado"
        }
    }
}

/// Pedido de saque de um correntista, aprovado por um operador de saques.
struct Withdrawal: Codable, Identifiable, Hashable {
    let id: UUID
    let clientID: UUID
    var clientName: String
    var amount: Money
    var status: WithdrawalStatus
    let requestedAt: Date
    var decidedBy: UUID?     // operador que aprovou/cancelou (auditoria)
    var decidedAt: Date?
}
