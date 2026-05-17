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

/// Custom chat bubble shape with an elegant message tail
struct ChatBubbleShape: Shape {
    let isUser: Bool
    
    func path(in rect: CGRect) -> Path {
        let path = CGMutablePath()
        
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        
        let radius: CGFloat = 16
        
        let topLeftRadius = radius
        let topRightRadius = radius
        let bottomLeftRadius = isUser ? radius : 4
        let bottomRightRadius = isUser ? 4 : radius
        
        path.move(to: CGPoint(x: minX + topLeftRadius, y: minY))
        path.addLine(to: CGPoint(x: maxX - topRightRadius, y: minY))
        path.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: minY + topRightRadius), radius: topRightRadius)
        
        path.addLine(to: CGPoint(x: maxX, y: maxY - bottomRightRadius))
        path.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX - bottomRightRadius, y: maxY), radius: bottomRightRadius)
        
        path.addLine(to: CGPoint(x: minX + bottomLeftRadius, y: maxY))
        path.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX, y: maxY - bottomLeftRadius), radius: bottomLeftRadius)
        
        path.addLine(to: CGPoint(x: minX, y: minY + topLeftRadius))
        path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX + topLeftRadius, y: minY), radius: topLeftRadius)
        
        return Path(path)
    }
}

private struct ChatMessageRow: View {
    let message: LLMService.ChatMessage
    var streamingContent: String? = nil
    
    private var isUser: Bool {
        message.role == "user"
    }
    
    @State private var isHovering = false
    @State private var copySuccess = false
    
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
            
            VStack(alignment: .leading, spacing: 6) {
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
                    Text(.init(message.content))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .textSelection(.enabled)
                }
                
                // Copy Action Button for AI messages
                if !isUser && !message.content.isEmpty && streamingContent == nil {
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                            withAnimation {
                                copySuccess = true
                            }
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                await MainActor.run {
                                    withAnimation { copySuccess = false }
                                }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: copySuccess ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10))
                                Text(copySuccess ? "Скопійовано" : "Копіювати")
                                    .font(Theme.Typography.caption)
                                    .font(.system(size: 9))
                            }
                            .foregroundStyle(copySuccess ? Theme.Colors.accentSecondary : Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.xs)
                            .padding(.vertical, 4)
                            .background(Theme.Colors.backgroundPrimary.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovering ? 1.0 : 0.4)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                isUser ?
                AnyView(Theme.Gradients.accent) :
                AnyView(Theme.Colors.backgroundSecondary.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isUser ? Color.clear : Theme.Colors.borderSubtle.opacity(0.3),
                        lineWidth: 1
                    )
            )
            .clipShape(ChatBubbleShape(isUser: isUser))
            .onHover { hovering in
                withAnimation(Theme.Animation.fast) {
                    isHovering = hovering
                }
            }
            
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
