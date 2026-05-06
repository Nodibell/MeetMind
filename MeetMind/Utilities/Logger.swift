//
//  Logger.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation
import os

/// Simple logging utility for the app
enum AppLogger {
    nonisolated private static let logger = Logger(subsystem: "com.meetmind.app", category: "General")
    
    nonisolated static func info(_ message: String) {
        print("ℹ️ [MeetMind] \(message)")
        logger.info("\(message, privacy: .public)")
    }
    
    nonisolated static func error(_ message: String, error: Error? = nil) {
        let errorDesc = error != nil ? " Error: \(error!.localizedDescription)" : ""
        print("❌ [MeetMind] \(message)\(errorDesc)")
        logger.error("\(message, privacy: .public)\(errorDesc, privacy: .public)")
    }
    
    nonisolated static func warning(_ message: String) {
        print("⚠️ [MeetMind] \(message)")
        logger.warning("\(message, privacy: .public)")
    }
    
    nonisolated static func debug(_ message: String) {
        #if DEBUG
        print("🪲 [MeetMind] \(message)")
        logger.debug("\(message, privacy: .public)")
        #endif
    }
    
    nonisolated static func audio(_ message: String) {
        print("🎤 [MeetMind][Audio] \(message)")
    }
    
    nonisolated static func ai(_ message: String) {
        print("🤖 [MeetMind][AI] \(message)")
    }
}
