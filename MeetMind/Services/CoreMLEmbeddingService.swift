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
    static let embeddingDim: Int = 384
    static let maxSeqLen: Int    = 128

    // MARK: - Init

    init() {}

    // MARK: - Lazy Load

    private func loadIfNeeded() throws {
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
        tokenizer = try BertTokenizer(vocabURL: vocabURL)
    }

    // MARK: - EmbeddingProvider

    func generateEmbedding(for text: String) async throws -> [Float] {
        try loadIfNeeded()

        guard let model, let tokenizer else {
            throw CoreMLEmbeddingError.modelNotFound
        }

        // Tokenise
        let encoding = tokenizer.encode(
            text: text,
            maxLength: CoreMLEmbeddingService.maxSeqLen
        )

        // Build MLFeatureProvider
        let inputIDs     = try MLMultiArray(shape: [1, NSNumber(value: CoreMLEmbeddingService.maxSeqLen)], dataType: .int32)
        let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: CoreMLEmbeddingService.maxSeqLen)], dataType: .int32)
        let tokenTypeIDs  = try MLMultiArray(shape: [1, NSNumber(value: CoreMLEmbeddingService.maxSeqLen)], dataType: .int32)

        for i in 0..<CoreMLEmbeddingService.maxSeqLen {
            inputIDs[[0, i] as [NSNumber]]     = NSNumber(value: encoding.inputIDs[i])
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

// MARK: - BERT WordPiece Tokenizer

/// Minimal BERT WordPiece tokenizer — no external dependencies.
/// Handles basic lowercasing, punctuation splitting, and WordPiece segmentation.
struct BertTokenizer {

    private let vocab: [String: Int]
    private let ids: [Int: String]
    private let clsID:  Int
    private let sepID:  Int
    private let padID:  Int
    private let unkID:  Int

    init(vocabURL: URL) throws {
        let content = try String(contentsOf: vocabURL, encoding: .utf8)
        var v: [String: Int] = [:]
        var iv: [Int: String] = [:]
        for (idx, line) in content.components(separatedBy: "\n").enumerated() {
            let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            v[token] = idx
            iv[idx]  = token
        }
        vocab = v
        ids   = iv
        clsID = v["[CLS]"] ?? 101
        sepID = v["[SEP]"] ?? 102
        padID = v["[PAD]"] ?? 0
        unkID = v["[UNK]"] ?? 100
    }

    struct Encoding {
        var inputIDs:     [Int32]
        var attentionMask: [Int32]
    }

    func encode(text: String, maxLength: Int) -> Encoding {
        let tokens = tokenize(text: text)

        // [CLS] tokens… [SEP], truncate to maxLength
        var ids: [Int] = [clsID]
        for t in tokens.prefix(maxLength - 2) {
            ids.append(wordPieceID(for: t))
        }
        ids.append(sepID)

        var inputIDs      = [Int32](repeating: Int32(padID), count: maxLength)
        var attentionMask = [Int32](repeating: 0,            count: maxLength)

        for (i, id) in ids.enumerated() where i < maxLength {
            inputIDs[i]      = Int32(id)
            attentionMask[i] = 1
        }

        return Encoding(inputIDs: inputIDs, attentionMask: attentionMask)
    }

    // MARK: - Private

    private func tokenize(text: String) -> [String] {
        // 1. Basic whitespace tokenization with lowercase
        let lower = text.lowercased()
        var words: [String] = []
        var current = ""

        for ch in lower.unicodeScalars {
            if ch.properties.isWhitespace {
                if !current.isEmpty { words.append(current); current = "" }
            } else if isPunct(ch) {
                if !current.isEmpty { words.append(current); current = "" }
                words.append(String(ch))
            } else {
                current.unicodeScalars.append(ch)
            }
        }
        if !current.isEmpty { words.append(current) }

        // 2. WordPiece segmentation
        var subtokens: [String] = []
        for word in words {
            subtokens.append(contentsOf: wordPiece(word: word))
        }
        return subtokens
    }

    private func wordPiece(word: String) -> [String] {
        guard !word.isEmpty else { return [] }
        if vocab[word] != nil { return [word] }

        var subTokens: [String] = []
        var start = word.startIndex
        var isBad = false

        while start < word.endIndex {
            var end = word.endIndex
            var curStr: String? = nil

            while start < end {
                var substr = String(word[start..<end])
                if start != word.startIndex { substr = "##" + substr }
                if vocab[substr] != nil {
                    curStr = substr
                    break
                }
                end = word.index(before: end)
            }

            if curStr == nil { isBad = true; break }
            subTokens.append(curStr!)
            start = end
        }

        return isBad ? ["[UNK]"] : subTokens
    }

    private func wordPieceID(for token: String) -> Int {
        vocab[token] ?? unkID
    }

    private func isPunct(_ s: Unicode.Scalar) -> Bool {
        let c = s.value
        // ASCII punctuation ranges
        if (c >= 33 && c <= 47) || (c >= 58 && c <= 64) ||
           (c >= 91 && c <= 96) || (c >= 123 && c <= 126) { return true }
        return s.properties.generalCategory == .otherPunctuation
            || s.properties.generalCategory == .dashPunctuation
            || s.properties.generalCategory == .openPunctuation
            || s.properties.generalCategory == .closePunctuation
    }
}
