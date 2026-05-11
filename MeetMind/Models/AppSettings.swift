//
//  AppSettings.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation
import SwiftUI

/// Application settings backed by UserDefaults
@Observable
final class AppSettings: @unchecked Sendable {
    nonisolated static let shared = AppSettings()

    // MARK: - Keys
    private enum Keys {
        nonisolated static let obsidianVaultPath = "obsidianVaultPath"
        nonisolated static let preferredInputDevice = "preferredInputDevice"
        nonisolated static let preferredDisplayID = "preferredDisplayID"
        nonisolated static let preferredSystemAudioSourceID = "preferredSystemAudioSourceID"
        nonisolated static let defaultLanguage = "defaultLanguage"
        nonisolated static let ollamaModel = "ollamaModel"
        nonisolated static let ollamaEndpoint = "ollamaEndpoint"
        nonisolated static let autoExportToObsidian = "autoExportToObsidian"
        nonisolated static let watchFolderPath = "watchFolderPath"
        nonisolated static let autoProcessWatchFolder = "autoProcessWatchFolder"
        nonisolated static let whisperModelLive = "whisperModelLive"
        nonisolated static let whisperModelPost = "whisperModelPost"
        nonisolated static let lastUsedTitle = "lastUsedTitle"
    }

    // MARK: - Obsidian
    nonisolated var obsidianVaultPath: URL? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Keys.obsidianVaultPath) else { return nil }
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if isStale {
                    // Update bookmark if stale
                    Task {
                        self.obsidianVaultPath = url
                    }
                }
                return url
            } catch {
                AppLogger.error("Помилка відновлення доступу до Obsidian", error: error)
                return nil
            }
        }
        set {
            guard let url = newValue else {
                UserDefaults.standard.removeObject(forKey: Keys.obsidianVaultPath)
                return
            }
            do {
                let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(data, forKey: Keys.obsidianVaultPath)
            } catch {
                AppLogger.error("Помилка створення закладки для Obsidian", error: error)
            }
        }
    }

    nonisolated var autoExportToObsidian: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.autoExportToObsidian) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoExportToObsidian) }
    }

    // MARK: - Audio
    nonisolated var preferredInputDevice: String? {
        get { UserDefaults.standard.string(forKey: Keys.preferredInputDevice) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.preferredInputDevice) }
    }

    nonisolated var preferredDisplayID: UInt32? {
        get {
            let value = UserDefaults.standard.object(forKey: Keys.preferredDisplayID) as? UInt32
            return value
        }
        set {
            if let newValue = newValue {
                UserDefaults.standard.set(newValue, forKey: Keys.preferredDisplayID)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.preferredDisplayID)
            }
        }
    }

    nonisolated var preferredSystemAudioSourceID: String? {
        get {
            if let sourceID = UserDefaults.standard.string(forKey: Keys.preferredSystemAudioSourceID) {
                return sourceID
            }
            if let legacyDisplayID = preferredDisplayID {
                return "display:\(legacyDisplayID)"
            }
            return nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Keys.preferredSystemAudioSourceID)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.preferredSystemAudioSourceID)
                UserDefaults.standard.removeObject(forKey: Keys.preferredDisplayID)
            }
        }
    }

    // MARK: - Language
    nonisolated var defaultLanguage: String {
        get { UserDefaults.standard.string(forKey: Keys.defaultLanguage) ?? Constants.defaultLanguage }
        set { UserDefaults.standard.set(newValue, forKey: Keys.defaultLanguage) }
    }

    // MARK: - Ollama
    nonisolated var ollamaModel: String {
        get { UserDefaults.standard.string(forKey: Keys.ollamaModel) ?? Constants.defaultOllamaModel }
        set { UserDefaults.standard.set(newValue, forKey: Keys.ollamaModel) }
    }

    nonisolated var ollamaEndpoint: String {
        get { UserDefaults.standard.string(forKey: Keys.ollamaEndpoint) ?? Constants.defaultOllamaEndpoint }
        set { UserDefaults.standard.set(newValue, forKey: Keys.ollamaEndpoint) }
    }

    // MARK: - Whisper Models
    nonisolated var whisperModelLive: String {
        get {
            let value = UserDefaults.standard.string(forKey: Keys.whisperModelLive) ?? Constants.liveTranscriptionModel
            // Fix legacy hyphenated names from previous runs
            return value.replacingOccurrences(of: "large-v3-turbo", with: "large-v3_turbo")
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.whisperModelLive) }
    }

    nonisolated var whisperModelPost: String {
        get {
            let value = UserDefaults.standard.string(forKey: Keys.whisperModelPost) ?? Constants.postProcessingModel
            // Ensure we use the best available large model
            if value == "large-v3" || value == "openai_whisper-large-v3" { return value }
            return Constants.postProcessingModel
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.whisperModelPost) }
    }

    // MARK: - File Processing
    nonisolated var watchFolderPath: URL? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Keys.watchFolderPath) else { return nil }
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if isStale {
                    Task { self.watchFolderPath = url }
                }
                return url
            } catch {
                return nil
            }
        }
        set {
            guard let url = newValue else {
                UserDefaults.standard.removeObject(forKey: Keys.watchFolderPath)
                return
            }
            do {
                let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(data, forKey: Keys.watchFolderPath)
            } catch { }
        }
    }

    nonisolated var autoProcessWatchFolder: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.autoProcessWatchFolder) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoProcessWatchFolder) }
    }

    // MARK: - Supported Languages
    nonisolated static let supportedLanguages: [(code: String, name: String)] = [
        ("uk", "Українська"),
        ("en", "English"),
        ("auto", "Авто-визначення"),
    ]
}
