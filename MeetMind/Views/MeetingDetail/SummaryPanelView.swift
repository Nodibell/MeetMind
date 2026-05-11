//
//  SummaryPanelView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI

/// AI summary panel with markdown rendering and streaming support
struct SummaryPanelView: View {
    let summary: String
    let streamingSummary: String
    @Binding var selectedLanguage: String
    var isGenerating: Bool = false
    var onRegenerate: (() -> Void)?
    var onCopy: (() -> Void)?
    var onExport: (() -> Void)?
    
    @State private var isHoveringRegenerate = false
    @State private var didCopy = false

    var onCancel: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Compact Action Bar
            HStack(spacing: Theme.Spacing.md) {
                // Language Picker (Compact)
                Picker("", selection: $selectedLanguage) {
                    ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 100)
                .controlSize(.small)
                .disabled(isGenerating)
                
                Spacer()
                
                // Action Buttons with Labels
                HStack(spacing: Theme.Spacing.sm) {
                    if isGenerating, let onCancel {
                        Button(action: onCancel) {
                            Label("Скасувати", systemImage: "xmark.circle.fill")
                                .foregroundStyle(Theme.Colors.error)
                        }
                    } else {
                        if let onCopy, !displayText.isEmpty {
                            Button(action: {
                                onCopy()
                                withAnimation(Theme.Animation.fast) { didCopy = true }
                                Task {
                                    try? await Task.sleep(for: .seconds(1.5))
                                    await MainActor.run {
                                        withAnimation(Theme.Animation.fast) { self.didCopy = false }
                                    }
                                }
                            }) {
                                Label(didCopy ? "Готово" : "Копіювати", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                                    .foregroundStyle(didCopy ? Theme.Colors.success : Theme.Colors.textTertiary)
                            }
                        }

                        if let onExport {
                            Button(action: onExport) {
                                Label("Obsidian", systemImage: "square.and.arrow.up")
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }

                        if let onRegenerate {
                            Button(action: onRegenerate) {
                                Label("Оновити", systemImage: "arrow.clockwise")
                                    .foregroundStyle(isHoveringRegenerate ? Theme.Colors.accentPrimary : Theme.Colors.textTertiary)
                            }
                            .disabled(isGenerating)
                            .onHover { isHoveringRegenerate = $0 }
                        }
                    }
                }
                .font(Theme.Typography.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.backgroundSecondary.opacity(0.8))
            
            Divider()
                .background(Theme.Colors.borderSubtle)
            
            // Content
            if isGenerating {
                StreamingMarkdownView(text: streamingSummary, isStreaming: true)
            } else if !displayText.isEmpty {
                MarkdownWebView(markdown: displayText)
            } else {
                emptyState
            }
        }
        .background(Theme.Colors.backgroundSecondary.opacity(0.3))
    }
    
    private var displayText: String {
        summary.isEmpty ? streamingSummary : summary
    }
    
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Colors.accentPrimary, Theme.Colors.accentSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Резюме буде згенеровано після запису")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textTertiary)
            
            if let onRegenerate {
                Button(action: onRegenerate) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "sparkles")
                        Text("Згенерувати резюме")
                    }
                    .font(Theme.Typography.captionMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Gradients.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SummaryPanelView(
        summary: """
        ## Резюме
        - Обговорили нову архітектуру проєкту
        - Прийняли рішення використовувати SwiftUI
        - Визначили дедлайн: 15 червня
        
        ## Завдання
        - [ ] Створити прототип UI (Олексій)
        - [ ] Налаштувати CI/CD (Марія)
        
        ## Рішення
        - SwiftUI для інтерфейсу
        - Ollama для LLM
        """,
        streamingSummary: "",
        selectedLanguage: .constant("uk"),
        isGenerating: false,
        onRegenerate: {},
        onCopy: {},
        onExport: {}
    )
    .frame(width: 400, height: 500)
    .background(Theme.Colors.backgroundPrimary)
}
