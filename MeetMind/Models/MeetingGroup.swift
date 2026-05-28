//
//  MeetingGroup.swift
//  MeetMind
//
//  Created by Developer on 28.05.2026.
//

import Foundation
import SwiftData

/// A SwiftData Model representing a folder or project grouping of meetings
@Model
final class MeetingGroup {
    var id: UUID
    var name: String
    var customDescription: String?
    var createdAt: Date
    
    @Relationship(inverse: \Meeting.groups) var meetings: [Meeting] = []
    
    init(
        name: String = "Нова група",
        customDescription: String? = nil,
        meetings: [Meeting] = []
    ) {
        self.id = UUID()
        self.name = name
        self.customDescription = customDescription
        self.createdAt = .now
        self.meetings = meetings
    }
}
