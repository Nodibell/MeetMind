//
//  TranscriptSegmentModel.swift
//  MeetMind
//
//  Created by Developer on 18.05.2026.
//

import Foundation
import SwiftData

@Model
final class TranscriptSegment {
    var id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var speakerID: String?
    var speakerName: String?
    var language: String?
    
    var meeting: Meeting?
    
    init(
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
    
    var timestampRange: String {
        "\(startTime.formattedTimestamp) – \(endTime.formattedTimestamp)"
    }
    
    var duration: TimeInterval {
        endTime - startTime
    }
    
    var displayName: String {
        if let name = speakerName, !name.isEmpty { return name }
        guard let id = speakerID else { return String(localized: "Невідомий") }
        if id.hasPrefix("Speaker "), let range = id.range(of: #"\d+"#, options: .regularExpression) {
            let number = String(id[range])
            return String(localized: "Спікер \(number)")
        }
        return id
    }
}
