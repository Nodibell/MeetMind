//
//  ExportMeetingUseCaseTests.swift
//  MeetMindTests
//
//  Unit tests for ExportMeetingUseCase — tests Markdown generation
//  using a real temporary directory (no Obsidian required).
//

import XCTest
@testable import MeetMind

final class ExportMeetingUseCaseTests: XCTestCase {

    var sut: ExportMeetingUseCase!
    var tempDir: URL!

    override func setUpWithError() throws {
        super.setUp()
        sut = ExportMeetingUseCase()
        // Create isolated temp directory for each test
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeMeeting(
        title: String = "Тестова нарада",
        duration: TimeInterval = 3600,
        language: String = "uk",
        tags: [String] = ["meeting", "test"]
    ) -> Meeting {
        return Meeting(
            title: title,
            date: Date(timeIntervalSince1970: 1_700_000_000), // fixed date for determinism
            duration: duration,
            language: language,
            tags: tags
        )
    }

    // MARK: - Error Cases

    func testExecute_vaultPathNotConfigured_throws() throws {
        let meeting = makeMeeting()
        // Don't set AppSettings.shared.obsidianVaultPath
        // Use the overload that reads from AppSettings — it should throw
        let savedVault = AppSettings.shared.obsidianVaultPath
        AppSettings.shared.obsidianVaultPath = nil
        defer { AppSettings.shared.obsidianVaultPath = savedVault }

        XCTAssertThrowsError(
            try sut.execute(meeting: meeting, transcript: nil, summary: "")
        ) { error in
            guard let exportError = error as? ExportMeetingUseCase.ExportError,
                  case .vaultPathNotConfigured = exportError else {
                XCTFail("Expected vaultPathNotConfigured, got \(error)")
                return
            }
        }
    }

    // MARK: - Successful Export

    func testExecute_withVaultURL_createsFile() throws {
        let meeting = makeMeeting()
        let fileURL = try sut.execute(
            meeting: meeting,
            transcript: nil,
            summary: "",
            vaultURL: tempDir
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
                      "Expected Markdown file to be created at \(fileURL.path)")
        XCTAssertEqual(fileURL.pathExtension, "md")
    }

    func testExecute_createsInsideMeetingsSubfolder() throws {
        let meeting = makeMeeting()
        let fileURL = try sut.execute(
            meeting: meeting,
            transcript: nil,
            summary: "",
            vaultURL: tempDir
        )

        // File should be inside <vault>/Meetings/
        let meetingsDir = tempDir.appendingPathComponent(Constants.obsidianMeetingsFolder)
        XCTAssertTrue(fileURL.path.hasPrefix(meetingsDir.path),
                      "Expected file inside Meetings subfolder, got: \(fileURL.path)")
    }

    func testExecute_markdownContainsTitle() throws {
        let meeting = makeMeeting(title: "Щотижневий синк")
        let fileURL = try sut.execute(
            meeting: meeting,
            transcript: nil,
            summary: "",
            vaultURL: tempDir
        )

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("Щотижневий синк"),
                      "Expected title in Markdown content")
    }

    func testExecute_markdownContainsYAMLFrontmatter() throws {
        let meeting = makeMeeting(tags: ["daily", "team"])
        let fileURL = try sut.execute(
            meeting: meeting,
            transcript: nil,
            summary: "",
            vaultURL: tempDir
        )

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("---\n"), "Expected YAML frontmatter at start")
        XCTAssertTrue(content.contains("tags:"), "Expected tags in frontmatter")
        XCTAssertTrue(content.contains("daily"), "Expected tag 'daily' in frontmatter")
        XCTAssertTrue(content.contains("language:"), "Expected language in frontmatter")
        XCTAssertTrue(content.contains("duration:"), "Expected duration in frontmatter")
    }

    func testExecute_markdownContainsTranscript() throws {
        let meeting = makeMeeting()
        let transcript = MeetingTranscriptDocument(
            meetingId: meeting.id,
            createdAt: Date(),
            language: "uk",
            segments: [
                MeetingTranscriptSegment(
                    startTime: 0,
                    endTime: 10,
                    text: "Привіт, це тестовий транскрипт.",
                    speakerID: "Speaker 1",
                    speakerName: "Олексій"
                )
            ]
        )

        let fileURL = try sut.execute(
            meeting: meeting,
            transcript: transcript,
            summary: "",
            vaultURL: tempDir
        )

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("Привіт, це тестовий транскрипт."),
                      "Expected transcript text in Markdown")
    }

    func testExecute_markdownContainsSummary() throws {
        let meeting = makeMeeting()
        let summary = "## Резюме\n\nВажлива нарада щодо архітектури."

        let fileURL = try sut.execute(
            meeting: meeting,
            transcript: nil,
            summary: summary,
            vaultURL: tempDir
        )

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("Важлива нарада щодо архітектури."),
                      "Expected summary text in Markdown")
    }

    func testExecute_noSummary_containsPlaceholder() throws {
        let meeting = makeMeeting()
        let fileURL = try sut.execute(
            meeting: meeting,
            transcript: nil,
            summary: "",
            vaultURL: tempDir
        )

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("## Резюме"),
                      "Expected placeholder summary section")
    }

    func testExecute_duplicateFiles_createsUniqueNames() throws {
        let meeting = makeMeeting(title: "Duplicate Test")

        let url1 = try sut.execute(
            meeting: meeting,
            transcript: nil,
            summary: "First",
            vaultURL: tempDir
        )
        let url2 = try sut.execute(
            meeting: meeting,
            transcript: nil,
            summary: "Second",
            vaultURL: tempDir
        )

        XCTAssertNotEqual(url1.lastPathComponent, url2.lastPathComponent,
                          "Duplicate exports should have unique filenames")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url2.path))
    }

    func testExecute_emptyTagsGetsDefaultMeetingTag() throws {
        let meeting = makeMeeting(tags: [])
        let fileURL = try sut.execute(
            meeting: meeting,
            transcript: nil,
            summary: "",
            vaultURL: tempDir
        )

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("meeting"),
                      "Expected default 'meeting' tag when tags array is empty")
    }
}
