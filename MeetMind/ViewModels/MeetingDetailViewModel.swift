//
//  MeetingDetailViewModel.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation
import SwiftData
import AppKit

/// ViewModel for viewing and managing a completed meeting
@Observable
final class MeetingDetailViewModel {
    
    // MARK: - State
    var meeting: Meeting
    var transcript: MeetingTranscriptDocument?
    var summary: String = ""
    var isLoadingTranscript = false
    var isLoadingSummary = false
    var isRegeneratingSummary = false
    var streamingSummary: String = ""
    var meetingTitle: String = ""
    var errorMessage: String?
    var searchText: String = ""
    var exportSuccess: Bool = false
    
    // MARK: - Services
    private let llmService: LLMService
    private var modelContext: ModelContext?
    private var summaryTask: Task<Void, Never>?
    
    // MARK: - Computed
    
    var filteredSegments: [MeetingTranscriptSegment] {
        guard let segments = transcript?.segments else { return [] }
        if searchText.isEmpty { return segments }
        return segments.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }
    
    // MARK: - Init
    
    init(meeting: Meeting, llmService: LLMService) {
        self.meeting = meeting
        self.meetingTitle = meeting.title
        self.llmService = llmService
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Load Data
    
    func loadData() async {
        await loadTranscript()
        await loadSummary()
    }
    
    private func loadTranscript() async {
        guard let path = meeting.transcriptPath else { return }
        let url = URL(fileURLWithPath: path)
        
        isLoadingTranscript = true
        defer { isLoadingTranscript = false }
        
        do {
            let document = try MeetingTranscriptDocument.load(from: url)
            await MainActor.run {
                self.transcript = document
            }
        } catch {
            errorMessage = "Не вдалося завантажити транскрипт: \(error.localizedDescription)"
        }
    }
    
    private func loadSummary() async {
        guard let path = meeting.summaryPath else { return }
        let url = URL(fileURLWithPath: path)
        
        isLoadingSummary = true
        defer { isLoadingSummary = false }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            await MainActor.run {
                self.summary = content
                self.streamingSummary = content
            }
        } catch {
            errorMessage = "Не вдалося завантажити резюме: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Chat State
    var chatMessages: [LLMService.ChatMessage] = []
    var isChatting: Bool = false
    var streamingChatResponse: String = ""
    private var chatTask: Task<Void, Never>?
    
    // MARK: - Chat Actions
    
    func sendChatMessage(_ message: String) async {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let transcriptText = transcript?.fullText else { return }
        
        await MainActor.run {
            chatMessages.append(.init(role: "user", content: message))
            isChatting = true
            streamingChatResponse = ""
            errorMessage = nil
        }
        
        chatTask?.cancel()
        
        await llmService.setOnTokenReceived { [weak self] token in
            guard let self else { return }
            Task { @MainActor in
                self.streamingChatResponse += token
            }
        }
        
        chatTask = Task {
            do {
                let history = await MainActor.run { self.chatMessages }
                let response = try await llmService.answerQuestion(
                    transcript: transcriptText,
                    question: message,
                    history: history
                )
                
                await MainActor.run {
                    self.chatMessages.append(.init(role: "assistant", content: response))
                    self.streamingChatResponse = ""
                    self.isChatting = false
                }
            } catch {
                await MainActor.run {
                    if !Task.isCancelled {
                        self.errorMessage = "Помилка чату: \(error.localizedDescription)"
                    }
                    self.isChatting = false
                }
            }
        }
    }
    
    func cancelChat() {
        chatTask?.cancel()
        chatTask = nil
        isChatting = false
    }

    // MARK: - Transcript Translation
    var translatedTranscript: String? = nil
    var isTranslatingTranscript: Bool = false
    private var translationTask: Task<Void, Never>?
    
    func translateTranscript(to languageName: String) async {
        guard let transcriptText = transcript?.fullText, !transcriptText.isEmpty else { return }
        
        await MainActor.run {
            isTranslatingTranscript = true
            errorMessage = nil
        }
        
        translationTask?.cancel()
        
        translationTask = Task {
            do {
                let translated = try await llmService.translateText(text: transcriptText, to: languageName)
                await MainActor.run {
                    self.translatedTranscript = translated
                    self.isTranslatingTranscript = false
                }
            } catch {
                await MainActor.run {
                    if !Task.isCancelled {
                        self.errorMessage = "Помилка перекладу: \(error.localizedDescription)"
                    }
                    self.isTranslatingTranscript = false
                }
            }
        }
    }

    // MARK: - Regenerate Summary
    
    func regenerateSummary() async {
        guard let transcriptText = transcript?.fullText, !transcriptText.isEmpty else {
            errorMessage = "Немає транскрипту для аналізу"
            return
        }

        isRegeneratingSummary = true
        streamingSummary = ""
        errorMessage = nil

        // Setup streaming
        await llmService.setOnTokenReceived { [weak self] token in
            guard let self else { return }
            Task { @MainActor in
                self.streamingSummary += token
            }
        }

        summaryTask = Task {
            do {
                let targetLanguage = AppSettings.shared.summaryLanguage
                let newSummary = try await llmService.generateSummary(transcript: transcriptText, targetLanguage: targetLanguage)

                await MainActor.run {
                    self.summary = newSummary
                    self.streamingSummary = newSummary
                    self.isRegeneratingSummary = false
                }

                // Save updated summary
                if let path = meeting.summaryPath {
                    try? newSummary.write(toFile: path, atomically: true, encoding: .utf8)
                }
            } catch {
                await MainActor.run {
                    if !Task.isCancelled {
                        self.errorMessage = error.localizedDescription
                    }
                    self.isRegeneratingSummary = false
                }
            }
        }
    }

    func cancelSummaryGeneration() {
        summaryTask?.cancel()
        summaryTask = nil
        isRegeneratingSummary = false
        streamingSummary = summary // restore last saved
    }
    
    // MARK: - Export
    
    func exportToObsidian() {
        guard let vaultURL = AppSettings.shared.obsidianVaultPath else {
            errorMessage = "Шлях до Obsidian vault не налаштовано"
            return
        }
        
        let data = MeetingSummaryData(
            title: meeting.title,
            date: meeting.date,
            duration: meeting.duration,
            language: transcript?.language ?? meeting.language,
            tags: meeting.tags.isEmpty ? ["meeting"] : meeting.tags,
            transcript: transcript?.formattedText,
            summary: summary.isEmpty ? nil : summary
        )
        
        do {
            let _ = try ObsidianExporter.export(meeting: data, to: vaultURL)
            meeting.isExportedToObsidian = true
            try? modelContext?.save()
            exportSuccess = true
            
            // Auto-dismiss success
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                self.exportSuccess = false
            }
        } catch {
            errorMessage = "Помилка експорту: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Copy
    
    func copyTranscript() {
        let text = transcript?.formattedText ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    func copySummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
    }
    
    func updateMeetingTitle() {
        let trimmed = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            meetingTitle = meeting.title
            return
        }
        meeting.title = trimmed
        meetingTitle = trimmed
        try? modelContext?.save()
        AppLogger.info("Назву наради змінено на: \(trimmed)")
    }
    
    // MARK: - Transcript Actions
    
    func addTag(_ tag: String) {
        let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !meeting.tags.contains(cleaned) else { return }
        meeting.tags.append(cleaned)
        try? modelContext?.save()
    }
    
    func removeTag(_ tag: String) {
        meeting.tags.removeAll { $0 == tag }
        try? modelContext?.save()
    }
}
