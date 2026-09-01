import Foundation
import LibSignalClient

/// Implementações dos protocolos de store da LibSignalClient sobre um
/// `SignalKeyValueStore` (no app, cifrado em disco; em teste, em memória).
///
/// Chaves de identidade e sessões vivem só aqui — nunca são enviadas ao
/// servidor. Ao servidor vão apenas as PARTES PÚBLICAS (pre-key bundles),
/// publicadas por `SignalProtocolManager`.
final class MChatProtocolStore {
    let kv: SignalKeyValueStore
    let identityStore: MChatIdentityStore
    let sessionStore: MChatSessionStore
    let preKeyStore: MChatPreKeyStore
    let signedPreKeyStore: MChatSignedPreKeyStore
    let kyberPreKeyStore: MChatKyberPreKeyStore

    init(kv: SignalKeyValueStore) throws {
        self.kv = kv
        self.identityStore = try MChatIdentityStore(kv: kv)
        self.sessionStore = MChatSessionStore(kv: kv)
        self.preKeyStore = MChatPreKeyStore(kv: kv)
        self.signedPreKeyStore = MChatSignedPreKeyStore(kv: kv)
        self.kyberPreKeyStore = MChatKyberPreKeyStore(kv: kv)
    }
}

// MARK: - Identidade

final class MChatIdentityStore: IdentityKeyStore {
    private let kv: SignalKeyValueStore
    private let identityKey: IdentityKeyPair
    private let registrationId: UInt32

    init(kv: SignalKeyValueStore) throws {
        self.kv = kv
        if let raw = try kv.data(forKey: "identity_key") {
            self.identityKey = try IdentityKeyPair(bytes: raw)
        } else {
            let pair = IdentityKeyPair.generate()
            try kv.set(Data(pair.serialize()), forKey: "identity_key")
            self.identityKey = pair
        }
        if let raw = try kv.data(forKey: "registration_id"),
           let value = UInt32(data: raw) {
            self.registrationId = value
        } else {
            let value = UInt32.random(in: 1...16380)
            try kv.set(value.dataRepresentation, forKey: "registration_id")
            self.registrationId = value
        }
    }

    func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair { identityKey }
    func localRegistrationId(context: StoreContext) throws -> UInt32 { registrationId }

    func saveIdentity(_ identity: IdentityKey, for address: ProtocolAddress,
                      context: StoreContext) throws -> IdentityChange {
        let key = "identity:\(address.name).\(address.deviceId)"
        let previous = try kv.data(forKey: key)
        let serialized = Data(identity.serialize())
        try kv.set(serialized, forKey: key)
        // Troca de chave conhecida → sinaliza para a UI alertar o usuário.
        return (previous != nil && previous != serialized) ? .replacedExisting : .newOrUnchanged
    }

    func isTrustedIdentity(_ identity: IdentityKey, for address: ProtocolAddress,
                           direction: Direction, context: StoreContext) throws -> Bool {
        let key = "identity:\(address.name).\(address.deviceId)"
        guard let known = try kv.data(forKey: key) else { return true } // TOFU
        return known == Data(identity.serialize())
    }

    func identity(for address: ProtocolAddress, context: StoreContext) throws -> IdentityKey? {
        guard let raw = try kv.data(forKey: "identity:\(address.name).\(address.deviceId)") else { return nil }
        return try IdentityKey(bytes: raw)
    }
}

// MARK: - Sessões

final class MChatSessionStore: SessionStore {
    private let kv: SignalKeyValueStore
    init(kv: SignalKeyValueStore) { self.kv = kv }

    private func key(_ a: ProtocolAddress) -> String { "session:\(a.name).\(a.deviceId)" }

    func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SessionRecord? {
        guard let raw = try kv.data(forKey: key(address)) else { return nil }
        return try SessionRecord(bytes: raw)
    }

    func loadExistingSessions(for addresses: [ProtocolAddress], context: StoreContext) throws -> [SessionRecord] {
        try addresses.map { addr in
            guard let s = try loadSession(for: addr, context: context) else {
                throw SignalError.sessionNotFound("nenhuma sessão para \(addr)")
            }
            return s
        }
    }

    func storeSession(_ record: SessionRecord, for address: ProtocolAddress, context: StoreContext) throws {
        try kv.set(Data(record.serialize()), forKey: key(address))
    }
}

// MARK: - Pré-chaves (one-time)

final class MChatPreKeyStore: PreKeyStore {
    private let kv: SignalKeyValueStore
    init(kv: SignalKeyValueStore) { self.kv = kv }

    func loadPreKey(id: UInt32, context: StoreContext) throws -> PreKeyRecord {
        guard let raw = try kv.data(forKey: "prekey:\(id)") else {
            throw SignalError.invalidKeyIdentifier("pre-key \(id) ausente")
        }
        return try PreKeyRecord(bytes: raw)
    }
    func storePreKey(_ record: PreKeyRecord, id: UInt32, context: StoreContext) throws {
        try kv.set(Data(record.serialize()), forKey: "prekey:\(id)")
    }
    func removePreKey(id: UInt32, context: StoreContext) throws {
        try kv.removeValue(forKey: "prekey:\(id)")
    }
}

// MARK: - Signed pre-key

final class MChatSignedPreKeyStore: SignedPreKeyStore {
    private let kv: SignalKeyValueStore
    init(kv: SignalKeyValueStore) { self.kv = kv }

    func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> SignedPreKeyRecord {
        guard let raw = try kv.data(forKey: "signed_prekey:\(id)") else {
            throw SignalError.invalidKeyIdentifier("signed pre-key \(id) ausente")
        }
        return try SignedPreKeyRecord(bytes: raw)
    }
    func storeSignedPreKey(_ record: SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
        try kv.set(Data(record.serialize()), forKey: "signed_prekey:\(id)")
    }
}

// MARK: - Kyber pre-key (PQXDH)

final class MChatKyberPreKeyStore: KyberPreKeyStore {
    private let kv: SignalKeyValueStore
    init(kv: SignalKeyValueStore) { self.kv = kv }

    func loadKyberPreKey(id: UInt32, context: StoreContext) throws -> KyberPreKeyRecord {
        guard let raw = try kv.data(forKey: "kyber_prekey:\(id)") else {
            throw SignalError.invalidKeyIdentifier("kyber pre-key \(id) ausente")
        }
        return try KyberPreKeyRecord(bytes: raw)
    }
    func storeKyberPreKey(_ record: KyberPreKeyRecord, id: UInt32, context: StoreContext) throws {
        try kv.set(Data(record.serialize()), forKey: "kyber_prekey:\(id)")
    }
    func markKyberPreKeyUsed(id: UInt32, signedPreKeyId: UInt32, baseKey: PublicKey,
                             context: StoreContext) throws {
        // one-time kyber pre-keys seriam removidas aqui; mantemos as "last resort".
    }
}

// MARK: - Helpers

private extension UInt32 {
    init?(data: Data) {
        guard data.count == 4 else { return nil }
        self = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }
    var dataRepresentation: Data { withUnsafeBytes(of: self) { Data($0) } }
}
