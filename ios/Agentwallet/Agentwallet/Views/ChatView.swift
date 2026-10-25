import SwiftUI

struct ChatView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if !viewModel.catalogItems.isEmpty {
                            ChatSavedItems()
                        }
                        ChatWelcome { isInputFocused = true }
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if viewModel.isLoading {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Spendy is thinking…").font(.subheadline)
                            }
                            .padding(.horizontal, 4)
                            .accessibilityElement(children: .combine)
                        }
                        Color.clear.frame(height: 1).id("chatBottom")
                    }
                    .padding(20)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.messages.count) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("chatBottom", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.isLoading) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("chatBottom", anchor: .bottom)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ChatComposer(isInputFocused: $isInputFocused)
                }
            }
            .background(SpendyHomeStyle.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                SpendyHeader()
            }
            .foregroundStyle(SpendyHomeStyle.ink)
            .tint(SpendyHomeStyle.orange)
            .environment(\.colorScheme, .light)
            .task { await viewModel.refreshWallet() }
        }
    }
}

private struct ChatSavedItems: View {
    @Environment(ChatViewModel.self) private var viewModel
    private let columns = [
        GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top),
        GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Things you want, bought when you ask.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(viewModel.catalogItems) { item in
                        Button {
                            Task { await viewModel.send(suggestion: "Buy the " + item.name) }
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                if let merchant = item.merchant {
                                    Text(merchant)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text(item.name)
                                    .font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.price)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                            .padding(16)
                            .background(.white, in: .rect(cornerRadius: 24))
                            .foregroundStyle(SpendyHomeStyle.ink)
                            .contentShape(.rect(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isLoading)
                        .accessibilityHint("Sends a purchase request to Spendy")
                    }
                }
        }
    }
}

private struct ChatWelcome: View {
    @Environment(ChatViewModel.self) private var viewModel
    let focusComposer: () -> Void

    var body: some View {
        Card {
            HomeIconTile(symbol: "sparkles")
            Text("Hi, I’m Spendy.")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Tell me what you’d like to buy. I’ll check the store and handle the payment.")
                .font(.body)
                .foregroundStyle(.secondary)
            if viewModel.messages.isEmpty {
                VStack(spacing: 12) {
                    ChatPromptButton(title: "What's Spendy?") {
                        Task { await viewModel.send(suggestion: "What's Spendy?") }
                    }
                    .disabled(viewModel.isLoading)
                    ChatPromptButton(title: "Show me my saved items") {
                        Task { await viewModel.send(suggestion: "Show me my saved items") }
                    }
                    .disabled(viewModel.isLoading)
                    ChatPromptButton(title: "Ask anything", action: focusComposer)
                }
            }
            WalletLimitsText()
            Text("Test payments on Base Sepolia. Card purchases use one-time cards; bank balances are simulated.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ChatPromptButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.up.right")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(SpendyHomeStyle.background, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private struct ChatComposer: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var isInputFocused: FocusState<Bool>.Binding

    var body: some View {
        @Bindable var viewModel = viewModel
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
        layout {
            TextField("Ask Spendy…", text: $viewModel.draft, axis: .vertical)
                .font(.body)
                .lineLimit(1...5)
                .focused(isInputFocused)
                .submitLabel(.send)
                .onSubmit(sendMessage)
                .padding(14)
                .background(.white, in: .rect(cornerRadius: 20))
                .accessibilityLabel("Message to Spendy")
            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold))
                    .frame(minWidth: 24, minHeight: 24)
                    .padding(10)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(SpendyHomeStyle.orange)
            .disabled(!viewModel.canSend)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(SpendyHomeStyle.background)
    }

    private func sendMessage() {
        guard viewModel.canSend else { return }
        isInputFocused.wrappedValue = false
        Task { await viewModel.send() }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                if message.role == .user {
                    Spacer(minLength: 12)
                }
                VStack(alignment: .leading, spacing: message.role == .error ? 8 : 12) {
                    ChatAvatarTile(symbol: message.role == .user ? "person.fill" : "sparkles",
                                   isUser: message.role == .user)
                    Text(message.role == .user ? "You" : message.role == .error ? "Unable to complete request" : "Spendy")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(message.role == .agent ? SpendyHomeStyle.purple :
                                         message.role == .user ? Color.white : SpendyHomeStyle.ink)
                    if message.role == .agent {
                        Divider()
                    } else if message.role == .user {
                        Divider()
                            .overlay(Color.white.opacity(0.5))
                    }
                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .padding(18)
                .background(background, in: .rect(cornerRadius: 24))
                .foregroundStyle(message.role == .user ? .white : SpendyHomeStyle.ink)
                if message.role != .user {
                    Spacer(minLength: 12)
                }
            }
            ForEach(message.receipts) { receipt in
                ChatReceiptCard(purchase: receipt)
            }
        }
    }

    private var background: Color {
        switch message.role {
        case .user: SpendyHomeStyle.purple
        case .agent: .white
        case .error: .red.opacity(0.08)
        }
    }
}

private struct ChatAvatarTile: View {
    let symbol: String
    let isUser: Bool
    @ScaledMetric(relativeTo: .caption) private var size = 32
    @ScaledMetric(relativeTo: .caption) private var cornerRadius = 10

    var body: some View {
        Image(systemName: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(SpendyHomeStyle.purple, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.white.opacity(isUser ? 0.2 : 0))
            }
            .accessibilityHidden(true)
    }
}

private struct ChatReceiptCard: View {
    let purchase: Purchase

    var body: some View {
        Card {
            HStack(spacing: 12) {
                HomeIconTile(symbol: "checkmark")
                Text("Purchase receipt").font(.headline)
            }
            Text(purchase.item).font(.title3.weight(.semibold))
            Text(purchase.amount)
                .font(.title2.bold())
                .monospacedDigit()
            Label(purchase.method == "card" ? "One-time card" : purchase.method,
                  systemImage: purchase.method == "x402" ? "bolt.fill" : "creditcard")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ChatView()
        .environment(ChatViewModel())
}

#Preview("Chat — larger text") {
    ChatView()
        .environment(ChatViewModel())
        .environment(\.dynamicTypeSize, .accessibility3)
}
