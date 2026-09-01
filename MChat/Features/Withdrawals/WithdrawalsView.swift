import SwiftUI

struct WithdrawalsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var withdrawals: [Withdrawal] = []
    @State private var filter: WithdrawalStatus?

    var body: some View {
        NavigationStack {
            List {
                Picker("Filtro", selection: $filter) {
                    Text("Todos").tag(WithdrawalStatus?.none)
                    ForEach(WithdrawalStatus.allCases, id: \.self) { status in
                        Text(status.displayName + "s").tag(WithdrawalStatus?.some(status))
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if withdrawals.isEmpty {
                    Text("Nenhum saque encontrado.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }

                ForEach(withdrawals) { withdrawal in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(withdrawal.clientName).font(.headline)
                            Spacer()
                            Text(withdrawal.amount.formatted).font(.body.monospaced())
                        }
                        HStack {
                            Text(withdrawal.status.displayName)
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if withdrawal.status == .pending && appState.can(.approveWithdrawals) {
                                Button("Aprovar") { Task { await decide(withdrawal, approve: true) } }
                                    .buttonStyle(.borderedProminent).controlSize(.small)
                                Button("Cancelar", role: .destructive) {
                                    Task { await decide(withdrawal, approve: false) }
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saques")
            .task(id: filter) { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        withdrawals = (try? await appState.finance.withdrawals(status: filter)) ?? []
    }

    private func decide(_ withdrawal: Withdrawal, approve: Bool) async {
        guard let acting = appState.currentUser else { return }
        _ = try? await appState.finance.decideWithdrawal(id: withdrawal.id, approve: approve, actingUser: acting)
        await load()
    }
}
