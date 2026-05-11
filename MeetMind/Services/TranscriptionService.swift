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
actor TranscriptionService {

    // MARK: - State
    enum ServiceState: Sendable {
        case notReady
        case downloading(progress: Double)
        case ready
        case transcribing(progress: Double)
        case error(String)
    }

    private(set) var state: ServiceState = .notReady
    private var whisperKit: WhisperKit?
    private var currentModelName: String = ""

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
        let model = modelName ?? AppSettings.shared.whisperModelLive
        currentModelName = model
        AppLogger.info("Ініціалізація WhisperKit з моделлю: \(model)")

        updateState(.downloading(progress: 0))

        do {
            updateState(.downloading(progress: 0))

            // 1. Download the model with progress tracking
            let modelFolderURL = try await WhisperKit.download(
                variant: model,
                progressCallback: { progress in
                    Task { [weak self] in
                        await self?.updateState(.downloading(progress: progress.fractionCompleted))
                    }
                }
            )

            AppLogger.info("Модель завантажена в: \(modelFolderURL.path)")

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
            AppLogger.info("WhisperKit успішно ініціалізовано")
            updateState(.ready)
        } catch {
            AppLogger.error("Помилка завантаження моделі WhisperKit", error: error)
            updateState(.error("Не вдалося завантажити модель: \(error.localizedDescription)"))
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }
    }

    // MARK: - Live Transcription

    /// Transcribe audio samples in real-time (streaming chunks)
    func transcribeLive(samples: [Float], offset: TimeInterval = 0) async throws -> [MeetingTranscriptSegment] {
        AppLogger.debug("Транскрипція live-чанку: \(samples.count) семплів, offset: \(offset)")

        guard let whisperKit else {
            throw TranscriptionError.notInitialized
        }

        guard !samples.isEmpty else { return [] }

        let language = AppSettings.shared.defaultLanguage
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
            updateState(.error("Помилка транскрипції: \(error.localizedDescription)"))
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    // MARK: - Post-Processing (High Quality)

    /// Full high-quality transcription of an audio file
    func transcribeFile(at url: URL) async throws -> MeetingTranscriptDocument {
        // Load or switch to high-quality model
        let postModel = AppSettings.shared.whisperModelPost
        if currentModelName != postModel {
            try await initialize(modelName: postModel)
        }

        guard let whisperKit else {
            throw TranscriptionError.notInitialized
        }

        let language = AppSettings.shared.defaultLanguage
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

            let segments = convertResults(results, offset: 0)

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

            // Switch back to live model for next recording
            if currentModelName != AppSettings.shared.whisperModelLive {
                try? await initialize(modelName: AppSettings.shared.whisperModelLive)
            }

            return document
        } catch {
            updateState(.error("Помилка транскрипції файлу: \(error.localizedDescription)"))
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
            return "Сервіс транскрипції не ініціалізовано. Зачекайте завантаження моделі."
        case .modelLoadFailed(let detail):
            return "Не вдалося завантажити модель Whisper: \(detail)"
        case .transcriptionFailed(let detail):
            return "Помилка транскрипції: \(detail)"
        case .audioLoadFailed(let detail):
            return "Не вдалося завантажити аудіо: \(detail)"
        }
    }
}
