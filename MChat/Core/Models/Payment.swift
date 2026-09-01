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
    case pix    = "pix"
    case boleto = "boleto"

    var displayName: String {
        switch self {
        case .pix:    return "PIX"
        case .boleto: return "Boleto"
        }
    }
}

/// Pagamento solicitado por um cliente, processado por um operador de pagamentos.
struct Payment: Codable, Identifiable, Hashable {
    let id: UUID
    let clientID: UUID
    var clientName: String
    var type: PaymentType
    /// Rótulo legível do destino (ex.: "Boleto Itaú · venc 10/10" ou
    /// "Fulano de Tal (PIX)"), derivado de `PaymentDestination.parse`.
    var beneficiary: String
    /// Chave PIX, código Copia e Cola ou linha digitável, como digitado.
    var destination: String? = nil
    var amount: Money
    var status: PaymentStatus
    let requestedAt: Date
    var processedBy: UUID?
    var processedAt: Date?
}
