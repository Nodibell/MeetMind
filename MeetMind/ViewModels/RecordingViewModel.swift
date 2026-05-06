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
        case recording
        case stopping
        case transcribing
        case summarizing
        case complete
        case error(String)
    }
    
    var state: RecordingState = .idle
    var meetingTitle: String = "Нова нарада"
    var elapsedTime: TimeInterval = 0
    var liveTranscript: [MeetingTranscriptSegment] = []
    var fullTranscript: MeetingTranscriptDocument?
    var summary: String = ""
    var streamingSummary: String = ""
    var errorMessage: String?
    var isTranscriptionReady: Bool = false
    var transcriptionProgress: String = ""
    
    // MARK: - Services
    var audioManager: AudioManager
    private let transcriptionService: TranscriptionService
    private let llmService: LLMService
    
    // MARK: - Private
    private var recordingURL: URL?
    private var liveTranscriptionTask: Task<Void, Never>?
    private var currentMeeting: Meeting?
    private var modelContext: ModelContext?
    
    // MARK: - Init
    init(
        audioManager: AudioManager,
        transcriptionService: TranscriptionService,
        llmService: LLMService
    ) {
        self.audioManager = audioManager
        self.transcriptionService = transcriptionService
        self.llmService = llmService
        
        setupCallbacks()
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Setup
    
    private func setupCallbacks() {
        Task {
            await transcriptionService.setOnStateChanged { [weak self] newState in
                guard let self else { return }
                Task { @MainActor in
                    switch newState {
                    case .downloading(let progress):
                        self.transcriptionProgress = "Завантаження моделі: \(Int(progress * 100))%"
                        self.isTranscriptionReady = false
                    case .ready:
                        self.transcriptionProgress = ""
                        self.isTranscriptionReady = true
                    case .error(let msg):
                        self.transcriptionProgress = msg
                        self.isTranscriptionReady = false
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
            try await transcriptionService.initialize()
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
        
        do {
            let url = try audioManager.startRecording()
            recordingURL = url
            state = .recording
            
            // Create meeting in SwiftData
            let meeting = Meeting(title: meetingTitle)
            meeting.audioPath = url.path
            currentMeeting = meeting
            modelContext?.insert(meeting)
            try? modelContext?.save()
            
            // Start live transcription loop
            startLiveTranscription()
            
        } catch {
            state = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
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
                
                let samples = audioManager.consumeAudioChunk()
                guard !samples.isEmpty else { continue }
                
                do {
                    let segments = try await transcriptionService.transcribeLive(
                        samples: samples,
                        offset: chunkOffset
                    )
                    
                    await MainActor.run {
                        self.liveTranscript.append(contentsOf: segments)
                    }
                    
                    chunkOffset += Constants.audioChunkDuration
                } catch {
                    // Don't break on transcription errors during live mode
                    print("Live transcription chunk error: \(error)")
                }
            }
        }
    }
    
    // MARK: - Post Processing
    
    private func postProcess() async {
        guard let recordingURL else {
            state = .error("Файл запису не знайдено")
            return
        }
        
        // Step 1: High-quality transcription
        await MainActor.run { state = .transcribing }
        
        do {
            let document = try await transcriptionService.transcribeFile(at: recordingURL)
            
            await MainActor.run {
                self.fullTranscript = document
                self.liveTranscript = document.segments
            }
            
            // Save transcript to file
            let transcriptURL = Constants.transcriptsDirectory
                .appendingPathComponent("\(currentMeeting?.filenameBase ?? "transcript").\(Constants.transcriptFileExtension)")
            try document.save(to: transcriptURL)
            currentMeeting?.transcriptPath = transcriptURL.path
            try? modelContext?.save()
            
        } catch {
            await MainActor.run {
                // Fall back to live transcript if post-processing fails
                self.errorMessage = "Повна транскрипція не вдалась, використовується live-версія: \(error.localizedDescription)"
            }
        }
        
        // Step 2: AI Summary
        await MainActor.run { state = .summarizing }
        
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
            
            // Setup streaming callback
            await llmService.setOnTokenReceived { [weak self] token in
                guard let self else { return }
                Task { @MainActor in
                    self.streamingSummary += token
                }
            }
            
            let summaryResult = try await llmService.generateSummary(transcript: transcriptText)
            
            await MainActor.run {
                self.summary = summaryResult
                self.streamingSummary = summaryResult
            }
            
            // Save summary to file
            let summaryURL = Constants.summariesDirectory
                .appendingPathComponent("\(currentMeeting?.filenameBase ?? "summary").\(Constants.summaryFileExtension)")
            try summaryResult.write(to: summaryURL, atomically: true, encoding: .utf8)
            currentMeeting?.summaryPath = summaryURL.path
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Помилка генерації резюме: \(error.localizedDescription)"
            }
        }
        
        // Complete
        await MainActor.run {
            state = .complete
            currentMeeting?.status = .complete
            try? modelContext?.save()
            
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
            print("Exported to: \(exportedURL.path)")
        } catch {
            errorMessage = "Помилка експорту в Obsidian: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Reset
    
    func resetForNewRecording() {
        state = .idle
        meetingTitle = "Нова нарада"
        liveTranscript = []
        fullTranscript = nil
        summary = ""
        streamingSummary = ""
        errorMessage = nil
        currentMeeting = nil
        recordingURL = nil
    }
    
    // MARK: - Helpers
    
    private var isErrorState: Bool {
        if case .error = state { return true }
        return false
    }
}
