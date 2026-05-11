import SwiftUI

/// Renders markdown string with proper block spacing and styling
struct MarkdownRendererView: View {
    let markdown: String
    
    var body: some View {
        if markdown.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach(parseBlocks(markdown), id: \.id) { block in
                        renderBlock(block)
                    }
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Parser
    
    private struct MarkdownBlock: Identifiable {
        let id = UUID()
        let type: BlockType
        let content: String
        
        enum BlockType {
            case header(level: Int)
            case paragraph
            case listItem
        }
    }
    
    private func parseBlocks(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            if trimmed.hasPrefix("### ") {
                blocks.append(MarkdownBlock(type: .header(level: 3), content: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                blocks.append(MarkdownBlock(type: .header(level: 2), content: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                blocks.append(MarkdownBlock(type: .header(level: 1), content: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(MarkdownBlock(type: .listItem, content: String(trimmed.dropFirst(2))))
            } else {
                // If the last block was a paragraph, maybe append? 
                // For simplicity, let's treat each non-empty line as a block
                blocks.append(MarkdownBlock(type: .paragraph, content: trimmed))
            }
        }
        
        return blocks
    }
    
    // MARK: - Renderer
    
    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block.type {
        case .header(let level):
            Text(block.content)
                .font(headerFont(for: level))
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.accentPrimary)
                .padding(.top, Theme.Spacing.sm)
                .textSelection(.enabled)
            
        case .paragraph:
            Text(parseInlineMarkdown(block.content))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineSpacing(4)
                .textSelection(.enabled)
            
        case .listItem:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .foregroundStyle(Theme.Colors.accentPrimary)
                Text(parseInlineMarkdown(block.content))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .textSelection(.enabled)
            }
            .padding(.leading, 4)
        }
    }
    
    private func headerFont(for level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title3
        default: return .headline
        }
    }
    
    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text, options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            ))
        } catch {
            return AttributedString(text)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.textTertiary)
            
            Text("Немає контенту")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Streaming markdown view that shows text being generated token by token
struct StreamingMarkdownView: View {
    let text: String
    let isStreaming: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                // For streaming, we use simple text to avoid flickering during parsing.
                // We use TypewriterTextView to smooth out the large token chunks from Ollama.
                TypewriterTextView(fullText: text, isStreaming: isStreaming, delayMilliseconds: 10)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textSelection(.enabled)
                
                if isStreaming {
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(Theme.Colors.accentPrimary)
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    VStack {
        MarkdownRendererView(markdown: """
        ## Резюме
        - Обговорили архітектуру проєкту
        - Прийняли рішення щодо технологій
        
        ## Завдання
        - [ ] Створити прототип (Олексій)
        - [ ] Підготувати документацію (Марія)
        
        ## Рішення
        - Використовувати SwiftUI для UI
        - Ollama для локального LLM
        """)
        .frame(height: 300)
    }
    .background(Theme.Colors.backgroundPrimary)
}
