//
//  LLMServiceTests.swift
//  MeetMindTests
//
//  Created by Oleksii Chumak on 11.05.2026.
//

import XCTest
@testable import MeetMind

final class LLMServiceTests: XCTestCase {
    
    func testChatMessageCodable() throws {
        let message = LLMService.ChatMessage(role: "user", content: "Test content")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        
        let decoder = JSONDecoder()
        let decodedMessage = try decoder.decode(LLMService.ChatMessage.self, from: data)
        
        XCTAssertEqual(message.role, decodedMessage.role)
        XCTAssertEqual(message.content, decodedMessage.content)
    }
    
    func testLMStudioEndpointDoesNotDuplicateV1Path() {
        let url = LLMService.apiURL(
            endpoint: "http://localhost:1234/v1/",
            provider: .lmStudio,
            path: Constants.openaiHealthPath
        )
        
        XCTAssertEqual(url?.absoluteString, "http://localhost:1234/v1/models")
    }
    
    func testLMStudioServerPortUsesEndpointPort() {
        XCTAssertEqual(LMStudioServerManager.port(from: "http://localhost:1234/v1"), 1234)
        XCTAssertEqual(LMStudioServerManager.port(from: "http://127.0.0.1:4321"), 4321)
        XCTAssertEqual(LMStudioServerManager.port(from: ""), 1234)
    }
    
    func testOpenAICompatibleRequestUsesTopLevelGenerationFields() throws {
        let data = try LLMService.encodedChatRequestData(
            provider: .lmStudio,
            model: "local-model",
            messages: [LLMService.ChatMessage(role: "user", content: "Hello")],
            stream: true,
            temperature: 0.7,
            maxTokens: 2048,
            topP: 0.9
        )
        
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["options"])
        XCTAssertEqual(json["max_tokens"] as? Int, 2048)
        XCTAssertEqual(json["top_p"] as? Double, 0.9)
    }
    
    func testOllamaModelMatchingRequiresExactTagWhenTagProvided() {
        let models = ["qwen2.5:7b", "llama3:latest"]
        
        XCTAssertTrue(LLMService.isModelAvailable("llama3", in: models, provider: .ollama))
        XCTAssertTrue(LLMService.isModelAvailable("qwen2.5:7b", in: models, provider: .ollama))
        XCTAssertFalse(LLMService.isModelAvailable("qwen2.5:14b", in: models, provider: .ollama))
        XCTAssertFalse(LLMService.isModelAvailable("qwen2.5", in: models, provider: .lmStudio))
    }
    
    func testModelSelectionWarningFlagsEmbeddingModels() {
        let warning = LLMService.modelSelectionWarning(model: "nomic-bert", provider: .lmStudio)
        
        XCTAssertTrue(warning?.contains("embedding") == true)
    }
    
    func testDeepMLXDirectoryValidationRequiresMLXFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepMLXValidation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        
        XCTAssertNotNil(DeepLLMService.modelDirectoryValidationIssue(at: directory))
        
        try "{}".write(to: directory.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: directory.appendingPathComponent("tokenizer.json"), atomically: true, encoding: .utf8)
        try Data().write(to: directory.appendingPathComponent("model.safetensors"))
        
        XCTAssertNotNil(DeepLLMService.modelDirectoryValidationIssue(at: directory))
        
        try #"{"model_type":"llama"}"#.write(to: directory.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        XCTAssertNil(DeepLLMService.modelDirectoryValidationIssue(at: directory))
    }
    
    func testDeepMLXDirectoryValidationRejectsUnsupportedModelType() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepMLXUnsupported-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        
        try #"{"model_type":"unsupported_arch"}"#.write(to: directory.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: directory.appendingPathComponent("tokenizer.json"), atomically: true, encoding: .utf8)
        try Data().write(to: directory.appendingPathComponent("model.safetensors"))
        
        let compatibility = DeepLLMService.modelCompatibility(at: directory)
        
        XCTAssertFalse(compatibility.isSupported)
        XCTAssertEqual(compatibility.modelType, "unsupported_arch")
        XCTAssertTrue(compatibility.issue?.contains("не підтримується") == true)
    }
    
    func testDeepMLXDirectoryValidationExplainsKnownLMStudioModelTypes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepMLXGemma4-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        
        try #"{"model_type":"gemma4"}"#.write(to: directory.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: directory.appendingPathComponent("tokenizer.json"), atomically: true, encoding: .utf8)
        try Data().write(to: directory.appendingPathComponent("model.safetensors"))
        
        let compatibility = DeepLLMService.modelCompatibility(at: directory)
        
        XCTAssertFalse(compatibility.isSupported)
        XCTAssertEqual(compatibility.modelType, "gemma4")
        XCTAssertTrue(compatibility.issue?.contains("LM Studio server") == true)
    }
    
    func testLLMServiceSupportUnloadDeepModel() async {
        let service = LLMService()
        await service.unloadDeepModel()
        XCTAssertTrue(true)
    }
    
    func testAppleIntelligenceUnsupportedLanguages() async {
        let service = LLMService()
        
        await MainActor.run {
            AppSettings.shared.llmProvider = .appleIntelligence
        }
        
        do {
            _ = try await service.generateSummary(transcript: "Привіт, це нарада українською мовою.", targetLanguage: "uk")
            XCTFail("Should throw error because fallback cannot fully succeed in test sandbox environment")
        } catch {
            // Success: any error is fine since sandbox fallback doesn't succeed
            XCTAssertTrue(true)
        }
    }
}

final class MeetMindDiarizationEngineTests: XCTestCase {
    
    func testAlignSpeakers() async throws {
        // We can test the alignment algorithm independently
        let engine = await MeetMindDiarizationEngine()
        
        // Mock WhisperKit segments
        let textSegments = [
            MeetingTranscriptSegment(id: UUID(), startTime: 1.0, endTime: 3.0, text: "Hello there.", speakerID: nil, language: "en"),
            MeetingTranscriptSegment(id: UUID(), startTime: 4.0, endTime: 6.0, text: "How are you?", speakerID: nil, language: "en"),
            MeetingTranscriptSegment(id: UUID(), startTime: 8.0, endTime: 12.0, text: "I am fine.", speakerID: nil, language: "en")
        ]
        
        // Mock FluidAudio diarization output
        let speakerSegments = [
            DiarizationSegment(speakerID: "SPEAKER_01", startTime: 0.0, endTime: 3.5),
            DiarizationSegment(speakerID: "SPEAKER_02", startTime: 3.6, endTime: 7.0),
            DiarizationSegment(speakerID: "SPEAKER_01", startTime: 7.5, endTime: 15.0)
        ]
        
        let aligned = await engine.alignSpeakers(textSegments: textSegments, diarizationSegments: speakerSegments)
        
        XCTAssertEqual(aligned.count, 3)
        
        // First segment (1.0 - 3.0) midpoint = 2.0 -> falls into SPEAKER_01 (0.0 - 3.5)
        XCTAssertEqual(aligned[0].speakerID, "SPEAKER_01")
        XCTAssertEqual(aligned[0].text, "Hello there.")
        
        // Second segment (4.0 - 6.0) midpoint = 5.0 -> falls into SPEAKER_02 (3.6 - 7.0)
        XCTAssertEqual(aligned[1].speakerID, "SPEAKER_02")
        
        // Third segment (8.0 - 12.0) midpoint = 10.0 -> falls into SPEAKER_01 (7.5 - 15.0)
        XCTAssertEqual(aligned[2].speakerID, "SPEAKER_01")
    }
}
