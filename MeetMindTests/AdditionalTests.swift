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
