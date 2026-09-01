import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var showRegister = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("E-mail", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    SecureField("Senha", text: $password)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                Section {
                    Button("Entrar") { Task { await signIn() } }
                        .disabled(email.isEmpty || password.isEmpty)
                    Button("Tenho um convite") { showRegister = true }
                }
            }
            .navigationTitle("MChat")
            .sheet(isPresented: $showRegister) { InviteSignupView() }
        }
    }

    private func signIn() async {
        do {
            appState.currentUser = try await appState.auth.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
