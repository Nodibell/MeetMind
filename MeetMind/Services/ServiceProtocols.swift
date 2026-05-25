//
//  ServiceProtocols.swift
//  MeetMind
//
//  Created by Antigravity on 16.05.2026.
//

import Foundation
import CoreAudio
import AVFoundation

enum LLMServiceState: Sendable, Equatable {
    case idle
    case checking
    case available(models: [String])
    case generating
    case unavailable(reason: String)
}

/// Protocol defining the interface for LLM operations.
/// Enables Dependency Injection and Unit Testing.
protocol LLMProvider: Sendable {
    var state: LLMServiceState { get async }
    func checkHealth() async -> Bool
    func generateSummary(transcript: String, targetLanguage: String?) async throws -> String
    func generateTitle(transcript: String) async throws -> String
    func answerQuestion(transcript: String, question: String, history: [LLMService.ChatMessage]) async throws -> String
    func translateText(text: String, to languageName: String) async throws -> String
    func extractSpeakerNames(transcript: String) async throws -> [String: String]
    func generateResponseStream(prompt: String, systemPrompt: String) async -> AsyncThrowingStream<String, Error>
    func setOnTokenReceived(_ callback: (@Sendable (String) -> Void)?) async
    func setOnStateChanged(_ callback: (@Sendable (LLMServiceState) -> Void)?) async
    func unloadDeepModel() async
}

/// Protocol defining the interface for speech-to-text operations.
protocol TranscriptionProvider: Sendable {
    var isReady: Bool { get async }
    var state: TranscriptionService.ServiceState { get async }
    func initialize(modelName: String?) async throws
    func transcribeLive(samples: [Float], offset: TimeInterval) async throws -> [MeetingTranscriptSegment]
    func transcribeFile(at url: URL) async throws -> MeetingTranscriptDocument
    func unloadModels() async
    func setOnStateChanged(_ callback: (@Sendable (TranscriptionService.ServiceState) -> Void)?) async
}

/// Protocol defining the interface for audio management.
protocol AudioProvider: AnyObject, Sendable {
    var isRecording: Bool { get }
    var isPaused: Bool { get }
    var elapsedTime: TimeInterval { get }
    var audioLevels: [Float] { get }
    var availableDevices: [AudioManager.AudioDevice] { get }
    var selectedDeviceID: AudioDeviceID? { get }
    var audioSource: AudioManager.AudioSource { get set }
    
    func startRecording() async throws -> URL
    func stopRecording() -> URL?
    func pauseRecording()
    func resumeRecording()
    func refreshDevices()
    func selectDevice(_ device: AudioManager.AudioDevice)
    func getAvailableSystemAudioSources() async throws -> [AudioManager.SystemAudioSourceInfo]
    func consumeAudioChunk() -> [Float]
}
