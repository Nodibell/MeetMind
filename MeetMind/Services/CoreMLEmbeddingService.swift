//
//  CoreMLEmbeddingService.swift
//  MeetMind
//
//  On-device sentence embedding using the bundled all-MiniLM-L6-v2 CoreML model.
//  Produces L2-normalised 384-dim Float vectors without any network requests.
//
//  Model: sentence-transformers/all-MiniLM-L6-v2 (Float16, ~22 MB)
//  Tokenizer: BERT WordPiece (vocab.txt bundled in Resources)
//

import CoreML
import Foundation
import Accelerate

// MARK: - CoreML Embedding Service

actor CoreMLEmbeddingService: EmbeddingProvider {

    // MARK: - State

    private var model: MLModel?
    private var tokenizer: BertTokenizer?
    // nonisolated so callers outside the actor can read these constants
    // without an actor hop (required in Swift 6 strict concurrency mode)
    nonisolated static let embeddingDim: Int = 384
    nonisolated static let maxSeqLen: Int    = 128

    // MARK: - Init

    init() {}

    // MARK: - Lazy Load

    private func loadIfNeeded() async throws {
        guard model == nil else { return }

        // Locate the .mlmodelc compiled package inside the app bundle
        guard let modelURL = Bundle.main.url(
            forResource: "MiniLMEmbedder",
            withExtension: "mlmodelc"
        ) ?? Bundle.main.url(
            forResource: "MiniLMEmbedder",
            withExtension: "mlpackage"
        ) else {
            throw CoreMLEmbeddingError.modelNotFound
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all   // CPU + Neural Engine + GPU
        model = try MLModel(contentsOf: modelURL, configuration: config)

        // Load vocab
        guard let vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "txt") else {
            throw CoreMLEmbeddingError.vocabNotFound
        }
        // BertTokenizer.init is nonisolated (see BertTokenizer.swift) — safe to call directly
        tokenizer = try BertTokenizer(vocabURL: vocabURL)
    }

    // MARK: - EmbeddingProvider

    func generateEmbedding(for text: String) async throws -> [Float] {
        try await loadIfNeeded()

        guard let model, let tokenizer else {
            throw CoreMLEmbeddingError.modelNotFound
        }

        // Tokenise — nonisolated pure computation, no actor hop required
        let encoding = tokenizer.encode(
            text: text,
            maxLength: CoreMLEmbeddingService.maxSeqLen
        )

        // Build MLFeatureProvider
        let inputIDs      = try MLMultiArray(shape: [1, NSNumber(value: CoreMLEmbeddingService.maxSeqLen)], dataType: .int32)
        let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: CoreMLEmbeddingService.maxSeqLen)], dataType: .int32)
        let tokenTypeIDs  = try MLMultiArray(shape: [1, NSNumber(value: CoreMLEmbeddingService.maxSeqLen)], dataType: .int32)

        for i in 0..<CoreMLEmbeddingService.maxSeqLen {
            inputIDs[[0, i] as [NSNumber]]      = NSNumber(value: encoding.inputIDs[i])
            attentionMask[[0, i] as [NSNumber]] = NSNumber(value: encoding.attentionMask[i])
            tokenTypeIDs[[0, i] as [NSNumber]]  = 0
        }

        let features = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids":      MLFeatureValue(multiArray: inputIDs),
            "attention_mask": MLFeatureValue(multiArray: attentionMask),
            "token_type_ids": MLFeatureValue(multiArray: tokenTypeIDs),
        ])

        let prediction = try await model.prediction(from: features)

        guard let embeddingArray = prediction.featureValue(for: "embedding")?.multiArrayValue else {
            throw CoreMLEmbeddingError.badOutput
        }

        // Copy MLMultiArray → [Float]
        var result = [Float](repeating: 0, count: CoreMLEmbeddingService.embeddingDim)
        for i in 0..<CoreMLEmbeddingService.embeddingDim {
            result[i] = embeddingArray[[0, i] as [NSNumber]].floatValue
        }
        return result
    }
}

// MARK: - Errors

enum CoreMLEmbeddingError: LocalizedError {
    case modelNotFound
    case vocabNotFound
    case badOutput

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Вбудовану модель ембедингів (MiniLMEmbedder) не знайдено в ресурсах застосунку."
        case .vocabNotFound:
            return "Файл словника (vocab.txt) для вбудованої моделі ембедингів не знайдено."
        case .badOutput:
            return "Вбудована модель ембедингів повернула некоректний результат."
        }
    }
}
