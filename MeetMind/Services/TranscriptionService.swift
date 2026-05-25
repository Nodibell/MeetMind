//
//  TranscriptionService.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation
import AVFoundation
import WhisperKit

/// On-device speech-to-text transcription using WhisperKit
actor TranscriptionService: TranscriptionProvider {

    enum ServiceState: Sendable {
        case notReady
        case downloading(progress: Double)
        case loading
        case ready
        case transcribing(progress: Double)
        case error(String)
    }

    private(set) var state: ServiceState = .notReady
    
    private var whisperKit: WhisperKit?
    private var currentModelName: String = ""
    private var unloadTask: Task<Void, Never>?
    private var memoryPressureSource: (any DispatchSourceMemoryPressure)?
    private let inactivityTimeout: UInt64 = 5 * 60 * 1_000_000_000 // 5 minutes in nanoseconds

    // Monotonic download progress tracking variables
    private var fileDownloadsCompleted = 0
    private var lastRawProgress: Double = 0.0
    private var monotonicDownloadProgress: Double = 0.0

    // MARK: - Callbacks
    var onStateChanged: (@Sendable (ServiceState) -> Void)?
    var onSegmentTranscribed: (@Sendable (MeetingTranscriptSegment) -> Void)?

    func setOnStateChanged(_ callback: (@Sendable (ServiceState) -> Void)?) {
        self.onStateChanged = callback
    }

    func setOnSegmentTranscribed(_ callback: (@Sendable (MeetingTranscriptSegment) -> Void)?) {
        self.onSegmentTranscribed = callback
    }

    // MARK: - Initialization

    /// Initialize WhisperKit with specified model
    func initialize(modelName: String? = nil) async throws {
        let model = await MainActor.run { modelName ?? AppSettings.shared.whisperModelLive }
        currentModelName = model
        setupMemoryPressureListener()
        AppLogger.info("Initializing WhisperKit with model: \(model)")

        // Reset progress tracking
        fileDownloadsCompleted = 0
        lastRawProgress = 0.0
        monotonicDownloadProgress = 0.0

        updateState(.downloading(progress: 0))

        do {
            // 1. Download the model with progress tracking
            let modelFolderURL = try await WhisperKit.download(
                variant: model,
                progressCallback: { progress in
                    Task { [weak self] in
                        await self?.updateDownloadProgress(progress.fractionCompleted)
                    }
                }
            )

            AppLogger.info("Model downloaded to: \(modelFolderURL.path)")

            updateState(.loading)

            // 2. Initialize WhisperKit with the EXACT folder path
            let config = WhisperKitConfig(
                model: model,
                modelFolder: modelFolderURL.path,
                verbose: false,
                prewarm: true,
                download: false
            )

            let pipe = try await WhisperKit(config)
            self.whisperKit = pipe
            AppLogger.info("WhisperKit successfully initialized")
            updateState(.ready)
        } catch {
            AppLogger.error("Failed to load WhisperKit model", error: error)
            updateState(.error(String(localized: "Не вдалося завантажити модель: \(error.localizedDescription)")))
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }
    }

    private func updateDownloadProgress(_ rawProgress: Double) {
        // Detect when a file finishes and a new one starts (progress drops from high to low)
        if rawProgress < 0.15 && self.lastRawProgress > 0.85 {
            self.fileDownloadsCompleted += 1
        }
        self.lastRawProgress = rawProgress
        
        // Weighted progress calculation assuming 5 files (config, tokenizer, preprocessor, encoder, decoder)
        let filesCount = 5.0
        let base = Double(self.fileDownloadsCompleted) / filesCount
        let currentSegmentWeight = 1.0 / filesCount
        let computedProgress = base + (rawProgress * currentSegmentWeight)
        
        // Strict monotonic filter capped at 99% to prevent visual jumping
        self.monotonicDownloadProgress = min(0.99, max(self.monotonicDownloadProgress, computedProgress))
        
        updateState(.downloading(progress: self.monotonicDownloadProgress))
    }

    /// Setup listener for system-wide memory pressure
    func setupMemoryPressureListener() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            let event = source.data
            if event.contains(.critical) || event.contains(.warning) {
                AppLogger.systemHealth("Memory pressure detected (\(event)), unloading WhisperKit models...")
                Task { [weak self] in
                    await self?.unloadModels()
                }
            }
        }
        source.resume()
        self.memoryPressureSource = source
    }

    // MARK: - Live Transcription

    /// Transcribe audio samples in real-time (streaming chunks)
    func transcribeLive(samples: [Float], offset: TimeInterval = 0) async throws -> [MeetingTranscriptSegment] {
        cancelUnloadTask()
        AppLogger.debug("Transcribing live chunk: \(samples.count) samples, offset: \(offset)")

        if whisperKit == nil {
            AppLogger.info("WhisperKit was unloaded, reinitializing...")
            try await initialize(modelName: currentModelName.isEmpty ? nil : currentModelName)
        }

        guard let whisperKit else {
            throw TranscriptionError.notInitialized
        }

        guard !samples.isEmpty else { return [] }
        
        let language = await MainActor.run { AppSettings.shared.defaultLanguage }
        let options = DecodingOptions(
            task: .transcribe,
            language: language == "auto" ? nil : language,
            temperatureFallbackCount: 3,
            sampleLength: 224,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: false
        )

        updateState(.transcribing(progress: 0.0))

        let startTime = CFAbsoluteTimeGetCurrent()
        AppLogger.ai("WhisperKit inference started...")

        defer {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let audioDuration = Double(samples.count) / 16000.0
            let rtf = audioDuration > 0 ? duration / audioDuration : 0
            AppLogger.ai("Inference completed in \(String(format: "%.2f", duration))s (RTF: \(String(format: "%.3f", rtf)))")
            scheduleUnload()
        }

        do {
            let results = try await whisperKit.transcribe(
                audioArray: samples,
                decodeOptions: options
            )

            let segments = convertResults(results, offset: offset)
            updateState(.ready)

            for segment in segments {
                onSegmentTranscribed?(segment)
            }

            return segments
        } catch {
            updateState(.error(String(localized: "Помилка транскрипції: \(error.localizedDescription)")))
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    // MARK: - Post-Processing (High Quality)

    /// Full high-quality transcription of an audio file
    func transcribeFile(at url: URL) async throws -> MeetingTranscriptDocument {
        cancelUnloadTask()
        // Load or switch to high-quality model
        let postModel = await MainActor.run { AppSettings.shared.whisperModelPost }
        let defaultLanguage = await MainActor.run { AppSettings.shared.defaultLanguage }
        
        if currentModelName != postModel || whisperKit == nil {
            try await initialize(modelName: postModel)
        }

        guard let whisperKit else {
            throw TranscriptionError.notInitialized
        }

        let language = defaultLanguage
        let options = DecodingOptions(
            task: .transcribe,
            language: language == "auto" ? nil : language,
            temperatureFallbackCount: 5,
            sampleLength: 448,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: false
        )

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let totalWindows = max(1, Int(ceil(duration / 30.0)))

        updateState(.transcribing(progress: 0.0))

        let startTime = CFAbsoluteTimeGetCurrent()
        AppLogger.ai("File post-processing started (\(String(format: "%.1f", duration))s)...")

        defer {
            scheduleUnload()
        }

        do {
            let results = try await whisperKit.transcribe(
                audioPath: url.path,
                decodeOptions: options,
                callback: { [weak self] progress in
                    let currentProgress = min(1.0, Double(progress.windowId + 1) / Double(totalWindows))
                    Task { [weak self] in
                        await self?.updateState(.transcribing(progress: currentProgress))
                    }
                    return true
                }
            )

            // 3. Diarization (Speaker Recognition) via FluidAudio
            AppLogger.ai("Starting FluidAudio speaker diarization...")
            let diarizationEngine = await MeetMindDiarizationEngine()
            var segments = convertResults(results, offset: 0)

            do {
                try await diarizationEngine.prepareModels()
                let (diarizationSegments, centroids) = try await diarizationEngine.diarize(fileURL: url)
                segments = diarizationEngine.alignSpeakers(
                    textSegments: segments,
                    diarizationSegments: diarizationSegments
                )
                
                // New: Identify speakers by name from centroids
                segments = await diarizationEngine.identifySpeakers(segments: segments, centroids: centroids)
                
                AppLogger.ai("Diarization alignment & identification complete: \(Set(segments.compactMap(\.speakerID)).count) speakers detected.")
                // Free CoreML models after use
                await diarizationEngine.unloadModels()
            } catch {
                AppLogger.aiError("Diarization failed, continuing without speaker labels", error: error)
                // Continue without speaker labels — transcription is still valid
            }

            // Detect dominant language
            let fullText = segments.map(\.text).joined(separator: " ")
            let language = await MainActor.run { fullText.detectedLanguage } ?? Constants.defaultLanguage

            let document = MeetingTranscriptDocument(
                meetingId: UUID(),
                createdAt: Date(),
                language: language,
                segments: segments
            )

            updateState(.ready)

            let totalTime = CFAbsoluteTimeGetCurrent() - startTime
            let rtf = duration > 0 ? totalTime / duration : 0
            AppLogger.ai("Full file post-processing completed in \(String(format: "%.2f", totalTime))s (RTF: \(String(format: "%.3f", rtf)))")

            // Switch back to live model for next recording
            let liveModel = await MainActor.run { AppSettings.shared.whisperModelLive }
            if currentModelName != liveModel {
                try? await initialize(modelName: liveModel)
            }

            return document
        } catch {
            updateState(.error(String(localized: "Помилка транскрипції файлу: \(error.localizedDescription)")))
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func convertResults(_ results: [TranscriptionResult], offset: TimeInterval) -> [MeetingTranscriptSegment] {
        var segments: [MeetingTranscriptSegment] = []
        var fallbackOffset = offset

        for result in results {
            let resultSeekTime = TimeInterval(result.seekTime ?? 0)
            let resultOffset = offset + resultSeekTime
            let firstStart = result.segments.first.map { TimeInterval($0.start) } ?? 0
            let shouldApplySeekTime = result.seekTime != nil && firstStart + 0.5 < resultSeekTime
            let timingOffset = shouldApplySeekTime ? resultOffset : offset

            for segment in result.segments {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                var startTime = TimeInterval(segment.start) + timingOffset
                var endTime = TimeInterval(segment.end) + timingOffset

                if let previous = segments.last, startTime + 0.5 < previous.startTime {
                    startTime += fallbackOffset
                    endTime += fallbackOffset
                }

                if endTime < startTime {
                    endTime = startTime
                }

                let transcriptSegment = MeetingTranscriptSegment(
                    startTime: startTime,
                    endTime: endTime,
                    text: text,
                    speakerID: nil,
                    speakerName: nil,
                    language: nil
                )
                segments.append(transcriptSegment)
            }

            if result.seekTime == nil {
                fallbackOffset += result.timings.inputAudioSeconds
            }
        }

        return segments.sorted { $0.startTime < $1.startTime }
    }



    private func updateState(_ newState: ServiceState) {
        state = newState
        onStateChanged?(newState)
    }

    /// Check if the service is ready for transcription
    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    // MARK: - Memory Management

    /// Unload models from memory to save resources
    func unloadModels() {
        AppLogger.info("Unloading WhisperKit models due to inactivity")
        whisperKit = nil
        updateState(.notReady)
    }

    private func scheduleUnload() {
        cancelUnloadTask()
        unloadTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: self.inactivityTimeout)
            guard !Task.isCancelled else { return }
            await self.unloadModels()
        }
    }

    private func cancelUnloadTask() {
        unloadTask?.cancel()
        unloadTask = nil
    }
}

// MARK: - Errors
enum TranscriptionError: LocalizedError, Sendable {
    case notInitialized
    case modelLoadFailed(String)
    case transcriptionFailed(String)
    case audioLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return String(localized: "Сервіс транскрипції не ініціалізовано. Зачекайте завантаження моделі.")
        case .modelLoadFailed(let detail):
            return String(localized: "Не вдалося завантажити модель Whisper: \(detail)")
        case .transcriptionFailed(let detail):
            return String(localized: "Помилка транскрипції: \(detail)")
        case .audioLoadFailed(let detail):
            return String(localized: "Не вдалося завантажити аудіо: \(detail)")
        }
    }
}
