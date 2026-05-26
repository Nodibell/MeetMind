//
//  RecordingControlsView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI

/// Start/Stop button and device picker controls
struct RecordingControlsView: View {
    @Bindable var viewModel: RecordingViewModel

    @State private var isHoveringRecord = false
    @State private var isPressing = false
    @State private var spinAngle: Double = 0

    var body: some View {
        VStack(spacing: Theme.Spacing.xl * 1.5) {
            // Record Button
            recordButton

            // Audio Source & Device Block
            VStack(spacing: Theme.Spacing.lg) {
                // Custom Audio Source Picker
                HStack(spacing: 0) {
                    customPickerOption("Мікрофон", systemImage: "mic.fill", source: .microphone)
                    customPickerOption("Система", systemImage: "speaker.wave.2.fill", source: .system)
                    customPickerOption("Мікс", systemImage: "plus.circle.fill", source: .mixed)
                }
                .padding(Theme.Spacing.xxs)
                .background(Theme.Colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                .overlay(RoundedRectangle(cornerRadius: Theme.CornerRadius.md).stroke(Theme.Colors.border.opacity(0.3), lineWidth: 0.5))
                .frame(width: 320)
                .disabled(viewModel.state == .recording)

                // Device, system source & language pickers
                HStack(spacing: Theme.Spacing.md) {
                    if viewModel.audioManager.audioSource != .system {
                        devicePicker
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    if viewModel.audioManager.audioSource != .microphone {
                        systemAudioSourcePicker
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    languagePicker
                }
                .animation(Theme.Animation.standard, value: viewModel.audioManager.audioSource)
            }
            .padding(.top, Theme.Spacing.lg)
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        HStack(spacing: Theme.Spacing.xxl) {
            // Record Button
            VStack(spacing: Theme.Spacing.md) {
                Button(action: handleRecordTap) {
                    ZStack {
                        // Outer glow ring
                        Circle()
                            .stroke(buttonColor.opacity(0.3), lineWidth: 2)
                            .frame(width: 88, height: 88)
                            .scaleEffect(viewModel.state == .recording ? 1.2 : 1.0)
                            .blur(radius: viewModel.state == .recording ? 4 : 0)
                            .opacity(viewModel.state == .recording ? 0.6 : (isHoveringRecord ? 0.4 : 0.15))
                            .animation(viewModel.state == .recording ? Theme.Animation.pulse : .default,
                                       value: viewModel.state)

                        // Main button
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: buttonGradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)
                            .shadow(color: buttonColor.opacity(0.4), radius: isHoveringRecord ? 16 : 8)
                            .scaleEffect(isPressing ? 0.92 : 1.0)

                        // Icon
                        Group {
                            if viewModel.state == .recording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white)
                                    .frame(width: 22, height: 22)
                            } else if isProcessing {
                                // Spinning arc indicator
                                Circle()
                                    .stroke(lineWidth: 3)
                                    .opacity(0.3)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .trim(from: 0, to: 0.3)
                                            .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                            .rotationEffect(.degrees(spinAngle))
                                    )
                                    .foregroundStyle(.white)
                                    .onAppear {
                                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                            spinAngle = 360
                                        }
                                    }
                                    .onDisappear {
                                        spinAngle = 0
                                    }
                            } else {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 24, height: 24)
                            }
                        }
                    }
                    .frame(width: 110, height: 110)
                    .drawingGroup() // Flattens layers to prevent "floating" animation offsets
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
                .onHover { hovering in
                    withAnimation(Theme.Animation.fast) {
                        isHoveringRecord = hovering
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isPressing = true }
                        .onEnded { _ in isPressing = false }
                )

                // Label below button
                Text(buttonLabel)
                    .font(Theme.Typography.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            // Pause / Resume Button
            if viewModel.state == .recording {
                VStack(spacing: Theme.Spacing.md) {
                    Button(action: handlePauseTap) {
                        ZStack {
                            Circle()
                                .fill(Theme.Colors.backgroundSecondary)
                                .frame(width: 56, height: 56)
                                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                            
                            Image(systemName: viewModel.audioManager.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Text(viewModel.audioManager.isPaused ? "Продовжити" : "Пауза")
                        .font(Theme.Typography.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(), value: viewModel.state)
    }

    // MARK: - Device Picker

    private var devicePicker: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "mic.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.textTertiary)

            Picker("", selection: Binding(
                get: { viewModel.audioManager.selectedDeviceID ?? 0 },
                set: { newID in
                    if let device = viewModel.audioManager.availableDevices.first(where: { $0.id == newID }) {
                        viewModel.audioManager.selectDevice(device)
                    }
                }
            )) {
                ForEach(viewModel.audioManager.availableDevices) { device in
                    Text(device.name)
                        .tag(device.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.surfacePrimary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
    }

    // MARK: - System Audio Source Picker

    private var systemAudioSourcePicker: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.textTertiary)

            Picker("", selection: Binding(
                get: { AppSettings.shared.preferredSystemAudioSourceID ?? "" },
                set: { newID in
                    AppSettings.shared.preferredSystemAudioSourceID = newID.isEmpty ? nil : newID
                }
            )) {
                Text("Авто")
                    .tag("")
                ForEach(viewModel.availableSystemAudioSources) { source in
                    Label(source.title, systemImage: source.kind == .display ? "display" : "macwindow")
                        .tag(source.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 190)

            // Manual refresh button
            Button(action: { viewModel.refreshSystemAudioSources(forcePrompt: true) }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Оновити список вікон")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.surfacePrimary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
    }

    // MARK: - Language Picker

    private var languagePicker: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "globe")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.textTertiary)

            Picker("", selection: Binding(
                get: { AppSettings.shared.defaultLanguage },
                set: { AppSettings.shared.defaultLanguage = $0 }
            )) {
                ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 150)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.surfacePrimary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
    }

    // MARK: - Helpers

    private func handleRecordTap() {
        switch viewModel.state {
        case .idle, .complete, .error:
            viewModel.startRecording()
        case .recording:
            viewModel.stopRecording()
        default:
            break
        }
    }

    private func handlePauseTap() {
        if viewModel.audioManager.isPaused {
            viewModel.resumeRecording()
        } else {
            viewModel.pauseRecording()
        }
    }

    private var buttonColor: Color {
        viewModel.state == .recording ? Theme.Colors.recording : Theme.Colors.accentPrimary
    }

    private var buttonGradientColors: [Color] {
        if viewModel.state == .recording {
            return [Theme.Colors.recording, Theme.Colors.recording.opacity(0.8)]
        } else {
            return [Theme.Colors.accentPrimary, Theme.Colors.accentSecondary]
        }
    }

    private var buttonLabel: LocalizedStringKey {
        switch viewModel.state {
        case .idle: return "Почати запис"
        case .recording: return "Зупинити"
        case .preparing: return "Підготовка..."
        case .extracting: return "Вилучення..."
        case .stopping: return "Зупинка..."
        case .transcribing: return "Транскрипція..."
        case .summarizing: return "Аналіз..."
        case .complete: return "Новий запис"
        case .error: return "Спробувати знову"
        }
    }

    private var isProcessing: Bool {
        switch viewModel.state {
        case .preparing, .extracting, .stopping, .transcribing, .summarizing: return true
        default: return false
        }
    }

    @ViewBuilder
    private func customPickerOption(_ label: LocalizedStringKey, systemImage: String, source: AudioManager.AudioSource) -> some View {
        let isSelected = viewModel.audioManager.audioSource == source
        Button(action: {
            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.75)) {
                viewModel.audioManager.audioSource = source
                if source == .system || source == .mixed {
                    // Load sources silently — do NOT force a prompt here.
                    // forcePrompt: true would open System Settings on every tap.
                    viewModel.refreshSystemAudioSources(forcePrompt: false)
                }
            }
        }) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(Theme.Typography.captionMedium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .foregroundStyle(isSelected ? .white : Theme.Colors.textSecondary)
            .background(isSelected ? Theme.Colors.accentPrimary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
        }
        .buttonStyle(.plain)
    }
}
