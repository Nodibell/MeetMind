//
//  LMStudioServerManager.swift
//  MeetMind
//
//  Created by Codex on 16.05.2026.
//

import AppKit
import Foundation

struct LMStudioServerStatus: Decodable, Equatable, Sendable {
    let running: Bool
    let port: Int?
}

enum LMStudioStartResult: Equatable, Sendable {
    case alreadyRunning(port: Int?)
    case started(port: Int)
    case missingCLI
    case failed(String)
    
    nonisolated var isUsable: Bool {
        switch self {
        case .alreadyRunning, .started:
            return true
        case .missingCLI, .failed:
            return false
        }
    }
    
    nonisolated var message: String {
        switch self {
        case .alreadyRunning(let port):
            if let port {
                return "LM Studio server вже запущено на port \(port)."
            }
            return "LM Studio server вже запущено."
        case .started(let port):
            return "LM Studio server запущено на port \(port)."
        case .missingCLI:
            return "Не знайдено LM Studio CLI `lms`. Відкрийте LM Studio один раз і виконайте `~/.lmstudio/bin/lms bootstrap`."
        case .failed(let detail):
            return "Не вдалося запустити LM Studio server: \(detail)"
        }
    }
}

enum LMStudioServerManager {
    private struct CommandResult: Sendable {
        let exitCode: Int32
        let output: String
    }
    
    nonisolated static func port(from endpoint: String) -> Int {
        guard let url = normalizedURL(from: endpoint) else {
            return 1234
        }
        
        if let port = url.port {
            return port
        }
        
        return url.scheme == "https" ? 443 : 1234
    }
    
    nonisolated static func ensureServerRunning(endpoint: String) async -> LMStudioStartResult {
        guard let executableURL = lmsExecutableURL() else {
            await openLMStudioApp()
            return .missingCLI
        }
        
        let desiredPort = port(from: endpoint)
        
        if let status = await serverStatus(executableURL: executableURL),
           status.running,
           status.port == nil || status.port == desiredPort {
            return .alreadyRunning(port: status.port)
        }
        
        let result = await runLMS(executableURL: executableURL, arguments: ["server", "start", "--port", "\(desiredPort)"])
        guard result.exitCode == 0 else {
            await openLMStudioApp()
            return .failed(cleanOutput(result.output))
        }
        
        return .started(port: desiredPort)
    }
    
    nonisolated static func lmsExecutableURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.lmstudio/bin/lms",
            "/opt/homebrew/bin/lms",
            "/usr/local/bin/lms"
        ]
        
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    
    @MainActor
    private static func serverStatus(executableURL: URL) async -> LMStudioServerStatus? {
        let result = await runLMS(executableURL: executableURL, arguments: ["server", "status", "--json", "--quiet"])
        guard result.exitCode == 0,
              let data = result.output.data(using: .utf8) else {
            return nil
        }
        
        return try? JSONDecoder().decode(LMStudioServerStatus.self, from: data)
    }
    
    private nonisolated static func runLMS(executableURL: URL, arguments: [String]) async -> CommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: CommandResult(exitCode: process.terminationStatus, output: output))
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(returning: CommandResult(exitCode: -1, output: error.localizedDescription))
            }
        }
    }
    
    private nonisolated static func normalizedURL(from endpoint: String) -> URL? {
        var rawEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        while rawEndpoint.hasSuffix("/") {
            rawEndpoint.removeLast()
        }
        return URL(string: rawEndpoint)
    }
    
    private nonisolated static func cleanOutput(_ output: String) -> String {
        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "невідома помилка" : cleaned
    }
    
    @MainActor
    private static func openLMStudioApp() {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "ai.lmstudio.LMStudio")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.lmstudio.LMStudio")
            ?? (FileManager.default.fileExists(atPath: "/Applications/LM Studio.app")
                ? URL(fileURLWithPath: "/Applications/LM Studio.app")
                : nil) else {
            return
        }
        
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
