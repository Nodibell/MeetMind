//
//  MeetingChatView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 11.05.2026.
//

import SwiftUI

struct MeetingChatView: View {
    let messages: [LLMService.ChatMessage]
    let streamingResponse: String
    let isChatting: Bool
    
    var onSendMessage: ((String) -> Void)?
    var onCancel: (() -> Void)?
    
    @State private var inputText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        if messages.isEmpty {
                            emptyState
                        } else {
                            ForEach(messages) { message in
                                ChatMessageRow(message: message)
                            }
                            
                            if isChatting && !streamingResponse.isEmpty {
                                ChatMessageRow(
                                    message: .init(role: "assistant", content: ""),
                                    streamingContent: streamingResponse
                                )
                                .id("streaming")
                            } else if isChatting {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                                    .id("loading")
                            }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: streamingResponse) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }
            
            Divider()
                .background(Theme.Colors.borderSubtle)
            
            // Input
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Задайте питання по транскрипту...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.backgroundPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.Colors.borderSubtle, lineWidth: 1)
                    )
                    .onSubmit {
                        sendMessage()
                    }
                
                if isChatting {
                    Button(action: {
                        onCancel?()
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.Colors.error)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        sendMessage()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(inputText.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.accentPrimary)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundSecondary.opacity(0.3))
        }
    }
    
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSendMessage?(inputText)
        inputText = ""
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if isChatting {
            withAnimation {
                proxy.scrollTo(streamingResponse.isEmpty ? "loading" : "streaming", anchor: .bottom)
            }
        } else if let last = messages.last {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.textTertiary)
            
            Text("Задайте питання щодо наради")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }
}

private struct ChatMessageRow: View {
    let message: LLMService.ChatMessage
    var streamingContent: String? = nil
    
    private var isUser: Bool {
        message.role == "user"
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            if isUser {
                Spacer(minLength: 40)
            } else {
                Image(systemName: "brain")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Theme.Gradients.accent)
                    .clipShape(Circle())
            }
            
            VStack(alignment: isUser ? .trailing : .leading) {
                if let streamingContent {
                    TypewriterTextView(fullText: streamingContent, isStreaming: true, delayMilliseconds: 10)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .textSelection(.enabled)
                } else if isUser {
                    Text(message.content)
                        .font(Theme.Typography.body)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                } else {
                    MarkdownRendererView(markdown: message.content)
                }
            }
            .padding(isUser ? Theme.Spacing.sm : 0)
            .background(isUser ? Theme.Colors.accentPrimary : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            if !isUser {
                Spacer(minLength: 40)
            }
        }
    }
}

#Preview {
    MeetingChatView(
        messages: [
            .init(role: "user", content: "Які були ключові рішення?"),
            .init(role: "assistant", content: "Вирішили перейти на SwiftUI.")
        ],
        streamingResponse: "",
        isChatting: false
    )
    .frame(width: 400, height: 500)
}
