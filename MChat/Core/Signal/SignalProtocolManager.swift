import Foundation
import LibSignalClient

/// Pipeline E2EE real (X3DH/PQXDH + Double Ratchet) sobre a LibSignalClient.
///
/// Garantias implementadas:
///  - Chaves privadas geradas e guardadas SÓ no aparelho (stores sobre
///    `SignalKeyValueStore`; no app, cifrado + Keychain). Nunca transmitidas.
///  - Ao servidor vão apenas partes públicas (pre-key bundles) e envelopes
///    cifrados; o servidor não tem como ler conteúdo.
///  - Sealed sender: o remetente é cifrado dentro do envelope.
///  - Safety number (fingerprint) para verificação e detecção de troca de chave.
///  - Reposição automática de one-time pre-keys.
///
/// O histórico de mensagens NÃO passa por aqui em claro para persistência —
/// quem grava é `LocalMessageStore` (banco local cifrado).
final class SignalProtocolManager {
    let localUserId: String
    let deviceId: UInt32
    private let store: MChatProtocolStore
    private let transport: MessageTransport
    private let senderCert: SenderCertificate?
    private let lowWaterMark = 10
    private let refillCount = 100

    init(localUserId: String,
         deviceId: UInt32 = 1,
         kv: SignalKeyValueStore,
         transport: MessageTransport,
         senderCertificate: SenderCertificate? = nil) throws {
        self.localUserId = localUserId
        self.deviceId = deviceId
        self.store = try MChatProtocolStore(kv: kv)
        self.transport = transport
        self.senderCert = senderCertificate
    }

    private func address(_ userId: String, _ device: UInt32) -> ProtocolAddress {
        try! ProtocolAddress(name: userId, deviceId: device)
    }

    // MARK: Registro inicial — publica bundle público, guarda privadas localmente.

    func registerAndPublishBundle(oneTimeKeyCount: Int = 100) async throws {
        let ctx = NullContext()
        let identity = try store.identityStore.identityKeyPair(context: ctx)
        let regId = try store.identityStore.localRegistrationId(context: ctx)

        // Signed pre-key
        let signedId = UInt32.random(in: 1...0x7FFFFF)
        let signedPair = PrivateKey.generate()
        let signedSig = identity.privateKey.generateSignature(message: signedPair.publicKey.serialize())
        let signedRecord = try SignedPreKeyRecord(id: signedId, timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                                                  privateKey: signedPair, signature: signedSig)
        try store.signedPreKeyStore.storeSignedPreKey(signedRecord, id: signedId, context: ctx)

        // Kyber pre-key (PQXDH)
        let kyberId = UInt32.random(in: 1...0x7FFFFF)
        let kyberPair = KEMKeyPair.generate()
        let kyberSig = identity.privateKey.generateSignature(message: kyberPair.publicKey.serialize())
        let kyberRecord = try KyberPreKeyRecord(id: kyberId, timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                                                keyPair: kyberPair, signature: kyberSig)
        try store.kyberPreKeyStore.storeKyberPreKey(kyberRecord, id: kyberId, context: ctx)

        // One-time pre-keys
        var publicOTPs: [PublicSinglePreKey] = []
        for _ in 0..<oneTimeKeyCount {
            let id = UInt32.random(in: 1...0x7FFFFF)
            let pair = PrivateKey.generate()
            let rec = try PreKeyRecord(id: id, privateKey: pair)
            try store.preKeyStore.storePreKey(rec, id: id, context: ctx)
            publicOTPs.append(PublicSinglePreKey(id: id, publicKey: Data(pair.publicKey.serialize())))
        }

        let first = publicOTPs.first
        let bundle = PublicPreKeyBundle(
            registrationId: regId, deviceId: deviceId,
            identityKey: Data(identity.identityKey.serialize()),
            signedPreKeyId: signedId, signedPreKeyPublic: Data(signedPair.publicKey.serialize()),
            signedPreKeySignature: Data(signedSig),
            preKeyId: first?.id, preKeyPublic: first?.publicKey,
            kyberPreKeyId: kyberId, kyberPreKeyPublic: Data(kyberPair.publicKey.serialize()),
            kyberPreKeySignature: Data(kyberSig))

        try await transport.publishBundle(bundle, for: localUserId)
        // As pré-chaves além da primeira vão para o pool consumível do servidor.
        if publicOTPs.count > 1 {
            try await transport.replenishPreKeys(Array(publicOTPs.dropFirst()), for: localUserId)
        }
    }

    // MARK: Estabelecer sessão a partir do bundle público do destinatário.

    func establishSession(with userId: String, device: UInt32 = 1) async throws {
        let ctx = NullContext()
        let b = try await transport.fetchBundle(for: userId, deviceId: device)
        let identity = try IdentityKey(bytes: b.identityKey)
        let signedPrekey = try PublicKey(b.signedPreKeyPublic)
        let kyberPrekey = try KEMPublicKey(b.kyberPreKeyPublic)

        // Duas variantes: com ou sem one-time pre-key disponível no servidor.
        let bundle: PreKeyBundle
        if let preKeyId = b.preKeyId, let preKeyPublicData = b.preKeyPublic {
            bundle = try PreKeyBundle(
                registrationId: b.registrationId, deviceId: b.deviceId,
                prekeyId: preKeyId, prekey: try PublicKey(preKeyPublicData),
                signedPrekeyId: b.signedPreKeyId, signedPrekey: signedPrekey,
                signedPrekeySignature: Array(b.signedPreKeySignature),
                identity: identity,
                kyberPrekeyId: b.kyberPreKeyId, kyberPrekey: kyberPrekey,
                kyberPrekeySignature: Array(b.kyberPreKeySignature))
        } else {
            bundle = try PreKeyBundle(
                registrationId: b.registrationId, deviceId: b.deviceId,
                signedPrekeyId: b.signedPreKeyId, signedPrekey: signedPrekey,
                signedPrekeySignature: Array(b.signedPreKeySignature),
                identity: identity,
                kyberPrekeyId: b.kyberPreKeyId, kyberPrekey: kyberPrekey,
                kyberPrekeySignature: Array(b.kyberPreKeySignature))
        }
        try processPreKeyBundle(bundle, for: address(userId, device),
                                ourAddress: address(localUserId, deviceId),
                                sessionStore: store.sessionStore, identityStore: store.identityStore,
                                context: ctx)
    }

    // MARK: Envio (cifra + sealed sender).

    func encryptAndSend(_ plaintext: Data, to userId: String, device: UInt32 = 1) async throws {
        let ctx = NullContext()
        let addr = address(userId, device)
        if try store.sessionStore.loadSession(for: addr, context: ctx) == nil {
            try await establishSession(with: userId, device: device)
        }
        let cipher = try signalEncrypt(message: plaintext, for: addr,
                                       localAddress: address(localUserId, deviceId),
                                       sessionStore: store.sessionStore,
                                       identityStore: store.identityStore, context: ctx)

        let payload: Data
        let senderHint: String?
        if let cert = senderCert {
            // Sealed sender: o remetente é cifrado dentro do envelope.
            let usmc = try UnidentifiedSenderMessageContent(
                cipher, from: cert, contentHint: .default, groupId: [])
            payload = try sealedSenderEncrypt(usmc, for: addr,
                                              identityStore: store.identityStore, context: ctx)
            senderHint = nil // remetente vai cifrado dentro do envelope
        } else {
            payload = cipher.serialize()
            senderHint = localUserId // modo identificado (testes locais)
        }

        try await transport.send(SealedEnvelope(
            recipient: userId, deviceId: device, ciphertext: payload,
            contentHint: cipher.messageType.rawValue, timestamp: Date(),
            senderHint: senderHint))
    }

    // MARK: Recepção (decifra tudo o que o servidor enfileirou).

    struct DecryptedMessage { let senderUserId: String; let plaintext: Data; let receivedAt: Date }

    func fetchAndDecrypt() async throws -> [DecryptedMessage] {
        let ctx = NullContext()
        let envelopes = try await transport.drainInbox(for: localUserId, deviceId: deviceId)
        var out: [DecryptedMessage] = []
        for env in envelopes {
            do {
                let (senderId, plaintext) = try decryptEnvelope(env, ctx: ctx)
                out.append(DecryptedMessage(senderUserId: senderId, plaintext: plaintext, receivedAt: env.timestamp))
            } catch {
                // Envelope indecifrável (ex.: cover traffic residual) é ignorado.
                continue
            }
        }
        try await replenishPreKeysIfNeeded()
        return out
    }

    private func decryptEnvelope(_ env: SealedEnvelope, ctx: StoreContext) throws -> (String, Data) {
        // Sealed sender: desembrulha o USMC (recupera o remetente de dentro,
        // via certificado) e então decifra a mensagem Signal interna.
        if senderCert != nil, env.senderHint == nil {
            let usmc = try UnidentifiedSenderMessageContent(
                message: env.ciphertext,
                identityStore: store.identityStore, context: ctx)
            let sender = usmc.senderCertificate.sender
            let senderId = sender.uuidString
            let plaintext = try decryptInner(type: usmc.messageType, bytes: usmc.contents,
                                             from: address(senderId, sender.deviceId), ctx: ctx)
            return (senderId, plaintext)
        }
        // Caminho identificado (testes locais sem certificado de sealed sender):
        // o remetente vem em `senderHint`.
        let senderId = env.senderHint ?? "desconhecido"
        let type = CiphertextMessage.MessageType(rawValue: env.contentHint)
        let plaintext = try decryptInner(type: type, bytes: env.ciphertext,
                                         from: address(senderId, 1), ctx: ctx)
        return (senderId, plaintext)
    }

    private func decryptInner(type: CiphertextMessage.MessageType, bytes: Data,
                              from sender: ProtocolAddress, ctx: StoreContext) throws -> Data {
        if type == .preKey {
            let msg = try PreKeySignalMessage(bytes: bytes)
            return try signalDecryptPreKey(message: msg, from: sender,
                                           localAddress: address(localUserId, deviceId),
                                           sessionStore: store.sessionStore,
                                           identityStore: store.identityStore,
                                           preKeyStore: store.preKeyStore,
                                           signedPreKeyStore: store.signedPreKeyStore,
                                           kyberPreKeyStore: store.kyberPreKeyStore, context: ctx)
        } else {
            let msg = try SignalMessage(bytes: bytes)
            return try signalDecrypt(message: msg, from: sender,
                                     to: address(localUserId, deviceId),
                                     sessionStore: store.sessionStore,
                                     identityStore: store.identityStore, context: ctx)
        }
    }

    // MARK: Reposição de one-time pre-keys.

    func replenishPreKeysIfNeeded() async throws {
        let remaining = try await transport.remainingPreKeyCount(for: localUserId, deviceId: deviceId)
        guard remaining < lowWaterMark else { return }
        let ctx = NullContext()
        var newOTPs: [PublicSinglePreKey] = []
        for _ in 0..<refillCount {
            let id = UInt32.random(in: 1...0x7FFFFF)
            let pair = PrivateKey.generate()
            try store.preKeyStore.storePreKey(try PreKeyRecord(id: id, privateKey: pair), id: id, context: ctx)
            newOTPs.append(PublicSinglePreKey(id: id, publicKey: Data(pair.publicKey.serialize())))
        }
        try await transport.replenishPreKeys(newOTPs, for: localUserId)
    }

    // MARK: Safety number (verificação de identidade / troca de chave).

    func safetyNumber(with userId: String, device: UInt32 = 1) throws -> String? {
        let ctx = NullContext()
        let local = try store.identityStore.identityKeyPair(context: ctx).identityKey
        guard let remote = try store.identityStore.identity(for: address(userId, device), context: ctx)
        else { return nil }
        let fp = try NumericFingerprintGenerator(iterations: 5200).create(
            version: 2,
            localIdentifier: Array(localUserId.utf8), localKey: local.publicKey,
            remoteIdentifier: Array(userId.utf8), remoteKey: remote.publicKey)
        return fp.displayable.formatted
    }
}
