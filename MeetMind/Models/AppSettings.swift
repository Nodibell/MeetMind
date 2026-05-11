//
//  AppSettings.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation
import AppKit

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
        static let ollamaModel              = "ollamaModel"
        static let ollamaEndpoint           = "ollamaEndpoint"
        static let customSummaryPrompt      = "customSummaryPrompt"
        static let whisperModelLive         = "whisperModelLive"
        static let whisperModelPost         = "whisperModelPost"
        static let watchFolderPath          = "watchFolderPath"
        static let autoProcessWatchFolder   = "autoProcessWatchFolder"
        static let appLanguage              = "appLanguage"
    }

    // MARK: - App Language
    
    var appLanguage: String {
        didSet { UserDefaults.standard.set(appLanguage, forKey: Keys.appLanguage) }
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

    // MARK: - Ollama

    var ollamaModel: String {
        didSet { UserDefaults.standard.set(ollamaModel, forKey: Keys.ollamaModel) }
    }

    var ollamaEndpoint: String {
        didSet { UserDefaults.standard.set(ollamaEndpoint, forKey: Keys.ollamaEndpoint) }
    }

    var customSummaryPrompt: String {
        didSet { UserDefaults.standard.set(customSummaryPrompt, forKey: Keys.customSummaryPrompt) }
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
        ("uk", "Українська"),
        ("en", "English"),
        ("auto", "Авто-визначення"),
    ]

    // MARK: - Init

    private init() {
        // --- Simple scalar values ---
        autoExportToObsidian    = UserDefaults.standard.bool(forKey: Keys.autoExportToObsidian)
        autoProcessWatchFolder  = UserDefaults.standard.bool(forKey: Keys.autoProcessWatchFolder)
        preferredInputDevice    = UserDefaults.standard.string(forKey: Keys.preferredInputDevice)
        defaultLanguage         = UserDefaults.standard.string(forKey: Keys.defaultLanguage) ?? Constants.defaultLanguage
        summaryLanguage         = UserDefaults.standard.string(forKey: Keys.summaryLanguage) ?? "auto"
        ollamaModel             = UserDefaults.standard.string(forKey: Keys.ollamaModel) ?? Constants.defaultOllamaModel
        ollamaEndpoint          = UserDefaults.standard.string(forKey: Keys.ollamaEndpoint) ?? Constants.defaultOllamaEndpoint
        customSummaryPrompt     = UserDefaults.standard.string(forKey: Keys.customSummaryPrompt) ?? ""
        appLanguage             = UserDefaults.standard.string(forKey: Keys.appLanguage) ?? "uk"

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
    }

    // MARK: - Bookmark Helpers

    private func saveBookmark(_ url: URL?, forKey key: String) {
        guard let url else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: key)
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
