//
//  VectorStore.swift
//  MeetMind
//
//  Created by Developer on 28.05.2026.
//

import Foundation
import Accelerate
import SQLite3

/// A lightweight, Sendable struct representing a vector embedding item in memory
struct VectorItem: Sendable, Codable {
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
    nonisolated static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
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

/// Actor representing high-performance local vector index matcher and FTS5 keyword indexer
actor VectorStore {
    private var db: OpaquePointer?
    
    init() {
        self.db = Self.setupDatabase()
    }
    
    private static func setupDatabase() -> OpaquePointer? {
        let fileManager = FileManager.default
        let appSupportDir = URL.applicationSupportDirectory
        if !fileManager.fileExists(atPath: appSupportDir.path) {
            try? fileManager.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        }
        
        let path = appSupportDir.appending(path: "MeetMindFTS.db").path
        var db: OpaquePointer?
        if sqlite3_open(path, &db) == SQLITE_OK {
            let createTableQuery = """
            CREATE VIRTUAL TABLE IF NOT EXISTS fts_transcript USING fts5(
                segment_id, 
                text_content, 
                meeting_title
            );
            """
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, createTableQuery, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) != SQLITE_DONE {
                    AppLogger.error("Failed to create FTS5 virtual table")
                }
            }
            sqlite3_finalize(statement)
            AppLogger.info("FTS5 virtual table configured at: \(path)")
            return db
        } else {
            AppLogger.error("Failed to open FTS5 database")
            return nil
        }
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    /// Indexes a transcript segment text in the FTS virtual table
    func indexSegment(segmentID: UUID, text: String, meetingTitle: String) {
        guard let db = db else { return }
        
        // Let's first delete existing index for this segment ID to avoid duplicates
        let deleteQuery = "DELETE FROM fts_transcript WHERE segment_id = ?;"
        var deleteStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteQuery, -1, &deleteStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteStmt, 1, segmentID.uuidString, -1, nil)
            sqlite3_step(deleteStmt)
        }
        sqlite3_finalize(deleteStmt)
        
        // Insert new entry
        let insertQuery = "INSERT INTO fts_transcript (segment_id, text_content, meeting_title) VALUES (?, ?, ?);"
        var insertStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertQuery, -1, &insertStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStmt, 1, segmentID.uuidString, -1, nil)
            sqlite3_bind_text(insertStmt, 2, text, -1, nil)
            sqlite3_bind_text(insertStmt, 3, meetingTitle, -1, nil)
            
            if sqlite3_step(insertStmt) != SQLITE_DONE {
                AppLogger.error("Failed to insert FTS index for segment: \(segmentID)")
            }
        } else {
            if let err = sqlite3_errmsg(db) {
                AppLogger.error("Prepare insert failed: \(String(cString: err))")
            }
        }
        sqlite3_finalize(insertStmt)
    }
    
    /// Clears FTS index entries for specified segments
    func clearFTSIndex(for segmentIDs: [UUID]) {
        guard let db = db, !segmentIDs.isEmpty else { return }
        let idsString = segmentIDs.map { "'\($0.uuidString)'" }.joined(separator: ",")
        let deleteQuery = "DELETE FROM fts_transcript WHERE segment_id IN (\(idsString));"
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteQuery, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) != SQLITE_DONE {
                AppLogger.error("Failed to delete FTS indexes")
            }
        }
        sqlite3_finalize(stmt)
    }
    
    /// Runs an FTS5 MATCH query and returns the matching segment IDs in order of SQLite ranking
    func searchFTS(query: String) -> [UUID] {
        guard let db = db, !query.isEmpty else { return [] }
        
        // Escape special FTS characters or handle query syntax safely.
        let sanitizedQuery = query.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " OR ")
        
        guard !sanitizedQuery.isEmpty else { return [] }
        
        let selectQuery = "SELECT segment_id FROM fts_transcript WHERE fts_transcript MATCH ? ORDER BY rank;"
        var stmt: OpaquePointer?
        var results: [UUID] = []
        
        if sqlite3_prepare_v2(db, selectQuery, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sanitizedQuery, -1, nil)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cString = sqlite3_column_text(stmt, 0) {
                    let uuidStr = String(cString: cString)
                    if let uuid = UUID(uuidString: uuidStr) {
                        results.append(uuid)
                    }
                }
            }
        } else {
            if let err = sqlite3_errmsg(db) {
                AppLogger.error("Prepare search failed: \(String(cString: err))")
            }
        }
        sqlite3_finalize(stmt)
        return results
    }
    
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
    
    struct HybridMatch: Sendable, Identifiable {
        let id: UUID
        let item: VectorItem
        let score: Float
    }
    
    /// Executes a parallel hybrid search combining semantic distance and Keyword FTS5 search merged with RRF
    func searchHybrid(
        query: String,
        queryVector: [Float],
        in items: [VectorItem],
        topK: Int = 5
    ) -> [HybridMatch] {
        // 1. Calculate Semantic Ranks (Sorted descending by similarity score)
        let semanticMatches = items.map { item -> (VectorItem, Float) in
            let sim = VectorMath.cosineSimilarity(queryVector, item.vector)
            return (item, sim)
        }.sorted(by: { $0.1 > $1.1 })
        
        // 2. Run Keyword FTS5 Search
        let ftsResults = searchFTS(query: query)
        
        // 3. Build RRF Rank maps
        var rrfScores: [UUID: Float] = [:]
        var itemMap: [UUID: VectorItem] = [:]
        
        // Map 1-based ranks from Semantic Run
        for (rank, match) in semanticMatches.enumerated() {
            let id = match.0.id
            itemMap[id] = match.0
            
            let rankScore = 1.0 / (60.0 + Float(rank + 1))
            rrfScores[id, default: 0.0] += rankScore
        }
        
        // Map 1-based ranks from FTS5 Keyword Match Run
        for (rank, ftsSegmentID) in ftsResults.enumerated() {
            // Find corresponding VectorItem in current set
            guard let item = items.first(where: { $0.segmentID == ftsSegmentID }) else { continue }
            let id = item.id
            itemMap[id] = item
            
            let rankScore = 1.0 / (60.0 + Float(rank + 1))
            rrfScores[id, default: 0.0] += rankScore
        }
        
        // 4. Synthesize Hybrid Matches sorted by merged RRF scores
        let hybridMatches = rrfScores.map { (id, score) -> HybridMatch in
            return HybridMatch(id: id, item: itemMap[id]!, score: score)
        }.sorted(by: { $0.score > $1.score })
        
        return Array(hybridMatches.prefix(topK))
    }
}
