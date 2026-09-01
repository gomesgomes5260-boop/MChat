import SwiftUI

struct PaymentsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var payments: [Payment] = []
    @State private var filter: PaymentStatus?

    var body: some View {
        NavigationStack {
            List {
                Picker("Filtro", selection: $filter) {
                    Text("Todos").tag(PaymentStatus?.none)
                    ForEach(PaymentStatus.allCases, id: \.self) { status in
                        Text(status.displayName + "s").tag(PaymentStatus?.some(status))
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if payments.isEmpty {
                    Text("Nenhum pagamento encontrado.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }

                ForEach(payments) { payment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(payment.clientName).font(.headline)
                            Spacer()
                            Text(payment.amount.formatted).font(.body.monospaced())
                        }
                        Text("\(payment.type.displayName) → \(payment.beneficiary)")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text(payment.status.displayName)
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if payment.status == .pending && appState.can(.processPayments) {
                                Button("Processar") { Task { await process(payment, complete: true) } }
                                    .buttonStyle(.borderedProminent).controlSize(.small)
                                Button("Cancelar", role: .destructive) {
                                    Task { await process(payment, complete: false) }
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pagamentos")
            .task(id: filter) { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        payments = (try? await appState.finance.payments(status: filter)) ?? []
    }

    private func process(_ payment: Payment, complete: Bool) async {
        guard let acting = appState.currentUser else { return }
        _ = try? await appState.finance.processPayment(id: payment.id, complete: complete, actingUser: acting)
        await load()
    }
}
