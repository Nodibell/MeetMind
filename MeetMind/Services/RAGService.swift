//
//  RAGService.swift
//  MeetMind
//
//  Created by Developer on 28.05.2026.
//

import Foundation
import SwiftData

/// Coordinator of text chunking, embedding generation, and search context retrieval isolated to MainActor
@MainActor
final class RAGService {
    private let embeddingService: any EmbeddingProvider
    private let vectorStore = VectorStore()
    
    init() {
        self.embeddingService = EmbeddingService()
    }
    
    init(embeddingService: any EmbeddingProvider) {
        self.embeddingService = embeddingService
    }
    
    /// Helper to split text into sliding window child chunks
    private func splitIntoChunks(_ text: String, size: Int, overlap: Int) -> [String] {
        var chunks: [String] = []
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }
        
        var i = 0
        while i < characters.count {
            let endIdx = min(i + size, characters.count)
            let chunk = String(characters[i..<endIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(chunk)
            }
            if endIdx == characters.count { break }
            i += (size - overlap)
        }
        return chunks
    }
    
    /// Chunks the segments of a meeting and indexes them (generates embeddings for child chunks).
    func indexMeeting(meeting: Meeting, modelContext: ModelContext) async throws {
        // Clear any existing child embeddings for this meeting to prevent duplicates
        let meetingID = meeting.id
        let descriptor = FetchDescriptor<ChildEmbeddingEntity>()
        let allEntities = try modelContext.fetch(descriptor)
        let existing = allEntities.filter { $0.meeting?.id == meetingID || $0.parentSegment?.meeting?.id == meetingID }
        for entity in existing {
            modelContext.delete(entity)
        }
        try modelContext.save()
        
        // Clear old FTS indexes for this meeting
        let segmentIDs = meeting.transcriptSegments.map { $0.id }
        if !segmentIDs.isEmpty {
            await vectorStore.clearFTSIndex(for: segmentIDs)
        }
        
        let segments = meeting.transcriptSegments.sorted(by: { $0.startTime < $1.startTime })
        guard !segments.isEmpty else { return }
        
        for segment in segments {
            let parentText = "\(segment.speakerName ?? String(localized: "Невідомий")): \(segment.text)"
            guard !parentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            
            // Index the parent segment in FTS5
            await vectorStore.indexSegment(segmentID: segment.id, text: parentText, meetingTitle: meeting.title)
            
            // Split into child chunks (100-150 characters, sliding window with overlap)
            let childChunks = splitIntoChunks(parentText, size: 120, overlap: 30)
            
            for chunk in childChunks {
                do {
                    let vector = try await embeddingService.generateEmbedding(for: chunk)
                    let entity = ChildEmbeddingEntity(
                        vector: vector,
                        text: chunk,
                        startTime: Double(segment.startTime)
                    )
                    entity.parentSegment = segment
                    entity.meeting = meeting
                    modelContext.insert(entity)
                } catch {
                    AppLogger.error("Failed to generate embedding for child chunk: \(error.localizedDescription)")
                }
            }
        }
        
        try modelContext.save()
    }
    
    /// Queries a group of meetings, retrieves relevant chunks using Parent-Child matching, and returns the expanded context.
    func retrieveContext(
        query: String,
        group: MeetingGroup,
        modelContext: ModelContext,
        topK: Int = 5
    ) async throws -> (contextText: String, referencedItems: [VectorItem]) {
        let queryVector = try await embeddingService.generateEmbedding(for: query)
        
        let meetings = group.meetings
        let meetingIDs = Set(meetings.map { $0.id })
        guard !meetingIDs.isEmpty else { return ("", []) }
        
        var meetingTitles: [UUID: String] = [:]
        for meeting in meetings {
            meetingTitles[meeting.id] = meeting.title
        }
        
        // Fetch all ChildEmbeddingEntities for these meetings
        let descriptor = FetchDescriptor<ChildEmbeddingEntity>()
        let allEntities = try modelContext.fetch(descriptor)
        let groupEntities = allEntities.filter { entity in
            if let mID = entity.meeting?.id {
                return meetingIDs.contains(mID)
            }
            if let mID = entity.parentSegment?.meeting?.id {
                return meetingIDs.contains(mID)
            }
            return false
        }
        
        let items = groupEntities.map { entity in
            VectorItem(
                id: entity.id,
                meetingID: entity.meeting?.id ?? entity.parentSegment?.meeting?.id ?? UUID(),
                segmentID: entity.parentSegment?.id,
                textChunk: entity.text,
                vector: entity.vector,
                startIndex: 0
            )
        }
        
        guard !items.isEmpty else { return ("", []) }
        
        // Find similar child chunks using Hybrid Search (FTS5 + Cosine Similarity with RRF)
        let matches = await vectorStore.searchHybrid(query: query, queryVector: queryVector, in: items, topK: topK)
        
        var context = ""
        var referenced: [VectorItem] = []
        
        // Build expanded context windows for parent segments
        var processedSegmentIDs = Set<UUID>()
        
        for (index, match) in matches.enumerated() {
            referenced.append(match.item)
            
            guard let segmentID = match.item.segmentID else {
                // If no parent segment, just append the child text chunk
                let meetingTitle = meetingTitles[match.item.meetingID] ?? "Нарада"
                context += "[Джерело \(index + 1): \(meetingTitle)]\n\(match.item.textChunk)\n\n"
                continue
            }
            
            // Skip if we already processed this segment's window
            guard !processedSegmentIDs.contains(segmentID) else { continue }
            processedSegmentIDs.insert(segmentID)
            
            // Fetch parent segment
            let segmentDescriptor = FetchDescriptor<TranscriptSegment>()
            let allSegments = try modelContext.fetch(segmentDescriptor)
            guard let parentSegment = allSegments.first(where: { $0.id == segmentID }),
                  let meeting = parentSegment.meeting else { continue }
            
            let meetingTitle = meetingTitles[meeting.id] ?? meeting.title
            
            // Fetch all segments in this meeting and sort them chronologically
            let sortedSegments = meeting.transcriptSegments.sorted(by: { $0.startTime < $1.startTime })
            
            if let parentIndex = sortedSegments.firstIndex(where: { $0.id == segmentID }) {
                // Get window of +/- 2 segments
                let startIndex = max(0, parentIndex - 2)
                let endIndex = min(sortedSegments.count - 1, parentIndex + 2)
                
                let windowSegments = sortedSegments[startIndex...endIndex]
                
                // Construct context block
                var blockText = ""
                for winSeg in windowSegments {
                    processedSegmentIDs.insert(winSeg.id) // Avoid repeating segments in other hits
                    blockText += "\(winSeg.displayName): \(winSeg.text)\n"
                }
                
                context += """
                [Джерело: \(meetingTitle)]
                \(blockText.trimmingCharacters(in: .whitespacesAndNewlines))
                
                """
            }
        }
        
        return (context.trimmingCharacters(in: .whitespacesAndNewlines), referenced)
    }
}
