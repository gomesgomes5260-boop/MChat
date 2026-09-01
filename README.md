# MChat — App iOS

App iOS que espelha a estrutura do painel web (Vezoa Admin): gestão de clientes,
ativos financeiros multi-moeda (BRL, USD, EUR, GBP), saques, pagamentos,
usuários com roles complexas, convites rastreáveis e chat/ligações de voz com
criptografia ponta-a-ponta (protocolo Signal).

## Como gerar o projeto Xcode

O projeto usa [XcodeGen](https://github.com/yonaskolb/XcodeGen) — o `.xcodeproj`
não é versionado, é gerado a partir do `project.yml`:

```bash
brew install xcodegen
xcodegen generate
open MChat.xcodeproj
```

Dependências (resolvidas via SPM ao abrir o projeto):

- `signalapp/libsignal` (LibSignalClient) — protocolo Signal (E2EE)
- `stasel/WebRTC` — mídia das ligações de voz

## Estrutura

```
MChat/
├── App/                  # Entrada, estado global (sessão + injeção de serviços), navegação raiz
├── Core/
│   ├── Models/           # User, Role/Permission, Invite, Money/Wallet, Withdrawal, Payment, Chat
│   ├── Services/         # Protocolos de serviço + mocks em memória (trocáveis pelo backend)
│   ├── Signal/           # Fachada da LibSignalClient (identidade, sessões, cifra)
│   └── Calls/            # CallManager (WebRTC + CallKit, sinalização via canal Signal)
└── Features/             # Uma pasta por tela: Auth, Dashboard, Clients, Withdrawals,
                          # Payments, Users, Invites, Chat
MChatTests/               # Testes de RBAC e convites
```

## RBAC — roles e permissões

O controle de acesso é **baseado em permissões**, não em roles diretamente:

- Cada `Role` mapeia para um conjunto de `Permission` (`Role.permissions`).
- Um usuário pode ter **várias roles**; as permissões efetivas são a **união**.
- UI e serviços sempre checam `user.can(.permissao)` — nunca "é admin?".
  Isso permite criar/ajustar roles sem tocar nas telas.
- Usuário suspenso ou pendente de aprovação perde todo o acesso (`can` retorna
  `false` fora do status `active`).

| Role | Acesso |
|---|---|
| Super Admin | Tudo, incluindo revogar convites de terceiros e conceder Super Admin |
| ADM | Dashboard, clientes, usuários, visão de saques/pagamentos, árvore de convites |
| Gestor Financeiro | Saldos e movimentação de ativos (BRL/USD/EUR/GBP) |
| Operador de Saques | Aprovar/cancelar saques |
| Operador de Pagamentos | Processar/cancelar pagamentos |
| Correntista | Carteira própria, chat, ligações |
| Somente Chat | Apenas chat e ligações |

As abas do app (`MainTabView`) aparecem/desaparecem conforme as permissões do
usuário logado.

## Convites

- **Cadastro só por convite**: `register` exige um código válido; o novo usuário
  nasce com `invitedByUserID` + `inviteID`, preservando a árvore de quem
  convidou quem.
- Quem convida escolhe as **roles concedidas** no aceite, limitadas ao que pode
  conceder (`grantableRoles`): usuário comum só concede "Somente Chat"; ADM
  concede roles operacionais; só o Super Admin concede qualquer role.
- **Revogação**: o criador revoga os próprios convites pendentes; o Super Admin
  (`revokeInvites`) revoga qualquer um, com auditoria (`revokedBy`/`revokedAt`).
- Convites expiram em 7 dias e usam código de 8 caracteres sem caracteres
  ambíguos.
- Todo cadastro entra como **pendente de aprovação manual** (espelha o fluxo do
  painel web).

## Signal / Ligações

- `SignalProtocolManager` define o contrato de E2EE (identidade no Keychain,
  pre-key bundles, sessões X3DH + Double Ratchet, safety numbers). A
  implementação concreta com `LibSignalClient` entra quando o backend de troca
  de chaves existir.
- `CallManager` segue o desenho do app Signal: a **sinalização** da ligação
  (offer/answer/ICE) trafega dentro do canal Signal já cifrado; a mídia usa
  WebRTC (DTLS-SRTP) com STUN/TURN próprios; CallKit + PushKit para integração
  nativa.

## Backend

Toda a UI funciona hoje sobre **mocks em memória** (`MockServices.swift`) que
implementam os mesmos protocolos (`AuthServicing`, `InviteServicing`, etc.).
Para ligar no backend real, basta trocar as implementações injetadas em
`AppState.init` — nenhuma tela muda.
