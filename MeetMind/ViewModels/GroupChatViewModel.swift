//
//  GroupChatViewModel.swift
//  MeetMind
//
//  Created by Developer on 28.05.2026.
//

import Foundation
import SwiftData
import SwiftUI

/// Message model for multi-meeting chat including referenced sources/citations
struct GroupChatMessage: Identifiable, Sendable, Codable {
    var id = UUID()
    let role: String // "user" or "assistant"
    let content: String
    let timestamp: Date
    let sources: [VectorItem]?
    
    init(role: String, content: String, timestamp: Date = Date(), sources: [VectorItem]? = nil) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.sources = sources
    }
}

/// ViewModel coordinating Q&A Chat over a group of meetings using local RAG
@MainActor
@Observable
final class GroupChatViewModel {
    
    // MARK: - State
    var group: MeetingGroup
    var chatMessages: [GroupChatMessage] = []
    var isChatting = false
    var streamingChatResponse = ""
    var isIndexing = false
    var indexingProgress = 0.0
    var indexingStatusText = ""
    var errorMessage: String? = nil
    var activeSession: GroupChatSessionEntity?
    var chatSessions: [GroupChatSessionEntity] = []
    
    // MARK: - Services
    private let llmService: any LLMProvider
    private let ragService: RAGService
    private var modelContext: ModelContext?
    private var chatTask: Task<Void, Never>?
    private var indexingTask: Task<Void, Never>?
    
    // MARK: - Init
    
    init(group: MeetingGroup, llmService: any LLMProvider) {
        self.group = group
        self.llmService = llmService
        self.ragService = RAGService()
    }
    
    init(group: MeetingGroup, llmService: any LLMProvider, ragService: RAGService) {
        self.group = group
        self.llmService = llmService
        self.ragService = ragService
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadSessionsAndMessages()
    }
    
    func loadSessionsAndMessages() {
        guard let context = modelContext else { return }
        
        let sessions = group.chatSessions.sorted(by: { $0.createdAt < $1.createdAt })
        self.chatSessions = sessions
        
        if sessions.isEmpty {
            let defaultSession = GroupChatSessionEntity(title: "Основна розмова")
            defaultSession.group = group
            context.insert(defaultSession)
            
            // Migrate any existing messages directly on the group to the new default session
            let directMessages = group.chatMessages.filter { $0.session == nil }
            for msg in directMessages {
                msg.session = defaultSession
            }
            
            try? context.save()
            self.chatSessions = [defaultSession]
            self.activeSession = defaultSession
        } else {
            if activeSession == nil || !sessions.contains(where: { $0.id == activeSession?.id }) {
                self.activeSession = sessions.last
            }
        }
        
        loadActiveSessionMessages()
    }
    
    func loadActiveSessionMessages() {
        guard let session = activeSession else {
            self.chatMessages = []
            return
        }
        let sorted = session.chatMessages.sorted(by: { $0.timestamp < $1.timestamp })
        self.chatMessages = sorted.map { entity in
            GroupChatMessage(
                role: entity.role,
                content: entity.content,
                timestamp: entity.timestamp,
                sources: entity.sources
            )
        }
    }
    
    func createNewChatSession(title: String = "Нова розмова") {
        guard let context = modelContext else { return }
        
        let newSession = GroupChatSessionEntity(title: title)
        newSession.group = group
        context.insert(newSession)
        try? context.save()
        
        self.chatSessions.append(newSession)
        self.activeSession = newSession
        
        loadActiveSessionMessages()
        
        streamingChatResponse = ""
        errorMessage = nil
    }
    
    func deleteChatSession(_ session: GroupChatSessionEntity) {
        guard let context = modelContext else { return }
        
        let wasActive = (session.id == activeSession?.id)
        
        context.delete(session)
        try? context.save()
        
        self.chatSessions.removeAll(where: { $0.id == session.id })
        
        if wasActive {
            self.activeSession = chatSessions.last
            loadActiveSessionMessages()
        }
    }
    
    func selectChatSession(_ session: GroupChatSessionEntity) {
        self.activeSession = session
        loadActiveSessionMessages()
        
        cancelChat()
        streamingChatResponse = ""
        errorMessage = nil
    }
    
    // MARK: - Indexing
    
    /// Trigger background transcript chunking and embedding generation for all meetings in the group
    func indexAllMeetings() {
        guard let context = modelContext else {
            errorMessage = "Помилка бази даних: відсутній контекст моделей"
            return
        }
        
        let meetings = group.meetings
        guard !meetings.isEmpty else {
            indexingStatusText = "У цій групі ще немає нарад"
            return
        }
        
        indexingTask?.cancel()
        
        isIndexing = true
        indexingProgress = 0.0
        indexingStatusText = "Підготовка до індексації..."
        errorMessage = nil
        
        indexingTask = Task {
            var completedCount = 0
            
            for meeting in meetings {
                guard !Task.isCancelled else { break }
                
                await MainActor.run {
                    self.indexingStatusText = "Індексація: '\(meeting.title)' (\(completedCount + 1)/\(meetings.count))..."
                }
                
                do {
                    // Index single meeting in RAGService
                    try await ragService.indexMeeting(meeting: meeting, modelContext: context)
                    completedCount += 1
                    
                    let progress = Double(completedCount) / Double(meetings.count)
                    await MainActor.run {
                        self.indexingProgress = progress
                    }
                } catch {
                    AppLogger.error("Failed to index meeting '\(meeting.title)': \(error.localizedDescription)")
                    let adapted = self.adaptErrorMessage(error, meetingTitle: meeting.title)
                    await MainActor.run {
                        self.errorMessage = adapted
                    }
                }
            }
            
            await MainActor.run {
                self.isIndexing = false
                self.indexingStatusText = "Індексацію завершено (\(completedCount)/\(meetings.count) нарад)"
            }
        }
    }
    
    // MARK: - Chat Actions
    
    /// Sends a query, retrieves context from RAG, constructs system prompt, and streams LLM response
    func sendChatMessage(_ query: String) async {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else { return }
        guard let context = modelContext else {
            errorMessage = "Помилка бази даних: відсутній контекст моделей"
            return
        }
        
        await MainActor.run {
            guard let active = activeSession else { return }
            let userEntity = GroupChatMessageEntity(role: "user", content: cleanedQuery)
            userEntity.session = active
            userEntity.group = group
            context.insert(userEntity)
            
            if active.title == "Нова розмова" || active.title == "Основна розмова" {
                let trimmedTitle = String(cleanedQuery.prefix(30)) + (cleanedQuery.count > 30 ? "..." : "")
                active.title = trimmedTitle
            }
            try? context.save()
            
            chatMessages.append(GroupChatMessage(role: "user", content: cleanedQuery))
            isChatting = true
            streamingChatResponse = ""
            errorMessage = nil
        }
        
        chatTask?.cancel()
        
        chatTask = Task {
            do {
                // 1. Retrieve RAG context text and sources
                let (contextText, sources) = try await ragService.retrieveContext(
                    query: cleanedQuery,
                    group: group,
                    modelContext: context,
                    topK: 5
                )
                
                guard !Task.isCancelled else { return }
                
                // 2. Build system prompt
                let systemPrompt = """
                Ти — професійний асистент для аналізу нарад. Тобі надано текстовий контекст із репліками з нарад у цій групі.
                Твоє завдання — відповісти на запитання користувача, спираючись ВИКЛЮЧНО на наданий контекст.
                Не додавай інформації від себе, якої немає в контексті.
                Якщо в контексті немає відповіді, прямо так і скажи: "На жаль, у транскриптах нарад цієї групи немає інформації з цього питання."
                Пиши структуровано в Markdown форматі.
                
                КОНТЕКСТ НАРАД:
                \(contextText)
                """
                
                // 3. Setup token streaming callback
                await llmService.setOnTokenReceived { [weak self] token in
                    guard let self else { return }
                    Task { @MainActor in
                        self.streamingChatResponse += token
                    }
                }
                
                // 4. Stream response from LLM
                let stream = await llmService.generateResponseStream(
                    prompt: cleanedQuery,
                    systemPrompt: systemPrompt
                )
                
                var finalResponse = ""
                for try await token in stream {
                    finalResponse += token
                }
                
                await MainActor.run {
                    guard let active = self.activeSession else { return }
                    let assistantEntity = GroupChatMessageEntity(
                        role: "assistant",
                        content: finalResponse.trimmingCharacters(in: .whitespacesAndNewlines),
                        sources: sources
                    )
                    assistantEntity.session = active
                    assistantEntity.group = self.group
                    context.insert(assistantEntity)
                    try? context.save()
                    
                    self.chatMessages.append(
                        GroupChatMessage(
                            role: "assistant",
                            content: finalResponse.trimmingCharacters(in: .whitespacesAndNewlines),
                            sources: sources
                        )
                    )
                    self.streamingChatResponse = ""
                    self.isChatting = false
                }
            } catch {
                await MainActor.run {
                    if !Task.isCancelled {
                        self.errorMessage = "Помилка аналізу: \(error.localizedDescription)"
                    }
                    self.isChatting = false
                }
            }
        }
    }
    
    func cancelChat() {
        chatTask?.cancel()
        chatTask = nil
        isChatting = false
    }
    
    func clearHistory() {
        guard let context = modelContext, let active = activeSession else { return }
        let sortedEntities = active.chatMessages
        for entity in sortedEntities {
            context.delete(entity)
        }
        try? context.save()
        
        chatMessages.removeAll()
        streamingChatResponse = ""
        errorMessage = nil
    }
    
    func cancelAllTasks() {
        chatTask?.cancel()
        chatTask = nil
        indexingTask?.cancel()
        indexingTask = nil
    }
    
    private func adaptErrorMessage(_ error: Error, meetingTitle: String) -> String {
        let desc = error.localizedDescription
        if desc.contains("DeepMLX не підтримує") {
            return desc
        }
        if desc.contains("cannotConnectToHost") || desc.contains("Connection refused") || desc.contains("61") {
            return "Не вдалося з'єднатися з локальним сервером ШІ. Переконайтеся, що Ollama або LM Studio запущено на вашому комп'ютері, та перевірте адресу сервера у налаштуваннях."
        }
        if desc.contains("404") {
            return "Модель ембедингів не знайдена на сервері (HTTP 404). Будь ласка, переконайтеся, що ви завантажили модель (наприклад, виконавши 'ollama pull nomic-embed-text' у Терміналі) та вказали її правильну назву в налаштуваннях ШІ."
        }
        return "Помилка індексації наради «\(meetingTitle)»: \(desc)"
    }
}
