//
//  GroupChatSessionEntity.swift
//  MeetMind
//
//  Created by Developer on 29.05.2026.
//

import Foundation
import SwiftData

/// A SwiftData Model representing a single saved conversation thread (chat session) inside a meeting group
@Model
final class GroupChatSessionEntity {
    var id: UUID
    var title: String
    var createdAt: Date
    
    var group: MeetingGroup?
    
    @Relationship(deleteRule: .cascade, inverse: \GroupChatMessageEntity.session) 
    var chatMessages: [GroupChatMessageEntity] = []
    
    init(id: UUID = UUID(), title: String = "Нова розмова", createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
    }
}
