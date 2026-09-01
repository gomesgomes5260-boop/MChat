import XCTest
@testable import MChat

final class InviteTests: XCTestCase {

    private func makeUser(roles: Set<Role>) -> User {
        User(id: UUID(), name: "Teste", email: "t@t.com", phone: nil,
             roles: roles, status: .active, createdAt: Date(),
             invitedByUserID: nil, inviteID: nil, wallet: .empty)
    }

    private func makeInvite(status: InviteStatus = .pending,
                            expiresAt: Date = Date().addingTimeInterval(3600),
                            createdBy: UUID = UUID()) -> Invite {
        Invite(id: UUID(), code: Invite.generateCode(), createdBy: createdBy,
               invitedContact: nil, status: status, createdAt: Date(),
               expiresAt: expiresAt, acceptedByUserID: nil, acceptedAt: nil,
               revokedBy: nil, revokedAt: nil, grantedRoles: [.chatOnly])
    }

    func testInviteCodeFormat() {
        let code = Invite.generateCode()
        XCTAssertEqual(code.count, 8)
        // Alfabeto sem caracteres ambíguos (0, O, 1, I).
        XCTAssertFalse(code.contains("0"))
        XCTAssertFalse(code.contains("O"))
        XCTAssertFalse(code.contains("1"))
        XCTAssertFalse(code.contains("I"))
    }

    func testPendingInviteIsUsable() {
        XCTAssertTrue(makeInvite().isUsable)
    }

    func testRevokedInviteIsNotUsable() {
        XCTAssertFalse(makeInvite(status: .revoked).isUsable)
    }

    func testExpiredInviteIsNotUsable() {
        XCTAssertFalse(makeInvite(expiresAt: Date().addingTimeInterval(-60)).isUsable)
    }

    func testGrantableRolesRespectHierarchy() {
        // Super admin concede qualquer role.
        XCTAssertEqual(MockInviteService.grantableRoles(by: makeUser(roles: [.superAdmin])),
                       Set(Role.allCases))
        // ADM concede roles operacionais (incluindo Chat Plus), nunca super admin.
        let admGrantable = MockInviteService.grantableRoles(by: makeUser(roles: [.admin]))
        XCTAssertFalse(admGrantable.contains(.superAdmin))
        XCTAssertTrue(admGrantable.contains(.withdrawalOperator))
        XCTAssertTrue(admGrantable.contains(.chatPlus))
        // Chat Plus só convida usuários de chat.
        XCTAssertEqual(MockInviteService.grantableRoles(by: makeUser(roles: [.chatPlus])),
                       [.chatOnly])
    }

    func testChatPlusInviteLimitBlocksCreation() async throws {
        var plus = makeUser(roles: [.chatPlus])
        plus.inviteLimit = 0
        let service = MockInviteService()
        do {
            _ = try await service.createInvite(from: plus, contact: "11911112222", grantedRoles: [.chatOnly])
            XCTFail("Deveria ter estourado o limite de convites")
        } catch let error as ServiceError {
            guard case .inviteLimitReached = error else {
                return XCTFail("Erro inesperado: \(error)")
            }
        }
    }

    func testMoneyFormattingUsesMinorUnits() {
        let money = Money(amountMinor: 1_250_000, currency: .brl)
        XCTAssertEqual(money.decimalValue, Decimal(12500))
    }
}
