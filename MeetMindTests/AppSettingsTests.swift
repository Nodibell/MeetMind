//
//  AppSettingsTests.swift
//  MeetMindTests
//
//  Created by Oleksii Chumak on 11.05.2026.
//

import XCTest
@testable import MeetMind

final class AppSettingsTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clear UserDefaults for tests
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        
        let settings = AppSettings.shared
        settings.summaryLanguage = "auto"
        settings.customSummaryPrompt = ""
        settings.autoExportToObsidian = false
        settings.defaultLanguage = "uk"
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testDefaultValues() {
        let settings = AppSettings.shared
        XCTAssertEqual(settings.defaultLanguage, "uk")
        XCTAssertEqual(settings.summaryLanguage, "auto")
        XCTAssertEqual(settings.customSummaryPrompt, "")
        XCTAssertEqual(settings.autoExportToObsidian, false)
    }
    
    func testPersistence() {
        let settings = AppSettings.shared
        
        settings.summaryLanguage = "en"
        settings.customSummaryPrompt = "Be concise."
        settings.autoExportToObsidian = true
        
        // Ensure values are stored
        XCTAssertEqual(UserDefaults.standard.string(forKey: "summaryLanguage"), "en")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "customSummaryPrompt"), "Be concise.")
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "autoExportToObsidian"), true)
        
        // Values read correctly from settings instance
        XCTAssertEqual(settings.summaryLanguage, "en")
        XCTAssertEqual(settings.customSummaryPrompt, "Be concise.")
        XCTAssertEqual(settings.autoExportToObsidian, true)
    }
}
