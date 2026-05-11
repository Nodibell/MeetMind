
import SwiftUI
import SwiftData

struct GlobalSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]
    
    let llmService: LLMService
    
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
                Text(String(localized: "Аналіз по всіх ваших нарад \(allMeetings.count)"))
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
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "sparkles.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.accentPrimary)
            
            Text("Запитайте що завгодно")
                .font(Theme.Typography.title3)
            
            Text("Я можу проаналізувати всі ваші наради і знайти відповіді на запитання на кшталт:\n• «Які рішення по бюджету ми приймали в квітні?»\n• «Хто відповідальний за проект X?»\n• «Зроби зведення всіх завдань за тиждень»")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 60)
    }
    
    private var chatSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ForEach(chatHistory) { message in
                ChatBubble(message: message)
            }
            
            if !streamingAnswer.isEmpty {
                ChatBubble(message: ChatMessage(role: .assistant, content: streamingAnswer))
            }
            
            if isAnalyzing && streamingAnswer.isEmpty {
                HStack {
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
            HStack(spacing: Theme.Spacing.md) {
                TextField("Запитайте MeetMind...", text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onSubmit(performQuery)
                
                Button(action: performQuery) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(query.isEmpty || isAnalyzing ? Theme.Colors.textTertiary : Theme.Colors.accentPrimary)
                }
                .buttonStyle(.plain)
                .disabled(query.isEmpty || isAnalyzing)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Colors.backgroundPrimary)
        }
    }
    
    private func performQuery() {
        guard !query.isEmpty && !isAnalyzing else { return }
        
        let userQuery = query
        chatHistory.append(ChatMessage(role: .user, content: userQuery))
        query = ""
        isAnalyzing = true
        streamingAnswer = ""
        
        Task {
            // Build context from all meetings
            var contexts: [String] = []
            for meeting in allMeetings {
                if let path = meeting.summaryPath,
                   let summary = try? String(contentsOfFile: path),
                   !summary.isEmpty {
                    contexts.append("Нарада: \(meeting.title) (\(meeting.date.shortDisplayFormatted))\nЗміст: \(summary)")
                }
            }
            let context = contexts.joined(separator: "\n\n---\n\n")
            
            let systemPrompt = """
            Ти — MeetMind AI. Твоє завдання — відповідати на запитання користувача, базуючись на зведеннях його нарад.
            Надавай чіткі, структуровані відповіді. Якщо в контексті немає інформації, так і скажи.
            Ось контекст нарад:
            \(context)
            """
            
            do {
                for try await chunk in llmService.generateResponseStream(prompt: userQuery, systemPrompt: systemPrompt) {
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

struct ChatBubble: View {
    let message: GlobalSearchView.ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .assistant {
                assistantBubble
                Spacer(minLength: 60)
            } else {
                Spacer(minLength: 60)
                userBubble
            }
        }
    }
    
    private var userBubble: some View {
        Text(message.content)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.accentPrimary)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(Theme.Colors.accentPrimary)
                Text("MeetMind AI")
                    .font(Theme.Typography.caption.bold())
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            MarkdownWebView(markdown: message.content)
                .frame(minHeight: 40)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.Colors.borderSubtle, lineWidth: 1)
        )
    }
}
