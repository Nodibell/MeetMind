//
//  ActionItem.swift
//  MeetMind
//
//  Created by Developer on 18.05.2026.
//

import Foundation
import SwiftData

@Model
final class ActionItem {
    var id: UUID
    var text: String
    var dueDate: Date?
    var isCompleted: Bool
    var assignee: String?
    
    var meeting: Meeting?
    
    init(
        id: UUID = UUID(),
        text: String,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        assignee: String? = nil
    ) {
        self.id = id
        self.text = text
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.assignee = assignee
    }
}
