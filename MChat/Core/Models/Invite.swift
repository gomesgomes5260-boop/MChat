import Foundation

enum InviteStatus: String, Codable, CaseIterable {
    case pending  = "pending"   // criado, ainda não usado
    case accepted = "accepted"  // usado em um cadastro
    case revoked  = "revoked"   // revogado (super admin ou quem criou)
    case expired  = "expired"

    var displayName: String {
        switch self {
        case .pending:  return "Pendente"
        case .accepted: return "Aceito"
        case .revoked:  return "Revogado"
        case .expired:  return "Expirado"
        }
    }
}

/// Convite de entrada no app. O cadastro SÓ é possível com um convite
/// pendente e válido; o vínculo `createdBy` → `acceptedByUserID`
/// preserva a árvore de quem convidou quem.
struct Invite: Codable, Identifiable, Hashable {
    let id: UUID
    let code: String                // código curto compartilhável
    let createdBy: UUID             // usuário que convidou
    var invitedContact: String?     // e-mail/telefone alvo (opcional)
    var status: InviteStatus
    let createdAt: Date
    var expiresAt: Date
    var acceptedByUserID: UUID?     // preenchido ao aceitar
    var acceptedAt: Date?
    var revokedBy: UUID?            // quem revogou (auditoria)
    var revokedAt: Date?

    /// Roles que o novo usuário receberá ao aceitar. Definidas por quem
    /// convida, limitadas às roles que o convidador pode conceder.
    var grantedRoles: Set<Role>

    var isUsable: Bool {
        status == .pending && expiresAt > Date()
    }

    static func generateCode() -> String {
        let alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<8).compactMap { _ in alphabet.randomElement() })
    }
}
