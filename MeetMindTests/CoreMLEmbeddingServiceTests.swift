//
//  CoreMLEmbeddingServiceTests.swift
//  MeetMindTests
//
//  Created by Developer on 29.05.2026.
//

import XCTest
@testable import MeetMind

final class CoreMLEmbeddingServiceTests: XCTestCase {
    
    var service: CoreMLEmbeddingService!
    
    override func setUp() {
        super.setUp()
        service = CoreMLEmbeddingService()
    }
    
    override func tearDown() {
        service = nil
        super.tearDown()
    }
    
    func testGenerateEmbedding_returnsCorrectDimension() async throws {
        let text = "Hello world! This is a test for the bundled CoreML sentence embedding model."
        
        let embedding = try await service.generateEmbedding(for: text)
        
        // MiniLM-L6-v2 outputs 384-dimensional vectors
        XCTAssertEqual(embedding.count, 384)
    }
    
    func testGenerateEmbedding_isL2Normalised() async throws {
        let text = "CoreML embeddings should be normalized to unit length."
        
        let embedding = try await service.generateEmbedding(for: text)
        
        // Compute L2 norm: sqrt(sum(x_i^2))
        let sumOfSquares = embedding.reduce(0) { $0 + ($1 * $1) }
        let l2Norm = sqrt(sumOfSquares)
        
        // Assert L2 norm is very close to 1.0
        XCTAssertEqual(l2Norm, 1.0, accuracy: 0.01)
    }
    
    func testGenerateEmbedding_semanticSimilarity() async throws {
        let sentenceA1 = "We will release the new version of the app next Tuesday."
        let sentenceA2 = "The next release of our application is scheduled for next Tuesday."
        let sentenceB = "I had a wonderful breakfast with pancakes and maple syrup."
        
        let embA1 = try await service.generateEmbedding(for: sentenceA1)
        let embA2 = try await service.generateEmbedding(for: sentenceA2)
        let embB  = try await service.generateEmbedding(for: sentenceB)
        
        let similarityA1A2 = VectorMath.cosineSimilarity(embA1, embA2)
        let similarityA1B  = VectorMath.cosineSimilarity(embA1, embB)
        
        // Similar sentences should have higher cosine similarity than unrelated ones
        XCTAssertGreaterThan(similarityA1A2, 0.6)
        XCTAssertLessThan(similarityA1B, 0.4)
        XCTAssertGreaterThan(similarityA1A2, similarityA1B)
    }
}
