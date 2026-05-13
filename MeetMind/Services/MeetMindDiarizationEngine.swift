//
//  MeetMindDiarizationEngine.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 13.05.2026.
//

import Foundation
import FluidAudio
import AVFoundation
import os

// MARK: - Diarization Global Actor

/// Dedicated global actor for diarization workloads, isolating CoreML inference
/// from the main thread and audio pipeline.
@globalActor
actor DiarizationActor: GlobalActor {
    static let shared = DiarizationActor()
}

// MARK: - Diarization Engine

/// Offline batch-mode speaker diarization engine using FluidAudio's
/// `OfflineDiarizerManager` (Pyannote segmentation + WeSpeaker embeddings + VBx clustering).
///
/// This engine is isolated to `DiarizationActor` to prevent CoreML inference
/// from blocking the UI or audio pipeline threads.
@DiarizationActor
final class MeetMindDiarizationEngine {

    // MARK: - State

    enum EngineState: Sendable {
        case idle
        case preparingModels
        case modelsReady
        case diarizing(progress: String)
        case error(String)
    }

    private(set) var state: EngineState = .idle

    // MARK: - FluidAudio Components

    private var offlineManager: OfflineDiarizerManager?
    private var modelsLoaded = false

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.meetmind.app",
        category: "DiarizationEngine"
    )

    // MARK: - Initialization

    /// Prepare CoreML diarization models. Downloads from HuggingFace on first use,
    /// then caches locally.
    func prepareModels() async throws {
        guard !modelsLoaded else {
            Self.logger.info("⏭️ Diarization models already loaded, skipping.")
            return
        }

        state = .preparingModels
        Self.logger.info("📦 Preparing FluidAudio diarization models...")

        do {
            let config = OfflineDiarizerConfig()
            let manager = OfflineDiarizerManager(config: config)
            try await manager.prepareModels()

            self.offlineManager = manager
            self.modelsLoaded = true
            self.state = .modelsReady

            Self.logger.info("✅ FluidAudio diarization models ready.")
        } catch {
            self.state = .error("Failed to prepare diarization models: \(error.localizedDescription)")
            Self.logger.error("❌ Model preparation failed: \(error.localizedDescription, privacy: .public)")
            throw DiarizationEngineError.modelPreparationFailed(error.localizedDescription)
        }
    }

    // MARK: - Offline Batch Diarization

    /// Run offline diarization on recorded audio samples.
    ///
    /// - Parameters:
    ///   - samples: Float32 linear PCM audio at 16kHz mono.
    ///   - sampleRate: Sample rate of the input (default 16000).
    /// - Returns: Array of `DiarizationSegment` with speaker IDs and time boundaries.
    func diarize(samples: [Float], sampleRate: Double = 16000) async throws -> [DiarizationSegment] {
        guard let manager = offlineManager else {
            throw DiarizationEngineError.notInitialized
        }

        state = .diarizing(progress: "Processing audio...")
        Self.logger.info("🔬 Starting offline diarization: \(samples.count) samples (\(Double(samples.count) / sampleRate, privacy: .public)s)")

        do {
            let result = try await manager.process(audio: samples)

            let segments = result.segments.map { segment in
                DiarizationSegment(
                    speakerID: segment.speakerId,
                    startTime: TimeInterval(segment.startTimeSeconds),
                    endTime: TimeInterval(segment.endTimeSeconds)
                )
            }

            state = .modelsReady
            Self.logger.info("✅ Diarization complete: \(segments.count) segments, \(Set(segments.map(\.speakerID)).count) speakers detected.")
            return segments
        } catch {
            state = .error("Diarization failed: \(error.localizedDescription)")
            Self.logger.error("❌ Diarization failed: \(error.localizedDescription, privacy: .public)")
            throw DiarizationEngineError.diarizationFailed(error.localizedDescription)
        }
    }

    /// Run offline diarization on a WAV file URL.
    ///
    /// - Parameter fileURL: Path to a WAV file (will be resampled internally by FluidAudio).
    /// - Returns: Array of `DiarizationSegment` with speaker IDs and time boundaries.
    func diarize(fileURL: URL) async throws -> [DiarizationSegment] {
        guard let manager = offlineManager else {
            throw DiarizationEngineError.notInitialized
        }

        state = .diarizing(progress: "Processing file...")
        Self.logger.info("🔬 Starting offline diarization from file: \(fileURL.lastPathComponent, privacy: .public)")

        do {
            let result = try await manager.process(fileURL)

            let segments = result.segments.map { segment in
                DiarizationSegment(
                    speakerID: segment.speakerId,
                    startTime: TimeInterval(segment.startTimeSeconds),
                    endTime: TimeInterval(segment.endTimeSeconds)
                )
            }

            state = .modelsReady
            Self.logger.info("✅ File diarization complete: \(segments.count) segments, \(Set(segments.map(\.speakerID)).count) speakers.")
            return segments
        } catch {
            state = .error("File diarization failed: \(error.localizedDescription)")
            Self.logger.error("❌ File diarization failed: \(error.localizedDescription, privacy: .public)")
            throw DiarizationEngineError.diarizationFailed(error.localizedDescription)
        }
    }

    // MARK: - Temporal Subsegment Alignment

    /// Align WhisperKit transcript segments to FluidAudio diarization speaker windows
    /// using a geometric-midpoint subsegment strategy.
    ///
    /// For each text segment, the midpoint is computed as:
    ///     `midpoint = startTime + (endTime - startTime) / 2`
    ///
    /// The speaker whose active window fully contains (or is nearest to) that midpoint
    /// is assigned to the text segment.
    ///
    /// - Parameters:
    ///   - textSegments: Transcript segments from WhisperKit.
    ///   - diarizationSegments: Speaker segments from FluidAudio.
    /// - Returns: Transcript segments with `speakerID` populated.
    nonisolated func alignSpeakers(
        textSegments: [MeetingTranscriptSegment],
        diarizationSegments: [DiarizationSegment]
    ) -> [MeetingTranscriptSegment] {
        guard !diarizationSegments.isEmpty else { return textSegments }

        return textSegments.map { textSegment in
            let midpoint = textSegment.startTime + (textSegment.endTime - textSegment.startTime) / 2.0

            // Primary: find the speaker whose window fully contains the midpoint
            let containingSpeaker = diarizationSegments.first { segment in
                midpoint >= segment.startTime && midpoint <= segment.endTime
            }

            // Fallback: nearest speaker by start-time proximity
            let bestSpeaker = containingSpeaker ?? diarizationSegments.min(by: {
                abs($0.startTime - midpoint) < abs($1.startTime - midpoint)
            })

            return MeetingTranscriptSegment(
                id: textSegment.id,
                startTime: textSegment.startTime,
                endTime: textSegment.endTime,
                text: textSegment.text,
                speakerID: bestSpeaker?.speakerID,
                language: textSegment.language
            )
        }
    }

    // MARK: - Cleanup

    /// Release CoreML models and free memory.
    func unloadModels() {
        offlineManager = nil
        modelsLoaded = false
        state = .idle
        Self.logger.info("🧹 Diarization models unloaded.")
    }

    /// Whether models are loaded and ready for inference.
    var isReady: Bool {
        modelsLoaded
    }
}

// MARK: - Diarization Segment

/// A speaker-labeled time segment produced by the diarization pipeline.
struct DiarizationSegment: Sendable, Codable, Identifiable {
    let id: UUID
    let speakerID: String
    let startTime: TimeInterval
    let endTime: TimeInterval

    init(speakerID: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.id = UUID()
        self.speakerID = speakerID
        self.startTime = startTime
        self.endTime = endTime
    }

    var duration: TimeInterval { endTime - startTime }
}

// MARK: - Errors

enum DiarizationEngineError: LocalizedError, Sendable {
    case notInitialized
    case modelPreparationFailed(String)
    case diarizationFailed(String)
    case audioValidationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Diarization engine is not initialized. Call prepareModels() first."
        case .modelPreparationFailed(let detail):
            return "Failed to prepare diarization models: \(detail)"
        case .diarizationFailed(let detail):
            return "Diarization failed: \(detail)"
        case .audioValidationFailed(let detail):
            return "Audio validation failed: \(detail)"
        }
    }
}
