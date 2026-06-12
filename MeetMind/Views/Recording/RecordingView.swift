//
//  RecordingView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI

/// Main recording screen with waveform, controls, and live transcript
struct RecordingView: View {
    @Bindable var viewModel: RecordingViewModel
    @State private var showCancelAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar
            
            // Error banner
            if let error = viewModel.errorMessage {
                ErrorBannerView(
                    message: error,
                    style: .error,
                    onDismiss: { viewModel.errorMessage = nil }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
            }
            

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    Spacer(minLength: Theme.Spacing.lg)
                    
                    // Waveform area
                    waveformSection
                    
                    // Controls
                    RecordingControlsView(viewModel: viewModel)
                    
                    Spacer(minLength: Theme.Spacing.md)
                    
                    // Live transcript
                    LiveTranscriptView(
                        segments: viewModel.liveTranscript,
                        isLive: viewModel.state == .recording
                    )
                    .frame(minHeight: 200) // Flexible height
                }
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .background(
            ZStack {
                Theme.Colors.backgroundPrimary
                
                // Ambient colorful glow circles for premium liquid glass backdrop
                GeometryReader { geo in
                    ZStack {
                        Circle()
                            .fill(Theme.Colors.accentPrimary.opacity(0.12))
                            .frame(width: geo.size.width * 0.6)
                            .blur(radius: 60)
                            .offset(x: geo.size.width * 0.3, y: geo.size.height * 0.1)
                        
                        Circle()
                            .fill(Theme.Colors.accentSecondary.opacity(0.10))
                            .frame(width: geo.size.width * 0.5)
                            .blur(radius: 50)
                            .offset(x: -geo.size.width * 0.2, y: geo.size.height * 0.4)
                    }
                }
            }
        )
        .task {
            // Only pre-warm the live model when truly idle.
            // Skip if an import or post-processing is already running — it
            // manages its own model lifecycle and this would cause a wasted
            // init that gets immediately cancelled.
            guard viewModel.state == .idle else { return }
            await viewModel.initializeTranscription()
        }
        .alert("Зупинити та видалити запис?", isPresented: $showCancelAlert) {
            Button("Скасувати", role: .cancel) {}
            Button("Видалити", role: .destructive) {
                viewModel.cancelActiveProcessing()
            }
        } message: {
            Text("Зараз триває запис або транскрибування цієї наради. Якщо ви видалите її, процес буде зупинено, а всі отримані дані (запис та транскрипт) буде видалено безповоротно.")
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Editable meeting title
            TextField("Назва наради", text: $viewModel.meetingTitle)
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.textPrimary)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .minimumScaleFactor(0.7)
            
            Spacer()
            
            // Timer and Status grouped
            HStack(spacing: Theme.Spacing.lg) {
                if viewModel.state == .recording {
                    TimerView(elapsedTime: viewModel.audioManager.elapsedTime, style: .medium)
                        .fixedSize()
                }
                
                // Status badge
                if viewModel.state != .idle {
                    StatusBadgeView(status: statusForState)
                        .fixedSize()
                }
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.lg)
        .background(Theme.Colors.backgroundSecondary.opacity(0.5))
    }
    
    // MARK: - Waveform
    
    private var waveformSection: some View {
        GlassCard(padding: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.md) {
                if viewModel.state == .recording {
                    AudioWaveformView(
                        levels: viewModel.audioManager.audioLevels,
                        isActive: true
                    )
                    .frame(height: 80)
                } else if viewModel.state == .idle || viewModel.state == .complete {
                    IdleWaveformView()
                        .frame(height: 80)
                } else if case .error = viewModel.state {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.Colors.error)
                        Text("Помилка обробки")
                            .font(Theme.Typography.caption)
                    }
                    .frame(height: 80)
                } else {
                    // Processing state (transcribing, summarizing, stopping)
                    processingIndicator
                }
            }
        }
        .frame(height: (viewModel.state == .preparing || viewModel.state == .extracting || viewModel.state == .transcribing || viewModel.state == .summarizing || viewModel.state == .stopping) ? 145 : 120)
    }
    
    // MARK: - Processing Indicator
    
    private var processingIndicator: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: currentStageIcon)
                    .foregroundStyle(Theme.Colors.accentPrimary)
                    .font(.system(size: 14))
                
                Text(currentStageLabel)
                    .font(Theme.Typography.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                Spacer()
                
                Text(String(format: "%.0f%%", viewModel.overallProgress * 100))
                    .font(Theme.Typography.monoCaption)
                    .foregroundStyle(Theme.Colors.accentPrimary)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: 220)
            
            ProgressView(value: viewModel.overallProgress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(Theme.Colors.accentPrimary)
                .frame(maxWidth: 220)
            
            let detail = currentStageDetail
            if !detail.isEmpty {
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            
            Button(action: {
                showCancelAlert = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                    Text("Скасувати")
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.error)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 3)
                .background(Theme.Colors.error.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(height: 110)
    }
    
    private var currentStageIcon: String {
        switch viewModel.state {
        case .preparing: return "cpu"
        case .extracting: return "arrow.down.circle"
        case .transcribing: return "text.viewfinder"
        case .summarizing: return "sparkles"
        case .stopping: return "square.and.arrow.down"
        default: return "hourglass"
        }
    }
    
    private var currentStageLabel: LocalizedStringKey {
        switch viewModel.state {
        case .preparing: return "Підготовка..."
        case .extracting: return "Вилучення аудіо..."
        case .transcribing: return "Транскрипція..."
        case .summarizing: return "Генерація резюме..."
        case .stopping: return "Зупинка запису..."
        default: return "Обробка..."
        }
    }
    
    private var currentStageDetail: String {
        switch viewModel.state {
        case .extracting:
            return viewModel.importProgressStage
        case .transcribing:
            return viewModel.transcriptionProgressText
        default:
            return ""
        }
    }
    
    private var statusForState: MeetingStatus {
        switch viewModel.state {
        case .recording: return .recording
        case .preparing, .extracting, .transcribing, .stopping: return .transcribing
        case .summarizing: return .summarizing
        case .complete: return .complete
        case .error: return .error
        case .idle: return .complete
        }
    }
}

#Preview {
    let audioManager = AudioManager()
    let transcriptionService = TranscriptionService()
    let llmService = LLMService()
    
    RecordingView(viewModel: RecordingViewModel(
        audioManager: audioManager,
        transcriptionService: transcriptionService,
        llmService: llmService
    ))
    .frame(width: 700, height: 600)
}
