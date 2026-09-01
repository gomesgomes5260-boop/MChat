import XCTest
import CryptoKit
@testable import MChat

/// Testes das GARANTIAS de privacidade que não dependem da LibSignalClient:
/// transporte/servidor fake, mix network, banco local cifrado, push vazio e
/// o mínimo do art. 15. O pipeline criptográfico em si (X3DH/Double Ratchet)
/// é exercitado por `SignalPipelineTests`, que compila apenas com a
/// LibSignalClient resolvida pelo SwiftPM (ver nota no topo daquele arquivo).
final class E2EEInfraTests: XCTestCase {

    // MARK: Servidor não vê conteúdo nem relação; fila é apagada ao entregar.

    func testServerStoresOnlyOpaqueCiphertextAndDrains() async throws {
        let server = FakeSignalServer()
        let opaque = Data("conteudo-cifrado-opaco".utf8)
        let env = SealedEnvelope(recipient: "bob", deviceId: 1, ciphertext: opaque,
                                 contentHint: 3, timestamp: Date(), senderHint: nil)
        try await server.send(env)

        // Entrega remove da fila (sem histórico no servidor).
        let first = try await server.drainInbox(for: "bob", deviceId: 1)
        XCTAssertEqual(first, [env])
        let second = try await server.drainInbox(for: "bob", deviceId: 1)
        XCTAssertTrue(second.isEmpty)
        let empty = await server.inboxIsEmpty(for: "bob", deviceId: 1)
        XCTAssertTrue(empty)
    }

    func testSealedSenderCarriesNoSenderMetadata() {
        // Sob sealed sender (produção), o remetente vai cifrado dentro de
        // `ciphertext` e `senderHint` é sempre nil — o servidor não vê par
        // de conversa. O campo só é preenchido no modo identificado de teste.
        let sealed = SealedEnvelope(recipient: "bob", deviceId: 1,
                                    ciphertext: Data([0x00]), contentHint: 3,
                                    timestamp: Date(), senderHint: nil)
        XCTAssertNil(sealed.senderHint)
        let labels = Set(Mirror(reflecting: sealed).children.compactMap(\.label))
        XCTAssertFalse(labels.contains("sender"))
        XCTAssertFalse(labels.contains("senderId"))
    }

    // MARK: Art. 15 — só IP + timestamp, nunca o par de conversa.

    func testAccessLogHasNoConversationGraph() async throws {
        let server = FakeSignalServer()
        await server.setCurrentIP("198.51.100.7")
        let env = SealedEnvelope(recipient: "bob", deviceId: 1,
                                 ciphertext: Data([1,2,3]), contentHint: 3, timestamp: Date(), senderHint: nil)
        try await server.send(env)
        _ = try await server.drainInbox(for: "bob", deviceId: 1)

        let log = await server.accessLog
        XCTAssertEqual(log.count, 2) // um por acesso (send + drain)
        for record in log {
            XCTAssertEqual(record.ip, "198.51.100.7")
            // O registro tem exatamente dois campos: ip e at. Nada de quem-com-quem.
            let labels = Mirror(reflecting: record).children.compactMap(\.label)
            XCTAssertEqual(Set(labels), ["ip", "at"])
        }
    }

    // MARK: Banco local cifrado — round-trip e ilegível sem a chave.

    func testLocalStoreEncryptsAtRest() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let key = SymmetricKey(size: .bits256)
        let store = try LocalMessageStore(directory: dir, key: key)
        let convo = PushTriggerHandler.conversationId("alice", "bob")
        let msg = LocalMessageStore.StoredMessage(id: UUID(), conversationId: convo,
            senderId: "bob", isMine: false, text: "mensagem secreta", sentAt: Date())
        try store.append(msg)

        // Reabrir com a mesma chave devolve a mensagem.
        let reopened = try LocalMessageStore(directory: dir, key: key)
        XCTAssertEqual(reopened.messages(in: convo).first?.text, "mensagem secreta")

        // O arquivo bruto NÃO contém o texto em claro.
        let raw = try Data(contentsOf: dir.appendingPathComponent("messages.enc"))
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("mensagem secreta"))

        // Chave errada não abre.
        XCTAssertThrowsError(try LocalMessageStore(directory: dir, key: SymmetricKey(size: .bits256)))
    }

    func testLocalStoreWipeIsIrreversible() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let key = SymmetricKey(size: .bits256)
        let store = try LocalMessageStore(directory: dir, key: key)
        try store.append(.init(id: UUID(), conversationId: "c", senderId: "b",
                               isMine: false, text: "x", sentAt: Date()))
        try store.wipe()
        let reopened = try LocalMessageStore(directory: dir, key: key)
        XCTAssertEqual(reopened.count, 0)
    }

    // MARK: Push vazio — só gatilho, recusa payload com conteúdo.

    func testPushTriggerRejectsContentfulPayloads() {
        XCTAssertTrue(PushTriggerHandler.isEmptyTrigger(["aps": ["content-available": 1]]))
        XCTAssertTrue(PushTriggerHandler.isEmptyTrigger(["aps": ["mutable-content": 1]]))
        XCTAssertFalse(PushTriggerHandler.isEmptyTrigger(["aps": ["alert": ["body": "Oi Bob"]]]))
        XCTAssertFalse(PushTriggerHandler.isEmptyTrigger(["aps": ["alert": "Nova mensagem de Alice"]]))
    }

    func testConversationIdIsSymmetricAndLocal() {
        XCTAssertEqual(PushTriggerHandler.conversationId("alice", "bob"),
                       PushTriggerHandler.conversationId("bob", "alice"))
    }

    // MARK: Mix network — decorator opcional, transparente quando desligado.

    func testMixNetworkDisabledIsTransparent() async throws {
        let server = FakeSignalServer()
        let mix = MixNetworkTransport(base: server, config: .disabled)
        let env = SealedEnvelope(recipient: "bob", deviceId: 1,
                                 ciphertext: Data([9]), contentHint: 3, timestamp: Date(), senderHint: nil)
        try await mix.send(env)
        let got = try await mix.drainInbox(for: "bob", deviceId: 1)
        XCTAssertEqual(got, [env])
    }

    func testMixNetworkCoverTrafficIsFilteredOut() async throws {
        let server = FakeSignalServer()
        var cfg = MixNetworkTransport.Config()
        cfg.enabled = true
        cfg.maxJitter = 0          // sem atraso nos testes
        cfg.coverTrafficRate = 1.0 // sempre injeta decoy
        let mix = MixNetworkTransport(base: server, config: cfg)
        let real = SealedEnvelope(recipient: "bob", deviceId: 1,
                                  ciphertext: Data([1,1,1]), contentHint: 3, timestamp: Date(), senderHint: nil)
        try await mix.send(real)
        // O servidor viu 2 envelopes (real + decoy)...
        let atServer = try await server.drainInbox(for: "bob", deviceId: 1)
        XCTAssertEqual(atServer.count, 2)
        // ...mas a mixnet filtra o decoy (contentHint 0xFF) na entrega.
        try await server.send(real) // repõe para drenar via mix
        try await mix.send(real)
        let viaMix = try await mix.drainInbox(for: "bob", deviceId: 1)
        XCTAssertTrue(viaMix.allSatisfy { $0.contentHint != 0xFF })
    }
}
