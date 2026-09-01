import Foundation
import SwiftUI

/// Estado global: sessão do usuário e injeção dos serviços.
/// Troque os mocks pelas implementações de rede num único lugar.
@MainActor
final class AppState: ObservableObject {
    @Published var currentUser: User?

    let auth: AuthServicing
    let userAdmin: UserAdminServicing
    let inviteService: InviteServicing
    let finance: FinanceServicing
    let chat: ChatServicing
    let callManager = CallManager()

    init(auth: AuthServicing = MockAuthService(),
         userAdmin: UserAdminServicing = MockUserAdminService(),
         inviteService: InviteServicing = MockInviteService(),
         finance: FinanceServicing = MockFinanceService(),
         chat: ChatServicing = MockChatService()) {
        self.auth = auth
        self.userAdmin = userAdmin
        self.inviteService = inviteService
        self.finance = finance
        self.chat = chat
    }

    var isAuthenticated: Bool { currentUser != nil }

    /// Atalho de RBAC para as views: `appState.can(.useChat)`.
    func can(_ permission: Permission) -> Bool {
        currentUser?.can(permission) ?? false
    }

    func signOut() async {
        await auth.signOut()
        currentUser = nil
    }
}
