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
