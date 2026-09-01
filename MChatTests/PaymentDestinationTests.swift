import XCTest
@testable import MChat

final class PaymentDestinationTests: XCTestCase {

    // Linha digitável válida construída com o mesmo mod10 do parser.
    private func makeLinhaDigitavel() -> String {
        let free = "1234567890123456789012345"
        let f1 = "341" + "9" + String(free.prefix(5))
        let f2 = String(free.dropFirst(5).prefix(10))
        let f3 = String(free.dropFirst(15).prefix(10))
        return f1 + String(PaymentDestination.mod10(f1))
             + f2 + String(PaymentDestination.mod10(f2))
             + f3 + String(PaymentDestination.mod10(f3))
             + "1" + "1100" + "0000055000"
    }

    func testBoletoLinhaDigitavelParsed() throws {
        // Injeta um "agora" anterior ao vencimento (~02/06/2025) para isolar
        // o parsing da regra de vencimento (coberta em outro teste).
        let before = Date(timeIntervalSince1970: 1_746_057_600) // 2025-05-01
        let result = PaymentDestination.parse(makeLinhaDigitavel(), now: before)
        guard case .success(.boleto(let bank, let due, let amount)) = result else {
            return XCTFail("Esperava boleto, obteve \(result)")
        }
        XCTAssertEqual(bank, "Itaú")
        XCTAssertEqual(amount, 55_000) // R$ 550,00
        XCTAssertNotNil(due)
    }

    func testBoletoExpiredIsRejected() {
        // A linha de teste vence ~02/06/2025 (fator 1100). Longe no futuro → vencido.
        let farFuture = Date(timeIntervalSince1970: 1_893_456_000) // 2030-01-01
        guard case .failure(.boletoExpired) = PaymentDestination.parse(makeLinhaDigitavel(), now: farFuture) else {
            return XCTFail("Boleto vencido deveria ser recusado")
        }
    }

    func testBoletoAcceptedOnOrBeforeDueDate() throws {
        // Antes do vencimento → aceito.
        let before = Date(timeIntervalSince1970: 1_746_057_600) // 2025-05-01
        guard case .success(.boleto) = PaymentDestination.parse(makeLinhaDigitavel(), now: before) else {
            return XCTFail("Boleto ainda válido deveria ser aceito")
        }
    }

    func testBoletoWrongCheckDigitRejected() {
        var linha = makeLinhaDigitavel()
        // corrompe o primeiro DV (posição 9)
        let idx = linha.index(linha.startIndex, offsetBy: 9)
        let dv = linha[idx].wholeNumberValue!
        linha.replaceSubrange(idx...idx, with: String((dv + 1) % 10))
        guard case .failure(.boletoInvalidCheckDigits) = PaymentDestination.parse(linha) else {
            return XCTFail("Boleto corrompido deveria ser rejeitado")
        }
    }

    func testPixCopiaEColaParsed() throws {
        let emv = "000201" + "26330014BR.GOV.BCB.PIX0111chave@x.com" + "52040000"
                + "5303986" + "540510.00" + "5802BR" + "5913Fulano de Tal"
                + "6009Sao Paulo" + "6304ABCD"
        guard case .success(.pixCopiaECola(let name, let amount)) = PaymentDestination.parse(emv) else {
            return XCTFail("Esperava PIX Copia e Cola")
        }
        XCTAssertEqual(name, "Fulano de Tal")
        XCTAssertEqual(amount, 1_000) // R$ 10,00
    }

    func testPixKeyKinds() {
        func kind(_ s: String) -> PaymentDestination.PixKeyKind? {
            if case .success(.pixKey(let k, _)) = PaymentDestination.parse(s) { return k }
            return nil
        }
        XCTAssertEqual(kind("fulano@exemplo.com"), .email)
        XCTAssertEqual(kind("123e4567-e89b-12d3-a456-426614174000"), .random)
        XCTAssertEqual(kind("+55 11 91234-5678"), .phone)
        XCTAssertEqual(kind("529.982.247-25"), .cpf)   // CPF com DVs válidos
        XCTAssertEqual(kind("12.345.678/0001-95"), .cnpj)
    }

    func testUnrecognizedRejected() {
        guard case .failure(.unrecognized) = PaymentDestination.parse("abc123") else {
            return XCTFail("Entrada aleatória deveria ser rejeitada")
        }
    }

    func testCPFValidation() {
        XCTAssertTrue(PaymentDestination.isValidCPF("52998224725"))
        XCTAssertFalse(PaymentDestination.isValidCPF("11111111111"))
        XCTAssertFalse(PaymentDestination.isValidCPF("52998224724"))
    }
}
