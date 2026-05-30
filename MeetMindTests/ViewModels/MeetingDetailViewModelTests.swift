//
//  MeetingDetailViewModelTests.swift
//  MeetMindTests
//
//  Unit tests for MeetingDetailViewModel — covers filteredSegments,
//  tag management, speaker updates, title updates, and chat cancel.
//

import XCTest
import SwiftData
@testable import MeetMind

@MainActor
final class MeetingDetailViewModelTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    var meeting: Meeting!
    var llmMock: MockLLMProvider!
    var transcriptionMock: MockTranscriptionProvider!
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

        llmMock = MockLLMProvider()
        transcriptionMock = MockTranscriptionProvider()
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

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertEqual(sut.meetingTitle, "Тестова нарада")
        XCTAssertTrue(sut.chatMessages.isEmpty)
        XCTAssertFalse(sut.isChatting)
        XCTAssertFalse(sut.isLoadingTranscript)
        XCTAssertFalse(sut.isLoadingSummary)
        XCTAssertFalse(sut.isRegeneratingSummary)
        XCTAssertTrue(sut.searchText.isEmpty)
    }

    // MARK: - filteredSegments

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

    func testFilteredSegments_noMatch_returnsEmpty() {
        let segments = [
            MeetingTranscriptSegment(startTime: 0, endTime: 5, text: "Привіт всім")
        ]
        sut.transcript = MeetingTranscriptDocument(
            meetingId: meeting.id, createdAt: Date(), language: "uk", segments: segments
        )
        sut.searchText = "xyz123_немає"

        XCTAssertTrue(sut.filteredSegments.isEmpty)
    }

    func testFilteredSegments_caseInsensitive() {
        let segments = [
            MeetingTranscriptSegment(startTime: 0, endTime: 5, text: "SwiftData Architecture Review")
        ]
        sut.transcript = MeetingTranscriptDocument(
            meetingId: meeting.id, createdAt: Date(), language: "en", segments: segments
        )
        sut.searchText = "swiftdata"

        XCTAssertEqual(sut.filteredSegments.count, 1)
    }

    func testFilteredSegments_nilTranscript_returnsEmpty() {
        sut.transcript = nil
        sut.searchText = "anything"
        XCTAssertTrue(sut.filteredSegments.isEmpty)
    }

    // MARK: - Tag Management

    func testAddTag_addsTagToMeeting() {
        sut.addTag("swift")
        XCTAssertTrue(meeting.tags.contains("swift"))
    }

    func testAddTag_trimmedWhitespace() {
        sut.addTag("  swift  ")
        XCTAssertTrue(meeting.tags.contains("swift"))
    }

    func testAddTag_emptyString_isIgnored() {
        sut.addTag("")
        XCTAssertTrue(meeting.tags.isEmpty)
    }

    func testAddTag_duplicate_isIgnored() {
        sut.addTag("swift")
        sut.addTag("swift")
        XCTAssertEqual(meeting.tags.filter { $0 == "swift" }.count, 1)
    }

    func testRemoveTag_removesCorrectTag() {
        meeting.tags = ["swift", "ios", "meetmind"]
        sut.removeTag("ios")
        XCTAssertFalse(meeting.tags.contains("ios"))
        XCTAssertTrue(meeting.tags.contains("swift"))
        XCTAssertTrue(meeting.tags.contains("meetmind"))
    }

    func testRemoveTag_nonExistentTag_doesNotCrash() {
        meeting.tags = ["swift"]
        sut.removeTag("nonexistent")
        XCTAssertEqual(meeting.tags, ["swift"])
    }

    // MARK: - Meeting Title Update

    func testUpdateMeetingTitle_validTitle_updates() {
        sut.meetingTitle = "Нова назва наради"
        sut.updateMeetingTitle()
        XCTAssertEqual(meeting.title, "Нова назва наради")
        XCTAssertEqual(sut.meetingTitle, "Нова назва наради")
    }

    func testUpdateMeetingTitle_trimmedWhitespace() {
        sut.meetingTitle = "  Назва з пробілами  "
        sut.updateMeetingTitle()
        XCTAssertEqual(meeting.title, "Назва з пробілами")
    }

    func testUpdateMeetingTitle_emptyString_revertsToExisting() {
        meeting.title = "Оригінальна назва"
        sut.meetingTitle = ""
        sut.updateMeetingTitle()
        // Empty title should be rejected and reverted to existing meeting.title
        XCTAssertEqual(sut.meetingTitle, "Оригінальна назва")
    }

    func testUpdateMeetingTitle_whitespaceOnly_reverts() {
        meeting.title = "Оригінал"
        sut.meetingTitle = "   "
        sut.updateMeetingTitle()
        XCTAssertEqual(sut.meetingTitle, "Оригінал")
    }

    // MARK: - Speaker Management

    func testUpdateSpeakerName_newSpeaker_addsMetadata() {
        sut.updateSpeakerName(id: "Speaker 1", newName: "Олексій")
        XCTAssertEqual(meeting.speakerMetadata.count, 1)
        XCTAssertEqual(meeting.speakerMetadata[0].name, "Олексій")
        XCTAssertEqual(meeting.speakerMetadata[0].id, "Speaker 1")
    }

    func testUpdateSpeakerName_existingSpeaker_updatesName() {
        meeting.speakerMetadata = [SpeakerMetadata(id: "Speaker 1", name: "Старе ім'я", colorHex: nil)]
        sut.updateSpeakerName(id: "Speaker 1", newName: "Нове ім'я")
        XCTAssertEqual(meeting.speakerMetadata.count, 1)
        XCTAssertEqual(meeting.speakerMetadata[0].name, "Нове ім'я")
    }

    func testUpdateSpeakerName_emptyName_setsNil() {
        meeting.speakerMetadata = [SpeakerMetadata(id: "Speaker 1", name: "Олексій", colorHex: nil)]
        sut.updateSpeakerName(id: "Speaker 1", newName: "")
        XCTAssertNil(meeting.speakerMetadata[0].name)
    }

    func testUpdateSpeakerName_withCentroid_createsGlobalProfile() async throws {
        let mockCentroid = Array(repeating: Float(0.1), count: 192)
        meeting.speakerMetadata = [SpeakerMetadata(id: "Speaker 1", name: nil, colorHex: nil, voiceCentroid: mockCentroid)]
        
        sut.updateSpeakerName(id: "Speaker 1", newName: "Олексій")
        
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        let store = SpeakerProfileStore.shared
        let profiles = store.getAllProfiles()
        
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.name, "Олексій")
        XCTAssertEqual(profiles.first?.voiceCentroid, mockCentroid)
    }

    // MARK: - Chat

    func testCancelChat_setsIsChattingFalse() {
        sut.isChatting = true
        sut.cancelChat()
        XCTAssertFalse(sut.isChatting)
    }

    func testCancelSummaryGeneration_restoresSummary() {
        sut.summary = "Збережене резюме"
        sut.streamingSummary = "Частковий стрімінг..."
        sut.isRegeneratingSummary = true

        sut.cancelSummaryGeneration()

        XCTAssertFalse(sut.isRegeneratingSummary)
        // After cancel, streamingSummary should be restored to saved summary
        XCTAssertEqual(sut.streamingSummary, "Збережене резюме")
    }

    // MARK: - Copy Actions

    func testCopyTranscript_withNoTranscript_doesNotCrash() {
        sut.transcript = nil
        // Should not throw or crash
        sut.copyTranscript()
    }

    func testCopySummary_withEmptySummary_doesNotCrash() {
        sut.summary = ""
        sut.copySummary()
    }
}
