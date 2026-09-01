# Criptografia ponta-a-ponta (E2EE) do MChat

Implementação sobre **libsignal** (X3DH/PQXDH + Double Ratchet), desenhada
para as garantias abaixo. Escopo v1: conversas **1:1**, **um dispositivo por
conta**.

## Garantias e onde vivem no código

| Requisito | Como é atendido | Arquivo |
|---|---|---|
| Chaves privadas nunca saem do aparelho | Stores do protocolo sobre `SignalKeyValueStore`; no app, backing cifrado + chave-mestra no **Keychain** (`ThisDeviceOnly`, fora de backup/iCloud) | `SignalStores.swift`, `KeychainStore.swift` |
| Servidor só repassa cifrado | Transporte troca apenas `SealedEnvelope` (blob opaco) e bundles de chaves **públicas** | `Transport.swift`, `SignalProtocolManager.swift` |
| Servidor não vê remetente | **Sealed sender**: o remetente é cifrado dentro do envelope; `senderHint` é sempre `nil` em produção | `SignalProtocolManager.encryptAndSend` |
| Histórico só local, cifrado | `LocalMessageStore` sela cada registro com AES-GCM (chave do Keychain); arquivo marcado como **excluído de backup** | `LocalMessageStore.swift` |
| Sem backup em servidor | Nenhum caminho de escrita do histórico para a rede; troca de aparelho **não** migra histórico (v1) | — |
| Push vazio como gatilho | `PushTriggerHandler.handleTrigger()` busca e decifra localmente; `isEmptyTrigger` recusa payload com conteúdo | `PushHandling.swift` |
| Mínimo do art. 15 (MCI) | Servidor guarda só **IP + timestamp de acesso**, retenção 6 meses e descarte automático; **nunca** o par de conversa | `FakeServer.swift` (`accessLog`) |
| Verificação de identidade | Safety number (numeric fingerprint) + `IdentityChange.replacedExisting` para alertar troca de chave | `SignalProtocolManager.safetyNumber`, `SignalStores.saveIdentity` |
| Reposição de pré-chaves | `replenishPreKeysIfNeeded()` repõe one-time pre-keys abaixo do low-water mark | `SignalProtocolManager.swift` |
| Mix network opcional | `MixNetworkTransport` é um **decorator** plugável (jitter + tráfego de cobertura), desligado por padrão | `MixNetworkTransport.swift` |

## O que o servidor tem direito de ver

- Bundles de chaves **públicas** (para iniciar sessões) — não são segredo.
- Filas de `SealedEnvelope` endereçadas ao **destinatário**, **apagadas na
  entrega** (sem histórico no servidor).
- `accessLog`: IP + data/hora de cada acesso (art. 15), e nada mais.

O servidor **não** consegue: ler conteúdo (blob cifrado), saber quem falou
com quem (sealed sender + sem grafo persistido), nem reconstruir histórico
(apagado ao entregar).

## Limitações conscientes (v1)

- **Sem multi-dispositivo e sem grupos** (sender keys ficam para depois).
- **Token APNs** fica com a Apple — inevitável em qualquer app iOS; não
  revela conteúdo.
- **Push silencioso** é best-effort no iOS; produção usa uma **Notification
  Service Extension** chamando `handleTrigger` (o gatilho não carrega texto).
- Sealed sender exige um **trust root / certificado** emitido pelo servidor
  de chaves; no modo de teste sem certificado, usa-se o caminho identificado
  (`senderHint`), que **não** é usado em produção.

## Estado de verificação

- **Camada de privacidade** (transporte, servidor fake, mix network, banco
  local cifrado, push, art. 15): coberta por `E2EEInfraTests` — **não**
  depende da libsignal, roda em qualquer toolchain Swift.
- **Pipeline criptográfico** (registro → sessão → cifra → decifra ponta-a-
  ponta): `SignalPipelineTests`, que **só compila/roda no Xcode** com o
  pacote `signalapp/libsignal` (v0.101.2) resolvido pelo SwiftPM. As
  assinaturas de API foram conferidas contra a v0.101.2, mas a compilação
  final precisa do Xcode (não há toolchain iOS neste ambiente Linux).
