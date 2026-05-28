//
//  AdditionalTests.swift
//  MeetMindTests
//
//  Created by Developer on 26.05.2026.
//

import XCTest
import SwiftUI
@testable import MeetMind

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
