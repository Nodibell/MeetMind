//
//  ExportMeetingUseCase.swift
//  MeetMind
//
//  Consolidates Obsidian export logic that was previously duplicated in:
//  - RecordingViewModel.exportToObsidian()
//  - MeetingDetailViewModel.exportToObsidian()
//

import Foundation

// MARK: - ExportMeetingUseCase

/// Exports a meeting to an Obsidian vault as a Markdown note.
/// Has no SwiftData or SwiftUI dependency — can be unit-tested in isolation.
struct ExportMeetingUseCase {

    // MARK: - Errors

    enum ExportError: LocalizedError {
        case vaultPathNotConfigured
        case exportFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .vaultPathNotConfigured:
                return "Шлях до Obsidian vault не налаштовано. Вкажіть його в Налаштуваннях."
            case .exportFailed(let error):
                return "Помилка експорту в Obsidian: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Execute

    /// Exports the meeting to the configured Obsidian vault.
    /// - Parameters:
    ///   - meeting: The `Meeting` SwiftData object.
    ///   - transcript: Loaded transcript document (optional).
    ///   - summary: The summary text (may be empty).
    ///   - vaultURL: The target vault directory URL.
    /// - Returns: The URL of the created Markdown file.
    @discardableResult
    func execute(
        meeting: Meeting,
        transcript: MeetingTranscriptDocument?,
        summary: String,
        vaultURL: URL
    ) throws -> URL {
        let transcriptText = transcript?.formattedText
            ?? meeting.transcriptURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            ?? ""

        let data = MeetingSummaryData(
            title: meeting.title,
            date: meeting.date,
            duration: meeting.duration,
            language: transcript?.language ?? meeting.language,
            tags: meeting.tags.isEmpty ? ["meeting"] : meeting.tags,
            transcript: transcriptText.isEmpty ? nil : transcriptText,
            summary: summary.isEmpty ? nil : summary
        )

        do {
            return try ObsidianExporter.export(meeting: data, to: vaultURL)
        } catch {
            throw ExportError.exportFailed(underlying: error)
        }
    }

    /// Convenience overload that reads the vault URL from `AppSettings`.
    @discardableResult
    func execute(
        meeting: Meeting,
        transcript: MeetingTranscriptDocument?,
        summary: String
    ) throws -> URL {
        guard let vaultURL = AppSettings.shared.obsidianVaultPath else {
            throw ExportError.vaultPathNotConfigured
        }
        return try execute(
            meeting: meeting,
            transcript: transcript,
            summary: summary,
            vaultURL: vaultURL
        )
    }
}
