//
//  LLMService.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation

/// Local LLM integration via Ollama REST API
actor LLMService: LLMProvider {
    
    // MARK: - State
    private(set) var state: LLMServiceState = .idle
    private var lastHealthCheckDate: Date?
    private var lastHealthCheckProvider: AppSettings.LLMProvider?
    private var lastHealthCheckEndpoint: String?
    private let healthCacheDuration: TimeInterval = 60 // seconds
    private let deepLLM = DeepLLMService()
    
    // MARK: - Callbacks
    var onStateChanged: (@Sendable (LLMServiceState) -> Void)?
    var onTokenReceived: (@Sendable (String) -> Void)?
    
    func setOnStateChanged(_ callback: (@Sendable (LLMServiceState) -> Void)?) {
        self.onStateChanged = callback
    }
    
    func setOnTokenReceived(_ callback: (@Sendable (String) -> Void)?) {
        self.onTokenReceived = callback
    }
    
    private var autoUnloadTask: Task<Void, Never>?
    
    private func cancelUnloadTask() {
        autoUnloadTask?.cancel()
        autoUnloadTask = nil
    }
    
    private func scheduleAutoUnload() {
        autoUnloadTask?.cancel()
        autoUnloadTask = Task {
            let timeout = await MainActor.run { AppSettings.shared.llmModelUnloadTimeout }
            guard timeout >= 0 else { return } // -1 means never unload
            
            if timeout == 0 {
                await self.unloadModel()
                return
            }
            
            do {
                try await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                await self.unloadModel()
            } catch {
                // Task was cancelled
            }
        }
    }
    
    func unloadModel() async {
        let provider = await MainActor.run { AppSettings.shared.llmProvider }
        let model = await MainActor.run { AppSettings.shared.llmModel }
        let endpoint = await MainActor.run { AppSettings.shared.llmEndpoint }
        
        switch provider {
        case .deepMLX:
            await deepLLM.unload()
            AppLogger.info("DeepMLX model unloaded automatically due to inactivity.")
            
        case .ollama:
            guard let url = Self.apiURL(endpoint: endpoint, provider: .ollama, path: "/api/generate") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10
            
            let payload: [String: Any] = [
                "model": model,
                "keep_alive": 0
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            
            _ = try? await URLSession.shared.data(for: request)
            AppLogger.info("Ollama model '\(model)' unloaded automatically due to inactivity.")
            
        case .lmStudio:
            guard let url = Self.apiURL(endpoint: endpoint, provider: .lmStudio, path: "/api/v1/models/unload") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10
            
            let payload: [String: Any] = [
                "instance_id": model
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            
            _ = try? await URLSession.shared.data(for: request)
            AppLogger.info("LM Studio model '\(model)' unloaded automatically due to inactivity.")
        }
    }
    
    func unloadDeepModel() async {
        await unloadModel()
    }
    
    // MARK: - API Models
    private struct OllamaChatRequest: Encodable {
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
    
    private struct OpenAIChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let temperature: Double?
        let maxTokens: Int?
        let topP: Double?
        
        enum CodingKeys: String, CodingKey {
            case model, messages, stream, temperature
            case maxTokens = "max_tokens"
            case topP = "top_p"
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
    
    // MARK: - OpenAI / LM Studio Models
    
    private struct OpenAITagsResponse: Decodable {
        let data: [ModelInfo]
        
        struct ModelInfo: Decodable {
            let id: String
        }
    }
    
    private struct OpenAIChatStreamResponse: Decodable {
        let choices: [Choice]?
        
        struct Choice: Decodable {
            let delta: Delta?
        }
        
        struct Delta: Decodable {
            let content: String?
        }
    }
    
    // MARK: - Request Helpers
    
    nonisolated static func apiURL(endpoint rawEndpoint: String, provider: AppSettings.LLMProvider, path: String) -> URL? {
        var endpoint = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        while endpoint.hasSuffix("/") {
            endpoint.removeLast()
        }
        
        guard !endpoint.isEmpty else { return nil }
        
        var normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        if provider == .lmStudio,
           endpoint.lowercased().hasSuffix("/v1"),
           normalizedPath.lowercased().hasPrefix("/v1/") {
            normalizedPath = String(normalizedPath.dropFirst(3))
        }
        
        return URL(string: endpoint + normalizedPath)
    }
    
    nonisolated static func isModelAvailable(_ model: String, in availableModels: [String], provider: AppSettings.LLMProvider) -> Bool {
        if provider == .deepMLX {
            return true
        }
        let selected = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return false }
        
        if availableModels.contains(selected) {
            return true
        }
        
        guard provider == .ollama, !selected.contains(":") else {
            return false
        }
        
        return availableModels.contains { available in
            available == "\(selected):latest" || available.hasPrefix("\(selected):")
        }
    }
    
    nonisolated static func modelSelectionWarning(model: String, provider: AppSettings.LLMProvider) -> String? {
        let normalized = model.lowercased()
        
        if normalized.contains("embed")
            || normalized.contains("embedding")
            || normalized.contains("nomic-bert")
            || normalized.contains("bge-")
            || normalized.contains("e5-") {
            return "Це embedding-модель. Для резюме та Q&A оберіть instruct/chat модель."
        }
        
        if provider == .lmStudio,
           normalized.contains("glm4v") || normalized.contains("vision") || normalized.contains("vl") {
            return "Це multimodal/vision модель. Через LM Studio може працювати для тексту, але DeepMLX напряму її не завантажить."
        }
        
        return nil
    }
    
    nonisolated static func encodedChatRequestData(
        provider: AppSettings.LLMProvider,
        model: String,
        messages: [ChatMessage],
        stream: Bool,
        temperature: Double,
        maxTokens: Int,
        topP: Double
    ) throws -> Data {
        let encoder = JSONEncoder()
        
        switch provider {
        case .ollama:
            let request = OllamaChatRequest(
                model: model,
                messages: messages,
                stream: stream,
                options: .init(temperature: temperature, num_predict: maxTokens, top_p: topP)
            )
            return try encoder.encode(request)
        case .lmStudio:
            let request = OpenAIChatRequest(
                model: model,
                messages: messages,
                stream: stream,
                temperature: temperature,
                maxTokens: maxTokens,
                topP: topP
            )
            return try encoder.encode(request)
        case .deepMLX:
            return Data()
        }
    }
    
    // MARK: - Health Check
    
    /// Check if LLM server is running and list available models
    func checkHealth() async -> Bool {
        let provider = await MainActor.run { AppSettings.shared.llmProvider }
        let endpoint = await MainActor.run { AppSettings.shared.llmEndpoint }
        
        if provider == .deepMLX {
            let deepModelPath = await MainActor.run { AppSettings.shared.deepMLXModelPath }
            guard let modelPath = deepModelPath else {
                updateState(.unavailable(reason: "Шлях до моделі MLX не обрано"))
                return false
            }
            
            if let issue = DeepLLMService.modelDirectoryValidationIssue(at: modelPath) {
                updateState(.unavailable(reason: "MLX-папка недійсна: \(issue)"))
                return false
            }
            
            let modelName = modelPath.lastPathComponent
            updateState(.available(models: [modelName]))
            return true
        }
        
        // Return cached result if still fresh
        if let lastCheck = lastHealthCheckDate,
           lastHealthCheckProvider == provider,
           lastHealthCheckEndpoint == endpoint,
           Date().timeIntervalSince(lastCheck) < healthCacheDuration,
           case .available = state {
            return true
        }

        updateState(.checking)
        
        do {
            let modelNames = try await fetchAvailableModels(provider: provider, endpoint: endpoint)
            lastHealthCheckDate = Date()
            lastHealthCheckProvider = provider
            lastHealthCheckEndpoint = endpoint
            updateState(.available(models: modelNames))
            return true
        } catch {
            if provider == .lmStudio {
                let startResult = await LMStudioServerManager.ensureServerRunning(endpoint: endpoint)
                AppLogger.info(startResult.message)
                
                if startResult.isUsable {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    
                    do {
                        let modelNames = try await fetchAvailableModels(provider: provider, endpoint: endpoint)
                        lastHealthCheckDate = Date()
                        lastHealthCheckProvider = provider
                        lastHealthCheckEndpoint = endpoint
                        updateState(.available(models: modelNames))
                        return true
                    } catch {
                        updateState(.unavailable(reason: "LM Studio server запущено, але API ще не відповідає: \(error.localizedDescription)"))
                        return false
                    }
                }
                
                updateState(.unavailable(reason: startResult.message))
                return false
            }
            
            updateState(.unavailable(reason: error.localizedDescription))
            return false
        }
    }
    
    private func fetchAvailableModels(provider: AppSettings.LLMProvider, endpoint: String) async throws -> [String] {
        if provider == .deepMLX {
            let deepModelPath = await MainActor.run { AppSettings.shared.deepMLXModelPath }
            if let path = deepModelPath {
                return [path.lastPathComponent]
            }
            return []
        }
        
        let path = provider == .lmStudio ? Constants.openaiHealthPath : Constants.ollamaHealthPath
        
        guard let url = Self.apiURL(endpoint: endpoint, provider: provider, path: path) else {
            throw LLMError.invalidEndpoint
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw LLMError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            
            if provider == .lmStudio {
                let tagsResponse = try JSONDecoder().decode(OpenAITagsResponse.self, from: data)
                return tagsResponse.data.map(\.id)
            } else {
                let tagsResponse = try JSONDecoder().decode(TagsResponse.self, from: data)
                return tagsResponse.models.map(\.name)
            }
        } catch let error as URLError where error.code == .cannotConnectToHost {
            let msg = provider == .lmStudio ? "LM Studio не запущено." : "Ollama не запущено."
            throw LLMError.requestFailed(msg)
        } catch {
            throw LLMError.requestFailed("Помилка з'єднання: \(error.localizedDescription)")
        }
    }
    
    private func executeWithDeepMLXIfEnabled(messages: [ChatMessage], maxTokens: Int = 2048) async throws -> String? {
        let provider = await MainActor.run { AppSettings.shared.llmProvider }
        let deepModelPath = await MainActor.run { AppSettings.shared.deepMLXModelPath }
        
        guard provider == .deepMLX else { return nil }
        
        guard let modelPath = deepModelPath, DeepLLMService.isLikelyMLXModelDirectory(modelPath) else {
            if let modelPath = deepModelPath, let issue = DeepLLMService.modelDirectoryValidationIssue(at: modelPath) {
                AppLogger.warning("DeepMLX selected but MLX folder is invalid: \(issue).")
            } else {
                AppLogger.warning("DeepMLX selected but MLX folder is not specified.")
            }
            return nil
        }
        
        cancelUnloadTask()
        
        defer {
            scheduleAutoUnload()
        }
        
        do {
            if await deepLLM.state != .ready {
                try await deepLLM.loadModel(modelPath: modelPath)
            }
            let response = try await deepLLM.generate(messages: messages, maxTokens: maxTokens)
            return cleanModelResponse(response)
        } catch {
            AppLogger.error("DeepMLX: request execution error: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func cleanModelResponse(_ response: String) -> String {
        // gpt-oss uses `<|channel|>analysis<|message|> ... <|end|><|start|>assistant<|channel|>final<|message|>`
        if let finalRange = response.range(of: "<|channel|>final<|message|>") {
            var cleanText = String(response[finalRange.upperBound...])
            if let endRange = cleanText.range(of: "<|end|>") {
                cleanText = String(cleanText[..<endRange.lowerBound])
            }
            return cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Fallback: strip any remaining special chat/channel tags
        var cleaned = response
        let tokensToRemove = [
            "<|channel|>analysis<|message|>",
            "<|channel|>final<|message|>",
            "<|end|>",
            "<|start|>assistant",
            "<|im_start|>",
            "<|im_end|>"
        ]
        for token in tokensToRemove {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Summary Generation
    
    /// Generate meeting summary from transcript text
    func generateSummary(transcript: String, targetLanguage: String? = nil) async throws -> String {
        AppLogger.info("Summary generation request (length: \(transcript.count) chars, language: \(targetLanguage ?? "auto"))")
        
        let provider = await MainActor.run { AppSettings.shared.llmProvider }
        let customPrompt = await MainActor.run { AppSettings.shared.customSummaryPrompt }
        
        if provider == .deepMLX {
            let systemPrompt = Self.buildSystemPrompt(targetLanguage: targetLanguage, customPrompt: customPrompt)
            let userPrompt = Self.buildUserPrompt(transcript: transcript)
            let messages = [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt)
            ]
            if let result = try await executeWithDeepMLXIfEnabled(messages: messages, maxTokens: 2048) {
                AppLogger.info("DeepMLX: Summary generation successful!")
                return result
            } else {
                throw LLMError.requestFailed("DeepMLX модель не обрана або недійсна. Будь ласка, оберіть MLX-папку в налаштуваннях.")
            }
        }
        
        let model = await MainActor.run { AppSettings.shared.llmModel }
        let endpoint = await MainActor.run { AppSettings.shared.llmEndpoint }
        
        // Check if Server is available
        let isAvailable = await checkHealth()
        guard isAvailable else {
            throw LLMError.ollamaNotRunning
        }
        
        // Check if model is available
        if case .available(let models) = state {
            if !Self.isModelAvailable(model, in: models, provider: provider) {
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
        let customPrompt = await MainActor.run { AppSettings.shared.customSummaryPrompt }
        let systemPrompt = Self.buildSystemPrompt(targetLanguage: targetLanguage, customPrompt: customPrompt)
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
        AppLogger.info("Meeting title generation request")
        
        let prompt = """
        Напиши КОРОТКУ, інформативну назву для цієї наради на основі транскрипту (максимум 5-6 слів).
        Не використовуй лапки, крапку в кінці, або слова "Назва:". Тільки саму назву.
        Відповідай мовою транскрипту.
        
        Транскрипт:
        \(String(transcript.prefix(3000))) // Use first 3000 chars to save time
        """
        
        let messages = [
            ChatMessage(role: "system", content: "Ти асистент, що генерує короткі та влучні назви."),
            ChatMessage(role: "user", content: prompt)
        ]
        
        if let result = try await executeWithDeepMLXIfEnabled(messages: messages, maxTokens: 64) {
            return result.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
        }
        
        let model = await MainActor.run { AppSettings.shared.llmModel }
        let endpoint = await MainActor.run { AppSettings.shared.llmEndpoint }
        
        let result = try await sendChatRequest(
            model: model,
            endpoint: endpoint,
            messages: messages
        )
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
    }
    
    /// Answer a user question based on the transcript
    func answerQuestion(transcript: String, question: String, history: [LLMService.ChatMessage] = []) async throws -> String {
        AppLogger.info("Q&A question answer request")
        
        let systemPrompt = """
        Ти — асистент для аналізу нарад. Відповідай на питання користувача базуючись ТІЛЬКИ на наданому транскрипті.
        Якщо відповіді немає в транскрипті, так і скажи.
        
        ТРАНСКРИПТ:
        \(transcript)
        """
        
        var messages: [ChatMessage] = [ChatMessage(role: "system", content: systemPrompt)]
        messages.append(contentsOf: history)
        messages.append(ChatMessage(role: "user", content: question))
        
        if let result = try await executeWithDeepMLXIfEnabled(messages: messages, maxTokens: 1024) {
            return result
        }
        
        let model = await MainActor.run { AppSettings.shared.llmModel }
        let endpoint = await MainActor.run { AppSettings.shared.llmEndpoint }
        
        return try await sendChatRequest(
            model: model,
            endpoint: endpoint,
            messages: messages
        )
    }
    
    /// Translate transcript or summary
    func translateText(text: String, to languageName: String) async throws -> String {
        AppLogger.info("Text translation request to \(languageName)")
        
        let prompt = """
        Переклади наступний текст на таку мову: \(languageName).
        Збережи форматування (маркдаун, списки, абзаци).
        Не додавай від себе жодних коментарів, тільки переклад.
        
        ТЕКСТ:
        \(text)
        """
        
        let messages = [
            ChatMessage(role: "system", content: "Ти професійний перекладач. Тільки перекладай текст, без додаткових коментарів."),
            ChatMessage(role: "user", content: prompt)
        ]
        
        if let result = try await executeWithDeepMLXIfEnabled(messages: messages, maxTokens: 2048) {
            return result
        }
        
        let model = await MainActor.run { AppSettings.shared.llmModel }
        let endpoint = await MainActor.run { AppSettings.shared.llmEndpoint }
        
        return try await sendChatRequest(
            model: model,
            endpoint: endpoint,
            messages: messages
        )
    }

    /// Generic streaming response generation
    func generateResponseStream(prompt: String, systemPrompt: String) async -> AsyncThrowingStream<String, Error> {
        cancelUnloadTask()
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let messages = [
                        ChatMessage(role: "system", content: systemPrompt),
                        ChatMessage(role: "user", content: prompt)
                    ]
                    
                    let provider = await MainActor.run { AppSettings.shared.llmProvider }
                    let model = await MainActor.run { AppSettings.shared.llmModel }
                    
                    let endpoint = await MainActor.run { AppSettings.shared.llmEndpoint }
                    let path = provider == .lmStudio ? Constants.openaiChatPath : Constants.ollamaChatPath
                    
                    guard let url = Self.apiURL(endpoint: endpoint, provider: provider, path: path) else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }
                    
                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.httpBody = try Self.encodedChatRequestData(
                        provider: provider,
                        model: model,
                        messages: messages,
                        stream: true,
                        temperature: 0.7,
                        maxTokens: 2048,
                        topP: 0.9
                    )
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    updateState(.generating)
                    
                    let (stream, _) = try await URLSession.shared.bytes(for: urlRequest)
                    
                    for try await line in stream.lines {
                        let parsedContent = try parseStreamLine(line, provider: provider)
                        if let content = parsedContent.content {
                            continuation.yield(content)
                        }
                        if parsedContent.isDone {
                            break
                        }
                    }
                    
                    updateState(.idle)
                    continuation.finish()
                    scheduleAutoUnload()
                } catch {
                    updateState(.idle)
                    continuation.finish(throwing: error)
                    scheduleAutoUnload()
                }
            }
        }
    }
    
    // MARK: - Chunked Summary (Long Meetings)
    
    private func generateChunkedSummary(transcript: String, model: String, endpoint: String, targetLanguage: String?) async throws -> String {
        AppLogger.info("Transcript too large, splitting into chunks...")
        
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
            AppLogger.info("Generating summary for chunk \(index + 1)/\(chunks.count)")
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
        let customPrompt = await MainActor.run { AppSettings.shared.customSummaryPrompt }
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
                ChatMessage(role: "system", content: Self.buildSystemPrompt(targetLanguage: targetLanguage, customPrompt: customPrompt)),
                ChatMessage(role: "user", content: mergePrompt)
            ]
        )
    }
    
    // MARK: - Chat Request with Streaming
    
    private func sendChatRequest(model: String, endpoint: String, messages: [ChatMessage]) async throws -> String {
        let provider = await MainActor.run { AppSettings.shared.llmProvider }
        let path = provider == .lmStudio ? Constants.openaiChatPath : Constants.ollamaChatPath
        
        guard let url = Self.apiURL(endpoint: endpoint, provider: provider, path: path) else {
            throw LLMError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Constants.llmRequestTimeout
        request.httpBody = try Self.encodedChatRequestData(
            provider: provider,
            model: model,
            messages: messages,
            stream: true,
            temperature: 0.3,
            maxTokens: 4096,
            topP: 0.9
        )
        
        cancelUnloadTask()
        
        defer {
            scheduleAutoUnload()
        }
        
        updateState(.generating)
        
        var fullResponse = ""
        
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw LLMError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            
            for try await line in bytes.lines {
                do {
                    let parsed = try parseStreamLine(line, provider: provider)
                    if let content = parsed.content {
                        fullResponse += content
                        onTokenReceived?(content)
                    }
                    if parsed.isDone {
                        break
                    }
                } catch {
                    continue
                }
            }
            
            updateState(.idle)
            guard !fullResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMError.emptyResponse
            }
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
    
    nonisolated private static func buildSystemPrompt(targetLanguage: String?, customPrompt: String) -> String {
        let languageInstruction: String
        if let targetLanguage, targetLanguage != "auto" {
            let langName = targetLanguage == "uk" ? "українською" : "англійською"
            languageInstruction = "Важливо: твоя відповідь має бути написана ВИКЛЮЧНО \(langName) мовою. Не пиши жодних вступних фраз чи підтверджень про мову, одразу починай резюме."
        } else {
            languageInstruction = "Відповідай ТІЄЮ Ж МОВОЮ, якою написано більшу частину транскрипту (за замовчуванням — українською)."
        }
        
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
    
    nonisolated private static func buildUserPrompt(transcript: String) -> String {
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
    
    /// Extract speaker names from transcript if they were mentioned
    func extractSpeakerNames(transcript: String) async throws -> [String: String] {
        AppLogger.info("Speaker name extraction request")
        
        let prompt = """
        Проаналізуй транскрипт наради. Текст подано у форматі "ID: Текст", де ID — це ідентифікатор спікера (наприклад, "S1:", "Speaker 0:", "Невідомий:").
        Твоє завдання — визначити справжні імена людей, якщо вони згадувалися в тексті (наприклад, коли хтось представляється: "Я Олексій", "Мене звати Марія", "Говорить Андрій").
        
        Поверни результат ТІЛЬКИ у форматі JSON, де ключ — це ідентифікатор спікера (точно як у тексті), а значення — його ім'я.
        Приклад: {"S1": "Алла Тіхановська", "Speaker 0": "Олексій"}
        Якщо ім'я для конкретного спікера неможливо визначити, не додавай його до JSON.
        
        Транскрипт:
        \(String(transcript.prefix(8000)))
        """
        
        let messages = [
            ChatMessage(role: "system", content: "Ти асистент, що витягує імена людей з тексту. Відповідай ТІЛЬКИ чистим JSON."),
            ChatMessage(role: "user", content: prompt)
        ]
        
        var result: String? = nil
        if let mlxResult = try await executeWithDeepMLXIfEnabled(messages: messages, maxTokens: 512) {
            result = mlxResult
        } else {
            let model = await MainActor.run { AppSettings.shared.llmModel }
            let endpoint = await MainActor.run { AppSettings.shared.llmEndpoint }
            result = try await sendChatRequest(
                model: model,
                endpoint: endpoint,
                messages: messages
            )
        }
        
        guard let finalResult = result else { return [:] }
        
        // Clean result from markdown code blocks
        let cleanJSON = finalResult.replacingOccurrences(of: "```json", with: "")
                                  .replacingOccurrences(of: "```", with: "")
                                  .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanJSON.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
    
    // MARK: - Helpers
    
    private func parseStreamLine(_ line: String, provider: AppSettings.LLMProvider) throws -> (content: String?, isDone: Bool) {
        if provider == .lmStudio {
            // OpenAI Format: `data: {...}`
            guard line.hasPrefix("data: ") else { return (nil, false) }
            let jsonString = String(line.dropFirst(6))
            if jsonString.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                return (nil, true)
            }
            guard let data = jsonString.data(using: .utf8) else { return (nil, false) }
            let decoded = try JSONDecoder().decode(OpenAIChatStreamResponse.self, from: data)
            let content = decoded.choices?.first?.delta?.content
            return (content, false)
        } else {
            // Ollama Format
            guard let data = line.data(using: .utf8) else { return (nil, false) }
            let decoded = try JSONDecoder().decode(ChatStreamResponse.self, from: data)
            return (decoded.message?.content, decoded.done)
        }
    }
    
    private func updateState(_ newState: LLMServiceState) {
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
            return "Локальний LLM-сервер не запущено. Для Ollama виконайте 'ollama serve', для LM Studio увімкніть Local Server."
        case .modelNotFound(let model):
            return "Модель '\(model)' не знайдено серед моделей поточного провайдера. Оновіть список і виберіть доступну модель."
        case .invalidEndpoint:
            return "Невірна адреса LLM API."
        case .requestFailed(let detail):
            return "Помилка запиту до LLM: \(detail)"
        case .emptyResponse:
            return "LLM повернув порожню відповідь."
        }
    }
}
