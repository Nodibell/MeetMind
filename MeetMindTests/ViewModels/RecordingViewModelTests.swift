//
//  RecordingViewModelTests.swift
//  MeetMindTests
//
//  Unit tests for RecordingViewModel state machine logic.
//  Uses protocol-based mocks (MockAudioProvider, MockTranscriptionProvider, MockLLMProvider)
//  to stay fully isolated from real hardware and network.
//

import XCTest
import SwiftData
@testable import MeetMind

// MARK: - Mock Audio Provider

final class MockAudioProvider: AudioProvider, @unchecked Sendable {
    var isRecording: Bool = false
    var isPaused: Bool = false
    var elapsedTime: TimeInterval = 0
    var audioLevels: [Float] = [0.5]
    var availableDevices: [AudioManager.AudioDevice] = []
    var selectedDeviceID: AudioDeviceID? = nil
    var audioSource: AudioManager.AudioSource = .microphone

    var startRecordingURL: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("test_recording.m4a")
    var shouldThrowOnStart = false

    func startRecording() async throws -> URL {
        if shouldThrowOnStart {
            throw NSError(domain: "MockAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated start failure"])
        }
        isRecording = true
        return startRecordingURL
    }

    func stopRecording() -> URL? {
        isRecording = false
        return startRecordingURL
    }

    func pauseRecording() { isPaused = true }
    func resumeRecording() { isPaused = false }
    func refreshDevices() {}
    func selectDevice(_ device: AudioManager.AudioDevice) {}
    func getAvailableSystemAudioSources() async throws -> [AudioManager.SystemAudioSourceInfo] { [] }
    func consumeAudioChunk() -> [Float] { [] }
}

// MARK: - RecordingViewModelTests

@MainActor
final class RecordingViewModelDetailedTests: XCTestCase {

    var audioMock: MockAudioProvider!
    var transcriptionMock: MockTranscriptionProvider!
    var llmMock: MockLLMProvider!
    var sut: RecordingViewModel!

    override func setUp() {
        super.setUp()
        audioMock = MockAudioProvider()
        transcriptionMock = MockTranscriptionProvider()
        llmMock = MockLLMProvider()
        sut = RecordingViewModel(
            audioManager: audioMock,
            transcriptionService: transcriptionMock,
            llmService: llmMock
        )
    }

    override func tearDown() {
        sut = nil
        audioMock = nil
        transcriptionMock = nil
        llmMock = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState_isIdle() {
        XCTAssertEqual(sut.state, .idle)
        XCTAssertEqual(sut.meetingTitle, "Нова нарада")
        XCTAssertTrue(sut.liveTranscript.isEmpty)
        XCTAssertNil(sut.fullTranscript)
        XCTAssertEqual(sut.summary, "")
        XCTAssertEqual(sut.transcriptionProgressValue, 0.0)
        XCTAssertNil(sut.errorMessage)
        XCTAssertNil(sut.completedMeetingID)
        XCTAssertTrue(sut.isFloatingIndicatorVisible)
    }

    // MARK: - isErrorState helper

    func testIsErrorState_whenError_returnsTrue() {
        // Access internal helper indirectly via state
        // We set the state to .error and check related behaviors
        sut.state = .error("Тестова помилка")
        if case .error(let msg) = sut.state {
            XCTAssertEqual(msg, "Тестова помилка")
        } else {
            XCTFail("Expected .error state")
        }
    }

    func testIsErrorState_whenRecording_returnsFalse() {
        sut.state = .recording
        if case .error = sut.state {
            XCTFail("Should not be in .error state")
        }
    }

    // MARK: - RecordingState Equatable

    func testRecordingStateEquatable_idle() {
        XCTAssertEqual(RecordingViewModel.RecordingState.idle, .idle)
        XCTAssertNotEqual(RecordingViewModel.RecordingState.idle, .recording)
    }

    func testRecordingStateEquatable_error() {
        let err1 = RecordingViewModel.RecordingState.error("msg")
        let err2 = RecordingViewModel.RecordingState.error("msg")
        let err3 = RecordingViewModel.RecordingState.error("different")
        XCTAssertEqual(err1, err2)
        XCTAssertNotEqual(err1, err3)
    }

    // MARK: - resetForNewRecording

    func testResetForNewRecording_clearsAllState() {
        // Arrange: set up dirty state
        sut.state = .complete
        sut.meetingTitle = "Стара нарада"
        sut.liveTranscript = [
            MeetingTranscriptSegment(startTime: 0, endTime: 1, text: "Привіт")
        ]
        sut.summary = "Старе резюме"
        sut.streamingSummary = "Стрімінг"
        sut.errorMessage = "Помилка"
        sut.transcriptionProgressValue = 0.75
        sut.isFloatingIndicatorVisible = false

        // Act
        sut.resetForNewRecording()

        // Assert
        XCTAssertEqual(sut.state, .idle)
        XCTAssertEqual(sut.meetingTitle, "Нова нарада")
        XCTAssertTrue(sut.liveTranscript.isEmpty)
        XCTAssertNil(sut.fullTranscript)
        XCTAssertEqual(sut.summary, "")
        XCTAssertEqual(sut.streamingSummary, "")
        XCTAssertNil(sut.errorMessage)
        XCTAssertNil(sut.completedMeetingID)
        XCTAssertEqual(sut.transcriptionProgressValue, 0.0)
        XCTAssertTrue(sut.isFloatingIndicatorVisible)
    }

    // MARK: - startRecording guard

    func testStartRecording_whenAlreadyRecording_doesNothing() {
        sut.state = .recording
        sut.startRecording()
        // Should remain in .recording since guard filters it
        XCTAssertEqual(sut.state, .recording)
    }

    func testStartRecording_whenTranscribing_doesNothing() {
        sut.state = .transcribing
        sut.startRecording()
        XCTAssertEqual(sut.state, .transcribing)
    }

    func testStartRecording_whenSummarizing_doesNothing() {
        sut.state = .summarizing
        sut.startRecording()
        XCTAssertEqual(sut.state, .summarizing)
    }

    // MARK: - stopRecording guard

    func testStopRecording_whenNotRecording_doesNothing() {
        sut.state = .idle
        sut.stopRecording()
        // Should remain idle, not go to .stopping
        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - Recording State Enum Coverage

    func testAllRecordingStates_areDistinct() {
        let states: [RecordingViewModel.RecordingState] = [
            .idle, .preparing, .extracting, .recording,
            .stopping, .transcribing, .summarizing, .complete, .error("x")
        ]
        // All states should be unique when compared pairwise
        for (i, stateA) in states.enumerated() {
            for (j, stateB) in states.enumerated() {
                if i == j {
                    XCTAssertEqual(stateA, stateB)
                } else {
                    XCTAssertNotEqual(stateA, stateB,
                        "\(stateA) should not equal \(stateB)")
                }
            }
        }
    }

    // MARK: - cancelActiveProcessing

    func testCancelActiveProcessing_resetsStateAndClearsMeeting() {
        // Arrange
        let meeting = Meeting(title: "Тест")
        sut.state = .recording
        sut.currentMeeting = meeting
        
        let container = try! ModelContainer(for: Meeting.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        sut.setModelContext(container.mainContext)
        try! container.mainContext.insert(meeting)
        try! container.mainContext.save()
        
        // Act
        sut.cancelActiveProcessing()
        
        // Assert
        XCTAssertEqual(sut.state, .idle)
        XCTAssertNil(sut.currentMeeting)
        
        // Verify it was deleted from context
        let descriptor = FetchDescriptor<Meeting>()
        let count = try! container.mainContext.fetchCount(descriptor)
        XCTAssertEqual(count, 0)
    }
}

// MARK: - MockTranscriptionProvider (reusable, defined in this file scope)

struct MockTranscriptionProvider: TranscriptionProvider {
    var isReady: Bool = true
    var state: TranscriptionService.ServiceState = .ready

    func initialize(modelName: String?) async throws {}

    func transcribeLive(samples: [Float], offset: TimeInterval) async throws -> [MeetingTranscriptSegment] {
        return []
    }

    func transcribeFile(at url: URL) async throws -> MeetingTranscriptDocument {
        return MeetingTranscriptDocument(
            meetingId: UUID(),
            createdAt: Date(),
            language: "uk",
            segments: []
        )
    }

    func unloadModels() async {}
    func setOnStateChanged(_ callback: (@Sendable (TranscriptionService.ServiceState) -> Void)?) async {}
}
