//
//  VectorStore.swift
//  MeetMind
//
//  Created by Developer on 28.05.2026.
//

import Foundation
import Accelerate

/// A lightweight, Sendable struct representing a vector embedding item in memory
struct VectorItem: Sendable {
    let id: UUID
    let meetingID: UUID
    let segmentID: UUID?
    let textChunk: String
    let vector: [Float]
    let startIndex: Int
    
    init(
        id: UUID = UUID(),
        meetingID: UUID,
        segmentID: UUID? = nil,
        textChunk: String,
        vector: [Float],
        startIndex: Int
    ) {
        self.id = id
        self.meetingID = meetingID
        self.segmentID = segmentID
        self.textChunk = textChunk
        self.vector = vector
        self.startIndex = startIndex
    }
}

/// Native Cosine Similarity calculator powered by Apple's Accelerate framework
enum VectorMath {
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        let count = a.count
        
        var dotProduct: Float = 0.0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(count))
        
        var sumSquaresA: Float = 0.0
        vDSP_svesq(a, 1, &sumSquaresA, vDSP_Length(count))
        
        var sumSquaresB: Float = 0.0
        vDSP_svesq(b, 1, &sumSquaresB, vDSP_Length(count))
        
        let magnitudeA = sqrt(sumSquaresA)
        let magnitudeB = sqrt(sumSquaresB)
        
        guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
}

/// Actor representing high-performance local vector index matcher
actor VectorStore {
    
    struct SearchResult: Sendable {
        let item: VectorItem
        let similarity: Float
    }
    
    /// Finds top-K most similar text chunks for a given query vector
    func findSimilarChunks(
        queryVector: [Float],
        in items: [VectorItem],
        topK: Int = 5
    ) -> [SearchResult] {
        var results: [SearchResult] = []
        results.reserveCapacity(items.count)
        
        for item in items {
            let similarity = VectorMath.cosineSimilarity(queryVector, item.vector)
            results.append(SearchResult(item: item, similarity: similarity))
        }
        
        // Sort descending by similarity
        results.sort(by: { $0.similarity > $1.similarity })
        
        return Array(results.prefix(topK))
    }
}
