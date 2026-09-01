import Foundation

/// Moedas suportadas pelo gerenciador de ativos.
enum Currency: String, Codable, CaseIterable, Identifiable {
    case brl = "BRL"
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .brl: return "R$"
        case .usd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        }
    }

    var displayName: String {
        switch self {
        case .brl: return "Real"
        case .usd: return "Dólar"
        case .eur: return "Euro"
        case .gbp: return "Libra"
        }
    }
}

/// Valor monetário em centavos para evitar erros de ponto flutuante.
struct Money: Codable, Hashable, Comparable {
    var amountMinor: Int   // centavos
    var currency: Currency

    var decimalValue: Decimal { Decimal(amountMinor) / 100 }

    static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currency == rhs.currency, "Não compare moedas diferentes")
        return lhs.amountMinor < rhs.amountMinor
    }

    var formatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: decimalValue as NSDecimalNumber)
            ?? "\(currency.symbol) \(decimalValue)"
    }
}

/// Carteira multi-moeda de um usuário.
struct Wallet: Codable, Hashable {
    var balances: [Currency: Money]

    static var empty: Wallet {
        Wallet(balances: Currency.allCases.reduce(into: [:]) {
            $0[$1] = Money(amountMinor: 0, currency: $1)
        })
    }

    func balance(in currency: Currency) -> Money {
        balances[currency] ?? Money(amountMinor: 0, currency: currency)
    }
}
