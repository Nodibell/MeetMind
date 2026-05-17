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

    // System audio sources
    var availableSystemAudioSources: [AudioManager.SystemAudioSourceInfo] = []


    // Settings (bound to AppSettings)
    var settings = AppSettings.shared
    
    var deepMLXModelCompatibility: DeepLLMService.ModelCompatibility? {
        guard let path = settings.deepMLXModelPath else { return nil }
        return DeepLLMService.modelCompatibility(at: path)
    }
    
    var selectedLLMModelWarning: String? {
        LLMService.modelSelectionWarning(model: settings.llmModel, provider: settings.llmProvider)
    }

    enum OllamaStatus: Equatable {
        case unknown
        case checking
        case connected
        case disconnected(String)
    }

    private let llmService: any LLMProvider
    let audioManager: any AudioProvider

    init(llmService: any LLMProvider, audioManager: any AudioProvider) {
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
                    if !models.isEmpty,
                       !LLMService.isModelAvailable(settings.llmModel, in: models, provider: settings.llmProvider) {
                        settings.llmModel = models[0]
                    }
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

    func refreshSystemAudioSources() {
        Task {
            do {
                let sources = try await audioManager.getAvailableSystemAudioSources()
                await MainActor.run {
                    self.availableSystemAudioSources = sources
                }
            } catch {
                AppLogger.error("Failed to fetch system audio sources: \(error)")
            }
        }
    }
    
    // MARK: - DeepMLX Model Picker
    func pickDeepMLXModelFolder() {
        let panel = NSOpenPanel()
        panel.title = "Оберіть папку моделі MLX"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            settings.deepMLXModelPath = url
            
            let compatibility = DeepLLMService.modelCompatibility(at: url)
            if !compatibility.isSupported {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Модель не підтримується DeepMLX"
                alert.informativeText = """
                \(compatibility.issue ?? "Невідома причина")

                Для DeepMLX потрібна MLX-модель із підтримуваним model_type у config.json.
                """
                alert.runModal()
            }
        }
    }
}
