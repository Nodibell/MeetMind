//
//  MeetingTranscriptSegment.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation

/// A single segment of transcribed speech with timing information
struct MeetingTranscriptSegment: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let speakerID: String?
    let speakerName: String?
    let language: String?
    
    nonisolated init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        speakerID: String? = nil,
        speakerName: String? = nil,
        language: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.speakerID = speakerID
        self.speakerName = speakerName
        self.language = language
    }
    
    /// Formatted timestamp range: "00:15 – 00:32"
    var timestampRange: String {
        "\(startTime.formattedTimestamp) – \(endTime.formattedTimestamp)"
    }
    
    /// Duration of this segment
    var duration: TimeInterval {
        endTime - startTime
    }

    /// Display name with localization support
    var displayName: String {
        if let name = speakerName, !name.isEmpty { return name }
        guard let id = speakerID else { return String(localized: "Невідомий") }
        
        // Localize "Speaker X" if it matches the pattern
        if id.hasPrefix("Speaker "), let range = id.range(of: #"\d+"#, options: .regularExpression) {
            let number = String(id[range])
            return String(localized: "Спікер \(number)")
        }
        
        return id
    }
}

// MARK: - Transcript Document

/// Full transcript containing multiple segments
struct MeetingTranscriptDocument: Codable, Sendable {
    let meetingId: UUID
    let createdAt: Date
    let language: String
    let segments: [MeetingTranscriptSegment]
    
    /// Full text with no timestamps
    var fullText: String {
        segments.map(\.text).joined(separator: " ")
    }
    
    /// Full text with speaker labels
    var fullTextWithSpeakers: String {
        segments.map { segment in
            return "\(segment.displayName): \(segment.text)"
        }.joined(separator: "\n")
    }
    
    /// Full text with timestamps
    var formattedText: String {
        segments.map { segment in
            "[\(segment.startTime.formattedTimestamp)] \(segment.text)"
        }.joined(separator: "\n")
    }
    
    /// Total duration
    var totalDuration: TimeInterval {
        guard let last = segments.last else { return 0 }
        return last.endTime
    }
    
    /// Save to file
    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
    
    /// Load from file
    static func load(from url: URL) throws -> MeetingTranscriptDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MeetingTranscriptDocument.self, from: data)
    }
}
