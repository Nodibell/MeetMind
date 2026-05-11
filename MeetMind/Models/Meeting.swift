//
//  Meeting.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation
import SwiftData

// MARK: - Meeting Status
enum MeetingStatus: String, Codable, CaseIterable, Sendable {
    case recording = "recording"
    case transcribing = "transcribing"
    case summarizing = "summarizing"
    case complete = "complete"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .recording: return "Запис"
        case .transcribing: return "Транскрипція"
        case .summarizing: return "Аналіз"
        case .complete: return "Завершено"
        case .error: return "Помилка"
        }
    }
    
    var systemImage: String {
        switch self {
        case .recording: return "record.circle.fill"
        case .transcribing: return "waveform"
        case .summarizing: return "brain.head.profile"
        case .complete: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Meeting Model
@Model
final class Meeting {
    var id: UUID
    var title: String
    var date: Date
    var duration: TimeInterval
    var language: String
    var tags: [String]
    var transcriptPath: String?
    var summaryPath: String?
    var summaryLanguage: String? // Language selected for THIS meeting's summary
    var audioPath: String?
    @Attribute var statusRaw: String
    var isExportedToObsidian: Bool
    var errorMessage: String?
    
    var status: MeetingStatus {
        get { MeetingStatus(rawValue: statusRaw) ?? .error }
        set { statusRaw = newValue.rawValue }
    }
    
    init(
        title: String = "Нова нарада",
        date: Date = .now,
        duration: TimeInterval = 0,
        language: String = Constants.defaultLanguage,
        tags: [String] = [],
        status: MeetingStatus = .recording
    ) {
        self.id = UUID()
        self.title = title
        self.date = date
        self.duration = duration
        self.language = language
        self.tags = tags
        self.statusRaw = status.rawValue
        self.isExportedToObsidian = false
    }
    
    // MARK: - Computed Properties
    
    var displayDate: String {
        date.shortDisplayFormatted
    }
    
    var displayDuration: String {
        duration.formattedDuration
    }
    
    var filenameBase: String {
        "\(date.filenameDateFormatted) - \(title.filenameSafe) - \(id.uuidString.prefix(6))"
    }
}
