//
//  RAGService.swift
//  MeetMind
//
//  Created by Developer on 28.05.2026.
//

import Foundation
import SwiftData

/// Local actor coordinating text chunking, embedding generation, and search context retrieval
actor RAGService {
    private let embeddingService = EmbeddingService()
    private let vectorStore = VectorStore()
    
    /// Chunks the segments of a meeting and indexes them (generates embeddings and saves VectorEmbeddingEntity records).
    func indexMeeting(meeting: Meeting, modelContext: ModelContext) async throws {
        // Clear any existing embeddings for this meeting to prevent duplicates
        let meetingID = meeting.id
        let descriptor = FetchDescriptor<VectorEmbeddingEntity>()
        let allEntities = try modelContext.fetch(descriptor)
        let existing = allEntities.filter { $0.meetingID == meetingID }
        for entity in existing {
            modelContext.delete(entity)
        }
        try modelContext.save()
        
        let segments = meeting.transcriptSegments.sorted(by: { $0.startTime < $1.startTime })
        guard !segments.isEmpty else { return }
        
        var currentChunkText = ""
        var currentChunkSegments: [TranscriptSegment] = []
        var chunkStartIndex = 0
        
        var chunksToEmbed: [(text: String, firstSegmentID: UUID?, startIndex: Int)] = []
        
        for (index, segment) in segments.enumerated() {
            let segmentText = "\(segment.speakerName ?? "Невідомий"): \(segment.text)\n"
            
            if currentChunkText.isEmpty {
                chunkStartIndex = index
            }
            
            currentChunkText += segmentText
            currentChunkSegments.append(segment)
            
            // If combined text is over 500 characters or this is the last segment, flush chunk
            if currentChunkText.count >= 500 || index == segments.count - 1 {
                chunksToEmbed.append(
                    (
                        text: currentChunkText.trimmingCharacters(in: .whitespacesAndNewlines),
                        firstSegmentID: currentChunkSegments.first?.id,
                        startIndex: chunkStartIndex
                    )
                )
                
                // Start a new chunk, with some overlap (keep the last 1 segment as overlap)
                if currentChunkSegments.count > 1 {
                    let lastSegment = currentChunkSegments.last!
                    currentChunkText = "\(lastSegment.speakerName ?? "Невідомий"): \(lastSegment.text)\n"
                    currentChunkSegments = [lastSegment]
                    chunkStartIndex = index
                } else {
                    currentChunkText = ""
                    currentChunkSegments = []
                }
            }
        }
        
        // Generate embeddings for chunks and insert into modelContext
        for chunk in chunksToEmbed {
            do {
                let vector = try await embeddingService.generateEmbedding(for: chunk.text)
                let entity = VectorEmbeddingEntity(
                    meetingID: meetingID,
                    segmentID: chunk.firstSegmentID,
                    textChunk: chunk.text,
                    vector: vector,
                    startIndex: chunk.startIndex
                )
                modelContext.insert(entity)
            } catch {
                AppLogger.error("Failed to generate embedding for chunk: \(error.localizedDescription)")
            }
        }
        
        try modelContext.save()
    }
    
    /// Queries a group of meetings, retrieves relevant chunks, and returns the constructed context.
    func retrieveContext(
        query: String,
        group: MeetingGroup,
        modelContext: ModelContext,
        topK: Int = 5
    ) async throws -> (contextText: String, referencedItems: [VectorItem]) {
        let queryVector = try await embeddingService.generateEmbedding(for: query)
        
        let meetingIDs = Set(group.meetings.map { $0.id })
        guard !meetingIDs.isEmpty else { return ("", []) }
        
        // Fetch all vector embedding entities
        let descriptor = FetchDescriptor<VectorEmbeddingEntity>()
        let allEntities = try modelContext.fetch(descriptor)
        let groupEntities = allEntities.filter { meetingIDs.contains($0.meetingID) }
        
        // Convert to lightweight VectorItem structs
        let items = groupEntities.map { entity in
            VectorItem(
                id: entity.id,
                meetingID: entity.meetingID,
                segmentID: entity.segmentID,
                textChunk: entity.textChunk,
                vector: entity.vector,
                startIndex: entity.startIndex
            )
        }
        
        let matches = await vectorStore.findSimilarChunks(queryVector: queryVector, in: items, topK: topK)
        
        var context = ""
        var referenced: [VectorItem] = []
        
        for (index, match) in matches.enumerated() {
            // Find meeting title
            let meetingTitle = group.meetings.first(where: { $0.id == match.item.meetingID })?.title ?? "Нарада"
            
            context += """
            [Джерело \(index + 1): \(meetingTitle)]
            \(match.item.textChunk)
            
            """
            
            referenced.append(match.item)
        }
        
        return (context.trimmingCharacters(in: .whitespacesAndNewlines), referenced)
    }
}
