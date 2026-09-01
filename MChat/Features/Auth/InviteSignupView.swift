import SwiftUI

/// Cadastro exclusivamente por convite: o fluxo valida o código antes de
/// liberar os campos de cadastro, e o novo usuário nasce vinculado a quem
/// o convidou (invitedByUserID).
struct InviteSignupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var inviteCode = ""
    @State private var validatedInvite: Invite?
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Convite") {
                    TextField("Código do convite", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .disabled(validatedInvite != nil)
                    if validatedInvite == nil {
                        Button("Validar convite") { Task { await validate() } }
                            .disabled(inviteCode.isEmpty)
                    } else {
                        Label("Convite válido", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }

                if validatedInvite != nil {
                    Section("Seus dados") {
                        TextField("Nome", text: $name)
                        TextField("E-mail", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        SecureField("Senha", text: $password)
                    }
                    Section {
                        Button("Criar conta") { Task { await register() } }
                            .disabled(name.isEmpty || email.isEmpty || password.isEmpty)
                    } footer: {
                        Text("Sua conta ficará pendente até aprovação manual de um administrador.")
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Cadastro por convite")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }

    private func validate() async {
        do {
            validatedInvite = try await appState.inviteService.validate(code: inviteCode)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func register() async {
        do {
            appState.currentUser = try await appState.auth.register(
                inviteCode: inviteCode, name: name, email: email, password: password
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
