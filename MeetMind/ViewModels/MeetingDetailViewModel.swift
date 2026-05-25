//
//  MeetingDetailViewModel.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation
import SwiftData
import AppKit
import SwiftUI

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
    var selectedSummaryLanguage: String {
        didSet {
            meeting.summaryLanguage = selectedSummaryLanguage
            try? modelContext?.save()
        }
    }
    
    // MARK: - Transcription State
    var isTranscribing: Bool = false
    var transcriptionProgressValue: Double = 0.0
    var transcriptionStatusText: String = ""
    
    // MARK: - Services
    private let llmService: any LLMProvider
    private let transcriptionService: any TranscriptionProvider
    private var modelContext: ModelContext?
    private var repository: MeetingRepository?
    private let exportUseCase = ExportMeetingUseCase()
    private var summaryTask: Task<Void, Never>?
    
    // MARK: - Computed
    
    var filteredSegments: [MeetingTranscriptSegment] {
        guard let segments = transcript?.segments else { return [] }
        if searchText.isEmpty { return segments }
        return segments.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }
    
    // MARK: - Init
    
    init(meeting: Meeting, llmService: any LLMProvider, transcriptionService: any TranscriptionProvider) {
        self.meeting = meeting
        self.meetingTitle = meeting.title
        self.selectedSummaryLanguage = meeting.summaryLanguage ?? AppSettings.shared.summaryLanguage
        self.llmService = llmService
        self.transcriptionService = transcriptionService
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        self.repository = MeetingRepository(context: context)
    }
    
    // MARK: - Load Data
    
    func loadData() async {
        await loadTranscript()
        await loadSummary()

        if let repository {
            await MainActor.run {
                try? repository.syncStructuredEntities(for: self.meeting)
            }
        }

        // Auto-detect names if not already set
        if meeting.speakerMetadata.allSatisfy({ $0.name == nil }) {
            await autoDetectSpeakerNames()
        }

        // Auto-detect title if still default
        if meeting.title == "Нова нарада" || meeting.title.isEmpty {
            await autoDetectTitle()
        }
    }
    
    private func autoDetectTitle() async {
        guard let transcriptText = transcript?.fullText, !transcriptText.isEmpty else { return }

        do {
            let newTitle = try await llmService.generateTitle(transcript: transcriptText)
            if !newTitle.isEmpty {
                await MainActor.run {
                    self.meetingTitle = newTitle
                    self.meeting.title = newTitle
                    self.repository?.trySave()
                }
            }
        } catch {
            AppLogger.warning("Failed to auto-detect meeting title: \(error)")
        }
    }
    
    private func loadTranscript() async {
        guard let url = meeting.transcriptURL else { return }
        
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
        guard let url = meeting.summaryURL else { return }
        
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
    var translatedSegments: [UUID: String] = [:]
    var isTranslatingTranscript: Bool = false
    private var translationTask: Task<Void, Never>?
    
    func translateTranscript(to languageName: String) async {
        guard let segments = transcript?.segments, !segments.isEmpty else { return }
        
        await MainActor.run {
            isTranslatingTranscript = true
            translatedTranscript = ""
            errorMessage = nil
            translatedSegments = [:]
        }
        
        translationTask?.cancel()
        
        await llmService.setOnTokenReceived { [weak self] token in
            guard let self else { return }
            Task { @MainActor in
                self.translatedTranscript = (self.translatedTranscript ?? "") + token
            }
        }
        
        translationTask = Task {
            do {
                // Build a structured text with line numbering to help preserve segment boundaries
                var structuredLines: [String] = []
                for (index, segment) in segments.enumerated() {
                    structuredLines.append("\(index + 1): \(segment.text)")
                }
                let combinedText = structuredLines.joined(separator: "\n")
                
                // Call standard translation API which internally supports DeepMLX/Ollama/LMStudio
                let resultText = try await llmService.translateText(text: combinedText, to: languageName)
                
                // Parse the response
                var parsedTranslations: [UUID: String] = [:]
                let lines = resultText.components(separatedBy: .newlines)
                
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    
                    if let colonIndex = trimmed.firstIndex(of: ":") {
                        let prefix = trimmed[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                        if let indexVal = Int(prefix), indexVal > 0, indexVal <= segments.count {
                            let translatedContent = trimmed[trimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
                            let segmentID = segments[indexVal - 1].id
                            parsedTranslations[segmentID] = translatedContent
                        }
                    }
                }
                
                // Fallback: If some lines failed to parse prefix, map clean lines sequentially
                if parsedTranslations.count < segments.count {
                    AppLogger.warning("Parsing matched only \(parsedTranslations.count)/\(segments.count) segments. Falling back to sequential alignment.")
                    
                    let cleanLines = lines.map { line -> String in
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let colonIndex = trimmed.firstIndex(of: ":") {
                            let prefix = trimmed[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                            if Int(prefix) != nil {
                                return String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        return trimmed
                    }.filter { !$0.isEmpty }
                    
                    for (index, segment) in segments.enumerated() {
                        if parsedTranslations[segment.id] == nil {
                            if index < cleanLines.count {
                                parsedTranslations[segment.id] = cleanLines[index]
                            } else {
                                parsedTranslations[segment.id] = segment.text
                            }
                        }
                    }
                }
                
                await MainActor.run {
                    self.translatedSegments = parsedTranslations
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
                let targetLanguage = await MainActor.run { self.selectedSummaryLanguage }
                let newSummary = try await llmService.generateSummary(transcript: transcriptText, targetLanguage: targetLanguage)

                await MainActor.run {
                    self.summary = newSummary
                    self.streamingSummary = newSummary
                    self.isRegeneratingSummary = false
                }

                // Save updated summary
                let url: URL
                if let existingURL = meeting.summaryURL {
                    url = existingURL
                } else {
                    let filename = "\(meeting.filenameBase).\(Constants.summaryFileExtension)"
                    await MainActor.run {
                        meeting.summaryFilename = filename
                        try? modelContext?.save()
                    }
                    url = Constants.summariesDirectory.appendingPathComponent(filename)
                }
                try? newSummary.write(to: url, atomically: true, encoding: .utf8)
                
                await MainActor.run {
                    try? self.repository?.syncStructuredEntities(for: self.meeting)
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

    // MARK: - Re-transcribe Meeting
    
    func retranscribeMeeting() async {
        guard let audioURL = meeting.audioURL else {
            errorMessage = "Файл аудіозапису відсутній"
            return
        }
        
        isTranscribing = true
        transcriptionProgressValue = 0.0
        transcriptionStatusText = String(localized: "Ініціалізація...")
        errorMessage = nil
        
        // Setup transcription service callback
        await transcriptionService.setOnStateChanged { [weak self] newState in
            guard let self else { return }
            Task { @MainActor in
                switch newState {
                case .downloading(let progress):
                    let percentInt = Int(round(progress * 100))
                    self.transcriptionStatusText = String(localized: "Завантаження моделі: \(percentInt)%")
                    // Show download progress in first half of the bar (0% → 50%)
                    self.transcriptionProgressValue = progress * 0.5
                case .loading:
                    self.transcriptionStatusText = String(localized: "Ініціалізація моделі AI...")
                    self.transcriptionProgressValue = 0.5
                case .ready:
                    self.transcriptionStatusText = String(localized: "Готово")
                case .error(let msg):
                    self.transcriptionStatusText = msg
                case .transcribing(let progress):
                    // Transcription occupies second half of the bar (50% → 100%)
                    self.transcriptionProgressValue = 0.5 + progress * 0.5
                    self.transcriptionStatusText = String(localized: "Транскрипція...")
                default:
                    break
                }
            }
        }
        
        do {
            // Set status to transcribing in database
            await MainActor.run {
                meeting.status = .transcribing
                try? modelContext?.save()
            }
            
            // Run transcription
            let document = try await transcriptionService.transcribeFile(at: audioURL)
            
            // Save transcript JSON to file
            let transcriptURL = Constants.transcriptsDirectory
                .appendingPathComponent("\(meeting.filenameBase).\(Constants.transcriptFileExtension)")
            try document.save(to: transcriptURL)
            
            await MainActor.run {
                self.meeting.transcriptFilename = transcriptURL.lastPathComponent
                self.meeting.language = document.language
                if document.totalDuration > 0 {
                    self.meeting.duration = document.totalDuration
                }
                try? self.modelContext?.save()
            }
            
            // Sync SwiftData ActionItems and segments
            if let repository {
                try repository.syncStructuredEntities(for: meeting)
            }
            
            // Set status back to complete
            await MainActor.run {
                meeting.status = .complete
                try? modelContext?.save()
                isTranscribing = false
            }
            
            // Reload local transcript view state
            await loadTranscript()
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Помилка транскрипції: \(error.localizedDescription)"
                self.meeting.status = .error
                self.meeting.errorMessage = error.localizedDescription
                try? self.modelContext?.save()
                isTranscribing = false
            }
        }
    }
    
    // MARK: - Export

    func exportToObsidian() {
        do {
            try exportUseCase.execute(
                meeting: meeting,
                transcript: transcript,
                summary: summary
            )
            meeting.isExportedToObsidian = true
            repository?.trySave()
            exportSuccess = true

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                self.exportSuccess = false
            }
        } catch {
            errorMessage = error.localizedDescription
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
        repository?.trySave()
        AppLogger.info("Meeting title changed to: \(trimmed)")
    }
    
    // MARK: - Transcript Actions
    
    func addTag(_ tag: String) {
        let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !meeting.tags.contains(cleaned) else { return }
        meeting.tags.append(cleaned)
        repository?.trySave()
    }

    func removeTag(_ tag: String) {
        meeting.tags.removeAll { $0 == tag }
        repository?.trySave()
    }
    
    // MARK: - Speaker Management
    
    func updateSpeakerName(id: String, newName: String) {
        if let index = meeting.speakerMetadata.firstIndex(where: { $0.id == id }) {
            meeting.speakerMetadata[index].name = newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newName
        } else {
            meeting.speakerMetadata.append(SpeakerMetadata(id: id, name: newName, colorHex: nil))
        }
        repository?.trySave()
    }

    func updateSpeakerColor(id: String, color: Color) {
        let hex = color.toHex()
        if let index = meeting.speakerMetadata.firstIndex(where: { $0.id == id }) {
            meeting.speakerMetadata[index].colorHex = hex
        } else {
            meeting.speakerMetadata.append(SpeakerMetadata(id: id, name: nil, colorHex: hex))
        }
        repository?.trySave()
    }
    
    func autoDetectSpeakerNames() async {
        guard let transcriptText = transcript?.fullTextWithSpeakers, !transcriptText.isEmpty else { return }
        
        do {
            let detected = try await llmService.extractSpeakerNames(transcript: transcriptText)
            await MainActor.run {
                for (id, name) in detected {
                    self.updateSpeakerName(id: id, newName: name)
                }
            }
        } catch {
            AppLogger.error("Failed to auto-detect speaker names: \(error)")
        }
    }
}
