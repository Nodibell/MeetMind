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
    
    // MARK: - Settings ViewModel
    @State private var settingsViewModel: SettingsViewModel?
    
    var body: some Scene {
        // Main Window
        WindowGroup {
            ContentView(
                audioManager: audioManager,
                transcriptionService: transcriptionService,
                llmService: llmService
            )
            .frame(minWidth: 800, minHeight: 550)
            .background(Theme.Colors.backgroundPrimary)
            .preferredColorScheme(.dark)
            .onAppear {
                configureAppAppearance()
            }
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 700)
        .commands {
            // Custom menu commands
            CommandGroup(after: .newItem) {
                Button("Новий запис") {
                    // Handled via notifications or through the main window
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
        
        // Settings Window
        Settings {
            SettingsView(viewModel: resolvedSettingsViewModel)
        }
    }
    
    // MARK: - Resolved Settings ViewModel
    
    private var resolvedSettingsViewModel: SettingsViewModel {
        if let existing = settingsViewModel {
            return existing
        }
        let vm = SettingsViewModel(llmService: llmService, audioManager: audioManager)
        DispatchQueue.main.async {
            self.settingsViewModel = vm
        }
        return vm
    }
    
    // MARK: - Appearance
    
    private func configureAppAppearance() {
        // Force dark mode appearance
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}
