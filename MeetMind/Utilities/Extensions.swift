//
//  Extensions.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation
import SwiftUI
import CryptoKit

// MARK: - TimeInterval Formatting
extension TimeInterval {
    /// Formats as "HH:MM:SS"
    var formattedDuration: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    /// Formats as "MM:SS.ms" for transcript timestamps
    var formattedTimestamp: String {
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Date Formatting
extension Date {
    /// ISO 8601 format: "2026-05-06T16:45:00+03:00"
    var isoFormatted: String {
        ISO8601DateFormatter().string(from: self)
    }
    
    /// Display format: "6 травня 2026" (Ukrainian locale)
    var displayFormatted: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
    
    /// Short display: "06.05.2026, 16:45"
    var shortDisplayFormatted: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        return formatter.string(from: self)
    }
    
    /// Filename-safe format: "2026-05-06"
    var filenameDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
    
    /// Relative time: "5 хв тому"
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - String Utilities
extension String {
    /// Makes string safe for use as a filename
    var filenameSafe: String {
        let invalidChars = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return self
            .components(separatedBy: invalidChars)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Truncates string to a maximum length with ellipsis
    func truncated(to maxLength: Int) -> String {
        if count <= maxLength { return self }
        return String(prefix(maxLength - 1)) + "…"
    }
    
    /// Detects the primary language of the string
    nonisolated var detectedLanguage: String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(self)
        return recognizer.dominantLanguage?.rawValue
    }
}

import NaturalLanguage

// MARK: - URL Utilities
extension URL {
    /// Creates a unique filename by appending a counter if file exists
    func uniqueFileURL() -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: self.path) else { return self }
        
        let directory = self.deletingLastPathComponent()
        let nameWithoutExtension = self.deletingPathExtension().lastPathComponent
        let ext = self.pathExtension
        
        var counter = 1
        var newURL: URL
        repeat {
            let newName = "\(nameWithoutExtension) (\(counter))"
            newURL = directory.appendingPathComponent(newName).appendingPathExtension(ext)
            counter += 1
        } while fm.fileExists(atPath: newURL.path)
        
        return newURL
    }
}

// MARK: - Data SHA-256 Hash
extension Data {
    nonisolated var sha256Hash: String {
        let hash = SHA256.hash(data: self)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Array Safe Subscript
extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Color from Tag String
extension String {
    var tagColor: Color {
        let hash = abs(self.hashValue)
        let index = hash % Theme.Colors.tagColors.count
        return Theme.Colors.tagColors[index]
    }
}
