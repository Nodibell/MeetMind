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
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
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
            .frame(minWidth: 800, minHeight: 550)
            .background(Theme.Colors.backgroundPrimary)
            .preferredColorScheme(.dark)
            .onAppear {
                configureAppAppearance()
                // Initialize SettingsViewModel eagerly so it's ready when Settings opens
                if settingsViewModel == nil {
                    settingsViewModel = SettingsViewModel(llmService: llmService, audioManager: audioManager)
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
                    .frame(width: 550, height: 420)
            }
        }
    }

    // MARK: - Appearance

    private func configureAppAppearance() {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}
