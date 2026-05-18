//
//  MeetMindApp.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI
import SwiftData

@main
struct MeetMindApp: App {
    
    // MARK: - SwiftData DB Diagnostics
    static var dbInitializationError: String? = nil
    static var isBackupCreated: Bool = false
    
    // MARK: - SwiftData
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Meeting.self,
            SpeakerProfile.self,
            TranscriptSegment.self,
            ActionItem.self,
            Decision.self
        ])
        let url = URL.applicationSupportDirectory.appending(path: "MeetMind.store")
        let modelConfiguration = ModelConfiguration(schema: schema, url: url)
        
        AppLogger.info("SwiftData Store URL: \(url.path)")
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            AppLogger.error("Failed to create ModelContainer: \(error)")
            
            // Backup the corrupt database files
            let fm = FileManager.default
            let timestamp = Int(Date().timeIntervalSince1970)
            let backupFolder = URL.applicationSupportDirectory.appending(path: "Backups")
            try? fm.createDirectory(at: backupFolder, withIntermediateDirectories: true)
            
            let filesToBackup = [
                "MeetMind.store",
                "MeetMind.store-wal",
                "MeetMind.store-shm"
            ]
            
            var backupDone = false
            for filename in filesToBackup {
                let fileURL = URL.applicationSupportDirectory.appending(path: filename)
                if fm.fileExists(atPath: fileURL.path) {
                    let backupFileURL = backupFolder.appending(path: "\(filename).backup-\(timestamp)")
                    do {
                        try fm.copyItem(at: fileURL, to: backupFileURL)
                        AppLogger.info("Successfully backed up \(filename) to \(backupFileURL.path)")
                        backupDone = true
                    } catch {
                        AppLogger.error("Failed to backup \(filename) to \(backupFileURL.path): \(error)")
                    }
                }
            }
            
            Self.isBackupCreated = backupDone
            Self.dbInitializationError = error.localizedDescription
            
            // Attempt clean reset so the user can still use the app
            do {
                for filename in filesToBackup {
                    let fileURL = URL.applicationSupportDirectory.appending(path: filename)
                    try? fm.removeItem(at: fileURL)
                }
                
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                AppLogger.error("Second attempt after reset failed: \(error)")
                Self.dbInitializationError = "Critical Database Failure: \(error.localizedDescription)"
                
                // Final safe fallback: in-memory store so the app does not crash
                let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, configurations: [inMemoryConfig])
                } catch {
                    fatalError("InMemory container failed: \(error)")
                }
            }
        }
    }()
    
    // MARK: - Services (shared instances)
    @State private var audioManager = AudioManager()
    @State private var transcriptionService = TranscriptionService()
    @State private var llmService = LLMService()
    
    // MARK: - Settings
    @State private var appSettings = AppSettings.shared
    @State private var settingsViewModel: SettingsViewModel?
    
    var body: some Scene {
        // Main Window
        WindowGroup {
            ContentView(
                audioManager: audioManager,
                transcriptionService: transcriptionService,
                llmService: llmService
            )
            .environment(\.locale, .init(identifier: appSettings.appLanguage))
            .frame(minWidth: 960, minHeight: 650)
            .background(Theme.Colors.backgroundPrimary)
            .preferredColorScheme(appSettings.preferredColorScheme)
            .onAppear {
                configureAppAppearance()
                // Initialize SettingsViewModel eagerly so it's ready when Settings opens
                if settingsViewModel == nil {
                    settingsViewModel = SettingsViewModel(llmService: llmService, audioManager: audioManager)
                }
                // Wire memory pressure: unload non-essential models on critical pressure
                audioManager.onCriticalMemoryPressure = { [weak transcriptionService, weak llmService] in
                    AppLogger.systemHealth("Critical memory pressure — requesting model unload.")
                    
                    // Unload transcription if possible
                    if let service = transcriptionService {
                        Task {
                            let isReady = await service.isReady
                            if isReady {
                                AppLogger.systemHealth("Transcription service model unload deferred (in active use).")
                            }
                        }
                    }
                    
                    // Unload large LLM models if possible
                    Task {
                        AppLogger.systemHealth("Unloading LLM DeepMLX model due to critical memory pressure.")
                        await llmService?.unloadDeepModel()
                    }
                }
            }
            .onChange(of: appSettings.appTheme) { _, _ in
                configureAppAppearance()
            }
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Новий запис") {
                    NotificationCenter.default.post(name: .startNewRecording, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        // Settings Window
        Settings {
            if let vm = settingsViewModel {
                SettingsView(viewModel: vm)
                    .environment(\.locale, .init(identifier: appSettings.appLanguage))
            } else {
                ProgressView("Ініціалізація...")
                    .frame(width: 580, height: 480)
            }
        }
    }

    // MARK: - Appearance

    private func configureAppAppearance() {
        switch appSettings.appTheme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
