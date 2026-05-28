import SwiftUI
import SwiftData

struct GlobalSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]
    
    let llmService: any LLMProvider
    
    @State private var query: String = ""
    @State private var chatHistory: [ChatMessage] = []
    @State private var isAnalyzing: Bool = false
    @State private var streamingAnswer: String = ""
    
    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: ChatRole
        let content: String
        
        enum ChatRole {
            case user, assistant
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    if chatHistory.isEmpty && query.isEmpty {
                        welcomeState
                    } else {
                        chatSection
                    }
                }
                .padding(Theme.Spacing.xxl)
            }
            
            searchBar
        }
        .background(Theme.Colors.backgroundPrimary)
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Глобальний запит")
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Аналіз усіх ваших нарад (\(allMeetings.count))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.xl)
        .background(Theme.Colors.backgroundSecondary.opacity(0.5))
    }
    
    private var welcomeState: some View {
        VStack(spacing: Theme.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.Colors.accentPrimary.opacity(0.15),
                                Theme.Colors.accentSecondary.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Gradients.accent)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Colors.accentSecondary)
                    .offset(x: 22, y: -22)
            }
            
            VStack(spacing: Theme.Spacing.xs) {
                Text("Запитайте що завгодно")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text("Я можу проаналізувати всі ваші наради і знайти відповіді на будь-яке запитання.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("СПРОБУЙТЕ ЗАПИТАТИ:")
                    .font(Theme.Typography.captionMedium)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .tracking(1)
                    .padding(.leading, 4)
                
                SuggestionCard(text: "Які рішення щодо бюджету було прийнято у квітні?") {
                    query = "Які рішення щодо бюджету було прийнято у квітні?"
                }
                
                SuggestionCard(text: "Хто відповідальний за проєкт X?") {
                    query = "Хто відповідальний за проєкт X?"
                }
                
                SuggestionCard(text: "Створи зведення всіх завдань за тиждень") {
                    query = "Створи зведення всіх завдань за тиждень"
                }
            }
            .frame(maxWidth: 420)
            .padding(.top, Theme.Spacing.md)
        }
        .padding(.top, 40)
    }
    
    private var chatSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ForEach(chatHistory) { message in
                ChatMessageBubbleView(
                    role: message.role == .user ? "user" : "assistant",
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
            }
            
            if !streamingAnswer.isEmpty {
                ChatMessageBubbleView(
                    role: "assistant",
                    content: streamingAnswer,
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
            }
            
            if isAnalyzing && streamingAnswer.isEmpty {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Шукаю інформацію в нарадах...")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(.leading, Theme.Spacing.md)
            }
        }
    }
    
    private var searchBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Theme.Colors.borderSubtle)
            
            HStack(spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(.leading, 4)
                    
                    TextField("Запитайте MeetMind...", text: $query)
                        .textFieldStyle(.plain)
                        .font(Theme.Typography.body)
                        .onSubmit(performQuery)
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 8)
                .background(Theme.Colors.backgroundSecondary.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            query.isEmpty ? Theme.Colors.borderSubtle : Theme.Colors.accentPrimary.opacity(0.5),
                            lineWidth: 1
                        )
                )
                
                Button(action: performQuery) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(query.isEmpty || isAnalyzing ? Theme.Colors.textTertiary : Theme.Colors.accentPrimary)
                }
                .buttonStyle(.plain)
                .disabled(query.isEmpty || isAnalyzing)
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.backgroundPrimary)
            .frame(maxWidth: 800)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.backgroundPrimary)
    }
    
    private func performQuery() {
        guard !query.isEmpty && !isAnalyzing else { return }
        
        let userQuery = query
        chatHistory.append(ChatMessage(role: .user, content: userQuery))
        query = ""
        isAnalyzing = true
        streamingAnswer = ""
        
        Task {
            var contexts: [String] = []
            
            do {
                let fm = FileManager.default
                for meeting in allMeetings {
                    var contextText = ""
                    
                    if let url = meeting.summaryURL,
                       fm.fileExists(atPath: url.path),
                       let summary = try? String(contentsOf: url, encoding: .utf8),
                       !summary.isEmpty {
                        contextText += "Резюме:\n\(summary)\n"
                    }
                    
                    if !meeting.transcriptSegments.isEmpty {
                        let sortedSegments = meeting.transcriptSegments.sorted(by: { $0.startTime < $1.startTime })
                        let transcriptText = sortedSegments.map { segment in
                            "[\(segment.timestampRange)] \(segment.displayName): \(segment.text)"
                        }.joined(separator: "\n")
                        
                        contextText += "Стенограма (фрагмент):\n\(transcriptText.truncated(to: 2500))\n"
                    }
                    
                    if !contextText.isEmpty {
                        contexts.append("Нарада: \(meeting.title) (\(meeting.date.shortDisplayFormatted))\n\(contextText)")
                    }
                }
                let context = contexts.joined(separator: "\n\n---\n\n")
                
                let systemPrompt = """
                Ти — MeetMind AI. Твоє завдання — відповідати на запитання користувача, базуючись на зведеннях його нарад.
                Надавай чіткі, структуровані відповіді. Якщо в контексті немає інформації, так і скажи.
                Ось контекст нарад:
                \(context)
                """
                
                for try await chunk in await llmService.generateResponseStream(prompt: userQuery, systemPrompt: systemPrompt) {
                    await MainActor.run {
                        streamingAnswer += chunk
                    }
                }
                
                await MainActor.run {
                    chatHistory.append(ChatMessage(role: .assistant, content: streamingAnswer))
                    streamingAnswer = ""
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    chatHistory.append(ChatMessage(role: .assistant, content: "Помилка аналізу: \(error.localizedDescription)"))
                    isAnalyzing = false
                }
            }
        }
    }
}

// MARK: - SuggestionCard Component
private struct SuggestionCard: View {
    let text: String
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.accentPrimary)
                
                Text(text)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(isHovered ? Theme.Colors.accentPrimary : Theme.Colors.textTertiary)
                    .padding(.trailing, 2)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isHovered ? Theme.Colors.surfaceHover.opacity(0.8) : Theme.Colors.surfacePrimary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovered ? Theme.Colors.accentPrimary.opacity(0.3) : Theme.Colors.borderSubtle.opacity(0.2), lineWidth: 1)
            )
            .themeShadow(isHovered ? Theme.Shadows.sm : Theme.Shadows.sm)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
