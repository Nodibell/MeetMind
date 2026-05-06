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
    
    private struct ChatMessage: Encodable {
        let role: String
        let content: String
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
    func generateSummary(transcript: String) async throws -> String {
        AppLogger.info("Запит на генерацію резюме (довжина транскрипту: \(transcript.count) симв.)")
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
            return try await generateChunkedSummary(transcript: transcript, model: model, endpoint: endpoint)
        }
        
        return try await generateSingleSummary(transcript: transcript, model: model, endpoint: endpoint)
    }
    
    // MARK: - Single Summary
    
    private func generateSingleSummary(transcript: String, model: String, endpoint: String) async throws -> String {
        let systemPrompt = Self.buildSystemPrompt()
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
    
    // MARK: - Chunked Summary (Long Meetings)
    
    private func generateChunkedSummary(transcript: String, model: String, endpoint: String) async throws -> String {
        // Split transcript into chunks
        let chunkSize = Constants.maxTokensPerChunk * 3 // rough char estimate
        let chunks = stride(from: 0, to: transcript.count, by: chunkSize).map { startIndex -> String in
            let start = transcript.index(transcript.startIndex, offsetBy: startIndex)
            let end = transcript.index(start, offsetBy: min(chunkSize, transcript.count - startIndex))
            return String(transcript[start..<end])
        }
        
        // Summarize each chunk
        var chunkSummaries: [String] = []
        for (index, chunk) in chunks.enumerated() {
            let prompt = """
            Це частина \(index + 1) з \(chunks.count) транскрипту наради.
            Витягни ключові тези, завдання та рішення з цієї частини.
            
            Транскрипт (частина \(index + 1)):
            \(chunk)
            """
            
            let summary = try await sendChatRequest(
                model: model,
                endpoint: endpoint,
                messages: [
                    ChatMessage(role: "system", content: Self.buildSystemPrompt()),
                    ChatMessage(role: "user", content: prompt)
                ]
            )
            chunkSummaries.append(summary)
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
                ChatMessage(role: "system", content: Self.buildSystemPrompt()),
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
    
    private static func buildSystemPrompt() -> String {
        """
        Ти — асистент для аналізу нарад. Аналізуй транскрипти нарад та створюй структуровані резюме.
        
        ПРАВИЛА:
        1. Відповідай ТІЄЮ Ж МОВОЮ, якою написано транскрипт (за замовчуванням — українською)
        2. НЕ вигадуй інформацію — витягуй ТІЛЬКИ те, що є в транскрипті
        3. Якщо в транскрипті змішані мови — збережи оригінальну мову кожної цитати
        4. Будь конкретним — уникай загальних фраз
        5. Якщо чогось немає в транскрипті — пиши "Не згадувалось"
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
