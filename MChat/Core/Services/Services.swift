import Foundation

/// Erros de domínio compartilhados pelos serviços.
enum ServiceError: LocalizedError {
    case notAuthorized
    case inviteInvalid
    case inviteAlreadyUsed
    case inviteLimitReached
    case notFound
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:      return "Você não tem permissão para esta ação."
        case .inviteInvalid:      return "Convite inválido ou expirado."
        case .inviteAlreadyUsed:  return "Este convite já foi utilizado."
        case .inviteLimitReached: return "Limite de convites atingido. Peça ao Super Admin para aumentar seu limite."
        case .notFound:           return "Registro não encontrado."
        case .network(let m):     return m
        }
    }
}

// MARK: - Contratos

protocol AuthServicing {
    func signIn(email: String, password: String) async throws -> User
    /// Cadastro só é possível com um convite válido.
    func register(inviteCode: String, name: String, email: String, password: String) async throws -> User
    func signOut() async
}

protocol UserAdminServicing {
    func fetchClients() async throws -> [User]
    func fetchAdminUsers() async throws -> [User]
    func updateRoles(userID: UUID, roles: Set<Role>, actingUser: User) async throws -> User
    func setStatus(userID: UUID, status: UserStatus, actingUser: User) async throws -> User
    /// Define o limite de convites (nil = ilimitado). Requer `manageInviteLimits`.
    func updateInviteLimit(userID: UUID, limit: Int?, actingUser: User) async throws -> User
}

protocol InviteServicing {
    func createInvite(from user: User, contact: String?, grantedRoles: Set<Role>) async throws -> Invite
    func invites(createdBy userID: UUID) async throws -> [Invite]
    /// Árvore completa — requer `viewAllInvites`.
    func allInvites(actingUser: User) async throws -> [Invite]
    /// Revogação: o criador revoga os próprios convites pendentes;
    /// `revokeInvites` (super admin) revoga qualquer um.
    func revoke(inviteID: UUID, actingUser: User) async throws -> Invite
    func validate(code: String) async throws -> Invite
}

protocol FinanceServicing {
    func dashboardSummary() async throws -> DashboardSummary
    func withdrawals(status: WithdrawalStatus?) async throws -> [Withdrawal]
    func decideWithdrawal(id: UUID, approve: Bool, actingUser: User) async throws -> Withdrawal
    func payments(status: PaymentStatus?) async throws -> [Payment]
    func processPayment(id: UUID, complete: Bool, actingUser: User) async throws -> Payment
}

protocol ChatServicing {
    func conversations(for userID: UUID) async throws -> [Conversation]
    func messages(in conversationID: UUID) async throws -> [ChatMessage]
    func send(_ content: MessageContent, to conversationID: UUID, from userID: UUID) async throws -> ChatMessage
}

/// Números agregados exibidos no Dashboard (espelha o painel web).
struct DashboardSummary: Codable {
    var totalClients: Int
    var activeClients: Int
    var pendingWithdrawals: Int
    var pendingPayments: Int
    var pendingApprovalClients: Int
    var suspendedClients: Int
}
