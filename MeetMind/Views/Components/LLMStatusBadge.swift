//
//  LLMStatusBadge.swift
//  MeetMind
//
//  Shows the currently active LLM provider with a pulsing animation
//  during generation. Appears in MeetingDetailView topBar so users
//  always know which model is processing their meeting.
//

import SwiftUI

/// A small animated badge indicating the active LLM provider and its state.
///
/// Usage:
/// ```swift
/// LLMStatusBadge(
///     provider: .ollama,
///     modelName: "gemma3:12b",
///     isGenerating: viewModel.isRegeneratingSummary
/// )
/// ```
struct LLMStatusBadge: View {

    let provider: AppSettings.LLMProvider
    /// Short model name shown next to the provider label (nil hides it)
    var modelName: String? = nil
    /// When `true`, shows a pulsing animation indicating active generation
    var isGenerating: Bool = false

    @State private var isPulsing = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    
    // Interactive states
    @State private var isHovered = false
    @State private var isShowingPopover = false
    @State private var hoveredProvider: AppSettings.LLMProvider? = nil
    
    // Model lists and check states
    @State private var ollamaModels: [String] = []
    @State private var lmStudioModels: [String] = []
    @State private var isLoadingModels = false
    @State private var checkStatus: String? = nil
    @State private var checkColor: Color = .gray

    var body: some View {
        Button {
            isShowingPopover = true
        } label: {
            HStack(spacing: 6) {
                // Status dot + Radar pulse glow stack
                ZStack {
                    if isGenerating {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 6, height: 6)
                            .scaleEffect(pulseScale)
                            .opacity(pulseOpacity)
                            .onAppear {
                                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                                    pulseScale = 2.6
                                    pulseOpacity = 0.0
                                }
                            }
                    }
                    
                    Circle()
                        .fill(dotColor)
                        .frame(width: 5, height: 5)
                        .shadow(color: dotColor.opacity(0.8), radius: isGenerating ? 4 : 1)
                }
                .frame(width: 12, height: 12)

                // Provider Icon
                Image(systemName: providerIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(dotColor)

                // Provider label
                Text(providerLabel)
                    .font(Theme.Typography.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(dotColor)

                // Optional model name
                if let modelName, !modelName.isEmpty {
                    Text("·")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)

                    Text(shortModelName(modelName))
                        .font(Theme.Typography.monoCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            popoverContent
        }
        .onAppear {
            isPulsing = isGenerating
            if isGenerating {
                pulseScale = 1.0
                pulseOpacity = 0.6
            }
        }
        .onChange(of: isGenerating) { _, generating in
            isPulsing = generating
            if generating {
                pulseScale = 1.0
                pulseOpacity = 0.6
            }
        }
    }

    // MARK: - Popover Content View

    private var popoverContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "brain.headlight")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Gradients.accent)
                
                Text(String(localized: "Локальний інтелект"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                // Status indicator pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(checkColor)
                        .frame(width: 5, height: 5)
                        .shadow(color: checkColor.opacity(0.5), radius: 1.5)
                    
                    Text(checkStatus ?? String(localized: "Очікування"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.Colors.backgroundTertiary.opacity(0.6))
                .cornerRadius(6)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            
            Divider()
                .background(Theme.Colors.border.opacity(0.4))
            
            // 2x2 Grid of Providers
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ProviderCard(
                    provider: .appleIntelligence,
                    name: "Apple",
                    icon: "sparkles",
                    activeColor: Color(red: 0.58, green: 0.38, blue: 0.98),
                    isActive: AppSettings.shared.llmProvider == .appleIntelligence,
                    isHovered: hoveredProvider == .appleIntelligence
                ) {
                    AppSettings.shared.llmProvider = .appleIntelligence
                }
                .onHover { isHover in hoveredProvider = isHover ? .appleIntelligence : nil }
                
                ProviderCard(
                    provider: .ollama,
                    name: "Ollama",
                    icon: "server.rack",
                    activeColor: Color(red: 0.35, green: 0.40, blue: 0.95),
                    isActive: AppSettings.shared.llmProvider == .ollama,
                    isHovered: hoveredProvider == .ollama
                ) {
                    AppSettings.shared.llmProvider = .ollama
                }
                .onHover { isHover in hoveredProvider = isHover ? .ollama : nil }
                
                ProviderCard(
                    provider: .lmStudio,
                    name: "LM Studio",
                    icon: "square.stack.3d.up.fill",
                    activeColor: Color(red: 0.95, green: 0.60, blue: 0.02),
                    isActive: AppSettings.shared.llmProvider == .lmStudio,
                    isHovered: hoveredProvider == .lmStudio
                ) {
                    AppSettings.shared.llmProvider = .lmStudio
                }
                .onHover { isHover in hoveredProvider = isHover ? .lmStudio : nil }
                
                ProviderCard(
                    provider: .deepMLX,
                    name: "DeepMLX",
                    icon: "cpu.fill",
                    activeColor: Color(red: 0.02, green: 0.70, blue: 0.82),
                    isActive: AppSettings.shared.llmProvider == .deepMLX,
                    isHovered: hoveredProvider == .deepMLX
                ) {
                    AppSettings.shared.llmProvider = .deepMLX
                }
                .onHover { isHover in hoveredProvider = isHover ? .deepMLX : nil }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            Divider()
                .background(Theme.Colors.border.opacity(0.4))
            
            // Model Selector / Config Area
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Обрана модель"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .textCase(.uppercase)
                
                switch AppSettings.shared.llmProvider {
                case .appleIntelligence:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 13))
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(localized: "Системна модель Apple"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(String(localized: "Працює нативно на Apple Silicon"))
                                .font(.system(size: 9))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surfacePrimary.opacity(0.3))
                    .cornerRadius(8)
                    
                case .deepMLX:
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(Color(red: 0.02, green: 0.70, blue: 0.82))
                            .font(.system(size: 13))
                        
                        VStack(alignment: .leading, spacing: 1) {
                            if let path = AppSettings.shared.deepMLXModelPath {
                                Text(path.lastPathComponent)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(path.deletingLastPathComponent().lastPathComponent)
                                    .font(.system(size: 9))
                                    .foregroundColor(Theme.Colors.textTertiary)
                            } else {
                                Text(String(localized: "Шлях не обрано"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button {
                            pickDeepMLXModelFolder()
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.Colors.accentPrimary)
                        }
                        .buttonStyle(.plain)
                        .help("Обрати папку моделі MLX")
                    }
                    .padding(8)
                    .background(Theme.Colors.surfacePrimary.opacity(0.3))
                    .cornerRadius(8)
                    
                case .ollama, .lmStudio:
                    let models = AppSettings.shared.llmProvider == .ollama ? ollamaModels : lmStudioModels
                    
                    if isLoadingModels {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(localized: "Отримання моделей..."))
                                .font(.system(size: 11))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    } else if models.isEmpty {
                        VStack(spacing: 4) {
                            Text(String(localized: "Моделі не знайдені"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.Colors.error)
                            Text(String(localized: "Перевірте з'єднання з \(AppSettings.shared.llmProvider.rawValue)"))
                                .font(.system(size: 9))
                                .foregroundColor(Theme.Colors.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    } else {
                        Menu {
                            ForEach(models, id: \.self) { model in
                                Button {
                                    AppSettings.shared.llmModel = model
                                } label: {
                                    HStack {
                                        Text(model)
                                        if AppSettings.shared.llmModel == model {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.Colors.textSecondary)
                                Text(AppSettings.shared.llmModel.isEmpty ? String(localized: "Оберіть модель...") : AppSettings.shared.llmModel)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundColor(Theme.Colors.textTertiary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Theme.Colors.surfacePrimary.opacity(0.4))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.Colors.border.opacity(0.4), lineWidth: 1)
                            )
                        }
                        .menuStyle(.button)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            Divider()
                .background(Theme.Colors.border.opacity(0.4))
            
            // Bottom Action Row
            HStack {
                SettingsLink {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 10))
                        Text(String(localized: "Налаштування ШІ..."))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Theme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    isShowingPopover = false
                })
                .onHover { isHover in
                    if isHover { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                
                Spacer()
                
                Button {
                    Task { await checkConnection() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .rotationEffect(.degrees(isLoadingModels ? 360 : 0))
                            .animation(isLoadingModels ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoadingModels)
                        Text(String(localized: "Оновити"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Theme.Colors.accentPrimary)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingModels)
                .onHover { isHover in
                    if isHover && !isLoadingModels { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.Colors.backgroundSecondary.opacity(0.5))
        }
        .frame(width: 290)
        .background(
            VisualEffectView(material: .popover, blendingMode: .withinWindow)
        )
        .onAppear {
            Task { await checkConnection() }
        }
        .onChange(of: AppSettings.shared.llmProvider) { _, _ in
            Task { await checkConnection() }
        }
    }

    // MARK: - Provider Card Grid Component

    struct ProviderCard: View {
        let provider: AppSettings.LLMProvider
        let name: String
        let icon: String
        let activeColor: Color
        let isActive: Bool
        let isHovered: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isActive ? .white : activeColor)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(isActive ? activeColor : activeColor.opacity(0.12))
                        )
                    
                    Text(name)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isActive ? .white : Theme.Colors.textPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isActive ? activeColor.opacity(0.85) : Theme.Colors.surfacePrimary.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isActive ? activeColor : Theme.Colors.border.opacity(isHovered ? 0.8 : 0.3),
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
                .shadow(
                    color: isActive ? activeColor.opacity(0.3) : Color.clear,
                    radius: 6,
                    x: 0,
                    y: 2
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func checkConnection() async {
        let provider = AppSettings.shared.llmProvider
        let endpoint = provider == .ollama ? AppSettings.shared.ollamaEndpoint : AppSettings.shared.lmStudioEndpoint
        
        await MainActor.run {
            self.isLoadingModels = true
            self.checkStatus = String(localized: "Перевірка...")
            self.checkColor = .orange
        }
        
        if provider == .appleIntelligence {
            await MainActor.run {
                self.isLoadingModels = false
                self.checkStatus = String(localized: "Активний")
                self.checkColor = .green
            }
            return
        }
        
        if provider == .deepMLX {
            await MainActor.run {
                self.isLoadingModels = false
                if AppSettings.shared.deepMLXModelPath != nil {
                    self.checkStatus = String(localized: "Активний")
                    self.checkColor = .green
                } else {
                    self.checkStatus = String(localized: "Оберіть модель")
                    self.checkColor = .red
                }
            }
            return
        }
        
        do {
            let models = try await LLMService.fetchAvailableModels(provider: provider, endpoint: endpoint)
            await MainActor.run {
                self.isLoadingModels = false
                if provider == .ollama {
                    self.ollamaModels = models
                } else {
                    self.lmStudioModels = models
                }
                self.checkStatus = String(localized: "Активний")
                self.checkColor = .green
            }
        } catch {
            await MainActor.run {
                self.isLoadingModels = false
                self.checkStatus = String(localized: "Немає зв’язку")
                self.checkColor = .red
            }
        }
    }


    private func pickDeepMLXModelFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Обрати")
        panel.message = String(localized: "Оберіть папку, що містить файли моделі MLX (наприклад, weights.npz або GGUF і config.json)")
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                AppSettings.shared.deepMLXModelPath = url
                Task { await checkConnection() }
            }
        }
    }

    // MARK: - Computed

    private var providerLabel: String {
        switch provider {
        case .appleIntelligence: return "Apple"
        case .ollama:            return "Ollama"
        case .deepMLX:           return "DeepMLX"
        case .lmStudio:          return "LM Studio"
        }
    }

    private var providerIcon: String {
        switch provider {
        case .appleIntelligence: return "sparkles"
        case .ollama:            return "server.rack"
        case .deepMLX:           return "cpu.fill"
        case .lmStudio:          return "square.stack.3d.up.fill"
        }
    }

    private var dotColor: Color {
        switch provider {
        case .appleIntelligence:
            // Electric Siri-like pastel violet
            return Color(red: 0.58, green: 0.38, blue: 0.98)
        case .ollama:
            // Cosmic Indigo
            return Color(red: 0.35, green: 0.40, blue: 0.95)
        case .deepMLX:
            // Cyber teal/cyan
            return Color(red: 0.02, green: 0.70, blue: 0.82)
        case .lmStudio:
            // Premium sunset amber
            return Color(red: 0.95, green: 0.60, blue: 0.02)
        }
    }

    /// Trims long model names to keep the badge compact
    private func shortModelName(_ name: String) -> String {
        // "gemma3:12b-instruct-q4" → "gemma3:12b"
        let parts = name.split(separator: "-")
        if parts.count > 2 {
            return parts.prefix(2).joined(separator: "-")
        }
        return name
    }
}

#Preview {
    VStack(spacing: 12) {
        LLMStatusBadge(provider: .appleIntelligence, modelName: nil, isGenerating: false)
        LLMStatusBadge(provider: .ollama, modelName: "gemma3:12b", isGenerating: false)
        LLMStatusBadge(provider: .ollama, modelName: "gemma3:12b", isGenerating: true)
        LLMStatusBadge(provider: .deepMLX, modelName: "gemma-3-12b-it-4bit", isGenerating: false)
        LLMStatusBadge(provider: .lmStudio, modelName: "qwen2.5-14b-instruct", isGenerating: true)
    }
    .padding()
    .background(Theme.Colors.backgroundPrimary)
}
