//
//  SettingsViewModel.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation
import AppKit

/// Manages application settings and service configuration
@Observable
final class SettingsViewModel {
    
    // MARK: - State
    var ollamaStatus: OllamaStatus = .unknown
    var availableModels: [String] = []
    var isCheckingOllama = false
    var ollamaError: String?
    
    // Settings (bound to AppSettings)
    var settings = AppSettings.shared
    
    enum OllamaStatus: Equatable {
        case unknown
        case checking
        case connected
        case disconnected(String)
    }
    
    private let llmService: LLMService
    let audioManager: AudioManager
    
    init(llmService: LLMService, audioManager: AudioManager) {
        self.llmService = llmService
        self.audioManager = audioManager
    }
    
    // MARK: - Ollama Health Check
    
    func checkOllamaConnection() async {
        isCheckingOllama = true
        ollamaStatus = .checking
        ollamaError = nil
        
        let isHealthy = await llmService.checkHealth()
        let state = await llmService.state
        
        await MainActor.run {
            if isHealthy {
                ollamaStatus = .connected
                if case .available(let models) = state {
                    self.availableModels = models
                }
            } else {
                if case .unavailable(let reason) = state {
                    ollamaStatus = .disconnected(reason)
                    ollamaError = reason
                } else {
                    ollamaStatus = .disconnected("Невідома помилка")
                }
            }
            isCheckingOllama = false
        }
    }
    
    // MARK: - Obsidian Vault Picker
    
    func pickObsidianVault() {
        let panel = NSOpenPanel()
        panel.title = "Оберіть папку Obsidian Vault"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            settings.obsidianVaultPath = url
        }
    }
    
    // MARK: - Watch Folder Picker
    
    func pickWatchFolder() {
        let panel = NSOpenPanel()
        panel.title = "Оберіть папку для автоматичної обробки"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            settings.watchFolderPath = url
        }
    }
    
    // MARK: - Audio Devices
    
    func refreshAudioDevices() {
        audioManager.refreshDevices()
    }
}
