//
//  Constants.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation

enum Constants {
    // MARK: - App Info
    nonisolated static let appName = "MeetMind"
    nonisolated static let appVersion = "1.3.0"
    
    // MARK: - Directories
    nonisolated static let recordingsDirectoryName = "Recordings"
    nonisolated static let transcriptsDirectoryName = "Transcripts"
    nonisolated static let summariesDirectoryName = "Summaries"
    nonisolated static let obsidianMeetingsFolder = "Meetings"
    
    // MARK: - File Extensions
    nonisolated static let audioFileExtension = "wav"
    nonisolated static let transcriptFileExtension = "json"
    nonisolated static let summaryFileExtension = "md"
    
    // MARK: - Audio
    nonisolated static let whisperSampleRate: Double = 16000
    nonisolated static let whisperChannelCount: UInt32 = 1
    nonisolated static let audioBufferSize: UInt32 = 4096
    nonisolated static let waveformSampleCount = 100
    nonisolated static let audioChunkDuration: TimeInterval = 5.0  // seconds per live chunk

    // MARK: - Audio Pipeline Infrastructure
    nonisolated static let audioPipelineQueueLabel = "com.meetmind.audio.pipeline"
    nonisolated static let keepAliveIntervalSeconds: Double = 5.0
    nonisolated static let streamStallThresholdSeconds: Double = 5.0
    nonisolated static let maxStreamReconnectionRetries = 3
    nonisolated static let reconnectionBaseDelaySeconds: Double = 1.0

    // MARK: - Diarization
    nonisolated static let diarizationDirectoryName = "Diarization"
    nonisolated static var diarizationDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent(diarizationDirectoryName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    // MARK: - Whisper Models
    nonisolated static let liveTranscriptionModel = "large-v3_turbo"
    nonisolated static let postProcessingModel = "large-v3"
    nonisolated static let defaultLanguage = "uk"
    
    // MARK: - LLM Settings
    nonisolated static let defaultOllamaEndpoint = "http://localhost:11434"
    nonisolated static let defaultOllamaModel = "gemma3:12b"
    nonisolated static let defaultLMStudioEndpoint = "http://localhost:1234"
    nonisolated static let defaultLMStudioModel = "local-model"
    
    nonisolated static let ollamaHealthPath = "/api/tags"
    nonisolated static let ollamaChatPath = "/api/chat"
    
    nonisolated static let openaiHealthPath = "/v1/models"
    nonisolated static let openaiChatPath = "/v1/chat/completions"
    
    nonisolated static let llmRequestTimeout: TimeInterval = 120
    nonisolated static let maxTokensPerChunk = 4000
    
    // MARK: - Supported Audio Formats
    nonisolated static let supportedAudioExtensions: Set<String> = ["wav", "mp3", "m4a", "flac", "aac"]
    
    // MARK: - File Processing
    nonisolated static let processedFilesManifest = "processed_files.json"
    nonisolated static let maxChunkDuration: TimeInterval = 1800  // 30 minutes
    nonisolated static let chunkOverlap: TimeInterval = 5.0       // 5 second overlap between chunks
    
    // MARK: - App Support Directory
    nonisolated static var appSupportDirectory: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent(appName)
        try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir
    }
    
    nonisolated static var recordingsDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent(recordingsDirectoryName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    nonisolated static var transcriptsDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent(transcriptsDirectoryName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    nonisolated static var summariesDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent(summariesDirectoryName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
