import XCTest
@testable import MChat

final class RBACTests: XCTestCase {

    private func makeUser(roles: Set<Role>, status: UserStatus = .active) -> User {
        User(id: UUID(), name: "Teste", email: "t@t.com", phone: nil,
             roles: roles, status: status, createdAt: Date(),
             invitedByUserID: nil, inviteID: nil, wallet: .empty)
    }

    func testSuperAdminHasAllPermissions() {
        let user = makeUser(roles: [.superAdmin])
        for permission in Permission.allCases {
            XCTAssertTrue(user.can(permission), "Super admin deveria ter \(permission)")
        }
    }

    func testChatOnlyCannotSeeFinanceNorInvite() {
        let user = makeUser(roles: [.chatOnly])
        XCTAssertTrue(user.can(.useChat))
        XCTAssertTrue(user.can(.useVoiceCalls))
        XCTAssertFalse(user.can(.createInvites), "Somente Chat não convida — só o Chat Plus")
        XCTAssertFalse(user.can(.viewBalances))
        XCTAssertFalse(user.can(.viewWithdrawals))
        XCTAssertFalse(user.can(.viewDashboard))
        XCTAssertFalse(user.can(.editRoles))
    }

    func testChatPlusCanInviteButNothingElse() {
        let user = makeUser(roles: [.chatPlus])
        XCTAssertTrue(user.can(.useChat))
        XCTAssertTrue(user.can(.createInvites))
        XCTAssertFalse(user.can(.viewBalances))
        XCTAssertFalse(user.can(.manageInviteLimits), "Limites de convite são do Super Admin")
    }

    func testOnlySuperAdminManagesInviteLimits() {
        XCTAssertTrue(makeUser(roles: [.superAdmin]).can(.manageInviteLimits))
        for role in Role.allCases where role != .superAdmin {
            XCTAssertFalse(makeUser(roles: [role]).can(.manageInviteLimits),
                           "\(role) não deveria gerenciar limites")
        }
    }

    func testWithdrawalOperatorScope() {
        let user = makeUser(roles: [.withdrawalOperator])
        XCTAssertTrue(user.can(.approveWithdrawals))
        XCTAssertFalse(user.can(.processPayments))
        XCTAssertFalse(user.can(.manageAssets))
    }

    func testMultipleRolesUnionPermissions() {
        let user = makeUser(roles: [.withdrawalOperator, .paymentOperator])
        XCTAssertTrue(user.can(.approveWithdrawals))
        XCTAssertTrue(user.can(.processPayments))
        XCTAssertFalse(user.can(.editRoles))
    }

    func testSuspendedUserLosesAllAccess() {
        let user = makeUser(roles: [.superAdmin], status: .suspended)
        XCTAssertFalse(user.can(.useChat))
        XCTAssertFalse(user.can(.viewDashboard))
    }

    func testPendingUserHasNoAccessUntilApproved() {
        let user = makeUser(roles: [.accountHolder], status: .pendingApproval)
        XCTAssertFalse(user.can(.viewBalances))
    }
}
