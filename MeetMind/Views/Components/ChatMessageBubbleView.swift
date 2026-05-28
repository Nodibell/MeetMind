//
//  ChatMessageBubbleView.swift
//  MeetMind
//
//  Created by Developer on 29.05.2026.
//

import SwiftUI

/// A highly polished, reusable chat bubble view for displaying user and AI messages.
/// Follows Clean Code guidelines, unifying design aesthetics across all chat experiences.
struct ChatMessageBubbleView: View {
    let role: String
    let content: String
    let isStreaming: Bool
    let showCopyButton: Bool
    let avatarContent: AnyView?
    let footerContent: AnyView?
    
    @State private var isHovering = false
    @State private var copySuccess = false
    @State private var webViewHeight: CGFloat = 40
    
    private var isUser: Bool {
        role == "user"
    }
    
    init(
        role: String,
        content: String,
        isStreaming: Bool = false,
        showCopyButton: Bool = true,
        avatarContent: AnyView? = nil,
        footerContent: AnyView? = nil
    ) {
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.showCopyButton = showCopyButton
        self.avatarContent = avatarContent
        self.footerContent = footerContent
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            if isUser {
                Spacer(minLength: 40)
            } else if let avatar = avatarContent {
                avatar
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // Text/Markdown Bubble Content
                VStack(alignment: .leading, spacing: 4) {
                    if isUser {
                        Text(content)
                            .font(Theme.Typography.body)
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                    } else if isStreaming {
                        TypewriterTextView(fullText: content, isStreaming: true, delayMilliseconds: 10)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .textSelection(.enabled)
                    } else {
                        MarkdownWebView(markdown: content, dynamicHeight: $webViewHeight)
                            .frame(height: webViewHeight)
                            .frame(maxWidth: .infinity)
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
                    ChatBubbleShape(isUser: isUser)
                        .stroke(
                            isUser ? Color.clear : Theme.Colors.borderSubtle.opacity(0.3),
                            lineWidth: 1
                        )
                )
                .clipShape(ChatBubbleShape(isUser: isUser))
                
                // Copy Action Button for AI messages
                if !isUser && !content.isEmpty && !isStreaming && showCopyButton {
                    HStack {
                        Spacer()
                        
                        Button(action: copyToClipboard) {
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
                
                // Footer Content (e.g. references / sources citations)
                if let footerContent {
                    footerContent
                }
            }
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
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        withAnimation {
            copySuccess = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation { copySuccess = false }
            }
        }
    }
}

// MARK: - Fluent Builders
extension ChatMessageBubbleView {
    /// Attach a custom avatar view to the chat bubble
    func avatar<V: View>(@ViewBuilder _ content: () -> V) -> ChatMessageBubbleView {
        ChatMessageBubbleView(
            role: self.role,
            content: self.content,
            isStreaming: self.isStreaming,
            showCopyButton: self.showCopyButton,
            avatarContent: AnyView(content()),
            footerContent: self.footerContent
        )
    }
    
    /// Attach a custom footer view (e.g. sources citation list) to the chat bubble
    func footer<V: View>(@ViewBuilder _ content: () -> V) -> ChatMessageBubbleView {
        ChatMessageBubbleView(
            role: self.role,
            content: self.content,
            isStreaming: self.isStreaming,
            showCopyButton: self.showCopyButton,
            avatarContent: self.avatarContent,
            footerContent: AnyView(content())
        )
    }
}
