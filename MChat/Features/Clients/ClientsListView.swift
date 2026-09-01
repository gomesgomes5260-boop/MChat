import SwiftUI

/// Lista de clientes com busca e filtros por status (Todos/Pendentes/Ativos/Suspensos).
struct ClientsListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var clients: [User] = []
    @State private var searchText = ""
    @State private var filter: UserStatus?

    private var filtered: [User] {
        clients.filter { client in
            (filter == nil || client.status == filter) &&
            (searchText.isEmpty
             || client.name.localizedCaseInsensitiveContains(searchText)
             || (client.email ?? "").localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Filtro", selection: $filter) {
                    Text("Todos").tag(UserStatus?.none)
                    ForEach(UserStatus.allCases, id: \.self) { status in
                        Text(status.displayName + "s").tag(UserStatus?.some(status))
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                ForEach(filtered) { client in
                    NavigationLink(value: client.id) {
                        ClientRow(client: client)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Buscar por nome ou e-mail")
            .navigationTitle("Clientes")
            .navigationDestination(for: UUID.self) { id in
                if let client = clients.first(where: { $0.id == id }) {
                    ClientDetailView(client: client) { await load() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        clients = (try? await appState.userAdmin.fetchClients()) ?? []
    }
}

struct ClientRow: View {
    let client: User

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(client.name).font(.headline)
                Spacer()
                StatusBadge(status: client.status)
            }
            if let email = client.email {
                Text(email).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(Array(client.roles).sorted(by: { $0.rawValue < $1.rawValue })) { role in
                    RoleBadge(role: role)
                }
                Spacer()
                Text(client.wallet.balance(in: .brl).formatted)
                    .font(.caption.monospaced())
            }
        }
        .padding(.vertical, 2)
    }
}

struct StatusBadge: View {
    let status: UserStatus

    private var tint: Color {
        switch status {
        case .active:          return .green
        case .pendingApproval: return .orange
        case .suspended:       return .red
        }
    }

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}

struct RoleBadge: View {
    let role: Role

    var body: some View {
        Text(role.displayName)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(role == .superAdmin ? Color.black : Color.gray.opacity(0.15),
                        in: Capsule())
            .foregroundStyle(role == .superAdmin ? .white : .primary)
    }
}

/// Detalhe do cliente: carteira multi-moeda, quem convidou, ações de status.
struct ClientDetailView: View {
    @EnvironmentObject private var appState: AppState
    let client: User
    let onChange: () async -> Void

    var body: some View {
        List {
            Section("Carteira") {
                ForEach(Currency.allCases) { currency in
                    LabeledContent(currency.displayName,
                                   value: client.wallet.balance(in: currency).formatted)
                }
            }

            Section("Convite") {
                if client.invitedByUserID != nil {
                    LabeledContent("Convidado por", value: "ver árvore em Convites")
                } else {
                    Text("Usuário raiz (sem convite)")
                }
            }

            if appState.can(.manageClients) {
                Section("Ações") {
                    if client.status != .suspended {
                        Button("Suspender", role: .destructive) {
                            Task { await setStatus(.suspended) }
                        }
                    }
                    if client.status != .active {
                        Button("Ativar") { Task { await setStatus(.active) } }
                    }
                }
            }
        }
        .navigationTitle(client.name)
    }

    private func setStatus(_ status: UserStatus) async {
        guard let acting = appState.currentUser else { return }
        _ = try? await appState.userAdmin.setStatus(userID: client.id, status: status, actingUser: acting)
        await onChange()
    }
}
