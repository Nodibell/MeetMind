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
