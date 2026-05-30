//
//  MeetingRepository.swift
//  MeetMind
//
//  Single point of access for all Meeting persistence operations.
//  Eliminates 23 scattered `try? modelContext?.save()` calls across ViewModels.
//

import SwiftData
import Foundation

// MARK: - MeetingRepository

/// Centralises all `Meeting` SwiftData read/write operations.
///
/// ViewModels receive this repository and call its methods instead of
/// holding a raw `ModelContext` and calling `save()` directly.
///
/// Usage:
/// ```swift
/// let repo = MeetingRepository(context: modelContext)
/// try repo.save()
/// let meetings = try repo.fetchAll()
/// ```
@MainActor
final class MeetingRepository {

    // MARK: - Dependencies

    private let context: ModelContext

    // MARK: - Init

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Write

    /// Inserts a new meeting into the store and saves.
    func insert(_ meeting: Meeting) throws {
        context.insert(meeting)
        try save()
    }

    /// Persists all pending changes.
    /// Uses `try?` internally so callers don't need to handle unlikely save errors,
    /// but logs them for diagnostics.
    @discardableResult
    func save() throws -> Bool {
        do {
            try context.save()
            return true
        } catch {
            AppLogger.error("MeetingRepository.save() failed: \(error)")
            throw error
        }
    }

    /// Soft save — logs errors but does not propagate them.
    /// Use for non-critical updates where data loss is acceptable (e.g. UI-only state).
    func trySave() {
        do { try context.save() } catch {
            AppLogger.error("MeetingRepository.trySave() silently failed: \(error)")
        }
    }

    /// Deletes a meeting and all its cascade-related entities, then saves.
    func delete(_ meeting: Meeting) throws {
        context.delete(meeting)
        try save()
    }

    // MARK: - Read

    /// Fetches all meetings, sorted by date descending.
    func fetchAll() throws -> [Meeting] {
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Fetches a single meeting by its stable UUID.
    func fetch(by id: UUID) throws -> Meeting? {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    // MARK: - Structured Entity Sync

    /// Re-syncs transcript segments, action items, and decisions for a meeting
    /// from its associated files. Delegates parsing to `ParseSummaryUseCase`.
    func syncStructuredEntities(for meeting: Meeting) throws {
        let parser = ParseSummaryUseCase()

        // 1. Sync TranscriptSegments from JSON
        if let url = meeting.transcriptURL,
           let doc = try? MeetingTranscriptDocument.load(from: url) {
            
            // Sync speaker centroids to meeting metadata
            if let centroids = doc.speakerCentroids {
                for (speakerID, centroid) in centroids {
                    if let index = meeting.speakerMetadata.firstIndex(where: { $0.id == speakerID }) {
                        meeting.speakerMetadata[index].voiceCentroid = centroid
                    } else {
                        meeting.speakerMetadata.append(SpeakerMetadata(id: speakerID, name: nil, colorHex: nil, voiceCentroid: centroid))
                    }
                }
            }

            meeting.transcriptSegments.forEach { context.delete($0) }
            meeting.transcriptSegments.removeAll()

            for seg in doc.segments {
                let segment = TranscriptSegment(
                    id: seg.id,
                    startTime: seg.startTime,
                    endTime: seg.endTime,
                    text: seg.text,
                    speakerID: seg.speakerID,
                    speakerName: seg.speakerName,
                    language: seg.language,
                    suggestedSpeakerName: seg.suggestedSpeakerName
                )
                segment.meeting = meeting
                meeting.transcriptSegments.append(segment)
            }
        }

        // 2. Sync ActionItems and Decisions from markdown summary
        if let url = meeting.summaryURL,
           let markdown = try? String(contentsOf: url, encoding: .utf8) {

            meeting.actionItems.forEach { context.delete($0) }
            meeting.actionItems.removeAll()
            meeting.decisions.forEach { context.delete($0) }
            meeting.decisions.removeAll()

            for dto in parser.extractActionItems(from: markdown) {
                let item = ActionItem(
                    id: UUID(),
                    text: dto.text,
                    dueDate: nil,
                    isCompleted: dto.isCompleted,
                    assignee: dto.assignee
                )
                item.meeting = meeting
                meeting.actionItems.append(item)
            }

            for dto in parser.extractDecisions(from: markdown) {
                let decision = Decision(id: UUID(), text: dto.text, context: nil)
                decision.meeting = meeting
                meeting.decisions.append(decision)
            }
        }

        try save()
    }
}
