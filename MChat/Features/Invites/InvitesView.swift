import SwiftUI

/// Gestão de convites:
///  - qualquer usuário com `createInvites` cria convites (limitado às roles
///    que pode conceder);
///  - cada convite registra quem convidou e quem aceitou (árvore de convites);
///  - o super admin (`viewAllInvites` + `revokeInvites`) vê e revoga tudo.
struct InvitesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var invites: [Invite] = []
    @State private var users: [User] = []
    @State private var showCreate = false
    @State private var errorMessage: String?

    private var canSeeAll: Bool { appState.can(.viewAllInvites) }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                if invites.isEmpty {
                    Text("Nenhum convite.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }

                ForEach(invites) { invite in
                    InviteRow(
                        invite: invite,
                        creatorName: name(of: invite.createdBy),
                        acceptedName: invite.acceptedByUserID.map(name(of:)),
                        canRevoke: canRevoke(invite)
                    ) {
                        Task { await revoke(invite) }
                    }
                }
            }
            .navigationTitle(canSeeAll ? "Convites (todos)" : "Meus Convites")
            .toolbar {
                if appState.can(.createInvites) {
                    Button {
                        showCreate = true
                    } label: {
                        Label("Novo convite", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateInviteView { await load() }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func name(of userID: UUID) -> String {
        users.first(where: { $0.id == userID })?.name ?? "—"
    }

    private func canRevoke(_ invite: Invite) -> Bool {
        guard invite.status == .pending, let me = appState.currentUser else { return false }
        return invite.createdBy == me.id || me.can(.revokeInvites)
    }

    private func load() async {
        guard let me = appState.currentUser else { return }
        users = (try? await appState.userAdmin.fetchClients()) ?? []
        do {
            invites = canSeeAll
                ? try await appState.inviteService.allInvites(actingUser: me)
                : try await appState.inviteService.invites(createdBy: me.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revoke(_ invite: Invite) async {
        guard let me = appState.currentUser else { return }
        do {
            _ = try await appState.inviteService.revoke(inviteID: invite.id, actingUser: me)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct InviteRow: View {
    let invite: Invite
    let creatorName: String
    let acceptedName: String?
    let canRevoke: Bool
    let onRevoke: () -> Void

    private var statusTint: Color {
        switch invite.status {
        case .pending:  return .orange
        case .accepted: return .green
        case .revoked:  return .red
        case .expired:  return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(invite.code).font(.headline.monospaced())
                Spacer()
                Text(invite.status.displayName)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusTint.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusTint)
            }
            Text("Convidado por: \(creatorName)")
                .font(.caption).foregroundStyle(.secondary)
            if let acceptedName {
                Text("Aceito por: \(acceptedName)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !invite.grantedRoles.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(invite.grantedRoles).sorted(by: { $0.rawValue < $1.rawValue })) { role in
                        RoleBadge(role: role)
                    }
                }
            }
        }
        .swipeActions {
            if canRevoke {
                Button("Revogar", role: .destructive, action: onRevoke)
            }
        }
    }
}

struct CreateInviteView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onCreate: () async -> Void

    @State private var contact = ""
    @State private var selectedRoles: Set<Role> = [.chatOnly]
    @State private var createdInvite: Invite?
    @State private var errorMessage: String?

    private var grantable: Set<Role> {
        guard let me = appState.currentUser else { return [] }
        return MockInviteService.grantableRoles(by: me)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let createdInvite {
                    Section("Convite criado") {
                        LabeledContent("Código", value: createdInvite.code)
                        ShareLink(item: "Você foi convidado para o MChat. Código: \(createdInvite.code)") {
                            Label("Compartilhar", systemImage: "square.and.arrow.up")
                        }
                    }
                } else {
                    Section("Destinatário (opcional)") {
                        TextField("E-mail ou telefone", text: $contact)
                    }
                    Section("Roles concedidas ao aceitar") {
                        ForEach(Role.allCases.filter(grantable.contains)) { role in
                            Toggle(role.displayName, isOn: Binding(
                                get: { selectedRoles.contains(role) },
                                set: { on in
                                    if on { selectedRoles.insert(role) } else { selectedRoles.remove(role) }
                                }
                            ))
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                    Section {
                        Button("Gerar convite") { Task { await create() } }
                            .disabled(selectedRoles.isEmpty)
                    }
                }
            }
            .navigationTitle("Novo Convite")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") {
                        Task { await onCreate() }
                        dismiss()
                    }
                }
            }
        }
    }

    private func create() async {
        guard let me = appState.currentUser else { return }
        do {
            createdInvite = try await appState.inviteService.createInvite(
                from: me,
                contact: contact.isEmpty ? nil : contact,
                grantedRoles: selectedRoles
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
