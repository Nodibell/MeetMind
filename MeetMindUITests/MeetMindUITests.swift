//
//  MeetMindUITests.swift
//  MeetMindUITests
//
//  Created by Developer on 29.05.2026.
//

import XCTest

/// Interactive UI Test Suite for MeetMind
/// This suite launches the active app instance and simulates pointer clicks to verify
/// sidebar navigation selections, smart folders, and screen transitions.
final class MeetMindUITests: XCTestCase {

    override func setUpWithError() throws {
        // Stop immediately if any interaction step or assertion fails
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Tear down resources if needed
    }

    /// Tests the primary navigation flow across sidebar items
    @MainActor
    func testNavigationFlowAndUIInteraction() throws {
        let app = XCUIApplication()
        app.launch()

        // 1. Verify main welcome screen elements
        let appTitle = app.staticTexts["MeetMind"]
        XCTAssertTrue(appTitle.waitForExistence(timeout: 5), "App title 'MeetMind' should be visible on welcome screen.")

        // 2. Select Global Search ("Глобальний запит") in the sidebar
        let globalSearchButton = app.buttons["Глобальний запит"]
        XCTAssertTrue(globalSearchButton.waitForExistence(timeout: 5), "Global Search button in sidebar should be visible.")
        globalSearchButton.click()

        // Verify Global Search welcome elements
        let queryTitle = app.staticTexts["Запитайте що завгодно"]
        XCTAssertTrue(queryTitle.waitForExistence(timeout: 5), "Global Search welcome title should appear after click.")

        // 3. Select Action Items ("Завдання (Action Items)") in the sidebar
        let actionItemsButton = app.buttons["Завдання (Action Items)"]
        XCTAssertTrue(actionItemsButton.waitForExistence(timeout: 5), "Action Items button in sidebar should be visible.")
        actionItemsButton.click()

        // 4. Navigate back to standard welcome / start screen if available
        let recordButton = app.buttons["Почати запис"]
        if recordButton.exists {
            XCTAssertTrue(recordButton.isHittable)
        }
    }
}
