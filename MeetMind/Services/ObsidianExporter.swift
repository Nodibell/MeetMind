//
//  ObsidianExporter.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation

/// Exports meeting notes to Obsidian vault in Markdown format
struct ObsidianExporter: Sendable {
    
    // MARK: - Export
    
    /// Export a meeting to Obsidian vault
    static func export(
        meeting: MeetingSummaryData,
        to vaultURL: URL
    ) throws -> URL {
        // Request access to security-scoped resource
        AppLogger.info("Requesting access to Obsidian folder: \(vaultURL.lastPathComponent)")
        let accessGranted = vaultURL.startAccessingSecurityScopedResource()
        
        if accessGranted {
            AppLogger.info("Access to Obsidian folder granted")
        } else {
            AppLogger.warning("Access to Obsidian folder NOT granted (permission may be stale)")
        }
        
        defer {
            if accessGranted {
                vaultURL.stopAccessingSecurityScopedResource()
                AppLogger.info("Access to Obsidian folder released")
            }
        }
        
        let meetingsDir = vaultURL.appendingPathComponent(Constants.obsidianMeetingsFolder)
        
        // Create Meetings directory if needed
        try FileManager.default.createDirectory(at: meetingsDir, withIntermediateDirectories: true)
        
        // Generate filename
        let filename = "\(meeting.date.filenameDateFormatted) - \(meeting.title.filenameSafe).md"
        var fileURL = meetingsDir.appendingPathComponent(filename)
        
        // Handle duplicates
        fileURL = fileURL.uniqueFileURL()
        
        // Generate content
        let content = generateMarkdown(for: meeting)
        
        // Write file
        AppLogger.info("Writing file to Obsidian: \(fileURL.lastPathComponent)")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        AppLogger.info("Export to Obsidian completed successfully")
        
        return fileURL
    }
    
    // MARK: - Markdown Generation
    
    private static func generateMarkdown(for meeting: MeetingSummaryData) -> String {
        var md = ""
        
        // YAML Frontmatter
        md += "---\n"
        md += "title: \(meeting.title)\n"
        md += "date: \(meeting.date.isoFormatted)\n"
        md += "tags: [\(meeting.tags.map { "\($0)" }.joined(separator: ", "))]\n"
        md += "language: \(meeting.language)\n"
        md += "duration: \(meeting.duration.formattedDuration)\n"
        md += "---\n\n"
        
        // Title
        md += "# \(meeting.title)\n\n"
        
        // Transcript
        md += "## Транскрипт\n\n"
        if let transcript = meeting.transcript {
            md += transcript
        } else {
            md += "_Транскрипт відсутній_"
        }
        md += "\n\n---\n\n"
        
        // Summary
        if let summary = meeting.summary {
            md += summary
        } else {
            md += "## Резюме\n\n_Резюме ще не створено_\n\n"
            md += "## Завдання\n\n_Немає_\n\n"
            md += "## Рішення\n\n_Немає_\n\n"
            md += "## Відкриті питання\n\n_Немає_\n\n"
            md += "## Ризики / Незрозумілі моменти\n\n_Немає_\n"
        }
        
        return md
    }
}

// MARK: - Data Transfer Object

/// Data needed for Obsidian export (decouples from SwiftData model)
struct MeetingSummaryData: Sendable {
    let title: String
    let date: Date
    let duration: TimeInterval
    let language: String
    let tags: [String]
    let transcript: String?
    let summary: String?
}
