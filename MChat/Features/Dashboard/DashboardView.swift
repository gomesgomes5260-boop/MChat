import SwiftUI

/// Espelha o dashboard do painel web: cards de totais, pendências e ações rápidas.
struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var summary: DashboardSummary?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let summary {
                    LazyVGrid(columns: columns, spacing: 12) {
                        StatCard(title: "Total de Clientes", value: summary.totalClients,
                                 subtitle: "Clientes cadastrados", icon: "person.2", tint: .blue)
                        StatCard(title: "Clientes Ativos", value: summary.activeClients,
                                 subtitle: "Com conta ativa", icon: "person.crop.circle.badge.checkmark", tint: .green)
                        StatCard(title: "Saques Pendentes", value: summary.pendingWithdrawals,
                                 subtitle: "Aguardando aprovação", icon: "arrow.down.circle", tint: .yellow)
                        StatCard(title: "Pagamentos Pendentes", value: summary.pendingPayments,
                                 subtitle: "Aguardando processamento", icon: "banknote", tint: .purple)
                        StatCard(title: "Aprovação Manual", value: summary.pendingApprovalClients,
                                 subtitle: "Clientes com aprovação pendente", icon: "clock", tint: .orange)
                        StatCard(title: "Clientes Suspensos", value: summary.suspendedClients,
                                 subtitle: "Contas suspensas", icon: "person.crop.circle.badge.xmark", tint: .red)
                    }
                    .padding()
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .navigationTitle("Dashboard")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        summary = try? await appState.finance.dashboardSummary()
    }
}

struct StatCard: View {
    let title: String
    let value: Int
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon).foregroundStyle(tint)
            }
            Text("\(value)").font(.system(size: 32, weight: .bold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
