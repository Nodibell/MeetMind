//
//  VectorStoreTests.swift
//  MeetMindTests
//
//  Created by Developer on 28.05.2026.
//

import XCTest
@testable import MeetMind

final class VectorStoreTests: XCTestCase {
    
    func testCosineSimilarityForIdenticalVectors() {
        let v1: [Float] = [1.0, 2.0, 3.0]
        let v2: [Float] = [1.0, 2.0, 3.0]
        
        let similarity = VectorMath.cosineSimilarity(v1, v2)
        XCTAssertEqual(similarity, 1.0, accuracy: 0.0001)
    }
    
    func testCosineSimilarityForOrthogonalVectors() {
        let v1: [Float] = [1.0, 0.0]
        let v2: [Float] = [0.0, 1.0]
        
        let similarity = VectorMath.cosineSimilarity(v1, v2)
        XCTAssertEqual(similarity, 0.0, accuracy: 0.0001)
    }
    
    func testCosineSimilarityForOppositeVectors() {
        let v1: [Float] = [1.0, 2.0, 3.0]
        let v2: [Float] = [-1.0, -2.0, -3.0]
        
        let similarity = VectorMath.cosineSimilarity(v1, v2)
        XCTAssertEqual(similarity, -1.0, accuracy: 0.0001)
    }
    
    @MainActor
    func testVectorStoreRetrievesTopMatches() async {
        let store = await VectorStore()
        
        let items = [
            VectorItem(id: UUID(), meetingID: UUID(), textChunk: "Apple", vector: [1.0, 0.0], startIndex: 0),
            VectorItem(id: UUID(), meetingID: UUID(), textChunk: "Banana", vector: [0.0, 1.0], startIndex: 0),
            VectorItem(id: UUID(), meetingID: UUID(), textChunk: "Pear", vector: [0.8, 0.2], startIndex: 0)
        ]
        
        // Query that is identical to "Apple"
        let results = await store.findSimilarChunks(queryVector: [1.0, 0.0], in: items, topK: 2)
        
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].item.textChunk, "Apple")
        XCTAssertEqual(results[0].similarity, 1.0, accuracy: 0.0001)
        
        XCTAssertEqual(results[1].item.textChunk, "Pear")
        XCTAssertGreaterThan(results[1].similarity, 0.7)
    }
}
