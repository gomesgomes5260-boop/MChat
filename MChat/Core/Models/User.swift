import Foundation

enum UserStatus: String, Codable, CaseIterable {
    case pendingApproval = "pending"   // aguardando aprovação manual
    case active          = "active"
    case suspended       = "suspended"

    var displayName: String {
        switch self {
        case .pendingApproval: return "Pendente"
        case .active:          return "Ativo"
        case .suspended:       return "Suspenso"
        }
    }
}

struct User: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var email: String?
    var phone: String?
    var roles: Set<Role>
    var status: UserStatus
    var createdAt: Date

    /// Rastreabilidade do convite: quem convidou este usuário e qual
    /// convite foi usado. Todo usuário (exceto o super admin raiz)
    /// entra no sistema por convite.
    var invitedByUserID: UUID?
    var inviteID: UUID?

    /// Carteira multi-moeda (só relevante para quem tem `viewBalances`).
    var wallet: Wallet

    // MARK: RBAC

    var effectivePermissions: Set<Permission> {
        roles.reduce(into: Set<Permission>()) { $0.formUnion($1.permissions) }
    }

    func can(_ permission: Permission) -> Bool {
        status == .active && effectivePermissions.contains(permission)
    }

    func canAny(_ permissions: Permission...) -> Bool {
        permissions.contains(where: can)
    }

    var isSuperAdmin: Bool { roles.contains(.superAdmin) }
}
