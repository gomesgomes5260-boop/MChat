import Foundation

enum PaymentStatus: String, Codable, CaseIterable {
    case pending   = "pending"
    case completed = "completed"
    case cancelled = "cancelled"

    var displayName: String {
        switch self {
        case .pending:   return "Pendente"
        case .completed: return "Concluído"
        case .cancelled: return "Cancelado"
        }
    }
}

enum PaymentType: String, Codable, CaseIterable {
    case pix          = "pix"
    case transfer     = "transfer"
    case boleto       = "boleto"
    case internationalWire = "wire"

    var displayName: String {
        switch self {
        case .pix:               return "PIX"
        case .transfer:          return "Transferência"
        case .boleto:            return "Boleto"
        case .internationalWire: return "Wire Internacional"
        }
    }
}

/// Pagamento solicitado por um cliente, processado por um operador de pagamentos.
struct Payment: Codable, Identifiable, Hashable {
    let id: UUID
    let clientID: UUID
    var clientName: String
    var type: PaymentType
    var beneficiary: String
    var amount: Money
    var status: PaymentStatus
    let requestedAt: Date
    var processedBy: UUID?
    var processedAt: Date?
}
