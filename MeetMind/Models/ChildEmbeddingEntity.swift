//
//  ChildEmbeddingEntity.swift
//  MeetMind
//
//  Created by Developer on 30.05.2026.
//

import Foundation
import SwiftData

@Model
final class ChildEmbeddingEntity {
    @Attribute(.unique) var id: UUID
    var vector: [Float]
    var text: String
    var startTime: TimeInterval
    
    // Parent relationship (to TranscriptSegment parent chunk)
    var parentSegment: TranscriptSegment?
    var meeting: Meeting?
    
    init(
        id: UUID = UUID(),
        vector: [Float],
        text: String,
        startTime: Double
    ) {
        self.id = id
        self.vector = vector
        self.text = text
        self.startTime = startTime
    }
}
