import SwiftUI

// MARK: - Model

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String // "user" | "assistant"
    let text: String
    var isLocal: Bool = false
}

@MainActor
final class ChatPanelModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isSending = false
    @Published var errorText: String?

    private let endpoint = URL(string: "http://localhost:2999/v1/messages")!
    private static let apiModel = "claude-haiku-20241022"

    func send(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        isSending = true
        errorText = nil
        messages.append(ChatMessage(role: "user", text: trimmed))

        let apiMessages: [[String: String]] = messages.map { ["role": $0.role, "content": $0.text] }
        let body: [String: Any] = [
            "model": Self.apiModel,
            "messages": apiMessages,
            "max_tokens": 1024,
        ]

        do {
            var req = URLRequest(url: endpoint, timeoutInterval: 30)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
                req.setValue(key, forHTTPHeaderField: "x-api-key")
            }
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = (json["content"] as? [[String: Any]])?.first,
               let responseText = content["text"] as? String
            {
                let responseModel = json["model"] as? String ?? ""
                messages.append(ChatMessage(
                    role: "assistant",
                    text: responseText,
                    isLocal: responseModel.hasPrefix("local/")
                ))
            } else {
                errorText = "Unexpected response format"
            }
        } catch {
            errorText = error.localizedDescription
        }

        isSending = false
    }

    func clear() {
        messages.removeAll()
        errorText = nil
    }
}

// MARK: - View

public struct ChatPanelView: View {
    @StateObject private var model = ChatPanelModel()
    @State private var inputText = ""
    var height: Double

    public init(height: Double = 200) {
        self.height = height
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            messageList
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            inputRow
        }
        .frame(maxWidth: .infinity, minHeight: CGFloat(height), maxHeight: CGFloat(height))
        .background(Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("QUICK-CHAT")
                .font(Theme.display(12, weight: .medium))
                .foregroundStyle(Theme.chromeForeground)

            Spacer()

            if model.isSending {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            }

            HoverableIconButton(
                systemName: "trash",
                fontSize: 11,
                size: 24,
                help: "Clear chat"
            ) {
                withAnimation(Theme.chromeTransition) { model.clear() }
            }
            .disabled(model.messages.isEmpty)
            .opacity(model.messages.isEmpty ? 0.3 : 1)
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
    }

    // MARK: Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.messages.isEmpty && model.errorText == nil {
                        emptyHint
                    }
                    ForEach(model.messages) { msg in
                        messageRow(msg).id(msg.id)
                    }
                    if let err = model.errorText {
                        Text(err)
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.activityFailure)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.vertical, 6)
            }
            .onChange(of: model.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: model.isSending) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 40)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 22))
                .foregroundStyle(Theme.chromeMuted.opacity(0.35))
            Text("routes to local model")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.chromeMuted.opacity(0.45))
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
    }

    private func messageRow(_ msg: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(msg.role == "user" ? "YOU" : "AI")
                    .font(Theme.mono(9, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(
                        msg.role == "user"
                            ? Theme.chromeForeground.opacity(0.45)
                            : Theme.gitInsertion.opacity(0.85)
                    )
                if msg.isLocal {
                    Text("LOCAL")
                        .font(Theme.mono(8, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.activityRunning)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.activityRunning.opacity(0.12))
                        )
                }
            }
            .padding(.horizontal, 10)

            Text(msg.text)
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.chromeForeground)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Input

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField("message…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.chromeForeground)
                .lineLimit(1 ... 4)
                .onSubmit { submit() }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(canSend ? Theme.gitInsertion : Theme.chromeMuted.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .padding(.trailing, 8)
            .padding(.bottom, 5)
        }
        .frame(minHeight: 40)
    }

    private var canSend: Bool {
        !model.isSending && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSend else { return }
        let text = inputText
        inputText = ""
        Task { await model.send(text: text) }
    }
}
