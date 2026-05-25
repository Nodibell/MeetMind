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
            
            // Transcription progress
            if !viewModel.transcriptionProgress.isEmpty {
                ErrorBannerView(
                    message: viewModel.transcriptionProgress,
                    style: .info
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
            }
            
            // Main content
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
        .background(Theme.Colors.backgroundPrimary)
        .task {
            await viewModel.initializeTranscription()
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
        .frame(height: 120)
    }
    
    // MARK: - Processing Indicator
    
    private var processingIndicator: some View {
        VStack(spacing: Theme.Spacing.md) {
            if viewModel.state == .transcribing {
                VStack(spacing: Theme.Spacing.xs) {
                    ProgressView(value: viewModel.transcriptionProgressValue)
                        .progressViewStyle(.linear)
                        .tint(Theme.Colors.accentPrimary)
                        .frame(maxWidth: 200)
                    
                    Text("Транскрибування (high-quality): \(viewModel.transcriptionProgressValue, format: .percent)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else {
                ProgressView()
                    .scaleEffect(0.9)
                    .tint(Theme.Colors.accentPrimary)
                
                Text(processingLabel)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(height: 80)
    }
    
    private var processingLabel: LocalizedStringKey {
        switch viewModel.state {
        case .preparing: return "Підготовка джерела аудіо..."
        case .extracting: return "Вилучення аудіодоріжки з файлу..."
        case .transcribing: return "Транскрипція аудіо (high-quality)..."
        case .summarizing: return "Генерація резюме через AI..."
        case .stopping: return "Зупинка запису..."
        default: return ""
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
