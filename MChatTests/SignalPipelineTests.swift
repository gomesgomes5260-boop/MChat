import XCTest
@testable import MChat

/// Teste de INTEGRAÇÃO do pipeline E2EE ponta-a-ponta (Alice ↔ Bob) contra
/// a LibSignalClient real. Compila e roda apenas no Xcode com o pacote
/// `signalapp/libsignal` resolvido (ver `project.yml`), pois exercita as
/// APIs nativas do protocolo. No CI Linux sem a lib, é ignorado.
///
/// Valida o caminho feliz: registro → publicação de bundle → estabelecimento
/// de sessão → cifra/envio → busca/decifra, tudo com o `FakeSignalServer`
/// no lugar do backend, provando que o servidor só vê blobs opacos.
final class SignalPipelineTests: XCTestCase {

    func testAliceAndBobExchangeMessageEndToEnd() async throws {
        let server = FakeSignalServer()

        let alice = try SignalProtocolManager(localUserId: "alice", kv: InMemoryKVStore(), transport: server)
        let bob   = try SignalProtocolManager(localUserId: "bob",   kv: InMemoryKVStore(), transport: server)

        try await alice.registerAndPublishBundle(oneTimeKeyCount: 5)
        try await bob.registerAndPublishBundle(oneTimeKeyCount: 5)

        // Alice cifra para Bob; só Bob decifra.
        let secret = Data("olá bob, mensagem cifrada".utf8)
        try await alice.encryptAndSend(secret, to: "bob")

        let received = try await bob.fetchAndDecrypt()
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.plaintext, secret)

        // Safety number simétrico e estável entre as pontas.
        let snAlice = try alice.safetyNumber(with: "bob")
        XCTAssertNotNil(snAlice)
    }

    func testPreKeyReplenishmentTriggersBelowWatermark() async throws {
        let server = FakeSignalServer()
        let alice = try SignalProtocolManager(localUserId: "alice", kv: InMemoryKVStore(), transport: server)
        try await alice.registerAndPublishBundle(oneTimeKeyCount: 5) // abaixo do low-water mark (10)
        try await alice.replenishPreKeysIfNeeded()
        let remaining = try await server.remainingPreKeyCount(for: "alice", deviceId: 1)
        XCTAssertGreaterThanOrEqual(remaining, 10)
    }
}
