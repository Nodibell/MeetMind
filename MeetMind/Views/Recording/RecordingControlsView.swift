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

    var body: some View {
        VStack(spacing: Theme.Spacing.xl * 1.5) {
            // Record Button
            recordButton

            // Audio Source & Device Block
            VStack(spacing: Theme.Spacing.lg) {
                // Audio Source Picker
                Picker("", selection: $viewModel.audioManager.audioSource) {
                    Label("Мікрофон", systemImage: "mic.fill").tag(AudioManager.AudioSource.microphone)
                    Label("Система", systemImage: "speaker.wave.2.fill").tag(AudioManager.AudioSource.system)
                    Label("Мікс", systemImage: "plus.circle.fill").tag(AudioManager.AudioSource.mixed)
                }
                .pickerStyle(.segmented)
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
        VStack(spacing: Theme.Spacing.md) {
            Button(action: handleRecordTap) {
                ZStack {
                    // Outer glow ring
                    Circle()
                        .stroke(buttonColor.opacity(isHoveringRecord ? 0.4 : 0.15), lineWidth: 3)
                        .frame(width: 88, height: 88)
                        .scaleEffect(viewModel.state == .recording ? 1.1 : 1.0)
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
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Circle()
                                .fill(.white)
                                .frame(width: 24, height: 24)
                        }
                    }
                }
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

    private var buttonLabel: String {
        switch viewModel.state {
        case .idle: return "Почати запис"
        case .recording: return "Зупинити"
        case .preparing: return "Підготовка..."
        case .stopping: return "Зупинка..."
        case .transcribing: return "Транскрипція..."
        case .summarizing: return "Аналіз..."
        case .complete: return "Новий запис"
        case .error: return "Спробувати знову"
        }
    }

    private var isProcessing: Bool {
        switch viewModel.state {
        case .preparing, .stopping, .transcribing, .summarizing: return true
        default: return false
        }
    }
}
