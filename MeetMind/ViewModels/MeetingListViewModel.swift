//
//  MeetingListViewModel.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation
import SwiftData

/// Manages the list of meetings with search and filter
@Observable
final class MeetingListViewModel {
    
    enum SortOption: String, CaseIterable, Identifiable {
        case date = "За датою"
        case title = "За назвою"
        case duration = "За тривалістю"
        var id: String { rawValue }
    }
    
    var searchText: String = ""
    var sortOption: SortOption = .date
    var errorMessage: String?
    
    private var modelContext: ModelContext?
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Delete Meeting
    
    func deleteMeeting(_ meeting: Meeting) {
        // Clean up associated files
        let fm = FileManager.default
        
        if let audioPath = meeting.audioPath {
            try? fm.removeItem(atPath: audioPath)
        }
        if let transcriptPath = meeting.transcriptPath {
            try? fm.removeItem(atPath: transcriptPath)
        }
        if let summaryPath = meeting.summaryPath {
            try? fm.removeItem(atPath: summaryPath)
        }
        
        modelContext?.delete(meeting)
        try? modelContext?.save()
    }
    
    // MARK: - Update Title
    
    func updateTitle(for meeting: Meeting, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        meeting.title = trimmed
        try? modelContext?.save()
    }
}
