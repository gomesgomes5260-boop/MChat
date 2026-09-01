import Foundation
// import WebRTC  // habilite após `xcodegen generate` resolver o pacote
// import CallKit

/// Gerencia ligações de voz.
///
/// Arquitetura alvo (mesmo desenho do app Signal):
///  - Sinalização (offer/answer/ICE) trafega DENTRO do canal Signal já
///    cifrado, via `SignalProtocolManager` — o servidor nunca vê SDP em claro.
///  - Mídia via WebRTC com SRTP (DTLS-SRTP), servidores STUN/TURN próprios.
///  - CallKit para integração nativa (tela de chamada, histórico, áudio em
///    background) e PushKit/VoIP push para chamadas recebidas.
@MainActor
final class CallManager: ObservableObject {
    enum CallState: Equatable {
        case idle
        case outgoing(to: UUID)
        case incoming(from: UUID)
        case connected(peer: UUID, since: Date)
    }

    @Published private(set) var state: CallState = .idle

    func startCall(to userID: UUID) {
        // TODO: criar RTCPeerConnection, gerar offer, cifrar via Signal e enviar.
        state = .outgoing(to: userID)
    }

    func acceptIncomingCall(from userID: UUID) {
        state = .connected(peer: userID, since: Date())
    }

    func endCall() {
        state = .idle
    }
}
