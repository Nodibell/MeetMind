//
//  BertTokenizer.swift
//  MeetMind
//
//  Minimal BERT WordPiece tokenizer — no external dependencies.
//  Lives in its own file so Swift 6 cannot infer @MainActor isolation
//  from the CoreML-adjacent CoreMLEmbeddingService.
//
//  All methods are explicitly nonisolated: this struct is pure computation,
//  reads only immutable value-type state, and must be callable from any
//  concurrency context (actor, Task.detached, etc.).
//

import Foundation

// MARK: - BERT WordPiece Tokenizer

/// Minimal BERT WordPiece tokenizer — no external dependencies.
/// Handles basic lowercasing, punctuation splitting, and WordPiece segmentation.
struct BertTokenizer: Sendable {

    private let vocab: [String: Int]
    private let ids: [Int: String]
    private let clsID: Int
    private let sepID: Int
    private let padID: Int
    private let unkID: Int

    // nonisolated: pure file I/O with no actor-isolated state.
    // Explicit keyword prevents Swift 6 from inferring @MainActor
    // from neighbouring types that use CoreML APIs.
    nonisolated init(vocabURL: URL) throws {
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

    // MARK: - Encoding

    struct Encoding: Sendable {
        var inputIDs:      [Int32]
        var attentionMask: [Int32]
    }

    // nonisolated: pure computation over immutable value-type state.
    nonisolated func encode(text: String, maxLength: Int) -> Encoding {
        let tokens = tokenize(text: text)

        // [CLS] token_ids… [SEP], truncated to maxLength
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

    // MARK: - Private Helpers

    private nonisolated func tokenize(text: String) -> [String] {
        // Basic whitespace tokenisation with lowercase
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

        // WordPiece segmentation
        var subtokens: [String] = []
        for word in words {
            subtokens.append(contentsOf: wordPiece(word: word))
        }
        return subtokens
    }

    private nonisolated func wordPiece(word: String) -> [String] {
        guard !word.isEmpty else { return [] }
        if vocab[word] != nil { return [word] }

        var subTokens: [String] = []
        var start = word.startIndex
        var isBad = false

        while start < word.endIndex {
            var end = word.endIndex
            var curStr: String?

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

    private nonisolated func wordPieceID(for token: String) -> Int {
        vocab[token] ?? unkID
    }

    private nonisolated func isPunct(_ s: Unicode.Scalar) -> Bool {
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
