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
    
    // MARK: - API Models
    
    private struct OllamaEmbedRequest: Encodable {
        let model: String
        let prompt: String
    }
    
    private struct OllamaEmbedResponse: Decodable {
        let embedding: [Float]
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
        let provider = await MainActor.run { AppSettings.shared.llmProvider }
        let model = await MainActor.run { AppSettings.shared.llmEmbeddingModel }
        let endpoint = await MainActor.run { AppSettings.shared.llmEndpoint }
        
        guard provider != .deepMLX else {
            throw EmbeddingError.unsupportedProvider("DeepMLX не підтримує локальну генерацію ембедингів. Виберіть Ollama або LM Studio.")
        }
        
        let path = provider == .lmStudio ? "/v1/embeddings" : "/api/embeddings"
        
        guard let url = LLMService.apiURL(endpoint: endpoint, provider: provider, path: path) else {
            throw EmbeddingError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        
        let encoder = JSONEncoder()
        if provider == .lmStudio {
            let payload = OpenAIEmbedRequest(input: text, model: model)
            request.httpBody = try encoder.encode(payload)
        } else {
            let payload = OllamaEmbedRequest(model: model, prompt: text)
            request.httpBody = try encoder.encode(payload)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EmbeddingError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        
        let decoder = JSONDecoder()
        if provider == .lmStudio {
            let res = try decoder.decode(OpenAIEmbedResponse.self, from: data)
            guard let first = res.data.first?.embedding else {
                throw EmbeddingError.emptyResponse
            }
            return first
        } else {
            let res = try decoder.decode(OllamaEmbedResponse.self, from: data)
            return res.embedding
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
