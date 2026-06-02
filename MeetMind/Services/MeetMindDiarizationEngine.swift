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
import CoreML
import Accelerate

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
        let startTime = CFAbsoluteTimeGetCurrent()
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

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            state = .modelsReady
            Self.logger.info("✅ Diarization complete: \(segments.count) segments, \(Set(segments.map(\.speakerID)).count) speakers detected. Time: \(String(format: "%.2f", duration))s")
            return segments
        } catch {
            state = .error("Diarization failed: \(error.localizedDescription)")
            Self.logger.error("❌ Diarization failed: \(error.localizedDescription, privacy: .public)")
            throw DiarizationEngineError.diarizationFailed(error.localizedDescription)
        }
    }

    private var lastEmbeddings: [String: [Float]] = [:]

    /// Run offline diarization on a WAV file URL.
    ///
    /// - Parameter fileURL: Path to a WAV file (will be resampled internally by FluidAudio).
    /// - Returns: Array of `DiarizationSegment` with speaker IDs and time boundaries.
    func diarize(fileURL: URL) async throws -> ([DiarizationSegment], [String: [Float]]) {
        guard let manager = offlineManager else {
            throw DiarizationEngineError.notInitialized
        }

        state = .diarizing(progress: "Processing file...")
        let startTime = CFAbsoluteTimeGetCurrent()
        Self.logger.info("🔬 Starting offline diarization from file: \(fileURL.lastPathComponent, privacy: .public)")

        do {
            let result = try await manager.process(fileURL)
            
            // Extract embeddings/centroids for identification
            self.lastEmbeddings = result.speakerDatabase ?? [:] 

            let segments = result.segments.map { segment in
                DiarizationSegment(
                    speakerID: segment.speakerId,
                    startTime: TimeInterval(segment.startTimeSeconds),
                    endTime: TimeInterval(segment.endTimeSeconds)
                )
            }

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            state = .modelsReady
            Self.logger.info("✅ File diarization complete: \(segments.count) segments, \(Set(segments.map(\.speakerID)).count) speakers. Time: \(String(format: "%.2f", duration))s")
            return (segments, lastEmbeddings)
        } catch {
            state = .error("File diarization failed: \(error.localizedDescription)")
            Self.logger.error("❌ File diarization failed: \(error.localizedDescription, privacy: .public)")
            throw DiarizationEngineError.diarizationFailed(error.localizedDescription)
        }
    }

    // MARK: - Temporal Subsegment Alignment

    /// Align WhisperKit transcript segments to speaker windows using a strict 
    /// overlap duration strategy for maximum attribution accuracy.
    nonisolated func alignSpeakers(
        textSegments: [MeetingTranscriptSegment],
        diarizationSegments: [DiarizationSegment]
    ) -> [MeetingTranscriptSegment] {
        guard !diarizationSegments.isEmpty else { return textSegments }

        return textSegments.map { textSegment in
            // Calculate temporal overlap with each diarization segment
            let bestSegment = diarizationSegments.map { segment -> (DiarizationSegment, TimeInterval) in
                let overlapStart = max(textSegment.startTime, segment.startTime)
                let overlapEnd = min(textSegment.endTime, segment.endTime)
                let overlap = max(0.0, overlapEnd - overlapStart)
                return (segment, overlap)
            }.max(by: { $0.1 < $1.1 })

            let speakerID: String?
            if let bestSegment, bestSegment.1 > 0 {
                speakerID = bestSegment.0.speakerID
            } else {
                // Fallback to nearest segment if no overlap is present
                let midpoint = textSegment.startTime + (textSegment.endTime - textSegment.startTime) / 2.0
                speakerID = diarizationSegments.min(by: {
                    let d1 = min(abs($0.startTime - midpoint), abs($0.endTime - midpoint))
                    let d2 = min(abs($1.startTime - midpoint), abs($1.endTime - midpoint))
                    return d1 < d2
                })?.speakerID
            }

            return MeetingTranscriptSegment(
                id: textSegment.id,
                startTime: textSegment.startTime,
                endTime: textSegment.endTime,
                text: textSegment.text,
                speakerID: speakerID,
                language: textSegment.language,
                suggestedSpeakerName: nil
            )
        }
    }

    /// Identify known speakers using the SpeakerProfileStore and update transcript segments.
    func identifySpeakers(segments: [MeetingTranscriptSegment], centroids: [String: [Float]]) async -> [MeetingTranscriptSegment] {
        var speakerMap: [String: SpeakerProfile] = [:]
        var suggestedMap: [String: String] = [:]
        let store = await SpeakerProfileStore.shared
        
        for (speakerID, centroid) in centroids {
            let result = await store.findMatchingProfileWithSuggestion(for: centroid)
            if let profile = result.profile {
                speakerMap[speakerID] = profile
            } else if let suggestion = result.suggestion {
                suggestedMap[speakerID] = suggestion.name
            }
        }
        
        return segments.map { segment in
            guard let id = segment.speakerID else {
                return segment
            }
            
            let matchedProfile = speakerMap[id]
            let suggestedName = suggestedMap[id]
            
            return MeetingTranscriptSegment(
                id: segment.id,
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: segment.text,
                speakerID: segment.speakerID,
                speakerName: matchedProfile?.name ?? segment.speakerName,
                language: segment.language,
                suggestedSpeakerName: suggestedName
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

    nonisolated init(speakerID: String, startTime: TimeInterval, endTime: TimeInterval) {
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
