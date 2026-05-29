//
//  ParseSummaryUseCaseTests.swift
//  MeetMindTests
//
//  Unit tests for ParseSummaryUseCase — pure business logic,
//  no SwiftData or UI dependencies.
//

import XCTest
@testable import MeetMind

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

    // MARK: - extractActionItems

    func testExtractActionItems_emptyMarkdown_returnsEmpty() {
        let result = sut.extractActionItems(from: "")
        XCTAssertTrue(result.isEmpty)
    }

    func testExtractActionItems_noCheckboxLines_returnsEmpty() {
        let markdown = """
        # Резюме
        Сьогодні обговорили плани на квартал.
        - Просто маркований список без чекбоксу
        """
        let result = sut.extractActionItems(from: markdown)
        XCTAssertTrue(result.isEmpty)
    }

    func testExtractActionItems_singleUnchecked() {
        let markdown = "- [ ] Написати юніт-тести"
        let result = sut.extractActionItems(from: markdown)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Написати юніт-тести")
        XCTAssertFalse(result[0].isCompleted)
        XCTAssertNil(result[0].assignee)
    }

    func testExtractActionItems_singleChecked() {
        let markdown = "- [x] Підготувати звіт"
        let result = sut.extractActionItems(from: markdown)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Підготувати звіт")
        XCTAssertTrue(result[0].isCompleted)
    }

    func testExtractActionItems_withParenthesesAssignee() {
        let markdown = "- [ ] Зробити рефакторинг (Олексій)"
        let result = sut.extractActionItems(from: markdown)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Зробити рефакторинг")
        XCTAssertEqual(result[0].assignee, "Олексій")
    }

    func testExtractActionItems_withAtSignAssignee() {
        let markdown = "- [ ] Написати документацію @Марія"
        let result = sut.extractActionItems(from: markdown)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Написати документацію")
        XCTAssertEqual(result[0].assignee, "Марія")
    }

    func testExtractActionItems_mixedCompletionAndAssignee() {
        let markdown = """
        - [ ] Завершити рефакторинг @Олексій
        - [x] Підготувати презентацію (Марія)
        - [ ] Написати юніт-тести
        """
        let result = sut.extractActionItems(from: markdown)
        XCTAssertEqual(result.count, 3)

        let refa = result.first(where: { $0.text.contains("рефакторинг") })
        XCTAssertNotNil(refa)
        XCTAssertFalse(refa!.isCompleted)
        XCTAssertEqual(refa!.assignee, "Олексій")

        let pres = result.first(where: { $0.text.contains("презентацію") })
        XCTAssertNotNil(pres)
        XCTAssertTrue(pres!.isCompleted)
        XCTAssertEqual(pres!.assignee, "Марія")

        let tests = result.first(where: { $0.text.contains("юніт-тести") })
        XCTAssertNotNil(tests)
        XCTAssertFalse(tests!.isCompleted)
        XCTAssertNil(tests!.assignee)
    }

    func testExtractActionItems_ignoresLinesInsideSections() {
        // Non-checkbox lines should NOT appear as action items
        let markdown = """
        ## Завдання
        - [ ] Реальне завдання
        Просто текст без маркера — не завдання
        """
        let result = sut.extractActionItems(from: markdown)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Реальне завдання")
    }

    func testExtractActionItems_emptyTextAfterPrefix_isSkipped() {
        // A "- [ ]" with no text should be skipped
        let markdown = "- [ ] "
        let result = sut.extractActionItems(from: markdown)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - extractDecisions

    func testExtractDecisions_emptyMarkdown_returnsEmpty() {
        let result = sut.extractDecisions(from: "")
        XCTAssertTrue(result.isEmpty)
    }

    func testExtractDecisions_noDecisionsSection_returnsEmpty() {
        let markdown = """
        ## Завдання
        - [ ] Написати код
        """
        let result = sut.extractDecisions(from: markdown)
        XCTAssertTrue(result.isEmpty)
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
        XCTAssertTrue(result.contains(where: { $0.text.contains("дизайн-систему") }))
    }

    func testExtractDecisions_englishSectionHeader() {
        let markdown = """
        ## Decisions
        * Adopted new architecture
        • Removed legacy module
        """
        let result = sut.extractDecisions(from: markdown)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(where: { $0.text.contains("architecture") }))
        XCTAssertTrue(result.contains(where: { $0.text.contains("legacy") }))
    }

    func testExtractDecisions_stopsAtNextSection() {
        let markdown = """
        ## Прийняті рішення
        - Рішення перше.

        ## Завдання
        - Це не рішення, це завдання.
        """
        let result = sut.extractDecisions(from: markdown)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Рішення перше.")
    }

    func testExtractDecisions_emptyBulletSkipped() {
        let markdown = """
        ## Рішення
        -
        - Реальне рішення.
        """
        let result = sut.extractDecisions(from: markdown)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Реальне рішення.")
    }

    // MARK: - Combined

    func testFullSummaryParsing() {
        let markdown = """
        # Резюме наради

        ## Прийняті рішення
        - Вирішили мігрувати на SwiftData.
        - Затвердили дизайн-систему.

        ## Завдання (Action Items)
        - [ ] Завершити рефакторинг @Олексій
        - [x] Підготувати презентацію (Марія)
        """

        let actionItems = sut.extractActionItems(from: markdown)
        let decisions = sut.extractDecisions(from: markdown)

        XCTAssertEqual(actionItems.count, 2)
        XCTAssertEqual(decisions.count, 2)

        // Verify action items are not cross-polluted with decision bullets
        XCTAssertFalse(actionItems.contains(where: { $0.text.contains("SwiftData") }))
    }
}
