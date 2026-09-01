import Foundation

/// Leitura OFFLINE do destino de um pagamento — sem BaaS/banco:
///  - Boleto: valida a linha digitável (DVs módulo 10, padrão FEBRABAN) e
///    extrai banco, valor e vencimento (fator de vencimento).
///  - PIX "Copia e Cola" (EMV/BR Code): decodifica o TLV e extrai nome do
///    recebedor e valor.
///  - Chave PIX: classifica CPF, CNPJ, e-mail, telefone ou chave aleatória.
/// O que exige instituição licenciada é LIQUIDAR o pagamento ou consultar
/// o beneficiário de boleto registrado — a leitura/validação, não.
enum PaymentDestination: Equatable {
    case pixKey(kind: PixKeyKind, key: String)
    case pixCopiaECola(receiverName: String?, amountMinor: Int?)
    case boleto(bankName: String, dueDate: Date?, amountMinor: Int?)

    enum PixKeyKind: String {
        case cpf = "CPF", cnpj = "CNPJ", email = "e-mail"
        case phone = "telefone", random = "chave aleatória"
    }

    enum ParseError: LocalizedError, Equatable {
        case boletoInvalidCheckDigits
        case boletoInvalidLength
        case malformedEmv
        case unrecognized

        var errorDescription: String? {
            switch self {
            case .boletoInvalidCheckDigits:
                return "Código de boleto inválido: dígitos verificadores não conferem."
            case .boletoInvalidLength:
                return "Boleto deve ter 47 dígitos (linha digitável) ou 44 (código de barras)."
            case .malformedEmv:
                return "Código PIX Copia e Cola malformado."
            case .unrecognized:
                return "Informe uma chave PIX, um código PIX Copia e Cola ou a linha digitável de um boleto."
            }
        }
    }

    /// Valor embutido no código, quando houver (centavos de BRL).
    var embeddedAmountMinor: Int? {
        switch self {
        case .pixKey:                          return nil
        case .pixCopiaECola(_, let amount):    return amount
        case .boleto(_, _, let amount):        return amount
        }
    }

    var paymentType: PaymentType {
        if case .boleto = self { return .boleto }
        return .pix
    }

    /// Rótulo curto para exibição/armazenamento em `Payment.beneficiary`.
    var label: String {
        switch self {
        case .pixKey(let kind, let key):
            let short = key.count > 30 ? String(key.prefix(27)) + "…" : key
            return "PIX \(kind.rawValue): \(short)"
        case .pixCopiaECola(let name, _):
            return name.map { "\($0) (PIX)" } ?? "PIX Copia e Cola"
        case .boleto(let bank, let due, _):
            guard let due else { return "Boleto \(bank)" }
            let df = DateFormatter()
            df.dateFormat = "dd/MM/yyyy"
            return "Boleto \(bank) · venc \(df.string(from: due))"
        }
    }

    // MARK: - Parsing

    static func parse(_ raw: String) -> Result<PaymentDestination, ParseError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.unrecognized) }

        let digits = trimmed.filter(\.isNumber)
        let boletoShaped = trimmed.allSatisfy { $0.isNumber || $0 == " " || $0 == "." }
        if boletoShaped && (digits.count == 47 || digits.count == 44) {
            return parseBoleto(digits: digits)
        }
        if trimmed.hasPrefix("000201") {
            return parsePixEmv(trimmed)
        }
        if let kind = detectPixKey(trimmed) {
            return .success(.pixKey(kind: kind, key: trimmed))
        }
        return .failure(.unrecognized)
    }

    // MARK: Boleto (FEBRABAN)

    private static let bankNames: [String: String] = [
        "001": "Banco do Brasil", "033": "Santander", "077": "Inter",
        "104": "Caixa", "237": "Bradesco", "260": "Nubank",
        "336": "C6 Bank", "341": "Itaú", "748": "Sicredi", "756": "Sicoob"
    ]

    static func mod10(_ s: String) -> Int {
        var sum = 0, weight = 2
        for ch in s.reversed() {
            var n = ch.wholeNumberValue! * weight
            if n > 9 { n = n / 10 + n % 10 }
            sum += n
            weight = weight == 2 ? 1 : 2
        }
        return (10 - sum % 10) % 10
    }

    private static func parseBoleto(digits d: String) -> Result<PaymentDestination, ParseError> {
        func slice(_ s: String, _ range: Range<Int>) -> String {
            let start = s.index(s.startIndex, offsetBy: range.lowerBound)
            let end = s.index(s.startIndex, offsetBy: range.upperBound)
            return String(s[start..<end])
        }
        var barcode: String
        if d.count == 47 {
            let f1 = slice(d, 0..<9), f2 = slice(d, 10..<20), f3 = slice(d, 21..<31)
            guard mod10(f1) == Int(slice(d, 9..<10)),
                  mod10(f2) == Int(slice(d, 20..<21)),
                  mod10(f3) == Int(slice(d, 31..<32)) else {
                return .failure(.boletoInvalidCheckDigits)
            }
            barcode = slice(d, 0..<4) + slice(d, 32..<33) + slice(d, 33..<47)
                    + slice(d, 4..<9) + slice(d, 10..<20) + slice(d, 21..<31)
        } else if d.count == 44 {
            barcode = d
        } else {
            return .failure(.boletoInvalidLength)
        }

        let bank = bankNames[slice(barcode, 0..<3)] ?? "Banco \(slice(barcode, 0..<3))"
        let fator = Int(slice(barcode, 5..<9)) ?? 0
        let rawAmount = Int(slice(barcode, 9..<19)) ?? 0
        let amount = rawAmount > 0 ? rawAmount : nil

        // Fator de vencimento: base 07/10/1997; reinicia em 1000 = 22/02/2025.
        var due: Date? = nil
        if fator > 0 {
            let day: TimeInterval = 86_400
            let base1997 = Date(timeIntervalSince1970: 876_182_400)   // 1997-10-07
            let base2025 = Date(timeIntervalSince1970: 1_740_182_400) // 2025-02-22
            let d1 = base1997.addingTimeInterval(TimeInterval(fator) * day)
            let d2 = base2025.addingTimeInterval(TimeInterval(fator - 1000) * day)
            let now = Date()
            due = (fator >= 1000 && abs(d2.timeIntervalSince(now)) < abs(d1.timeIntervalSince(now))) ? d2 : d1
        }
        return .success(.boleto(bankName: bank, dueDate: due, amountMinor: amount))
    }

    // MARK: PIX Copia e Cola (EMV/BR Code)

    private static func parsePixEmv(_ s: String) -> Result<PaymentDestination, ParseError> {
        var tags: [String: String] = [:]
        var i = s.startIndex
        while s.distance(from: i, to: s.endIndex) >= 4 {
            let tag = String(s[i..<s.index(i, offsetBy: 2)])
            guard let len = Int(s[s.index(i, offsetBy: 2)..<s.index(i, offsetBy: 4)]),
                  s.distance(from: i, to: s.endIndex) >= 4 + len else {
                return .failure(.malformedEmv)
            }
            let valueStart = s.index(i, offsetBy: 4)
            let valueEnd = s.index(valueStart, offsetBy: len)
            tags[tag] = String(s[valueStart..<valueEnd])
            i = valueEnd
        }
        guard i == s.endIndex else { return .failure(.malformedEmv) }
        let amount = tags["54"].flatMap { Double($0) }.map { Int(($0 * 100).rounded()) }
        return .success(.pixCopiaECola(receiverName: tags["59"], amountMinor: amount))
    }

    // MARK: Chave PIX

    private static func detectPixKey(_ t: String) -> PixKeyKind? {
        let digits = t.filter(\.isNumber)
        if t.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#,
                   options: .regularExpression) != nil { return .random }
        if t.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil { return .email }
        if digits.count == 14 && t.allSatisfy({ $0.isNumber || "./-".contains($0) }) { return .cnpj }
        if digits.count == 11 && isValidCPF(digits) && t.allSatisfy({ $0.isNumber || ".-".contains($0) }) { return .cpf }
        if (10...13).contains(digits.count) && t.allSatisfy({ $0.isNumber || "+ ()-".contains($0) }) { return .phone }
        return nil
    }

    static func isValidCPF(_ d: String) -> Bool {
        guard d.count == 11, d.allSatisfy(\.isNumber), Set(d).count > 1 else { return false }
        let nums = d.compactMap(\.wholeNumberValue)
        for len in [9, 10] {
            var sum = 0
            for i in 0..<len { sum += nums[i] * (len + 1 - i) }
            let dv = (sum * 10) % 11 % 10
            if dv != nums[len] { return false }
        }
        return true
    }
}
