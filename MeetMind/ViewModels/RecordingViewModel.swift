//
//  RecordingViewModel.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation
import SwiftData

/// Manages the recording flow: idle → recording → transcribing → summarizing → complete
@Observable
final class RecordingViewModel {

    // MARK: - State
    enum RecordingState: Equatable {
        case idle
        case preparing
        case recording
        case stopping
        case transcribing
        case summarizing
        case complete
        case error(String)
    }

    var state: RecordingState = .idle
    var meetingTitle: String = String(localized: "Нова нарада")
    var elapsedTime: TimeInterval = 0
    var liveTranscript: [MeetingTranscriptSegment] = []
    var fullTranscript: MeetingTranscriptDocument?
    var summary: String = ""
    var streamingSummary: String = ""
    var errorMessage: String?
    var isTranscriptionReady: Bool = false
    var transcriptionProgress: String = ""
    var transcriptionProgressValue: Double = 0.0

    // MARK: - Services
    var audioManager: any AudioProvider
    private let transcriptionService: any TranscriptionProvider
    private let llmService: any LLMProvider
    var availableSystemAudioSources: [AudioManager.SystemAudioSourceInfo] = []
    var completedMeetingID: UUID?
    var isFloatingIndicatorVisible = true
    private var isTranscribingLive = false

    // MARK: - Private
    private var recordingURL: URL?
    private var liveTranscriptionTask: Task<Void, Never>?
    private(set) var currentMeeting: Meeting?
    private var modelContext: ModelContext?

    // MARK: - Init
    init(
        audioManager: any AudioProvider,
        transcriptionService: any TranscriptionProvider,
        llmService: any LLMProvider
    ) {
        self.audioManager = audioManager
        self.transcriptionService = transcriptionService
        self.llmService = llmService

        setupCallbacks()
        refreshSystemAudioSources()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func refreshSystemAudioSources() {
        Task {
            do {
                let sources = try await audioManager.getAvailableSystemAudioSources()
                await MainActor.run {
                    self.availableSystemAudioSources = sources
                }
            } catch {
                AppLogger.error("Failed to fetch system audio sources: \(error)")
            }
        }
    }

    // MARK: - Setup

    private func setupCallbacks() {
        Task {
            await transcriptionService.setOnStateChanged { [weak self] newState in
                guard let self else { return }
                Task { @MainActor in
                    switch newState {
                    case .downloading(let progress):
                        self.transcriptionProgress = String(localized: "Завантаження моделі: \(Int(progress * 100))%")
                        self.isTranscriptionReady = false
                    case .loading:
                        self.transcriptionProgress = String(localized: "Ініціалізація моделі AI...")
                        self.isTranscriptionReady = false
                    case .ready:
                        self.transcriptionProgress = ""
                        self.isTranscriptionReady = true
                    case .error(let msg):
                        self.transcriptionProgress = msg
                        self.isTranscriptionReady = false
                    case .transcribing(let progress):
                        self.transcriptionProgressValue = progress
                    default:
                        break
                    }
                }
            }
        }
    }

    // MARK: - Initialize Transcription

    func initializeTranscription() async {
        do {
            try await transcriptionService.initialize(modelName: nil)
            isTranscriptionReady = true
        } catch {
            errorMessage = error.localizedDescription
            isTranscriptionReady = false
        }
    }

    // MARK: - Start Recording

    func startRecording() {
        guard state == .idle || state == .complete || isErrorState else { return }

        errorMessage = nil
        liveTranscript = []
        fullTranscript = nil
        summary = ""
        streamingSummary = ""
        transcriptionProgressValue = 0
        completedMeetingID = nil
        state = .preparing

        Task {
            do {
                let url = try await audioManager.startRecording()
                await MainActor.run {
                    self.recordingURL = url
                    self.state = .recording

                    let meeting = Meeting(title: self.meetingTitle)
                    meeting.audioFilename = url.lastPathComponent
                    self.currentMeeting = meeting
                    self.modelContext?.insert(meeting)
                    try? self.modelContext?.save()

                    // Show always-on-top indicator with full controls
                    FloatingIndicatorManager.shared.show(
                        isActiveSpeech: false,
                        speakerName: nil
                    )
                    
                    self.updateFloatingIndicator()
                    self.startLiveTranscription()
                    self.startIndicatorUpdates()
                }
            } catch {
                await MainActor.run {
                    self.state = .error(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func pauseRecording() {
        audioManager.pauseRecording()
    }

    func resumeRecording() {
        audioManager.resumeRecording()
    }

    private func startIndicatorUpdates() {
        Task {
            while state == .recording || state == .stopping {
                try? await Task.sleep(for: .milliseconds(200))
                if isFloatingIndicatorVisible {
                    self.updateFloatingIndicator()
                } else {
                    await MainActor.run {
                        FloatingIndicatorManager.shared.hide()
                    }
                }
            }
            await MainActor.run {
                FloatingIndicatorManager.shared.hide()
            }
        }
    }

    private func updateFloatingIndicator() {
        let isSpeaking: Bool
        let speakerText: String?
        
        if audioManager.isPaused {
            isSpeaking = false
            speakerText = String(localized: "Призупинено")
        } else {
            isSpeaking = audioManager.audioLevels.last ?? 0 > 0.1
            speakerText = liveTranscript.last?.speakerName ?? liveTranscript.last?.speakerID
        }
        
        let lastText = liveTranscript.last?.text
        
        FloatingIndicatorManager.shared.update(
            isActiveSpeech: isSpeaking,
            isPaused: audioManager.isPaused,
            speakerName: speakerText,
            elapsedTime: audioManager.elapsedTime,
            lastTranscript: lastText,
            onPause: { [weak self] in
                Task { @MainActor in self?.pauseRecording() }
            },
            onResume: { [weak self] in
                Task { @MainActor in self?.resumeRecording() }
            },
            onStop: { [weak self] in
                Task { @MainActor in self?.stopRecording() }
            },
            onHide: { [weak self] in
                Task { @MainActor in self?.isFloatingIndicatorVisible = false }
            }
        )
    }

    // MARK: - Stop Recording

    func stopRecording() {
        guard state == .recording else { return }
        state = .stopping

        // Stop audio
        let _ = audioManager.stopRecording()

        // Cancel live transcription
        liveTranscriptionTask?.cancel()
        liveTranscriptionTask = nil

        // Update meeting
        currentMeeting?.title = meetingTitle
        currentMeeting?.duration = audioManager.elapsedTime
        try? modelContext?.save()

        // Start post-processing
        Task {
            await postProcess()
        }
    }

    // MARK: - Live Transcription

    private func startLiveTranscription() {
        liveTranscriptionTask = Task {
            var chunkOffset: TimeInterval = 0

            while !Task.isCancelled && state == .recording {
                // Wait for transcription service to be ready
                var isReady = await transcriptionService.isReady
                while !isReady && !Task.isCancelled && state == .recording {
                    try? await Task.sleep(for: .seconds(1))
                    isReady = await transcriptionService.isReady
                }

                if Task.isCancelled || state != .recording { break }

                // Wait for enough audio to accumulate
                try? await Task.sleep(for: .seconds(Constants.audioChunkDuration))

                guard !Task.isCancelled else { break }

                if isTranscribingLive { continue }
                
                let samples = audioManager.consumeAudioChunk()
                guard !samples.isEmpty else { continue }

                let actualDuration = Double(samples.count) / Constants.whisperSampleRate

                do {
                    isTranscribingLive = true
                    let startTime = Date()
                    
                    let segments = try await transcriptionService.transcribeLive(
                        samples: samples,
                        offset: chunkOffset
                    )
                    
                    let duration = Date().timeIntervalSince(startTime)
                    AppLogger.debug("Live transcription chunk took \(String(format: "%.2f", duration))s (RTF: \(String(format: "%.2f", duration / actualDuration)))")

                    await MainActor.run {
                        self.liveTranscript.append(contentsOf: segments)
                        self.isTranscribingLive = false
                    }

                    chunkOffset += actualDuration
                } catch {
                    await MainActor.run { self.isTranscribingLive = false }
                    AppLogger.error("Live transcription chunk error", error: error)
                }
            }
        }
    }

    // MARK: - Post Processing

    private func postProcess() async {
        guard let recordingURL else {
            state = .error("Файл запису не знайдено")
            currentMeeting?.status = .error
            currentMeeting?.errorMessage = "Файл запису не знайдено"
            try? modelContext?.save()
            return
        }

        // Step 1: High-quality transcription
        await MainActor.run {
            state = .transcribing
            transcriptionProgressValue = 0
            currentMeeting?.status = .transcribing
            try? modelContext?.save()
        }

        do {
            let document = try await transcriptionService.transcribeFile(at: recordingURL)

            await MainActor.run {
                self.fullTranscript = document
                self.liveTranscript = document.segments
                self.currentMeeting?.language = document.language
                if document.totalDuration > 0 {
                    self.currentMeeting?.duration = document.totalDuration
                }
            }

            // Save transcript to file
            let transcriptURL = Constants.transcriptsDirectory
                .appendingPathComponent("\(currentMeeting?.filenameBase ?? "transcript").\(Constants.transcriptFileExtension)")
            try document.save(to: transcriptURL)
            currentMeeting?.transcriptFilename = transcriptURL.lastPathComponent
            try? modelContext?.save()

        } catch {
            await MainActor.run {
                // Fall back to live transcript if post-processing fails
                self.errorMessage = "Повна транскрипція не вдалась, використовується live-версія: \(error.localizedDescription)"
            }

            if !liveTranscript.isEmpty {
                let document = MeetingTranscriptDocument(
                    meetingId: currentMeeting?.id ?? UUID(),
                    createdAt: Date(),
                    language: AppSettings.shared.defaultLanguage,
                    segments: liveTranscript
                )
                do {
                    let transcriptURL = Constants.transcriptsDirectory
                        .appendingPathComponent("\(currentMeeting?.filenameBase ?? "transcript").\(Constants.transcriptFileExtension)")
                    try document.save(to: transcriptURL)
                    await MainActor.run {
                        self.fullTranscript = document
                        self.currentMeeting?.transcriptFilename = transcriptURL.lastPathComponent
                        self.currentMeeting?.errorMessage = self.errorMessage
                        try? self.modelContext?.save()
                    }
                } catch {
                    await MainActor.run {
                        self.currentMeeting?.errorMessage = "Не вдалося зберегти live-транскрипт: \(error.localizedDescription)"
                        try? self.modelContext?.save()
                    }
                }
            } else {
                await MainActor.run {
                    self.currentMeeting?.status = .error
                    self.currentMeeting?.errorMessage = self.errorMessage
                    try? self.modelContext?.save()
                }
            }
        }

        // Step 2: AI Summary
        await MainActor.run {
            state = .summarizing
            currentMeeting?.status = .summarizing
            try? modelContext?.save()
        }

        do {
            let transcriptText = fullTranscript?.formattedText
                ?? liveTranscript.map { "[\($0.startTime.formattedTimestamp)] \($0.text)" }.joined(separator: "\n")

            guard !transcriptText.isEmpty else {
                await MainActor.run {
                    state = .complete
                    currentMeeting?.status = .complete
                    try? modelContext?.save()
                }
                return
            }

            // Generate title
            do {
                let newTitle = try await llmService.generateTitle(transcript: transcriptText)
                if !newTitle.isEmpty {
                    await MainActor.run {
                        self.meetingTitle = newTitle
                        self.currentMeeting?.title = newTitle
                        try? self.modelContext?.save()
                    }
                }
            } catch {
                AppLogger.warning("Failed to generate meeting title: \(error.localizedDescription)")
            }

            // Setup streaming callback
            await llmService.setOnTokenReceived { [weak self] token in
                guard let self else { return }
                Task { @MainActor in
                    self.streamingSummary += token
                }
            }

            let targetLanguage = AppSettings.shared.summaryLanguage
            let summaryResult = try await llmService.generateSummary(transcript: transcriptText, targetLanguage: targetLanguage)

            await MainActor.run {
                self.summary = summaryResult
                self.streamingSummary = summaryResult
            }

            // Save summary to file
            let summaryURL = Constants.summariesDirectory
                .appendingPathComponent("\(currentMeeting?.filenameBase ?? "summary").\(Constants.summaryFileExtension)")
            try summaryResult.write(to: summaryURL, atomically: true, encoding: .utf8)
            currentMeeting?.summaryFilename = summaryURL.lastPathComponent

        } catch {
            await MainActor.run {
                self.errorMessage = "Помилка генерації резюме: \(error.localizedDescription)"
            }
        }

        // Complete
        await MainActor.run {
            currentMeeting?.status = .complete
            try? modelContext?.save()
            
            // Wait a tiny bit for DB consistency
            self.completedMeetingID = currentMeeting?.id
            state = .complete

            // Auto-export to Obsidian if enabled
            if AppSettings.shared.autoExportToObsidian {
                exportToObsidian()
            }
        }
    }

    // MARK: - Obsidian Export

    func exportToObsidian() {
        guard let vaultURL = AppSettings.shared.obsidianVaultPath else {
            errorMessage = "Шлях до Obsidian vault не налаштовано. Вкажіть його в Налаштуваннях."
            return
        }

        let transcriptText = fullTranscript?.formattedText
            ?? liveTranscript.map { "[\($0.startTime.formattedTimestamp)] \($0.text)" }.joined(separator: "\n")

        let data = MeetingSummaryData(
            title: meetingTitle,
            date: currentMeeting?.date ?? Date(),
            duration: currentMeeting?.duration ?? 0,
            language: fullTranscript?.language ?? Constants.defaultLanguage,
            tags: currentMeeting?.tags ?? ["meeting"],
            transcript: transcriptText,
            summary: summary.isEmpty ? nil : summary
        )

        do {
            let exportedURL = try ObsidianExporter.export(meeting: data, to: vaultURL)
            currentMeeting?.isExportedToObsidian = true
            try? modelContext?.save()
            AppLogger.info("Exported to: \(exportedURL.path)")
        } catch {
            errorMessage = "Помилка експорту в Obsidian: \(error.localizedDescription)"
        }
    }

    // MARK: - Reset

    func resetForNewRecording() {
        state = .idle
        meetingTitle = String(localized: "Нова нарада")
        liveTranscript = []
        fullTranscript = nil
        summary = ""
        streamingSummary = ""
        errorMessage = nil
        currentMeeting = nil
        recordingURL = nil
        completedMeetingID = nil
        isFloatingIndicatorVisible = true
        transcriptionProgressValue = 0
    }

    // MARK: - Helpers

    private var isErrorState: Bool {
        if case .error = state { return true }
        return false
    }
}
