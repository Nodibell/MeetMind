//
//  AdditionalTests.swift
//  MeetMindTests
//
//  Created by Developer on 26.05.2026.
//

import XCTest
import CoreAudio
import SwiftUI
import SwiftData
@testable import MeetMind

// MARK: - Core Original Tests

final class OnboardingViewModelTests: XCTestCase {
    
    struct MockTranscriptionProvider: TranscriptionProvider {
        var isReady: Bool = false
        var state: TranscriptionService.ServiceState = .notReady
        
        func initialize(modelName: String?) async throws {}
        func transcribeLive(samples: [Float], offset: TimeInterval) async throws -> [MeetingTranscriptSegment] { [] }
        func transcribeFile(at url: URL) async throws -> MeetingTranscriptDocument {
            MeetingTranscriptDocument(meetingId: UUID(), createdAt: Date(), language: "en", segments: [])
        }
        func unloadModels() async {}
        func setOnStateChanged(_ callback: (@Sendable (TranscriptionService.ServiceState) -> Void)?) async {}
    }
    
    @MainActor
    func testOnboardingStateChanges() async {
        var mockProvider = MockTranscriptionProvider()
        mockProvider.state = .downloading(progress: 0.5)
        
        let viewModel = OnboardingViewModel(transcriptionService: mockProvider)
        
        // Initial setup
        XCTAssertEqual(viewModel.currentStep, 0)
        XCTAssertFalse(viewModel.micPermission)
        XCTAssertFalse(viewModel.screenPermission)
        XCTAssertEqual(viewModel.downloadProgress, 0.0)
        XCTAssertFalse(viewModel.isDownloading)
        XCTAssertFalse(viewModel.isModelLoading)
        XCTAssertNil(viewModel.errorMessage)
        
        // Manual updates or status simulation
        viewModel.checkCurrentDownloadState()
        
        // After starting model download
        viewModel.startModelDownload()
        XCTAssertTrue(viewModel.isDownloading)
        XCTAssertEqual(viewModel.downloadProgress, 0.0)
    }
    
    func testSupportedFileExtensions() {
        let supportedExtensions: Set<String> = ["wav", "mp3", "m4a", "flac", "aac", "mp4", "mov", "m4v", "mkv", "avi", "caf", "opus", "ogg"]
        
        XCTAssertTrue(supportedExtensions.contains("mp3"))
        XCTAssertTrue(supportedExtensions.contains("wav"))
        XCTAssertTrue(supportedExtensions.contains("m4a"))
        XCTAssertTrue(supportedExtensions.contains("mp4"))
        XCTAssertFalse(supportedExtensions.contains("txt"))
        XCTAssertFalse(supportedExtensions.contains("pdf"))
        XCTAssertFalse(supportedExtensions.contains("png"))
    }
}

final class AudioPlaybackTests: XCTestCase {
    
    func testTimeIntervalFormatting() {
        let oneSecond: TimeInterval = 1
        let tenSeconds: TimeInterval = 10.5
        let fiveMinutes: TimeInterval = 300
        let hour: TimeInterval = 3600
        
        XCTAssertEqual(oneSecond.formattedTimestamp, "00:01")
        XCTAssertEqual(tenSeconds.formattedTimestamp, "00:10")
        XCTAssertEqual(fiveMinutes.formattedTimestamp, "05:00")
        XCTAssertEqual(hour.formattedTimestamp, "60:00")
    }
    
    func testSegmentHighlightingLookup() {
        let segments = [
            MeetingTranscriptSegment(startTime: 0, endTime: 5, text: "First segment"),
            MeetingTranscriptSegment(startTime: 5.1, endTime: 10, text: "Second segment"),
            MeetingTranscriptSegment(startTime: 10.1, endTime: 15, text: "Third segment")
        ]
        
        // Find segment at t = 2.5
        let segment1 = segments.first(where: { 2.5 >= $0.startTime && 2.5 <= $0.endTime })
        XCTAssertNotNil(segment1)
        XCTAssertEqual(segment1?.text, "First segment")
        
        // Find segment at t = 7.0
        let segment2 = segments.first(where: { 7.0 >= $0.startTime && 7.0 <= $0.endTime })
        XCTAssertNotNil(segment2)
        XCTAssertEqual(segment2?.text, "Second segment")
        
        // Find segment at t = 18.0 (out of bounds)
        let segment3 = segments.first(where: { 18.0 >= $0.startTime && 18.0 <= $0.endTime })
        XCTAssertNil(segment3)
    }
}

final class AppRouterTests: XCTestCase {
    
    @MainActor
    func testInitialDestination() {
        let router = AppRouter()
        XCTAssertEqual(router.current, .recording)
        XCTAssertTrue(router.isShowingRecording)
        XCTAssertNil(router.selectedMeetingID)
    }
    
    @MainActor
    func testNavigationTransitions() {
        let router = AppRouter()
        
        // Navigate to global search
        router.navigate(to: .globalSearch)
        XCTAssertEqual(router.current, .globalSearch)
        XCTAssertEqual(router.selectedMeetingID, UUID.globalSearch)
        
        // Navigate to action items
        router.navigate(to: .actionItems)
        XCTAssertEqual(router.current, .actionItems)
        XCTAssertEqual(router.selectedMeetingID, UUID.actionItems)
        
        // Navigate to a meeting
        let meetingUUID = UUID()
        router.navigate(to: .meeting(meetingUUID))
        XCTAssertEqual(router.current, .meeting(meetingUUID))
        XCTAssertEqual(router.selectedMeetingID, meetingUUID)
        
        // Navigate to a group chat
        let groupUUID = UUID()
        router.navigate(to: .groupChat(groupUUID))
        XCTAssertEqual(router.current, .groupChat(groupUUID))
        XCTAssertEqual(router.selectedMeetingID, groupUUID)
        
        // Navigate to recording complete
        let newMeetingUUID = UUID()
        router.navigateAfterRecordingComplete(meetingID: newMeetingUUID)
        XCTAssertEqual(router.current, .meeting(newMeetingUUID))
        
        // Reset to recording
        router.startNewRecording()
        XCTAssertTrue(router.isShowingRecording)
        XCTAssertNil(router.selectedMeetingID)
    }
}

// MARK: - Testing Mocks

final class UniqueMockAudioProvider: AudioProvider, @unchecked Sendable {
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

struct UniqueMockTranscriptionProvider: TranscriptionProvider {
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

final class UniqueMockLLMProvider: LLMProvider, @unchecked Sendable {
    var state: LLMServiceState = .idle
    var onStateChanged: (@Sendable (LLMServiceState) -> Void)?
    var onTokenReceived: (@Sendable (String) -> Void)?

    func checkHealth() async -> Bool { true }
    func generateSummary(transcript: String, targetLanguage: String?) async throws -> String { "Тестове резюме" }
    func generateTitle(transcript: String) async throws -> String { "Тестова назва" }
    func answerQuestion(transcript: String, question: String, history: [LLMService.ChatMessage]) async throws -> String { "Тестова відповідь" }
    func translateText(text: String, to languageName: String) async throws -> String { "Перекладений текст" }
    func extractSpeakerNames(transcript: String) async throws -> [String: String] { [:] }
    func generateResponseStream(prompt: String, systemPrompt: String) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("Частина відповіді")
            continuation.finish()
        }
    }
    func setOnTokenReceived(_ callback: (@Sendable (String) -> Void)?) async { self.onTokenReceived = callback }
    func setOnStateChanged(_ callback: (@Sendable (LLMServiceState) -> Void)?) async { self.onStateChanged = callback }
    func unloadDeepModel() async {}
}

// MARK: - RecordingViewModelTests

@MainActor
final class RecordingViewModelTests: XCTestCase {

    var audioMock: UniqueMockAudioProvider!
    var transcriptionMock: UniqueMockTranscriptionProvider!
    var llmMock: UniqueMockLLMProvider!
    var sut: RecordingViewModel!

    override func setUp() {
        super.setUp()
        audioMock = UniqueMockAudioProvider()
        transcriptionMock = UniqueMockTranscriptionProvider()
        llmMock = UniqueMockLLMProvider()
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

    func testInitialState_isIdle() {
        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(sut.meetingTitle == "Нова нарада" || sut.meetingTitle == "New Meeting", "Title should match default localized string 'Нова нарада' / 'New Meeting'")
        XCTAssertTrue(sut.liveTranscript.isEmpty)
        XCTAssertNil(sut.fullTranscript)
        XCTAssertEqual(sut.summary, "")
        XCTAssertEqual(sut.transcriptionProgressValue, 0.0)
        XCTAssertNil(sut.errorMessage)
        XCTAssertNil(sut.completedMeetingID)
        XCTAssertTrue(sut.isFloatingIndicatorVisible)
    }

    func testIsErrorState_whenError_returnsTrue() {
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

    func testResetForNewRecording_clearsAllState() {
        sut.state = .complete
        sut.meetingTitle = "Стара нарада"
        sut.liveTranscript = [
            MeetingTranscriptSegment(startTime: 0, endTime: 1, text: "Привіт")
        ]
        sut.summary = "Старе резюме"
        sut.streamingSummary = "Частковий стрімінг..."
        sut.errorMessage = "Помилка"
        sut.transcriptionProgressValue = 0.75
        sut.isFloatingIndicatorVisible = false

        sut.resetForNewRecording()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(sut.meetingTitle == "Нова нарада" || sut.meetingTitle == "New Meeting", "Title should be reset to default localized 'Нова нарада' / 'New Meeting'")
        XCTAssertTrue(sut.liveTranscript.isEmpty)
        XCTAssertNil(sut.fullTranscript)
        XCTAssertEqual(sut.summary, "")
        XCTAssertEqual(sut.streamingSummary, "")
        XCTAssertNil(sut.errorMessage)
        XCTAssertNil(sut.completedMeetingID)
        XCTAssertEqual(sut.transcriptionProgressValue, 0.0)
        XCTAssertTrue(sut.isFloatingIndicatorVisible)
    }

    func testStartRecording_whenAlreadyRecording_doesNothing() {
        sut.state = .recording
        sut.startRecording()
        XCTAssertEqual(sut.state, .recording)
    }

    func testCancelActiveProcessing_resetsStateAndClearsMeeting() {
        let meeting = Meeting(title: "Тест")
        sut.state = .recording
        sut.currentMeeting = meeting
        
        let container = try! ModelContainer(for: Meeting.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        sut.setModelContext(container.mainContext)
        try! container.mainContext.insert(meeting)
        try! container.mainContext.save()
        
        sut.cancelActiveProcessing()
        
        XCTAssertEqual(sut.state, .idle)
        XCTAssertNil(sut.currentMeeting)
        
        let descriptor = FetchDescriptor<Meeting>()
        let count = try! container.mainContext.fetchCount(descriptor)
        XCTAssertEqual(count, 0)
    }
}

// MARK: - MeetingDetailViewModelTests

@MainActor
final class MeetingDetailViewModelTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    var meeting: Meeting!
    var llmMock: UniqueMockLLMProvider!
    var transcriptionMock: UniqueMockTranscriptionProvider!
    var sut: MeetingDetailViewModel!

    override func setUpWithError() throws {
        let schema = Schema([
            Meeting.self, SpeakerProfile.self, TranscriptSegment.self,
            ActionItem.self, Decision.self, MeetingGroup.self,
            VectorEmbeddingEntity.self, GroupChatMessageEntity.self,
            GroupChatSessionEntity.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)

        meeting = Meeting(title: "Тестова нарада")
        context.insert(meeting)
        try context.save()

        llmMock = UniqueMockLLMProvider()
        transcriptionMock = UniqueMockTranscriptionProvider()
        sut = MeetingDetailViewModel(
            meeting: meeting,
            llmService: llmMock,
            transcriptionService: transcriptionMock
        )
        sut.setModelContext(context)
    }

    override func tearDownWithError() throws {
        sut = nil
        llmMock = nil
        transcriptionMock = nil
        meeting = nil
        context = nil
        container = nil
    }

    func testInitialState() {
        XCTAssertEqual(sut.meetingTitle, "Тестова нарада")
        XCTAssertTrue(sut.chatMessages.isEmpty)
        XCTAssertFalse(sut.isChatting)
        XCTAssertFalse(sut.isLoadingTranscript)
        XCTAssertFalse(sut.isLoadingSummary)
        XCTAssertFalse(sut.isRegeneratingSummary)
        XCTAssertTrue(sut.searchText.isEmpty)
    }

    func testFilteredSegments_noSearchText_returnsAll() {
        let segments = [
            MeetingTranscriptSegment(startTime: 0, endTime: 5, text: "Привіт всім"),
            MeetingTranscriptSegment(startTime: 5, endTime: 10, text: "Обговоримо плани")
        ]
        sut.transcript = MeetingTranscriptDocument(
            meetingId: meeting.id, createdAt: Date(), language: "uk", segments: segments
        )
        sut.searchText = ""

        XCTAssertEqual(sut.filteredSegments.count, 2)
    }

    func testFilteredSegments_withMatchingSearch_returnsFiltered() {
        let segments = [
            MeetingTranscriptSegment(startTime: 0, endTime: 5, text: "Привіт всім"),
            MeetingTranscriptSegment(startTime: 5, endTime: 10, text: "Обговоримо плани")
        ]
        sut.transcript = MeetingTranscriptDocument(
            meetingId: meeting.id, createdAt: Date(), language: "uk", segments: segments
        )
        sut.searchText = "привіт"

        XCTAssertEqual(sut.filteredSegments.count, 1)
        XCTAssertEqual(sut.filteredSegments[0].text, "Привіт всім")
    }

    func testAddTag_addsTagToMeeting() {
        sut.addTag("swift")
        XCTAssertTrue(meeting.tags.contains("swift"))
    }

    func testRemoveTag_removesCorrectTag() {
        meeting.tags = ["swift", "ios", "meetmind"]
        sut.removeTag("ios")
        XCTAssertFalse(meeting.tags.contains("ios"))
        XCTAssertTrue(meeting.tags.contains("swift"))
    }

    func testUpdateMeetingTitle_validTitle_updates() {
        sut.meetingTitle = "Нова назва наради"
        sut.updateMeetingTitle()
        XCTAssertEqual(meeting.title, "Нова назва наради")
    }

    func testUpdateSpeakerName_newSpeaker_addsMetadata() {
        sut.updateSpeakerName(id: "Speaker 1", newName: "Олексій")
        XCTAssertEqual(meeting.speakerMetadata.count, 1)
        XCTAssertEqual(meeting.speakerMetadata[0].name, "Олексій")
    }

    func testCancelChat_setsIsChattingFalse() {
        sut.isChatting = true
        sut.cancelChat()
        XCTAssertFalse(sut.isChatting)
    }
}

// MARK: - SettingsViewModelTests

@MainActor
final class SettingsViewModelTests: XCTestCase {

    var llmMock: UniqueMockLLMProvider!
    var audioMock: UniqueMockAudioProvider!
    var sut: SettingsViewModel!

    override func setUp() {
        super.setUp()
        llmMock = UniqueMockLLMProvider()
        audioMock = UniqueMockAudioProvider()
        sut = SettingsViewModel(llmService: llmMock, audioManager: audioMock)
    }

    override func tearDown() {
        sut = nil
        llmMock = nil
        audioMock = nil
        super.tearDown()
    }

    func testInitialState() {
        XCTAssertEqual(sut.ollamaStatus, .unknown)
        XCTAssertTrue(sut.availableModels.isEmpty)
        XCTAssertFalse(sut.isCheckingOllama)
        XCTAssertNil(sut.ollamaError)
    }

    func testOllamaStatus_unknown_equatable() {
        XCTAssertEqual(SettingsViewModel.OllamaStatus.unknown, .unknown)
        XCTAssertNotEqual(SettingsViewModel.OllamaStatus.unknown, .connected)
    }

    func testModelSelectionWarning_embeddingModel_returnsWarning() {
        let warning = LLMService.modelSelectionWarning(
            model: "nomic-embed-text",
            provider: .ollama
        )
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning!.contains("embedding"))
    }

    func testModelSelectionWarning_chatModel_returnsNil() {
        let warning = LLMService.modelSelectionWarning(
            model: "gemma3:12b",
            provider: .ollama
        )
        XCTAssertNil(warning)
    }
}

// MARK: - ParseSummaryUseCaseTests

final class ParseSummaryUseCaseTests: XCTestCase {

    var sut: ParseSummaryUseCase!

    override func setUp() {
        super.setUp()
        sut = ParseSummaryUseCase()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testExtractActionItems_emptyMarkdown_returnsEmpty() {
        let result = sut.extractActionItems(from: "")
        XCTAssertTrue(result.isEmpty)
    }

    func testExtractActionItems_singleUnchecked() {
        let markdown = "- [ ] Написати юніт-тести"
        let result = sut.extractActionItems(from: markdown)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Написати юніт-тести")
        XCTAssertFalse(result[0].isCompleted)
    }

    func testExtractActionItems_withAtSignAssignee() {
        let markdown = "- [ ] Написати документацію @Марія"
        let result = sut.extractActionItems(from: markdown)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Написати документацію")
        XCTAssertEqual(result[0].assignee, "Марія")
    }

    func testExtractDecisions_ukrainianSectionHeader() {
        let markdown = """
        ## Прийняті рішення
        - Вирішили перейти на SwiftData.
        - Затвердили нову дизайн-систему.
        """
        let result = sut.extractDecisions(from: markdown)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(where: { $0.text.contains("SwiftData") }))
    }
}

// MARK: - ExportMeetingUseCaseTests

final class ExportMeetingUseCaseTests: XCTestCase {

    var sut: ExportMeetingUseCase!
    var tempDir: URL!

    override func setUpWithError() throws {
        super.setUp()
        sut = ExportMeetingUseCase()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    private func makeMeeting() -> Meeting {
        return Meeting(
            title: "Тестова нарада",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 3600,
            language: "uk",
            tags: ["meeting", "test"]
        )
    }

    func testExecute_withVaultURL_createsFile() throws {
        let meeting = makeMeeting()
        let fileURL = try sut.execute(
            meeting: meeting,
            transcript: nil,
            summary: "",
            vaultURL: tempDir
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(fileURL.pathExtension, "md")
    }

    func testExecute_markdownContainsTitle() throws {
        let meeting = makeMeeting()
        let fileURL = try sut.execute(
            meeting: meeting,
            transcript: nil,
            summary: "",
            vaultURL: tempDir
        )

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("Тестова нарада"))
    }
}
