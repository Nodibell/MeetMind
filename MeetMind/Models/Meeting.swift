//
//  Meeting.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation
import SwiftData

// MARK: - Meeting Status
enum MeetingStatus: String, Codable, CaseIterable, Sendable {
    case recording = "recording"
    case transcribing = "transcribing"
    case summarizing = "summarizing"
    case complete = "complete"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .recording: return "Запис"
        case .transcribing: return "Транскрипція"
        case .summarizing: return "Аналіз"
        case .complete: return "Завершено"
        case .error: return "Помилка"
        }
    }
    
    var systemImage: String {
        switch self {
        case .recording: return "record.circle.fill"
        case .transcribing: return "waveform"
        case .summarizing: return "brain.head.profile"
        case .complete: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Meeting Model
@Model
final class Meeting {
    var id: UUID
    var title: String
    var date: Date
    var duration: TimeInterval
    var language: String
    var tags: [String]
    var transcriptFilename: String?
    var summaryFilename: String?
    var summaryLanguage: String? // Language selected for THIS meeting's summary
    var audioFilename: String?
    @Attribute var statusRaw: String
    var isExportedToObsidian: Bool
    var errorMessage: String?
    var speakerMetadata: [SpeakerMetadata] = []
    
    @Relationship(deleteRule: .cascade) var transcriptSegments: [TranscriptSegment] = []
    @Relationship(deleteRule: .cascade) var actionItems: [ActionItem] = []
    @Relationship(deleteRule: .cascade) var decisions: [Decision] = []
    @Relationship var groups: [MeetingGroup] = []
    
    var status: MeetingStatus {
        get { MeetingStatus(rawValue: statusRaw) ?? .error }
        set { statusRaw = newValue.rawValue }
    }
    
    init(
        title: String = "Нова нарада",
        date: Date = .now,
        duration: TimeInterval = 0,
        language: String = Constants.defaultLanguage,
        tags: [String] = [],
        status: MeetingStatus = .recording
    ) {
        self.id = UUID()
        self.title = title
        self.date = date
        self.duration = duration
        self.language = language
        self.tags = tags
        self.statusRaw = status.rawValue
        self.isExportedToObsidian = false
    }
    
    // MARK: - Computed Properties
    
    var transcriptURL: URL? {
        guard let name = transcriptFilename else { return nil }
        return Constants.transcriptsDirectory.appendingPathComponent(name)
    }
    
    var summaryURL: URL? {
        guard let name = summaryFilename else { return nil }
        return Constants.summariesDirectory.appendingPathComponent(name)
    }
    
    var audioURL: URL? {
        guard let name = audioFilename else { return nil }
        return Constants.recordingsDirectory.appendingPathComponent(name)
    }
    
    var displayDate: String {
        date.shortDisplayFormatted
    }
    
    var displayDuration: String {
        duration.formattedDuration
    }

    var filenameBase: String {
        "\(date.filenameDateFormatted) - \(title.filenameSafe) - \(id.uuidString.prefix(6))"
    }
}

// MARK: - Structured Entities Sync Extension
extension Meeting {
    /// - Warning: Deprecated. Use `MeetingRepository.syncStructuredEntities(for:)` instead.
    ///   This method mixes persistence concerns with the domain model.
    ///   Retained for backward compatibility only.
    @available(*, deprecated, message: "Use MeetingRepository.syncStructuredEntities(for:) instead.")
    func syncStructuredEntities(modelContext: ModelContext) {
        let parser = ParseSummaryUseCase()

        // 1. Sync TranscriptSegments from JSON file
        if let url = transcriptURL,
           let doc = try? MeetingTranscriptDocument.load(from: url) {

            for segment in transcriptSegments { modelContext.delete(segment) }
            transcriptSegments.removeAll()

            for seg in doc.segments {
                let segment = TranscriptSegment(
                    id: seg.id,
                    startTime: seg.startTime,
                    endTime: seg.endTime,
                    text: seg.text,
                    speakerID: seg.speakerID,
                    speakerName: seg.speakerName,
                    language: seg.language
                )
                segment.meeting = self
                transcriptSegments.append(segment)
            }
        }

        // 2. Sync ActionItems and Decisions from summary markdown
        if let url = summaryURL,
           let markdown = try? String(contentsOf: url, encoding: .utf8) {

            for item in actionItems { modelContext.delete(item) }
            actionItems.removeAll()
            for dec in decisions { modelContext.delete(dec) }
            decisions.removeAll()

            for dto in parser.extractActionItems(from: markdown) {
                let action = ActionItem(
                    id: UUID(), text: dto.text, dueDate: nil,
                    isCompleted: dto.isCompleted, assignee: dto.assignee
                )
                action.meeting = self
                actionItems.append(action)
            }
            for dto in parser.extractDecisions(from: markdown) {
                let decision = Decision(id: UUID(), text: dto.text, context: nil)
                decision.meeting = self
                decisions.append(decision)
            }
        }

        try? modelContext.save()
    }
}
