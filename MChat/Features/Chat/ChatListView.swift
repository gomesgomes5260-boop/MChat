import SwiftUI

struct ChatListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var conversations: [Conversation] = []

    var body: some View {
        NavigationStack {
            List {
                if conversations.isEmpty {
                    ContentUnavailableView(
                        "Nenhuma conversa",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("As mensagens são cifradas ponta-a-ponta com o protocolo Signal.")
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(conversations) { conversation in
                    NavigationLink(value: conversation) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(conversation.title).font(.headline)
                                Spacer()
                                if conversation.unreadCount > 0 {
                                    Text("\(conversation.unreadCount)")
                                        .font(.caption2.bold())
                                        .padding(6)
                                        .background(.blue, in: Circle())
                                        .foregroundStyle(.white)
                                }
                            }
                            if let preview = conversation.lastMessagePreview {
                                Text(preview).font(.caption)
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chat")
            .navigationDestination(for: Conversation.self) { conversation in
                ConversationView(conversation: conversation)
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard let me = appState.currentUser else { return }
        conversations = (try? await appState.chat.conversations(for: me.id)) ?? []
    }
}

struct ConversationView: View {
    @EnvironmentObject private var appState: AppState
    let conversation: Conversation

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        MessageBubble(message: message,
                                      isMine: message.senderID == appState.currentUser?.id)
                    }
                }
                .padding()
            }

            HStack {
                TextField("Mensagem cifrada…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(draft.isEmpty)
            }
            .padding()
        }
        .navigationTitle(conversation.title)
        .toolbar {
            if appState.can(.useVoiceCalls) {
                Button {
                    if let peer = conversation.participantIDs.first(where: { $0 != appState.currentUser?.id }) {
                        appState.callManager.startCall(to: peer)
                    }
                } label: {
                    Image(systemName: "phone")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        messages = (try? await appState.chat.messages(in: conversation.id)) ?? []
    }

    private func send() async {
        guard let me = appState.currentUser else { return }
        // No fluxo real o texto passa por SignalProtocolManager.encrypt antes do envio.
        if let message = try? await appState.chat.send(.text(draft), to: conversation.id, from: me.id) {
            messages.append(message)
            draft = ""
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer() }
            Group {
                switch message.content {
                case .text(let text):
                    Text(text)
                case .attachment(let fileName, _):
                    Label(fileName, systemImage: "paperclip")
                case .callEvent(let event):
                    Label(event.outcome == .missed ? "Ligação perdida" : "Ligação",
                          systemImage: "phone")
                }
            }
            .padding(10)
            .background(isMine ? Color.blue.opacity(0.85) : Color.gray.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(isMine ? .white : .primary)
            if !isMine { Spacer() }
        }
    }
}
