import Foundation

/// Banco em memória compartilhado pelos mocks — permite desenvolver e
/// testar toda a UI e o RBAC sem backend. Troque pelas implementações
/// de rede mantendo os mesmos protocolos.
actor MockDatabase {
    static let shared = MockDatabase()

    var users: [User]
    var invites: [Invite]
    var withdrawals: [Withdrawal]
    var payments: [Payment]
    var conversations: [Conversation]
    var messages: [ChatMessage]

    init() {
        let superID = UUID(), operatorID = UUID(), chatPlusID = UUID(), chatID = UUID()

        let superAdmin = User(
            id: superID, name: "Adm Super", email: "super@mchat.app", phone: "11900000001",
            roles: [.superAdmin, .accountHolder], status: .active,
            createdAt: Date().addingTimeInterval(-86400 * 60),
            invitedByUserID: nil, inviteID: nil,
            wallet: {
                var w = Wallet.empty
                w.balances[.brl] = Money(amountMinor: 1_000_000, currency: .brl)
                w.balances[.usd] = Money(amountMinor: 200_000, currency: .usd)
                return w
            }()
        )

        let operatorUser = User(
            id: operatorID, name: "Operador", email: "operador@mchat.app", phone: "11900000002",
            roles: [.withdrawalOperator, .paymentOperator], status: .active,
            createdAt: Date().addingTimeInterval(-86400 * 30),
            invitedByUserID: superID, inviteID: nil,
            wallet: .empty
        )

        // Convite aceito: Chat Plus convidou o usuário Chat.
        let invite = Invite(
            id: UUID(), code: Invite.generateCode(), createdBy: chatPlusID,
            invitedContact: "11900000003", status: .accepted,
            createdAt: Date().addingTimeInterval(-86400 * 15),
            expiresAt: Date().addingTimeInterval(86400 * 30),
            acceptedByUserID: chatID, acceptedAt: Date().addingTimeInterval(-86400 * 14),
            revokedBy: nil, revokedAt: nil,
            grantedRoles: [.chatOnly]
        )

        let chatPlusUser = User(
            id: chatPlusID, name: "Chat Plus", email: nil, phone: "11900000004",
            roles: [.chatPlus], status: .active,
            createdAt: Date().addingTimeInterval(-86400 * 20),
            invitedByUserID: superID, inviteID: nil,
            inviteLimit: 3,
            wallet: .empty
        )

        let chatUser = User(
            id: chatID, name: "Chat", email: nil, phone: "11900000003",
            roles: [.chatOnly], status: .active,
            createdAt: Date().addingTimeInterval(-86400 * 14),
            invitedByUserID: chatPlusID, inviteID: invite.id,
            wallet: .empty
        )

        users = [superAdmin, operatorUser, chatPlusUser, chatUser]
        invites = [invite]
        withdrawals = []
        payments = []
        conversations = []
        messages = []
    }

    // Helpers de mutação usados pelos serviços mock.
    func upsert(_ user: User) {
        if let i = users.firstIndex(where: { $0.id == user.id }) { users[i] = user }
        else { users.append(user) }
    }

    func upsert(_ invite: Invite) {
        if let i = invites.firstIndex(where: { $0.id == invite.id }) { invites[i] = invite }
        else { invites.append(invite) }
    }
}

// MARK: - Auth

struct MockAuthService: AuthServicing {
    let db = MockDatabase.shared

    func signIn(email: String, password: String) async throws -> User {
        guard let user = await db.users.first(where: { $0.email == email }) else {
            throw ServiceError.notFound
        }
        return user
    }

    func register(inviteCode: String, name: String, email: String, password: String) async throws -> User {
        guard var invite = await db.invites.first(where: { $0.code == inviteCode }) else {
            throw ServiceError.inviteInvalid
        }
        guard invite.isUsable else {
            throw invite.status == .accepted ? ServiceError.inviteAlreadyUsed : ServiceError.inviteInvalid
        }

        let user = User(
            id: UUID(), name: name, email: email, phone: nil,
            roles: invite.grantedRoles.isEmpty ? [.chatOnly] : invite.grantedRoles,
            status: .pendingApproval,
            createdAt: Date(),
            invitedByUserID: invite.createdBy, inviteID: invite.id,
            inviteLimit: invite.grantedRoles.contains(.chatPlus) ? 3 : nil,
            wallet: .empty
        )
        invite.status = .accepted
        invite.acceptedByUserID = user.id
        invite.acceptedAt = Date()

        await db.upsert(user)
        await db.upsert(invite)
        return user
    }

    func signOut() async {}
}

// MARK: - Administração de usuários

struct MockUserAdminService: UserAdminServicing {
    let db = MockDatabase.shared

    func fetchClients() async throws -> [User] {
        await db.users.sorted { $0.createdAt > $1.createdAt }
    }

    func fetchAdminUsers() async throws -> [User] {
        await db.users.filter { !$0.roles.isDisjoint(with: [.superAdmin, .admin, .financeManager, .withdrawalOperator, .paymentOperator]) }
    }

    func updateRoles(userID: UUID, roles: Set<Role>, actingUser: User) async throws -> User {
        guard actingUser.can(.editRoles) else { throw ServiceError.notAuthorized }
        // Só super admin concede/remove a role de super admin.
        guard var target = await db.users.first(where: { $0.id == userID }) else { throw ServiceError.notFound }
        if (roles.contains(.superAdmin) != target.roles.contains(.superAdmin)) && !actingUser.isSuperAdmin {
            throw ServiceError.notAuthorized
        }
        target.roles = roles
        await db.upsert(target)
        return target
    }

    func setStatus(userID: UUID, status: UserStatus, actingUser: User) async throws -> User {
        guard actingUser.can(.manageClients) else { throw ServiceError.notAuthorized }
        guard var target = await db.users.first(where: { $0.id == userID }) else { throw ServiceError.notFound }
        target.status = status
        await db.upsert(target)
        return target
    }

    func updateInviteLimit(userID: UUID, limit: Int?, actingUser: User) async throws -> User {
        guard actingUser.can(.manageInviteLimits) else { throw ServiceError.notAuthorized }
        guard var target = await db.users.first(where: { $0.id == userID }) else { throw ServiceError.notFound }
        target.inviteLimit = limit
        await db.upsert(target)
        return target
    }
}

// MARK: - Convites

struct MockInviteService: InviteServicing {
    let db = MockDatabase.shared

    func createInvite(from user: User, contact: String?, grantedRoles: Set<Role>) async throws -> Invite {
        guard user.can(.createInvites) else { throw ServiceError.notAuthorized }
        // Limite de convites (revogados/expirados não contam).
        if let limit = user.inviteLimit {
            let used = await db.invites.filter {
                $0.createdBy == user.id && $0.status != .revoked && $0.status != .expired
            }.count
            guard used < limit else { throw ServiceError.inviteLimitReached }
        }
        // Ninguém concede roles acima das próprias: as roles do convite
        // precisam estar contidas nas permissões de quem convida.
        let grantable = Self.grantableRoles(by: user)
        guard grantedRoles.isSubset(of: grantable) else { throw ServiceError.notAuthorized }

        let invite = Invite(
            id: UUID(), code: Invite.generateCode(), createdBy: user.id,
            invitedContact: contact, status: .pending,
            createdAt: Date(), expiresAt: Date().addingTimeInterval(86400 * 7),
            acceptedByUserID: nil, acceptedAt: nil, revokedBy: nil, revokedAt: nil,
            grantedRoles: grantedRoles
        )
        await db.upsert(invite)
        return invite
    }

    /// Roles que um usuário pode incluir num convite.
    static func grantableRoles(by user: User) -> Set<Role> {
        if user.isSuperAdmin { return Set(Role.allCases) }
        if user.roles.contains(.admin) {
            return [.accountHolder, .chatPlus, .chatOnly, .withdrawalOperator, .paymentOperator, .financeManager]
        }
        // Chat Plus e correntistas convidam apenas usuários de chat.
        return [.chatOnly]
    }

    func invites(createdBy userID: UUID) async throws -> [Invite] {
        await db.invites.filter { $0.createdBy == userID }
    }

    func allInvites(actingUser: User) async throws -> [Invite] {
        guard actingUser.can(.viewAllInvites) else { throw ServiceError.notAuthorized }
        return await db.invites.sorted { $0.createdAt > $1.createdAt }
    }

    func revoke(inviteID: UUID, actingUser: User) async throws -> Invite {
        guard var invite = await db.invites.first(where: { $0.id == inviteID }) else {
            throw ServiceError.notFound
        }
        let isOwner = invite.createdBy == actingUser.id
        guard isOwner || actingUser.can(.revokeInvites) else { throw ServiceError.notAuthorized }
        guard invite.status == .pending else { throw ServiceError.inviteInvalid }

        invite.status = .revoked
        invite.revokedBy = actingUser.id
        invite.revokedAt = Date()
        await db.upsert(invite)
        return invite
    }

    func validate(code: String) async throws -> Invite {
        guard let invite = await db.invites.first(where: { $0.code == code }), invite.isUsable else {
            throw ServiceError.inviteInvalid
        }
        return invite
    }
}

// MARK: - Financeiro

struct MockFinanceService: FinanceServicing {
    let db = MockDatabase.shared

    func dashboardSummary() async throws -> DashboardSummary {
        let users = await db.users
        let withdrawals = await db.withdrawals
        let payments = await db.payments
        return DashboardSummary(
            totalClients: users.count,
            activeClients: users.filter { $0.status == .active }.count,
            pendingWithdrawals: withdrawals.filter { $0.status == .pending }.count,
            pendingPayments: payments.filter { $0.status == .pending }.count,
            pendingApprovalClients: users.filter { $0.status == .pendingApproval }.count,
            suspendedClients: users.filter { $0.status == .suspended }.count
        )
    }

    func withdrawals(status: WithdrawalStatus?) async throws -> [Withdrawal] {
        let all = await db.withdrawals
        guard let status else { return all }
        return all.filter { $0.status == status }
    }

    func decideWithdrawal(id: UUID, approve: Bool, actingUser: User) async throws -> Withdrawal {
        guard actingUser.can(.approveWithdrawals) else { throw ServiceError.notAuthorized }
        guard var w = await db.withdrawals.first(where: { $0.id == id }) else { throw ServiceError.notFound }
        w.status = approve ? .approved : .cancelled
        w.decidedBy = actingUser.id
        w.decidedAt = Date()
        await MockDatabase.shared.replaceWithdrawal(w)
        return w
    }

    func payments(status: PaymentStatus?) async throws -> [Payment] {
        let all = await db.payments
        guard let status else { return all }
        return all.filter { $0.status == status }
    }

    func processPayment(id: UUID, complete: Bool, actingUser: User) async throws -> Payment {
        guard actingUser.can(.processPayments) else { throw ServiceError.notAuthorized }
        guard var p = await db.payments.first(where: { $0.id == id }) else { throw ServiceError.notFound }
        p.status = complete ? .completed : .cancelled
        p.processedBy = actingUser.id
        p.processedAt = Date()
        await MockDatabase.shared.replacePayment(p)
        return p
    }
}

extension MockDatabase {
    func replaceWithdrawal(_ w: Withdrawal) {
        if let i = withdrawals.firstIndex(where: { $0.id == w.id }) { withdrawals[i] = w }
    }
    func replacePayment(_ p: Payment) {
        if let i = payments.firstIndex(where: { $0.id == p.id }) { payments[i] = p }
    }
    func append(_ message: ChatMessage) { messages.append(message) }
}

// MARK: - Chat

struct MockChatService: ChatServicing {
    let db = MockDatabase.shared

    func conversations(for userID: UUID) async throws -> [Conversation] {
        await db.conversations.filter { $0.participantIDs.contains(userID) }
    }

    func messages(in conversationID: UUID) async throws -> [ChatMessage] {
        await db.messages.filter { $0.conversationID == conversationID }
    }

    func send(_ content: MessageContent, to conversationID: UUID, from userID: UUID) async throws -> ChatMessage {
        let message = ChatMessage(
            id: UUID(), conversationID: conversationID, senderID: userID,
            content: content, sentAt: Date(), deliveredAt: nil, readAt: nil
        )
        await db.append(message)
        return message
    }
}
