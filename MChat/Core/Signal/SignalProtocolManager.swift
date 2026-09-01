import Foundation
// import LibSignalClient  // habilite após `xcodegen generate` resolver o pacote

/// Fachada sobre a LibSignalClient (biblioteca oficial do Signal).
///
/// Responsabilidades quando integrada ao backend:
///  1. Gerar identidade (IdentityKeyPair) e registrationId no primeiro login,
///     guardando as chaves privadas no Keychain/Secure Enclave.
///  2. Publicar pre-key bundles (signed pre-key + one-time pre-keys) no servidor.
///  3. Estabelecer sessões X3DH com cada participante e cifrar/decifrar
///     mensagens com Double Ratchet.
///  4. Expor verificação de safety numbers (fingerprint) na UI.
///
/// Os métodos abaixo definem o contrato usado pelo ChatService real; a
/// implementação com LibSignalClient entra quando o backend de troca de
/// chaves existir.
final class SignalProtocolManager {
    static let shared = SignalProtocolManager()

    enum SignalError: Error {
        case identityMissing
        case sessionNotEstablished
        case notImplemented
    }

    /// Cria (ou carrega do Keychain) a identidade Signal do usuário local.
    func bootstrapIdentity(for userID: UUID) throws {
        // TODO: IdentityKeyPair.generate() + persistência no Keychain.
        throw SignalError.notImplemented
    }

    /// Cifra o payload para um destinatário com sessão estabelecida.
    func encrypt(_ plaintext: Data, for recipientID: UUID) throws -> Data {
        throw SignalError.notImplemented
    }

    /// Decifra um envelope recebido.
    func decrypt(_ ciphertext: Data, from senderID: UUID) throws -> Data {
        throw SignalError.notImplemented
    }

    /// Safety number para verificação manual entre dois usuários.
    func fingerprint(localUserID: UUID, remoteUserID: UUID) throws -> String {
        throw SignalError.notImplemented
    }
}
