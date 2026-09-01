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

    func testChatOnlyCannotSeeFinance() {
        let user = makeUser(roles: [.chatOnly])
        XCTAssertTrue(user.can(.useChat))
        XCTAssertTrue(user.can(.useVoiceCalls))
        XCTAssertFalse(user.can(.viewBalances))
        XCTAssertFalse(user.can(.viewWithdrawals))
        XCTAssertFalse(user.can(.viewDashboard))
        XCTAssertFalse(user.can(.editRoles))
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
