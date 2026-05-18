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
    /// Synchronizes SwiftData entities from associated transcripts and summaries
    func syncStructuredEntities(modelContext: ModelContext) {
        // 1. Sync TranscriptSegments from JSON file
        if let url = transcriptURL,
           let doc = try? MeetingTranscriptDocument.load(from: url) {
            
            // Remove existing segments
            for segment in transcriptSegments {
                modelContext.delete(segment)
            }
            transcriptSegments.removeAll()
            
            // Add new segments
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
        
        // 2. Sync ActionItems and Decisions from summary markdown file
        if let url = summaryURL,
           let summary = try? String(contentsOf: url, encoding: .utf8) {
            
            // Remove existing action items and decisions
            for item in actionItems {
                modelContext.delete(item)
            }
            actionItems.removeAll()
            
            for dec in decisions {
                modelContext.delete(dec)
            }
            decisions.removeAll()
            
            let lines = summary.components(separatedBy: CharacterSet.newlines)
            var inDecisionsSection = false
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                
                // Track section headers
                if trimmed.localizedCaseInsensitiveContains("рішення") || trimmed.localizedCaseInsensitiveContains("decisions") {
                    inDecisionsSection = true
                    continue
                } else if trimmed.hasPrefix("#") {
                    inDecisionsSection = false
                }
                
                // Parse Action Items: - [ ] or - [x]
                if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") {
                    let isDone = trimmed.hasPrefix("- [x]")
                    var text = trimmed.replacingOccurrences(of: "- [ ]", with: "")
                                      .replacingOccurrences(of: "- [x]", with: "")
                                      .trimmingCharacters(in: CharacterSet.whitespaces)
                    
                    // Extract assignee
                    var assignee: String? = nil
                    let regexAssignee = try? NSRegularExpression(pattern: #"\(([^)]+)\)$|@(\w+)$"#, options: [])
                    if let match = regexAssignee?.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
                        if let range = Range(match.range(at: 1), in: text) ?? Range(match.range(at: 2), in: text) {
                            assignee = String(text[range])
                            text = text.replacingCharacters(in: Range(match.range, in: text)!, with: "").trimmingCharacters(in: CharacterSet.whitespaces)
                        }
                    }
                    
                    if !text.isEmpty {
                        let action = ActionItem(
                            id: UUID(),
                            text: text,
                            dueDate: nil,
                            isCompleted: isDone,
                            assignee: assignee
                        )
                        action.meeting = self
                        actionItems.append(action)
                    }
                }
                // Parse Decisions: if inside decisions section and starts with bullet point
                else if inDecisionsSection && (trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("•")) {
                    let text = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "-*• ")).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        let decision = Decision(
                            id: UUID(),
                            text: text,
                            context: nil
                        )
                        decision.meeting = self
                        decisions.append(decision)
                    }
                }
            }
        }
        
        try? modelContext.save()
    }
}

