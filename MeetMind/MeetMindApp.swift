//
//  MeetMindApp.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//
//  Composition root: assembles dependencies and wires the app scene.
//  Business logic, DB recovery, and infrastructure are handled by their
//  respective dedicated types (PersistenceController, service layer, etc.).
//

import SwiftUI
import SwiftData

@main
struct MeetMindApp: App {

    // MARK: - Infrastructure

    private let persistence = PersistenceController.shared

    // MARK: - Services (shared instances)

    @State private var audioManager = AudioManager()
    @State private var transcriptionService = TranscriptionService()
    @State private var llmService = LLMService()

    // MARK: - Settings & ViewModels

    @State private var appSettings = AppSettings.shared
    @State private var settingsViewModel: SettingsViewModel?

    // MARK: - Scene

    var body: some Scene {
        // Main Window
        WindowGroup {
            ContentView(
                audioManager: audioManager,
                transcriptionService: transcriptionService,
                llmService: llmService,
                dbError: persistence.initializationError,
                dbBackupCreated: persistence.isBackupCreated
            )
            .environment(\.locale, .init(identifier: appSettings.appLanguage))
            .frame(minWidth: 960, minHeight: 650)
            .background(Theme.Colors.backgroundPrimary)
            .preferredColorScheme(appSettings.preferredColorScheme)
            .onAppear {
                configureAppAppearance()
                initializeSettingsViewModel()
                wireMemoryPressureHandling()
            }
            .onChange(of: appSettings.appTheme) { _, _ in
                configureAppAppearance()
            }
        }
        .modelContainer(persistence.container)
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

    // MARK: - Private Setup

    /// Initializes the SettingsViewModel eagerly so it's ready when Settings opens.
    private func initializeSettingsViewModel() {
        guard settingsViewModel == nil else { return }
        settingsViewModel = SettingsViewModel(llmService: llmService, audioManager: audioManager)
    }

    /// Wires memory pressure callbacks: unloads heavy models when system is critical.
    private func wireMemoryPressureHandling() {
        audioManager.onCriticalMemoryPressure = { [weak transcriptionService, weak llmService] in
            AppLogger.systemHealth("Critical memory pressure — requesting model unload.")

            if let service = transcriptionService {
                Task {
                    let isReady = await service.isReady
                    if isReady {
                        AppLogger.systemHealth("Transcription service model unload deferred (in active use).")
                    }
                }
            }

            Task {
                AppLogger.systemHealth("Unloading LLM DeepMLX model due to critical memory pressure.")
                await llmService?.unloadDeepModel()
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
