//
//  AppSettings.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation
import AppKit
import SwiftUI

/// Application settings backed by UserDefaults.
///
/// Uses `@Observable` **stored properties** (not computed properties) so that
/// SwiftUI views properly re-render when any setting changes.
/// Each property syncs to UserDefaults via `didSet`.
@Observable
final class AppSettings: @unchecked Sendable {
    nonisolated static let shared = AppSettings()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let obsidianVaultPath        = "obsidianVaultPath"
        static let autoExportToObsidian     = "autoExportToObsidian"
        static let preferredInputDevice     = "preferredInputDevice"
        static let preferredDisplayID       = "preferredDisplayID"       // legacy
        static let preferredSystemAudioSourceID = "preferredSystemAudioSourceID"
        static let defaultLanguage          = "defaultLanguage"
        static let summaryLanguage          = "summaryLanguage"
        static let llmProvider              = "llmProvider"
        static let llmModel                 = "llmModel"
        static let llmEndpoint              = "llmEndpoint"
        static let ollamaEndpoint           = "ollamaEndpoint"
        static let lmStudioEndpoint         = "lmStudioEndpoint"
        static let deepMLXModelPath         = "deepMLXModelPath"
        static let customSummaryPrompt      = "customSummaryPrompt"
        static let llmEmbeddingModel        = "llmEmbeddingModel"
        static let llmEmbeddingProvider     = "llmEmbeddingProvider"
        static let whisperModelLive         = "whisperModelLive"
        static let whisperModelPost         = "whisperModelPost"
        static let watchFolderPath          = "watchFolderPath"
        static let autoProcessWatchFolder   = "autoProcessWatchFolder"
        static let appLanguage              = "appLanguage"
        static let appTheme                 = "appTheme"
        static let waveformFPS              = "waveformFPS"
        static let llmModelUnloadTimeout    = "llmModelUnloadTimeout"
    }

    // MARK: - App Language
    
    var appLanguage: String {
        didSet { UserDefaults.standard.set(appLanguage, forKey: Keys.appLanguage) }
    }

    // MARK: - App Theme
    
    public enum AppTheme: String, CaseIterable, Identifiable, Codable, Sendable {
        case system = "system"
        case light = "light"
        case dark = "dark"
        public var id: String { rawValue }
        
        public var displayName: String {
            switch self {
            case .system: return String(localized: "Системна")
            case .light: return String(localized: "Світла")
            case .dark: return String(localized: "Темна")
            }
        }
    }
    
    var appTheme: AppTheme {
        didSet { UserDefaults.standard.set(appTheme.rawValue, forKey: Keys.appTheme) }
    }
    
    var preferredColorScheme: SwiftUI.ColorScheme? {
        switch appTheme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // MARK: - Visuals
    
    var waveformFPS: Int {
        didSet { UserDefaults.standard.set(waveformFPS, forKey: Keys.waveformFPS) }
    }

    // MARK: - Obsidian

    /// Security-scoped URL to the selected Obsidian vault folder.
    var obsidianVaultPath: URL? {
        didSet { saveBookmark(obsidianVaultPath, forKey: Keys.obsidianVaultPath) }
    }

    var autoExportToObsidian: Bool {
        didSet { UserDefaults.standard.set(autoExportToObsidian, forKey: Keys.autoExportToObsidian) }
    }

    // MARK: - Audio

    var preferredInputDevice: String? {
        didSet { UserDefaults.standard.set(preferredInputDevice, forKey: Keys.preferredInputDevice) }
    }

    /// Unified system audio source ID. Format:
    ///  - `"display:<displayID>"` for screen capture
    ///  - `"window:<windowID>"` for single-window capture
    ///  - `nil` for auto (first display)
    var preferredSystemAudioSourceID: String? {
        didSet {
            if let v = preferredSystemAudioSourceID {
                UserDefaults.standard.set(v, forKey: Keys.preferredSystemAudioSourceID)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.preferredSystemAudioSourceID)
                UserDefaults.standard.removeObject(forKey: Keys.preferredDisplayID) // clear legacy
            }
        }
    }

    // MARK: - Language

    var defaultLanguage: String {
        didSet { UserDefaults.standard.set(defaultLanguage, forKey: Keys.defaultLanguage) }
    }

    var summaryLanguage: String {
        didSet { UserDefaults.standard.set(summaryLanguage, forKey: Keys.summaryLanguage) }
    }

    enum LLMProvider: String, CaseIterable, Identifiable, Codable, Sendable {
        case ollama = "Ollama"
        case lmStudio = "LM Studio"
        case deepMLX = "DeepMLX"
        case appleIntelligence = "Apple Intelligence"
        var id: String { rawValue }
    }

    var llmProvider: LLMProvider {
        didSet { UserDefaults.standard.set(llmProvider.rawValue, forKey: Keys.llmProvider) }
    }

    var llmModel: String {
        didSet { UserDefaults.standard.set(llmModel, forKey: Keys.llmModel) }
    }

    var ollamaEndpoint: String {
        didSet { UserDefaults.standard.set(ollamaEndpoint, forKey: Keys.ollamaEndpoint) }
    }

    var lmStudioEndpoint: String {
        didSet { UserDefaults.standard.set(lmStudioEndpoint, forKey: Keys.lmStudioEndpoint) }
    }

    var llmEndpoint: String {
        get {
            switch llmProvider {
            case .ollama: return ollamaEndpoint
            case .lmStudio: return lmStudioEndpoint
            case .deepMLX, .appleIntelligence: return ""
            }
        }
        set {
            switch llmProvider {
            case .ollama: ollamaEndpoint = newValue
            case .lmStudio: lmStudioEndpoint = newValue
            case .deepMLX, .appleIntelligence: break
            }
        }
    }

    var customSummaryPrompt: String {
        didSet { UserDefaults.standard.set(customSummaryPrompt, forKey: Keys.customSummaryPrompt) }
    }

    var llmEmbeddingModel: String {
        didSet { UserDefaults.standard.set(llmEmbeddingModel, forKey: Keys.llmEmbeddingModel) }
    }

    /// Dedicated provider for RAG embedding generation (Ollama or LM Studio).
    /// Used instead of `llmProvider` because Apple Intelligence and DeepMLX have no embedding API.
    var llmEmbeddingProvider: LLMProvider {
        didSet { UserDefaults.standard.set(llmEmbeddingProvider.rawValue, forKey: Keys.llmEmbeddingProvider) }
    }

    /// Returns the real network endpoint to use for embedding generation.
    /// Falls back to `ollamaEndpoint` when the main provider has no HTTP API (Apple Intelligence / DeepMLX).
    var embeddingEndpoint: String {
        switch llmEmbeddingProvider {
        case .ollama: return ollamaEndpoint
        case .lmStudio: return lmStudioEndpoint
        case .deepMLX, .appleIntelligence:
            // These providers have no embedding API – fall back to Ollama
            return ollamaEndpoint
        }
    }

    /// Security-scoped URL to the selected DeepMLX model folder
    var deepMLXModelPath: URL? {
        didSet { saveBookmark(deepMLXModelPath, forKey: Keys.deepMLXModelPath) }
    }

    var enableSharding: Bool {
        didSet { UserDefaults.standard.set(enableSharding, forKey: "enableSharding") }
    }
    
    var enablePrefetch: Bool {
        didSet { UserDefaults.standard.set(enablePrefetch, forKey: "enablePrefetch") }
    }
    
    var llmModelUnloadTimeout: Int {
        didSet { UserDefaults.standard.set(llmModelUnloadTimeout, forKey: Keys.llmModelUnloadTimeout) }
    }

    // MARK: - Whisper Models

    var whisperModelLive: String {
        didSet { UserDefaults.standard.set(whisperModelLive, forKey: Keys.whisperModelLive) }
    }

    var whisperModelPost: String {
        didSet { UserDefaults.standard.set(whisperModelPost, forKey: Keys.whisperModelPost) }
    }

    // MARK: - File Processing

    var watchFolderPath: URL? {
        didSet { saveBookmark(watchFolderPath, forKey: Keys.watchFolderPath) }
    }

    var autoProcessWatchFolder: Bool {
        didSet { UserDefaults.standard.set(autoProcessWatchFolder, forKey: Keys.autoProcessWatchFolder) }
    }

    // MARK: - Supported Languages

    nonisolated static let supportedLanguages: [(code: String, name: String)] = [
        ("uk", String(localized: "Українська")),
        ("en", String(localized: "English")),
        ("auto", String(localized: "Авто-визначення")),
    ]

    // MARK: - Init

    private init() {
        // --- Simple scalar values ---
        autoExportToObsidian    = UserDefaults.standard.bool(forKey: Keys.autoExportToObsidian)
        autoProcessWatchFolder  = UserDefaults.standard.bool(forKey: Keys.autoProcessWatchFolder)
        preferredInputDevice    = UserDefaults.standard.string(forKey: Keys.preferredInputDevice)
        defaultLanguage         = UserDefaults.standard.string(forKey: Keys.defaultLanguage) ?? Constants.defaultLanguage
        summaryLanguage         = UserDefaults.standard.string(forKey: Keys.summaryLanguage) ?? "auto"
        appLanguage             = UserDefaults.standard.string(forKey: Keys.appLanguage) ?? "uk"
        
        if let themeStr = UserDefaults.standard.string(forKey: Keys.appTheme),
           let theme = AppTheme(rawValue: themeStr) {
            appTheme = theme
        } else {
            appTheme = .system
        }
        
        let savedFPS = UserDefaults.standard.integer(forKey: Keys.waveformFPS)
        waveformFPS = savedFPS == 0 ? 60 : savedFPS
        
        // --- LLM Settings ---
        if let providerStr = UserDefaults.standard.string(forKey: Keys.llmProvider),
           let provider = LLMProvider(rawValue: providerStr) {
            llmProvider = provider
        } else {
            llmProvider = .ollama
        }
        llmModel                = UserDefaults.standard.string(forKey: Keys.llmModel) ?? UserDefaults.standard.string(forKey: "ollamaModel") ?? Constants.defaultOllamaModel
        
        let legacyEndpoint = UserDefaults.standard.string(forKey: Keys.llmEndpoint) ?? UserDefaults.standard.string(forKey: "ollamaEndpoint")
        
        ollamaEndpoint          = UserDefaults.standard.string(forKey: Keys.ollamaEndpoint) ?? legacyEndpoint ?? Constants.defaultOllamaEndpoint
        lmStudioEndpoint        = UserDefaults.standard.string(forKey: Keys.lmStudioEndpoint) ?? Constants.defaultLMStudioEndpoint
        
        customSummaryPrompt     = UserDefaults.standard.string(forKey: Keys.customSummaryPrompt) ?? ""
        llmEmbeddingModel       = UserDefaults.standard.string(forKey: Keys.llmEmbeddingModel) ?? ""
        
        if let epStr = UserDefaults.standard.string(forKey: Keys.llmEmbeddingProvider),
           let ep = LLMProvider(rawValue: epStr),
           ep == .ollama || ep == .lmStudio {
            llmEmbeddingProvider = ep
        } else {
            llmEmbeddingProvider = .ollama
        }
        llmModelUnloadTimeout   = UserDefaults.standard.object(forKey: Keys.llmModelUnloadTimeout) as? Int ?? 60
        enableSharding          = UserDefaults.standard.object(forKey: "enableSharding") as? Bool ?? true
        enablePrefetch          = UserDefaults.standard.object(forKey: "enablePrefetch") as? Bool ?? true

        // --- Whisper models (with legacy name migration) ---
        let liveRaw = UserDefaults.standard.string(forKey: Keys.whisperModelLive) ?? Constants.liveTranscriptionModel
        whisperModelLive = liveRaw.replacingOccurrences(of: "large-v3-turbo", with: "large-v3_turbo")

        let postRaw = UserDefaults.standard.string(forKey: Keys.whisperModelPost) ?? Constants.postProcessingModel
        whisperModelPost = (postRaw == "large-v3" || postRaw == "openai_whisper-large-v3")
            ? postRaw
            : Constants.postProcessingModel

        // --- System audio source (with legacy display ID migration) ---
        if let sourceID = UserDefaults.standard.string(forKey: Keys.preferredSystemAudioSourceID) {
            preferredSystemAudioSourceID = sourceID
        } else if let legacyID = UserDefaults.standard.object(forKey: Keys.preferredDisplayID) as? UInt32 {
            preferredSystemAudioSourceID = "display:\(legacyID)"
        } else {
            preferredSystemAudioSourceID = nil
        }

        // --- Security-scoped bookmarks ---
        obsidianVaultPath = AppSettings.resolveBookmark(forKey: Keys.obsidianVaultPath)
        watchFolderPath   = AppSettings.resolveBookmark(forKey: Keys.watchFolderPath)
        deepMLXModelPath  = AppSettings.resolveBookmark(forKey: Keys.deepMLXModelPath)
    }

    // MARK: - Bookmark Helpers

    private func saveBookmark(_ url: URL?, forKey key: String) {
        guard let url else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        
        // Start accessing before creating bookmark data
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
        
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: key)
            AppLogger.info("Successfully saved security-scoped bookmark for \(key)")
        } catch {
            AppLogger.error("Failed to save security-scoped bookmark for \(key)", error: error)
        }
    }

    private static func resolveBookmark(forKey key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                AppLogger.warning("Security-scoped bookmark stale for key: \(key)")
                // Will be re-saved when property is next written
            }
            return url
        } catch {
            AppLogger.error("Failed to resolve security-scoped bookmark for \(key)", error: error)
            return nil
        }
    }
}
