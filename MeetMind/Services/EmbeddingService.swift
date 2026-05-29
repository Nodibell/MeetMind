//
//  EmbeddingService.swift
//  MeetMind
//
//  Created by Developer on 28.05.2026.
//

import Foundation

/// Protocol defining the interface for embedding generation
protocol EmbeddingProvider: Sendable {
    func generateEmbedding(for text: String) async throws -> [Float]
}

/// Local embedding generation service supporting Ollama and LM Studio
actor EmbeddingService: EmbeddingProvider {
    private let coreMLService = CoreMLEmbeddingService()
    
    init() {}
    
    // MARK: - API Models
    
    // Ollama current API: POST /api/embed
    // Replaces deprecated /api/embeddings which returns 404 on newer Ollama versions
    private struct OllamaEmbedRequest: Encodable {
        let model: String
        let input: String          // was "prompt" in the old /api/embeddings
    }
    
    private struct OllamaEmbedResponse: Decodable {
        let embeddings: [[Float]]  // array-of-arrays (batch support)
    }
    
    private struct OpenAIEmbedRequest: Encodable {
        let input: String
        let model: String
    }
    
    private struct OpenAIEmbedResponse: Decodable {
        let data: [EmbeddingData]
        
        struct EmbeddingData: Decodable {
            let embedding: [Float]
        }
    }
    
    // MARK: - Generate
    
    func generateEmbedding(for text: String) async throws -> [Float] {
        let useBuiltIn = await MainActor.run { AppSettings.shared.useBuiltInEmbedding }
        if useBuiltIn {
            return try await coreMLService.generateEmbedding(for: text)
        }
        
        let mainProvider = await MainActor.run { AppSettings.shared.llmProvider }
        let embeddingProvider = await MainActor.run { AppSettings.shared.llmEmbeddingProvider }
        let model = await MainActor.run { AppSettings.shared.llmEmbeddingModel }
        let endpoint = await MainActor.run { AppSettings.shared.embeddingEndpoint }
        
        // DeepMLX has no embedding REST API; guide user to use Ollama/LM Studio for RAG
        guard mainProvider != .deepMLX && embeddingProvider != .deepMLX else {
            throw EmbeddingError.unsupportedProvider("DeepMLX не підтримує локальну генерацію ембедингів. Виберіть Ollama або LM Studio у налаштуваннях RAG (Модель Ембедингів).")
        }
        
        // Ollama uses /api/embed (current) — /api/embeddings is deprecated → 404 on new Ollama
        // LM Studio uses the OpenAI-compatible /v1/embeddings
        let path = embeddingProvider == .lmStudio ? "/v1/embeddings" : "/api/embed"
        
        guard let url = LLMService.apiURL(endpoint: endpoint, provider: embeddingProvider, path: path) else {
            throw EmbeddingError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let encoder = JSONEncoder()
        if embeddingProvider == .lmStudio {
            let payload = OpenAIEmbedRequest(input: text, model: model)
            request.httpBody = try encoder.encode(payload)
        } else {
            let payload = OllamaEmbedRequest(model: model, input: text)
            request.httpBody = try encoder.encode(payload)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingError.requestFailed("Невалідна відповідь сервера")
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8).map { ". " + $0.prefix(120) } ?? ""
            throw EmbeddingError.requestFailed("HTTP \(httpResponse.statusCode)\(body)")
        }
        
        let decoder = JSONDecoder()
        if embeddingProvider == .lmStudio {
            let res = try decoder.decode(OpenAIEmbedResponse.self, from: data)
            guard let first = res.data.first?.embedding else {
                throw EmbeddingError.emptyResponse
            }
            return first
        } else {
            // /api/embed returns {"embeddings": [[float, ...], ...]}
            let res = try decoder.decode(OllamaEmbedResponse.self, from: data)
            guard let first = res.embeddings.first else {
                throw EmbeddingError.emptyResponse
            }
            return first
        }
    }
}

// MARK: - Errors
enum EmbeddingError: LocalizedError {
    case invalidEndpoint
    case unsupportedProvider(String)
    case requestFailed(String)
    case emptyResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Невірна адреса API для генерації ембедингів."
        case .unsupportedProvider(let reason):
            return reason
        case .requestFailed(let detail):
            return "Помилка запиту генерації ембедингів: \(detail)"
        case .emptyResponse:
            return "Сервер повернув порожній вектор ембедингу."
        }
    }
}
