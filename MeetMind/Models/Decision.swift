//
//  Decision.swift
//  MeetMind
//
//  Created by Developer on 18.05.2026.
//

import Foundation
import SwiftData

@Model
final class Decision {
    var id: UUID
    var text: String
    var context: String?
    
    var meeting: Meeting?
    
    init(
        id: UUID = UUID(),
        text: String,
        context: String? = nil
    ) {
        self.id = id
        self.text = text
        self.context = context
    }
}
