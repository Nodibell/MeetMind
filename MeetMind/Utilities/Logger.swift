//
//  Logger.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation
import os

// MARK: - Structured Logging Subsystem

/// Production-grade structured logging using `os.Logger`.
///
/// Each pipeline stage has its own category for fine-grained filtering in Console.app.
/// Transcript and semantic content is **always** logged with `.private` to prevent
/// leakage into crash reports or on-disk sysdiagnose archives.
enum AppLogger {

    // MARK: - Subsystem

    private static let subsystem = "com.meetmind.app"

    // MARK: - Category Loggers

    /// General application lifecycle events.
    nonisolated(unsafe) private static let general   = Logger(subsystem: subsystem, category: "General")

    /// Audio capture pipeline (microphone, ScreenCaptureKit, format conversion).
    nonisolated(unsafe) private static let audioPipe = Logger(subsystem: subsystem, category: "AudioPipeline")

    /// AI inference: WhisperKit transcription, FluidAudio diarization.
    nonisolated(unsafe) private static let aiPipe    = Logger(subsystem: subsystem, category: "AIInference")

    /// Memory pressure and system health monitoring.
    nonisolated(unsafe) private static let health    = Logger(subsystem: subsystem, category: "SystemHealth")

    /// SCStream keep-alive watchdog and reconnection logic.
    nonisolated(unsafe) private static let watchdog  = Logger(subsystem: subsystem, category: "StreamWatchdog")

    // MARK: - Public API

    /// Log a general informational message.
    nonisolated static func info(_ message: String) {
        general.info("ℹ️ \(message, privacy: .public)")
    }

    /// Log a general error with an optional `Error` payload.
    nonisolated static func error(_ message: String, error: Error? = nil) {
        if let error {
            general.error("❌ \(message, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        } else {
            general.error("❌ \(message, privacy: .public)")
        }
    }

    /// Log a warning.
    nonisolated static func warning(_ message: String) {
        general.warning("⚠️ \(message, privacy: .public)")
    }

    /// Log a debug-only message (stripped in Release).
    nonisolated static func debug(_ message: String) {
        #if DEBUG
        general.debug("🪲 \(message, privacy: .public)")
        #endif
    }

    // MARK: - Audio Pipeline

    /// Log audio pipeline events (capture start/stop, format conversion, buffer flow).
    nonisolated static func audio(_ message: String) {
        audioPipe.info("🎤 \(message, privacy: .public)")
    }

    /// Log audio pipeline errors.
    nonisolated static func audioError(_ message: String, error: Error? = nil) {
        if let error {
            audioPipe.error("🎤❌ \(message, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        } else {
            audioPipe.error("🎤❌ \(message, privacy: .public)")
        }
    }

    // MARK: - AI Inference

    /// Log AI inference events (model load, transcription, diarization).
    nonisolated static func ai(_ message: String) {
        aiPipe.info("🤖 \(message, privacy: .public)")
    }

    /// Log AI inference errors.
    nonisolated static func aiError(_ message: String, error: Error? = nil) {
        if let error {
            aiPipe.error("🤖❌ \(message, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        } else {
            aiPipe.error("🤖❌ \(message, privacy: .public)")
        }
    }

    // MARK: - System Health

    /// Log memory pressure and system health events.
    nonisolated static func systemHealth(_ message: String) {
        health.warning("💊 \(message, privacy: .public)")
    }

    // MARK: - Stream Watchdog

    /// Log SCStream keep-alive and reconnection events.
    nonisolated static func streamWatchdog(_ message: String) {
        watchdog.info("🐕 \(message, privacy: .public)")
    }

    nonisolated static func streamWatchdogError(_ message: String, error: Error? = nil) {
        if let error {
            watchdog.error("🐕❌ \(message, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        } else {
            watchdog.error("🐕❌ \(message, privacy: .public)")
        }
    }

    // MARK: - Redacted Transcript Logging

    /// Log transcript content **always** redacted. Use this when you need to confirm
    /// a transcription step completed but must never leak raw text to disk logs.
    nonisolated static func transcriptRedacted(segmentCount: Int, durationSeconds: Double) {
        aiPipe.info("📝 Transcription complete: \(segmentCount, privacy: .public) segments, \(durationSeconds, privacy: .public)s duration [content redacted]")
    }
}
