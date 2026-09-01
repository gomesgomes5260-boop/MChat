import Foundation

/// Permissões atômicas do sistema. A UI e os serviços são sempre
/// protegidos por permissão, nunca por role diretamente — isso permite
/// compor roles novas sem tocar nas telas.
enum Permission: String, Codable, CaseIterable, Hashable {
    // Dashboard / visão geral
    case viewDashboard

    // Clientes
    case viewClients
    case manageClients          // aprovar, suspender, reativar

    // Financeiro (ativos: BRL, EUR, GBP, USD)
    case viewBalances
    case manageAssets           // movimentar/ajustar ativos financeiros

    // Operações
    case viewWithdrawals
    case approveWithdrawals     // operador de saques
    case viewPayments
    case processPayments        // operador de pagamentos

    // Administração de usuários
    case viewUsers
    case editRoles
    case promoteClient

    // Convites
    case createInvites          // qualquer usuário ativo pode convidar
    case viewOwnInvites
    case viewAllInvites         // ver a árvore completa de convites
    case revokeInvites          // revogar convites de terceiros (super admin)

    // Comunicação
    case useChat
    case useVoiceCalls
}

/// Roles do sistema. Um usuário pode ter VÁRIAS roles; suas permissões
/// efetivas são a união das permissões de cada role.
enum Role: String, Codable, CaseIterable, Identifiable, Hashable {
    case superAdmin          = "super_admin"
    case admin               = "adm"
    case financeManager      = "finance_manager"
    case withdrawalOperator  = "withdrawal_operator"
    case paymentOperator     = "payment_operator"
    case accountHolder       = "correntista"   // cliente com conta financeira
    case chatOnly            = "somente_chat"  // acesso só a chat/ligações

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .superAdmin:         return "Super Admin"
        case .admin:              return "ADM"
        case .financeManager:     return "Gestor Financeiro"
        case .withdrawalOperator: return "Operador de Saques"
        case .paymentOperator:    return "Operador de Pagamentos"
        case .accountHolder:      return "Correntista"
        case .chatOnly:           return "Somente Chat"
        }
    }

    /// Permissões concedidas por esta role.
    var permissions: Set<Permission> {
        switch self {
        case .superAdmin:
            // Super admin tem tudo, inclusive gerenciar/revogar convites.
            return Set(Permission.allCases)

        case .admin:
            return [.viewDashboard, .viewClients, .manageClients,
                    .viewUsers, .promoteClient,
                    .viewWithdrawals, .viewPayments,
                    .createInvites, .viewOwnInvites, .viewAllInvites,
                    .useChat, .useVoiceCalls]

        case .financeManager:
            return [.viewDashboard, .viewBalances, .manageAssets,
                    .viewWithdrawals, .viewPayments,
                    .createInvites, .viewOwnInvites,
                    .useChat, .useVoiceCalls]

        case .withdrawalOperator:
            return [.viewDashboard, .viewWithdrawals, .approveWithdrawals,
                    .viewOwnInvites, .useChat]

        case .paymentOperator:
            return [.viewDashboard, .viewPayments, .processPayments,
                    .viewOwnInvites, .useChat]

        case .accountHolder:
            return [.viewBalances, .createInvites, .viewOwnInvites,
                    .useChat, .useVoiceCalls]

        case .chatOnly:
            return [.createInvites, .viewOwnInvites, .useChat, .useVoiceCalls]
        }
    }
}
