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

    var body: some View {
        HStack(spacing: 5) {
            // Status dot
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .shadow(color: dotColor.opacity(0.6), radius: isPulsing ? 5 : 2)
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .animation(
                    isGenerating
                        ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )

            // Provider label
            Text(providerLabel)
                .font(Theme.Typography.caption)
                .fontWeight(.medium)
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
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 3)
        .background(dotColor.opacity(0.1))
        .overlay(
            Capsule()
                .stroke(dotColor.opacity(0.2), lineWidth: 0.5)
        )
        .clipShape(Capsule())
        .onAppear {
            isPulsing = isGenerating
        }
        .onChange(of: isGenerating) { _, generating in
            isPulsing = generating
        }
    }

    // MARK: - Computed

    private var providerLabel: String {
        switch provider {
        case .appleIntelligence: return "Apple Intelligence"
        case .ollama:            return "Ollama"
        case .deepMLX:           return "DeepMLX"
        case .lmStudio:          return "LM Studio"
        }
    }

    private var dotColor: Color {
        if isGenerating {
            return Theme.Colors.accentPrimary
        }
        switch provider {
        case .appleIntelligence: return Theme.Colors.accentSecondary
        case .ollama:            return Color(hue: 0.36, saturation: 0.6, brightness: 0.65)
        case .deepMLX:           return Color(hue: 0.58, saturation: 0.7, brightness: 0.75)
        case .lmStudio:          return Color(hue: 0.08, saturation: 0.7, brightness: 0.8)
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
