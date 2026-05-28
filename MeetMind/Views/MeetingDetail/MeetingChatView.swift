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
                                ChatMessageBubbleView(
                                    role: message.role,
                                    content: message.content,
                                    isStreaming: false
                                )
                                .avatar {
                                    Image(systemName: "brain")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(Theme.Gradients.accent)
                                        .clipShape(Circle())
                                }
                                .id(message.id)
                            }
                            
                            if isChatting && !streamingResponse.isEmpty {
                                ChatMessageBubbleView(
                                    role: "assistant",
                                    content: streamingResponse,
                                    isStreaming: true
                                )
                                .avatar {
                                    Image(systemName: "brain")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(Theme.Gradients.accent)
                                        .clipShape(Circle())
                                }
                                .id("streaming")
                            } else if isChatting {
                                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                    Image(systemName: "brain")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(Theme.Gradients.accent)
                                        .clipShape(Circle())
                                    
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .scaleEffect(0.5)
                                            .controlSize(.small)
                                        Text("Аналізую...")
                                            .font(Theme.Typography.caption)
                                            .foregroundStyle(Theme.Colors.textSecondary)
                                    }
                                    .padding(.horizontal, Theme.Spacing.md)
                                    .padding(.vertical, Theme.Spacing.sm)
                                    .background(Theme.Colors.backgroundSecondary.opacity(0.5))
                                    .clipShape(ChatBubbleShape(isUser: false))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Theme.Colors.borderSubtle.opacity(0.3), lineWidth: 1)
                                    )
                                }
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
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(.leading, 4)
                    
                    TextField("Задайте питання щодо наради...", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(Theme.Typography.body)
                        .onSubmit {
                            sendMessage()
                        }
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 8)
                .background(Theme.Colors.backgroundPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            inputText.isEmpty ? Theme.Colors.borderSubtle : Theme.Colors.accentPrimary.opacity(0.5),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
                
                if isChatting {
                    Button(action: {
                        onCancel?()
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.Colors.error)
                    }
                    .buttonStyle(.plain)
                    .help("Зупинити відповідь")
                } else {
                    Button(action: {
                        sendMessage()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(inputText.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.accentPrimary)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty)
                    .help("Надіслати питання")
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundSecondary.opacity(0.4))
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

// ChatBubbleShape struct has been refactored into a shared SwiftUI custom component under Components/


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
