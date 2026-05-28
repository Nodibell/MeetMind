//
//  VectorEmbeddingEntity.swift
//  MeetMind
//
//  Created by Developer on 28.05.2026.
//

import Foundation
import SwiftData

/// A SwiftData Model representing a text chunk of a meeting transcript and its vector embedding
@Model
final class VectorEmbeddingEntity {
    var id: UUID
    var meetingID: UUID
    var segmentID: UUID?
    var textChunk: String
    var vector: [Float]
    var startIndex: Int
    
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
