import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.isAuthenticated {
            MainTabView()
        } else {
            LoginView()
        }
    }
}

/// As abas visíveis dependem exclusivamente das permissões do usuário:
/// um "Somente Chat" vê só Chat; um operador de saques vê Dashboard e
/// Saques; o super admin vê tudo.
struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            if appState.can(.viewDashboard) {
                DashboardView()
                    .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
            }
            if appState.can(.viewClients) {
                ClientsListView()
                    .tabItem { Label("Clientes", systemImage: "person.2") }
            }
            if appState.can(.viewWithdrawals) {
                WithdrawalsView()
                    .tabItem { Label("Saques", systemImage: "arrow.down.circle") }
            }
            if appState.can(.viewPayments) {
                PaymentsView()
                    .tabItem { Label("Pagamentos", systemImage: "banknote") }
            }
            if appState.can(.viewUsers) {
                UsersView()
                    .tabItem { Label("Usuários", systemImage: "checkmark.shield") }
            }
            if appState.can(.viewOwnInvites) || appState.can(.viewAllInvites) {
                InvitesView()
                    .tabItem { Label("Convites", systemImage: "paperplane") }
            }
            if appState.can(.useChat) {
                ChatListView()
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            }
        }
    }
}
