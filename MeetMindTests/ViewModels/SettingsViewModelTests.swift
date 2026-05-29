//
//  SettingsViewModelTests.swift
//  MeetMindTests
//
//  Unit tests for SettingsViewModel — covers OllamaStatus enum,
//  model warning logic, and computed properties.
//

import XCTest
@testable import MeetMind

final class SettingsViewModelTests: XCTestCase {

    var llmMock: MockLLMProvider!
    var audioMock: MockAudioProvider!
    var sut: SettingsViewModel!

    override func setUp() {
        super.setUp()
        llmMock = MockLLMProvider()
        audioMock = MockAudioProvider()
        sut = SettingsViewModel(llmService: llmMock, audioManager: audioMock)
    }

    override func tearDown() {
        sut = nil
        llmMock = nil
        audioMock = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertEqual(sut.ollamaStatus, .unknown)
        XCTAssertTrue(sut.availableModels.isEmpty)
        XCTAssertFalse(sut.isCheckingOllama)
        XCTAssertNil(sut.ollamaError)
    }

    // MARK: - OllamaStatus Equatable

    func testOllamaStatus_unknown_equatable() {
        XCTAssertEqual(SettingsViewModel.OllamaStatus.unknown, .unknown)
        XCTAssertNotEqual(SettingsViewModel.OllamaStatus.unknown, .connected)
    }

    func testOllamaStatus_connected_equatable() {
        XCTAssertEqual(SettingsViewModel.OllamaStatus.connected, .connected)
    }

    func testOllamaStatus_checking_equatable() {
        XCTAssertEqual(SettingsViewModel.OllamaStatus.checking, .checking)
    }

    func testOllamaStatus_disconnected_equatable() {
        XCTAssertEqual(
            SettingsViewModel.OllamaStatus.disconnected("err"),
            .disconnected("err")
        )
        XCTAssertNotEqual(
            SettingsViewModel.OllamaStatus.disconnected("err1"),
            .disconnected("err2")
        )
    }

    // MARK: - Model Warning Logic

    func testModelSelectionWarning_embeddingModel_returnsWarning() {
        // The static method on LLMService returns warnings for embedding-type models
        let warning = LLMService.modelSelectionWarning(
            model: "nomic-embed-text",
            provider: .ollama
        )
        XCTAssertNotNil(warning,
            "Expected warning for embedding model 'nomic-embed-text'")
        XCTAssertTrue(warning!.contains("embedding"),
            "Warning should mention 'embedding'")
    }

    func testModelSelectionWarning_chatModel_returnsNil() {
        let warning = LLMService.modelSelectionWarning(
            model: "gemma3:12b",
            provider: .ollama
        )
        XCTAssertNil(warning,
            "No warning expected for standard chat model 'gemma3:12b'")
    }

    func testModelSelectionWarning_bgeModel_returnsWarning() {
        let warning = LLMService.modelSelectionWarning(
            model: "bge-small-en",
            provider: .ollama
        )
        XCTAssertNotNil(warning)
    }

    func testModelSelectionWarning_e5Model_returnsWarning() {
        let warning = LLMService.modelSelectionWarning(
            model: "e5-base",
            provider: .ollama
        )
        XCTAssertNotNil(warning)
    }

    // MARK: - API URL Construction

    func testAPIURL_validEndpoint_returnsURL() {
        let url = LLMService.apiURL(
            endpoint: "http://localhost:11434",
            provider: .ollama,
            path: "/api/chat"
        )
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "http://localhost:11434/api/chat")
    }

    func testAPIURL_trailingSlashEndpoint_isStripped() {
        let url = LLMService.apiURL(
            endpoint: "http://localhost:11434///",
            provider: .ollama,
            path: "/api/chat"
        )
        XCTAssertEqual(url?.absoluteString, "http://localhost:11434/api/chat")
    }

    func testAPIURL_emptyEndpoint_returnsNil() {
        let url = LLMService.apiURL(
            endpoint: "",
            provider: .ollama,
            path: "/api/chat"
        )
        XCTAssertNil(url)
    }

    func testAPIURL_lmStudio_deduplicatesV1Prefix() {
        // If endpoint already has /v1 and path starts with /v1/, it should not double up
        let url = LLMService.apiURL(
            endpoint: "http://localhost:1234/v1",
            provider: .lmStudio,
            path: "/v1/chat/completions"
        )
        XCTAssertEqual(url?.absoluteString, "http://localhost:1234/v1/chat/completions")
    }

    // MARK: - isModelAvailable

    func testIsModelAvailable_exactMatch_returnsTrue() {
        let result = LLMService.isModelAvailable(
            "gemma3:12b",
            in: ["gemma3:12b", "llama3"],
            provider: .ollama
        )
        XCTAssertTrue(result)
    }

    func testIsModelAvailable_taglessOllama_matchesLatest() {
        // "gemma3" without tag should match "gemma3:latest"
        let result = LLMService.isModelAvailable(
            "gemma3",
            in: ["gemma3:latest", "llama3"],
            provider: .ollama
        )
        XCTAssertTrue(result)
    }

    func testIsModelAvailable_notInList_returnsFalse() {
        let result = LLMService.isModelAvailable(
            "gpt-4",
            in: ["gemma3:12b", "llama3"],
            provider: .ollama
        )
        XCTAssertFalse(result)
    }

    func testIsModelAvailable_emptyModel_returnsFalse() {
        let result = LLMService.isModelAvailable(
            "",
            in: ["gemma3:12b"],
            provider: .ollama
        )
        XCTAssertFalse(result)
    }

    func testIsModelAvailable_deepMLX_alwaysTrue() {
        // DeepMLX doesn't validate model lists
        let result = LLMService.isModelAvailable(
            "any-model",
            in: [],
            provider: .deepMLX
        )
        XCTAssertTrue(result)
    }
}
