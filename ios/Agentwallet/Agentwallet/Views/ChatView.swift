//
//  ChatView.swift
//  Agentwallet
//

import SwiftUI

struct ChatView: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            if viewModel.isLoading {
                                HStack {
                                    ProgressView()
                                    Text("Agent is thinking…")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .id("loading")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) {
                        withAnimation {
                            proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.isLoading) {
                        if viewModel.isLoading {
                            withAnimation { proxy.scrollTo("loading", anchor: .bottom) }
                        }
                    }
                }

                Divider()

                HStack {
                    TextField("Ask the agent to buy something…", text: $viewModel.draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .onSubmit(sendMessage)
                    Button("Send", action: sendMessage)
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canSend)
                }
                .padding()
            }
            .navigationTitle("Chat")
        }
    }

    private func sendMessage() {
        Task { await viewModel.send() }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .padding(10)
                .background(background, in: .rect(cornerRadius: 14))
                .foregroundStyle(message.role == .user ? .white : .primary)
            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private var background: Color {
        switch message.role {
        case .user: .accentColor
        case .agent: Color(.secondarySystemBackground)
        case .error: .red.opacity(0.2)
        }
    }
}

#Preview {
    ChatView()
        .environment(ChatViewModel())
}
