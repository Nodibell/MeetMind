//
//  SettingsView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI

/// Application preferences window with tabs
struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        TabView {
            Tab("Загальне", systemImage: "gear") {
                generalTab
            }

            Tab("Аудіо", systemImage: "mic.fill") {
                audioTab
            }

            Tab("AI / Ollama", systemImage: "brain.head.profile") {
                ollamaTab
            }

            Tab("Obsidian", systemImage: "doc.text") {
                obsidianTab
            }

            Tab("Файли", systemImage: "folder") {
                filesTab
            }
        }
        .frame(width: 550, height: 420)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Мова") {
                Picker("Мова інтерфейсу", selection: $viewModel.settings.appLanguage) {
                    Text("Українська").tag("uk")
                    Text("English").tag("en")
                }

                Picker("Транскрипція (за замовчуванням)", selection: $viewModel.settings.defaultLanguage) {
                    ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }

                Text("Мова використовується для транскрипції та аналізу")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Модель Whisper") {
                TextField("Live (швидка)", text: $viewModel.settings.whisperModelLive)
                TextField("Post-processing (якісна)", text: $viewModel.settings.whisperModelPost)

                Text("large-v3-turbo для live, large-v3 для якісної транскрипції")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Audio Tab

    private var audioTab: some View {
        Form {
            Section("Пристрій введення") {
                Picker("Аудіо пристрій", selection: Binding(
                    get: { viewModel.audioManager.selectedDeviceID ?? 0 },
                    set: { newID in
                        if let device = viewModel.audioManager.availableDevices.first(where: { $0.id == newID }) {
                            viewModel.audioManager.selectDevice(device)
                        }
                    }
                )) {
                    ForEach(viewModel.audioManager.availableDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }

                Button("Оновити список пристроїв") {
                    viewModel.refreshAudioDevices()
                }
            }

            Section("Системне аудіо") {
                Picker("Джерело", selection: Binding(
                    get: { viewModel.settings.preferredSystemAudioSourceID ?? "" },
                    set: { newID in
                        viewModel.settings.preferredSystemAudioSourceID = newID.isEmpty ? nil : newID
                    }
                )) {
                    Text("Авто").tag("")
                    ForEach(viewModel.availableSystemAudioSources) { source in
                        Text("\(source.title) — \(source.subtitle)").tag(source.id)
                    }
                }

                Button("Оновити список джерел") {
                    viewModel.refreshSystemAudioSources()
                }

                Text("Для режимів Система та Мікс можна вибрати весь екран або конкретне вікно")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            viewModel.refreshSystemAudioSources()
        }
    }

    // MARK: - Ollama Tab

    private var ollamaTab: some View {
        Form {
            Section("Провайдер") {
                Picker("Сервіс", selection: $viewModel.settings.llmProvider) {
                    ForEach(AppSettings.LLMProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Підключення") {
                TextField("Endpoint", text: $viewModel.settings.llmEndpoint)

                HStack {
                    statusIndicator

                    Spacer()

                    Button(viewModel.isCheckingOllama ? "Перевірка..." : "Перевірити з'єднання") {
                        Task { await viewModel.checkOllamaConnection() }
                    }
                    .disabled(viewModel.isCheckingOllama)
                }
                
                if viewModel.settings.llmProvider == .lmStudio {
                    Text("Для LM Studio вкажіть адресу локального сервера (напр. http://localhost:1234/v1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Для Ollama вкажіть адресу сервера (напр. http://localhost:11434)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Модель") {
                if viewModel.availableModels.isEmpty {
                    TextField("Модель", text: $viewModel.settings.llmModel)
                } else {
                    Picker("Модель", selection: $viewModel.settings.llmModel) {
                        ForEach(viewModel.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                if viewModel.settings.llmProvider == .ollama {
                    Text("Рекомендовані: gemma3:12b, qwen2.5:14b (підтримують українську)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Додатковий Промпт для Резюме") {
                TextEditor(text: $viewModel.settings.customSummaryPrompt)
                    .frame(height: 80)
                    .font(.body)
                
                Text("Тут можна додати власні інструкції (наприклад: 'Завжди форматуй як маркований список').")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = viewModel.ollamaError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await viewModel.checkOllamaConnection()
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch viewModel.ollamaStatus {
        case .connected:
            Label("Підключено", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.success)
                .font(.caption)
        case .disconnected(let reason):
            Label(reason, systemImage: "xmark.circle.fill")
                .foregroundStyle(Theme.Colors.error)
                .font(.caption)
                .lineLimit(2)
        case .checking:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.6)
                Text("Перевірка...").font(.caption)
            }
        case .unknown:
            Label("Не перевірено", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    // MARK: - Obsidian Tab

    private var obsidianTab: some View {
        Form {
            Section("Obsidian Vault") {
                HStack {
                    if let vaultPath = viewModel.settings.obsidianVaultPath {
                        Text(vaultPath.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Не обрано")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Обрати папку") {
                        viewModel.pickObsidianVault()
                    }
                }

                Toggle("Автоматичний експорт після завершення", isOn: $viewModel.settings.autoExportToObsidian)

                Text("Нотатки зберігаються в {Vault}/Meetings/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Files Tab

    private var filesTab: some View {
        Form {
            Section("Автоматична обробка") {
                HStack {
                    if let watchPath = viewModel.settings.watchFolderPath {
                        Text(watchPath.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Не обрано")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Обрати папку") {
                        viewModel.pickWatchFolder()
                    }
                }

                Toggle("Автоматично обробляти нові файли", isOn: $viewModel.settings.autoProcessWatchFolder)

                Text("Підтримувані формати: WAV, MP3, M4A, FLAC, AAC")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Сховище") {
                HStack {
                    Text("Записи").font(.caption)
                    Spacer()
                    Text(Constants.recordingsDirectory.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Text("Транскрипти").font(.caption)
                    Spacer()
                    Text(Constants.transcriptsDirectory.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
