//
//  GroupChatMessageEntity.swift
//  MeetMind
//
//  Created by Developer on 28.05.2026.
//

import Foundation
import SwiftData

/// A SwiftData Model representing a single persisted chat message in a group chat session
@Model
final class GroupChatMessageEntity {
    var id: UUID
    var role: String // "user" or "assistant"
    var content: String
    var timestamp: Date
    var sourcesData: Data? // JSON data representing array of VectorItem
    
    var group: MeetingGroup?
    var session: GroupChatSessionEntity?
    
    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        timestamp: Date = .now,
        sources: [VectorItem]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        if let sources {
            self.sourcesData = try? JSONEncoder().encode(sources)
        } else {
            self.sourcesData = nil
        }
    }
    
    var sources: [VectorItem]? {
        guard let data = sourcesData else { return nil }
        return try? JSONDecoder().decode([VectorItem].self, from: data)
    }
}
