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
    
    // MARK: - SwiftData
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Meeting.self,
            SpeakerProfile.self,
        ])
        let url = URL.applicationSupportDirectory.appending(path: "MeetMind.store")
        let modelConfiguration = ModelConfiguration(schema: schema, url: url)
        
        AppLogger.info("SwiftData Store URL: \(url.path)")
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            AppLogger.error("Failed to create ModelContainer, attempting to reset: \(error)")
            // Fallback: delete corrupted store and try again
            try? FileManager.default.removeItem(at: url)
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer even after reset: \(error)")
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
            .frame(minWidth: 900, minHeight: 600)
            .background(Theme.Colors.backgroundPrimary)
            .preferredColorScheme(.dark)
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
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Новий запис") { }
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
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}
