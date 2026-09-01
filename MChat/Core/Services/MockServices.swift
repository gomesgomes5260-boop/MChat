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
        let rootID = UUID()
        let clientID = UUID()

        let root = User(
            id: rootID, name: "Lucas", email: "lucasgiovanny@gmail.com", phone: "937259259",
            roles: [.superAdmin, .accountHolder], status: .active,
            createdAt: Date().addingTimeInterval(-86400 * 60),
            invitedByUserID: nil, inviteID: nil,
            wallet: {
                var w = Wallet.empty
                w.balances[.brl] = Money(amountMinor: 50_000, currency: .brl)
                return w
            }()
        )

        let invite = Invite(
            id: UUID(), code: Invite.generateCode(), createdBy: rootID,
            invitedContact: "appreview@finly.com.br", status: .accepted,
            createdAt: Date().addingTimeInterval(-86400 * 30),
            expiresAt: Date().addingTimeInterval(86400 * 30),
            acceptedByUserID: clientID, acceptedAt: Date().addingTimeInterval(-86400 * 29),
            revokedBy: nil, revokedAt: nil,
            grantedRoles: [.chatOnly]
        )

        let client = User(
            id: clientID, name: "App Review", email: "appreview@finly.com.br", phone: "11988887777",
            roles: [.accountHolder, .admin], status: .active,
            createdAt: Date().addingTimeInterval(-86400 * 29),
            invitedByUserID: rootID, inviteID: invite.id,
            wallet: {
                var w = Wallet.empty
                w.balances[.brl] = Money(amountMinor: 1_250_000, currency: .brl)
                return w
            }()
        )

        users = [root, client]
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
}

// MARK: - Convites

struct MockInviteService: InviteServicing {
    let db = MockDatabase.shared

    func createInvite(from user: User, contact: String?, grantedRoles: Set<Role>) async throws -> Invite {
        guard user.can(.createInvites) else { throw ServiceError.notAuthorized }
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
            return [.accountHolder, .chatOnly, .withdrawalOperator, .paymentOperator, .financeManager]
        }
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
