//
//  LLMService.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation

/// Local LLM integration via Ollama REST API
actor LLMService {
    
    // MARK: - State
    enum ServiceState: Sendable, Equatable {
        case idle
        case checking
        case available(models: [String])
        case generating
        case unavailable(reason: String)
    }
    
    private(set) var state: ServiceState = .idle
    private var lastHealthCheckDate: Date?
    private let healthCacheDuration: TimeInterval = 60 // seconds
    
    // MARK: - Callbacks
    var onStateChanged: (@Sendable (ServiceState) -> Void)?
    var onTokenReceived: (@Sendable (String) -> Void)?
    
    func setOnStateChanged(_ callback: (@Sendable (ServiceState) -> Void)?) {
        self.onStateChanged = callback
    }
    
    func setOnTokenReceived(_ callback: (@Sendable (String) -> Void)?) {
        self.onTokenReceived = callback
    }
    
    // MARK: - API Models
    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let options: Options?
        
        struct Options: Encodable {
            let temperature: Double?
            let num_predict: Int?
            let top_p: Double?
        }
    }
    
    struct ChatMessage: Codable, Identifiable, Equatable {
        var id = UUID()
        let role: String
        let content: String
        
        enum CodingKeys: String, CodingKey {
            case role, content
        }
    }
    
    private struct ChatStreamResponse: Decodable {
        let message: ResponseMessage?
        let done: Bool
        
        struct ResponseMessage: Decodable {
            let role: String
            let content: String
        }
    }
    
    private struct TagsResponse: Decodable {
        let models: [ModelInfo]
        
        struct ModelInfo: Decodable {
            let name: String
            let size: Int64?
            let digest: String?
        }
    }
    
    // MARK: - Health Check
    
    /// Check if Ollama is running and list available models
    func checkHealth() async -> Bool {
        // Return cached result if still fresh
        if let lastCheck = lastHealthCheckDate,
           Date().timeIntervalSince(lastCheck) < healthCacheDuration,
           case .available = state {
            return true
        }

        updateState(.checking)
        
        let endpoint = AppSettings.shared.ollamaEndpoint
        guard let url = URL(string: "\(endpoint)\(Constants.ollamaHealthPath)") else {
            updateState(.unavailable(reason: "Невірна URL-адреса Ollama"))
            return false
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            AppLogger.debug("Отримано відповідь від Ollama")
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                updateState(.unavailable(reason: "Ollama не відповідає (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))"))
                return false
            }
            
            let tagsResponse = try JSONDecoder().decode(TagsResponse.self, from: data)
            let modelNames = tagsResponse.models.map(\.name)

            lastHealthCheckDate = Date()
            updateState(.available(models: modelNames))
            return true
        } catch let error as URLError where error.code == .cannotConnectToHost {
            updateState(.unavailable(reason: "Ollama не запущено. Виконайте 'ollama serve' у терміналі."))
            return false
        } catch {
            updateState(.unavailable(reason: "Помилка з'єднання: \(error.localizedDescription)"))
            return false
        }
    }
    
    // MARK: - Summary Generation
    
    /// Generate meeting summary from transcript text
    func generateSummary(transcript: String, targetLanguage: String? = nil) async throws -> String {
        AppLogger.info("Запит на генерацію резюме (довжина: \(transcript.count) симв., мова: \(targetLanguage ?? "auto"))")
        let model = AppSettings.shared.ollamaModel
        let endpoint = AppSettings.shared.ollamaEndpoint
        
        // Check if Ollama is available
        let isAvailable = await checkHealth()
        guard isAvailable else {
            throw LLMError.ollamaNotRunning
        }
        
        // Check if model is available
        if case .available(let models) = state {
            if !models.contains(where: { $0.hasPrefix(model.components(separatedBy: ":").first ?? model) }) {
                throw LLMError.modelNotFound(model)
            }
        }
        
        // Handle long transcripts with chunking
        if transcript.count > Constants.maxTokensPerChunk * 4 {
            return try await generateChunkedSummary(transcript: transcript, model: model, endpoint: endpoint, targetLanguage: targetLanguage)
        }
        
        return try await generateSingleSummary(transcript: transcript, model: model, endpoint: endpoint, targetLanguage: targetLanguage)
    }
    
    // MARK: - Single Summary
    
    private func generateSingleSummary(transcript: String, model: String, endpoint: String, targetLanguage: String?) async throws -> String {
        let systemPrompt = Self.buildSystemPrompt(targetLanguage: targetLanguage)
        let userPrompt = Self.buildUserPrompt(transcript: transcript)
        
        return try await sendChatRequest(
            model: model,
            endpoint: endpoint,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt)
            ]
        )
    }
    
    // MARK: - Q&A, Translation, and Title Generation
    
    /// Generate a short, relevant title for the meeting based on the transcript
    func generateTitle(transcript: String) async throws -> String {
        AppLogger.info("Запит на генерацію назви наради")
        let model = AppSettings.shared.ollamaModel
        let endpoint = AppSettings.shared.ollamaEndpoint
        
        let prompt = """
        Напиши КОРОТКУ, інформативну назву для цієї наради на основі транскрипту (максимум 5-6 слів).
        Не використовуй лапки, крапку в кінці, або слова "Назва:". Тільки саму назву.
        Відповідай мовою транскрипту.
        
        Транскрипт:
        \(String(transcript.prefix(3000))) // Use first 3000 chars to save time
        """
        
        let result = try await sendChatRequest(
            model: model,
            endpoint: endpoint,
            messages: [
                ChatMessage(role: "system", content: "Ти асистент, що генерує короткі та влучні назви."),
                ChatMessage(role: "user", content: prompt)
            ]
        )
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
    }
    
    /// Answer a user question based on the transcript
    func answerQuestion(transcript: String, question: String, history: [ChatMessage] = []) async throws -> String {
        AppLogger.info("Запит на відповідь на питання")
        let model = AppSettings.shared.ollamaModel
        let endpoint = AppSettings.shared.ollamaEndpoint
        
        let systemPrompt = """
        Ти — асистент для аналізу нарад. Відповідай на питання користувача базуючись ТІЛЬКИ на наданому транскрипті.
        Якщо відповіді немає в транскрипті, так і скажи.
        
        ТРАНСКРИПТ:
        \(transcript)
        """
        
        var messages: [ChatMessage] = [ChatMessage(role: "system", content: systemPrompt)]
        messages.append(contentsOf: history)
        messages.append(ChatMessage(role: "user", content: question))
        
        return try await sendChatRequest(
            model: model,
            endpoint: endpoint,
            messages: messages
        )
    }
    
    /// Translate transcript or summary
    func translateText(text: String, to languageName: String) async throws -> String {
        AppLogger.info("Запит на переклад тексту на \(languageName)")
        let model = AppSettings.shared.ollamaModel
        let endpoint = AppSettings.shared.ollamaEndpoint
        
        let prompt = """
        Переклади наступний текст на таку мову: \(languageName).
        Збережи форматування (маркдаун, списки, абзаци).
        Не додавай від себе жодних коментарів, тільки переклад.
        
        ТЕКСТ:
        \(text)
        """
        
        return try await sendChatRequest(
            model: model,
            endpoint: endpoint,
            messages: [
                ChatMessage(role: "system", content: "Ти професійний перекладач. Тільки перекладай текст, без додаткових коментарів."),
                ChatMessage(role: "user", content: prompt)
            ]
        )
    }
    
    // MARK: - Chunked Summary (Long Meetings)
    
    private func generateChunkedSummary(transcript: String, model: String, endpoint: String, targetLanguage: String?) async throws -> String {
        AppLogger.info("Транскрипт завеликий, розбиваємо на частини...")
        
        let words = transcript.components(separatedBy: .whitespacesAndNewlines)
        let wordsPerChunk = Constants.maxTokensPerChunk * 2
        var chunks: [String] = []
        
        for i in stride(from: 0, to: words.count, by: wordsPerChunk) {
            let endIndex = min(i + wordsPerChunk, words.count)
            let chunk = words[i..<endIndex].joined(separator: " ")
            chunks.append(chunk)
        }
        
        var chunkSummaries: [String] = []
        
        for (index, chunk) in chunks.enumerated() {
            AppLogger.info("Генерація резюме для частини \(index + 1)/\(chunks.count)")
            let chunkPrompt = """
            Це частина \(index + 1) з \(chunks.count) великої наради.
            Зроби коротке резюме цієї частини. Виділи тільки ключові моменти.
            
            ТРАНСКРИПТ:
            \(chunk)
            """
            
            let chunkSummary = try await sendChatRequest(
                model: model,
                endpoint: endpoint,
                messages: [
                    ChatMessage(role: "system", content: "Ти асистент, який робить вижимку тексту. Пиши коротко."),
                    ChatMessage(role: "user", content: chunkPrompt)
                ]
            )
            chunkSummaries.append(chunkSummary)
        }
        
        // Merge summaries
        let mergePrompt = """
        Об'єднай наступні часткові резюме наради в одне цілісне резюме.
        Видали дублікати. Збережи формат відповіді (Markdown).
        
        Часткові резюме:
        \(chunkSummaries.joined(separator: "\n\n---\n\n"))
        """
        
        return try await sendChatRequest(
            model: model,
            endpoint: endpoint,
            messages: [
                ChatMessage(role: "system", content: Self.buildSystemPrompt(targetLanguage: targetLanguage)),
                ChatMessage(role: "user", content: mergePrompt)
            ]
        )
    }
    
    // MARK: - Chat Request with Streaming
    
    private func sendChatRequest(model: String, endpoint: String, messages: [ChatMessage]) async throws -> String {
        guard let url = URL(string: "\(endpoint)\(Constants.ollamaChatPath)") else {
            throw LLMError.invalidEndpoint
        }
        
        let requestBody = ChatRequest(
            model: model,
            messages: messages,
            stream: true,
            options: ChatRequest.Options(
                temperature: 0.3,
                num_predict: 4096,
                top_p: 0.9
            )
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Constants.ollamaRequestTimeout
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        updateState(.generating)
        
        var fullResponse = ""
        
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw LLMError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            
            for try await line in bytes.lines {
                guard let data = line.data(using: .utf8) else { continue }
                
                do {
                    let streamResponse = try JSONDecoder().decode(ChatStreamResponse.self, from: data)
                    
                    if let content = streamResponse.message?.content {
                        fullResponse += content
                        onTokenReceived?(content)
                    }
                    
                    if streamResponse.done {
                        break
                    }
                } catch {
                    // Skip malformed lines
                    continue
                }
            }
            
            updateState(.idle)
            return fullResponse
            
        } catch let error as LLMError {
            updateState(.unavailable(reason: error.localizedDescription))
            throw error
        } catch {
            updateState(.unavailable(reason: error.localizedDescription))
            throw LLMError.requestFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Prompt Templates
    
    private static func buildSystemPrompt(targetLanguage: String?) -> String {
        let languageInstruction: String
        if let targetLanguage, targetLanguage != "auto" {
            languageInstruction = "Відповідай мовою з кодом '\(targetLanguage)' (наприклад: 'uk' - українська, 'en' - англійська). Це ОДНОЗНАЧНА ВИМОГА."
        } else {
            languageInstruction = "Відповідай ТІЄЮ Ж МОВОЮ, якою написано більшу частину транскрипту (за замовчуванням — українською)."
        }
        
        let customPrompt = AppSettings.shared.customSummaryPrompt
        let customInstruction = customPrompt.isEmpty ? "" : "\nДОДАТКОВІ ІНСТРУКЦІЇ ВІД КОРИСТУВАЧА:\n\(customPrompt)\n"
        
        return """
        Ти — професійний асистент для аналізу нарад. Аналізуй транскрипти нарад та створюй структуровані резюме.
        
        ПРАВИЛА:
        1. \(languageInstruction)
        2. НЕ вигадуй інформацію — витягуй ТІЛЬКИ те, що є в транскрипті.
        3. Якщо в транскрипті змішані мови — збережи оригінальну мову кожної цитати, але загальне резюме пиши цільовою мовою.
        4. Будь конкретним — уникай загальних фраз і води.
        5. Форматуй відповідь у Markdown (використовуй заголовки, списки, жирний шрифт).
        \(customInstruction)
        """
    }
    
    private static func buildUserPrompt(transcript: String) -> String {
        """
        Проаналізуй наступний транскрипт наради та створи структуроване резюме.
        
        Формат відповіді (Markdown):
        
        ## Резюме
        - 5–7 ключових тезів
        
        ## Завдання
        - [ ] Завдання (відповідальна особа, якщо згадується)
        
        ## Рішення
        - Ключові рішення, прийняті під час наради
        
        ## Відкриті питання
        - Невирішені або відкладені теми
        
        ## Ризики / Незрозумілі моменти
        - Будь-що неоднозначне, суперечливе або ризиковане
        
        ---
        
        Транскрипт:
        \(transcript)
        """
    }
    
    // MARK: - Helpers
    
    private func updateState(_ newState: ServiceState) {
        state = newState
        onStateChanged?(newState)
    }
}

// MARK: - Errors
enum LLMError: LocalizedError, Sendable {
    case ollamaNotRunning
    case modelNotFound(String)
    case invalidEndpoint
    case requestFailed(String)
    case emptyResponse
    
    var errorDescription: String? {
        switch self {
        case .ollamaNotRunning:
            return "Ollama не запущено. Відкрийте термінал та виконайте 'ollama serve'."
        case .modelNotFound(let model):
            return "Модель '\(model)' не знайдено. Виконайте 'ollama pull \(model)' у терміналі."
        case .invalidEndpoint:
            return "Невірна адреса Ollama API."
        case .requestFailed(let detail):
            return "Помилка запиту до LLM: \(detail)"
        case .emptyResponse:
            return "LLM повернув порожню відповідь."
        }
    }
}
