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

            Tab("AI", systemImage: "brain.head.profile") {
                ollamaTab
            }

            Tab("Obsidian", systemImage: "doc.text") {
                obsidianTab
            }

            Tab("Файли", systemImage: "folder") {
                filesTab
            }
        }
        .frame(width: 680, height: 500)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Зовнішній вигляд та Мова") {
                Picker("Мова інтерфейсу", selection: $viewModel.settings.appLanguage) {
                    Text("Українська").tag("uk")
                    Text("English").tag("en")
                }
                
                Picker("Тема оформлення", selection: $viewModel.settings.appTheme) {
                    ForEach(AppSettings.AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }

                Picker("Транскрипція (за замовчуванням)", selection: $viewModel.settings.defaultLanguage) {
                    ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }

                Picker("Мова резюме (за замовчуванням)", selection: $viewModel.settings.summaryLanguage) {
                    Text("Мова транскрипту").tag("auto")
                    Text("Англійська").tag("en")
                    Text("Українська").tag("uk")
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
            Section("Візуалізація") {
                Picker("Частота оновлення хвилі", selection: $viewModel.settings.waveformFPS) {
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                    Text("90 FPS").tag(90)
                    Text("120 FPS").tag(120)
                }
                
                Text("Вища частота оновлення забезпечує плавнішу анімацію, але може споживати більше енергії")
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
                    viewModel.refreshSystemAudioSources(forcePrompt: true)
                }

                Text("Для режимів Система та Мікс можна вибрати весь екран або конкретне вікно")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            viewModel.refreshSystemAudioSources(forcePrompt: false)
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

            if viewModel.settings.llmProvider == .deepMLX {
                Section("Локальна MLX Модель") {
                    HStack {
                        if let path = viewModel.settings.deepMLXModelPath {
                            Text(path.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("Шлях до моделі MLX не обрано")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Обрати папку моделі MLX") {
                            viewModel.pickDeepMLXModelFolder()
                        }
                    }
                    
                    if let compatibility = viewModel.deepMLXModelCompatibility {
                        Label(
                            deepMLXCompatibilityText(compatibility),
                            systemImage: compatibility.isSupported ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(compatibility.isSupported ? Theme.Colors.success : Theme.Colors.error)
                    }
                    
                    Text("DeepMLX завантажує MLX-моделі безпосередньо в MeetMind через Apple Silicon Metal. Модель автоматично вивантажується з пам'яті (VRAM) одразу після завершення аналізу.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Для LM Studio вкажіть адресу локального сервера (напр. http://localhost:1234)")
                            Link("Завантажити LM Studio", destination: URL(string: "https://lmstudio.ai")!)
                                .font(.caption)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else if viewModel.settings.llmProvider == .ollama {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Для Ollama вкажіть адресу сервера (напр. http://localhost:11434)")
                            Link("Завантажити Ollama", destination: URL(string: "https://ollama.com")!)
                                .font(.caption)
                        }
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
                            if !viewModel.availableModels.contains(viewModel.settings.llmModel) && !viewModel.settings.llmModel.isEmpty {
                                Text("\(viewModel.settings.llmModel) (custom)").tag(viewModel.settings.llmModel)
                            }
                        }
                    }

                    if viewModel.settings.llmProvider == .ollama {
                        Text("Рекомендовані: gemma3:12b, qwen2.5:14b (підтримують українську)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let warning = viewModel.selectedLLMModelWarning {
                        Label(warning, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Модель Ембедингів (RAG)") {
                    if viewModel.availableModels.isEmpty {
                        TextField("Модель Ембедингів", text: $viewModel.settings.llmEmbeddingModel)
                    } else {
                        Picker("Модель Ембедингів", selection: $viewModel.settings.llmEmbeddingModel) {
                            ForEach(viewModel.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                            if !viewModel.availableModels.contains(viewModel.settings.llmEmbeddingModel) && !viewModel.settings.llmEmbeddingModel.isEmpty {
                                Text("\(viewModel.settings.llmEmbeddingModel) (custom)").tag(viewModel.settings.llmEmbeddingModel)
                            }
                        }
                    }
                    Text("Використовується для векторизації нарад. Рекомендовано: nomic-embed-text або bge-small-en.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Керування пам'яттю (VRAM / RAM)") {
                Picker("Вивантаження моделі", selection: $viewModel.settings.llmModelUnloadTimeout) {
                    Text("Вивантажити одразу").tag(0)
                    Text("Через 1 хвилину").tag(60)
                    Text("Через 5 хвилин").tag(300)
                    Text("Через 10 хвилин").tag(600)
                    Text("Не вивантажувати").tag(-1)
                }
                
                Text("Керує тим, коли завантажена модель вивантажується з пам'яті комп'ютера після останнього запиту. Це дозволяє економити ресурси відеокарти та оперативної пам'яті вашого Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .onChange(of: viewModel.settings.llmProvider) { _, _ in
            viewModel.availableModels = []
            Task { await viewModel.checkOllamaConnection() }
        }
        .onChange(of: viewModel.settings.llmModel) { _, _ in
            guard viewModel.settings.llmProvider == .lmStudio else { return }
            Task { await viewModel.checkOllamaConnection() }
        }
    }
    
    private func deepMLXCompatibilityText(_ compatibility: DeepLLMService.ModelCompatibility) -> String {
        if compatibility.isSupported {
            return "MLX підтримує model_type '\(compatibility.modelType ?? "unknown")'"
        }
        
        return "DeepMLX не підтримає цю папку: \(compatibility.issue ?? "невідома причина")"
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
