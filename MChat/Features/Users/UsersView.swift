import SwiftUI

/// Espelha a tela "Usuários" do painel: lista quem tem roles administrativas
/// e permite editar roles (gated por `editRoles`).
struct UsersView: View {
    @EnvironmentObject private var appState: AppState
    @State private var users: [User] = []
    @State private var editingUser: User?

    var body: some View {
        NavigationStack {
            List(users) { user in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(user.name).font(.headline)
                        if user.id == appState.currentUser?.id {
                            Text("(você)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(status: user.status)
                    }
                    if let email = user.email {
                        Text(email).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        ForEach(Array(user.roles).sorted(by: { $0.rawValue < $1.rawValue })) { role in
                            RoleBadge(role: role)
                        }
                    }
                }
                .swipeActions {
                    if appState.can(.editRoles) && user.id != appState.currentUser?.id {
                        Button("Editar Roles") { editingUser = user }.tint(.blue)
                    }
                }
            }
            .navigationTitle("Usuários")
            .sheet(item: $editingUser) { user in
                EditRolesView(user: user) { await load() }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        users = (try? await appState.userAdmin.fetchAdminUsers()) ?? []
    }
}

/// Edição de roles com as regras do domínio:
///  - requer permissão `editRoles`;
///  - a role Super Admin só pode ser concedida/removida por um super admin.
struct EditRolesView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let user: User
    let onSave: () async -> Void

    @State private var selectedRoles: Set<Role> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Roles de \(user.name)") {
                    ForEach(Role.allCases) { role in
                        Toggle(role.displayName, isOn: binding(for: role))
                            .disabled(role == .superAdmin && !(appState.currentUser?.isSuperAdmin ?? false))
                    }
                }

                Section("Permissões resultantes") {
                    let permissions = selectedRoles
                        .reduce(into: Set<Permission>()) { $0.formUnion($1.permissions) }
                    Text("\(permissions.count) permissões")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Editar Roles")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { Task { await save() } }
                        .disabled(selectedRoles.isEmpty)
                }
            }
            .onAppear { selectedRoles = user.roles }
        }
    }

    private func binding(for role: Role) -> Binding<Bool> {
        Binding(
            get: { selectedRoles.contains(role) },
            set: { on in
                if on { selectedRoles.insert(role) } else { selectedRoles.remove(role) }
            }
        )
    }

    private func save() async {
        guard let acting = appState.currentUser else { return }
        do {
            _ = try await appState.userAdmin.updateRoles(userID: user.id, roles: selectedRoles, actingUser: acting)
            await onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
