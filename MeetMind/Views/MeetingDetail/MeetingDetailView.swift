//
//  MeetingDetailView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI
import SwiftData
#if canImport(Translation)
import Translation
#endif

/// Post-recording split view: transcript on left, summary on right
struct MeetingDetailView: View {
    @Bindable var viewModel: MeetingDetailViewModel
    @Environment(\.modelContext) private var modelContext
    
    @State private var tagInput: String = ""
    @State private var showTagInput = false
    @State private var selectedRightTab: Int = 0
    
    #if canImport(Translation)
    @State private var translationConfig: Any? = nil
    #endif
    
    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar
            
            // Banners
            if let error = viewModel.errorMessage {
                ErrorBannerView(
                    message: error,
                    style: .error,
                    onDismiss: { viewModel.errorMessage = nil }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
            }
            
            if viewModel.exportSuccess {
                ErrorBannerView(
                    message: "Успішно експортовано в Obsidian!",
                    style: .success,
                    onDismiss: { viewModel.exportSuccess = false }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
            }
            
            // Split view
            HSplitView {
                TranscriptPanelView(
                    segments: viewModel.filteredSegments,
                    searchText: $viewModel.searchText,
                    speakerMetadata: viewModel.meeting.speakerMetadata,
                    isLoading: viewModel.isLoadingTranscript,
                    translatedText: viewModel.translatedTranscript,
                    translatedSegments: viewModel.translatedSegments,
                    isTranslating: viewModel.isTranslatingTranscript,
                    isTranscribing: viewModel.isTranscribing,
                    transcriptionProgress: viewModel.transcriptionProgressValue,
                    transcriptionStatusText: viewModel.transcriptionStatusText,
                    audioURL: viewModel.meeting.audioURL,
                    initialHighlightedSegmentID: viewModel.highlightedSegmentID,
                    onClearTranslation: {
                        viewModel.translatedTranscript = nil
                        viewModel.translatedSegments = [:]
                    },
                    onUpdateSpeakerName: { id, name in
                        viewModel.updateSpeakerName(id: id, newName: name)
                    },
                    onUpdateSpeakerColor: { id, color in
                        viewModel.updateSpeakerColor(id: id, color: color)
                    },
                    onRetranscribe: {
                        Task { await viewModel.retranscribeMeeting() }
                    }
                )
                .frame(minWidth: 300)
                
                TabView(selection: $selectedRightTab) {
                    SummaryPanelView(
                        summary: viewModel.summary,
                        streamingSummary: viewModel.streamingSummary,
                        selectedLanguage: $viewModel.selectedSummaryLanguage,
                        isGenerating: viewModel.isRegeneratingSummary,
                        onRegenerate: {
                            Task { await viewModel.regenerateSummary() }
                        },
                        onCopy: { viewModel.copySummary() },
                        onExport: { viewModel.exportToObsidian() },
                        onCancel: { viewModel.cancelSummaryGeneration() }
                    )
                    .tabItem { Text("Резюме") }
                    .tag(0)
                    
                    MeetingChatView(
                        messages: viewModel.chatMessages,
                        streamingResponse: viewModel.streamingChatResponse,
                        isChatting: viewModel.isChatting,
                        onSendMessage: { message in
                            Task { await viewModel.sendChatMessage(message) }
                        },
                        onCancel: {
                            viewModel.cancelChat()
                        }
                    )
                    .tabItem { Text("Q&A Чат") }
                    .tag(1)
                }
                .frame(minWidth: 300)
            }
        }
        .background(Theme.Colors.backgroundPrimary)
        .task {
            viewModel.setModelContext(modelContext)
            await viewModel.loadData()
        }
        #if canImport(Translation)
        .translationTask(translationConfig as? TranslationSession.Configuration) { session in
            Task {
                await viewModel.translateTranscriptWithAppleTranslation(session: session)
                translationConfig = nil
            }
        }
        #endif
        .onDisappear {
            AudioPlaybackManager.shared.reset()
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                // Meeting title and metadata
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    TextField("Назва наради", text: $viewModel.meetingTitle)
                        .font(Theme.Typography.title2)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .textFieldStyle(.plain)
                        .minimumScaleFactor(0.7)
                        .onSubmit {
                            viewModel.updateMeetingTitle()
                        }
                    
                    HStack(spacing: Theme.Spacing.md) {
                        Label(viewModel.meeting.displayDate, systemImage: "calendar")
                            .fixedSize()
                        
                        Label(viewModel.meeting.displayDuration, systemImage: "clock")
                            .fixedSize()
                        
                        StatusBadgeView(status: viewModel.meeting.status)
                            .fixedSize()
                    }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                .layoutPriority(1)
                
                Spacer(minLength: Theme.Spacing.md)
                
                // Actions
                HStack(spacing: Theme.Spacing.sm) {


                    Button(action: { viewModel.copyTranscript() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                            Text("Транскрипт")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.backgroundTertiary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Скопіювати повний транскрипт у буфер обміну")
                    
                    Button(action: { viewModel.exportToObsidian() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Obsidian")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.backgroundTertiary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Експортувати нараду як Markdown-нотатку в Obsidian Vault")
                    
                    translationMenu
                }
                .font(Theme.Typography.caption)
                .fixedSize(horizontal: true, vertical: false)
            }
            
            // Tags
            tagsRow
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.lg)
        .background(Theme.Colors.backgroundSecondary.opacity(0.5))
    }
    
    private var translationMenu: some View {
        Menu {
            ForEach(AppSettings.supportedLanguages.filter { $0.code != "auto" }, id: \.code) { lang in
                Menu(lang.name) {
                    Button("Локальний LLM (Ollama/MLX)") {
                        Task { await viewModel.translateTranscript(to: lang.name) }
                    }
                    
                    #if canImport(Translation)
                    if #available(macOS 15.0, *) {
                        Button("Apple Intelligence (офлайн)") {
                            let sourceLang = Locale.Language(languageCode: Locale.LanguageCode(viewModel.meeting.language))
                            let targetLang = Locale.Language(languageCode: Locale.LanguageCode(lang.code))
                            translationConfig = TranslationSession.Configuration(source: sourceLang, target: targetLang)
                        }
                    }
                    #endif
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text("Переклад")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.Colors.backgroundTertiary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isTranslatingTranscript)
        .help("Перекласти транскрипт на іншу мову за допомогою AI або Apple Intelligence")
    }
    
    // MARK: - Tags
    
    private var tagsRow: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(viewModel.meeting.tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text("#\(tag)")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    Button(action: { viewModel.removeTag(tag) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(tag.tagColor.opacity(0.3))
                .clipShape(Capsule())
            }
            
            // Add tag button
            if showTagInput {
                TextField("тег", text: $tagInput)
                    .font(Theme.Typography.footnote)
                    .textFieldStyle(.plain)
                    .frame(width: 80)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(Theme.Colors.backgroundTertiary)
                    .clipShape(Capsule())
                    .onSubmit {
                        viewModel.addTag(tagInput)
                        tagInput = ""
                        showTagInput = false
                    }
            } else {
                Button(action: { showTagInput = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(Theme.Colors.backgroundTertiary.opacity(0.5))
                .clipShape(Circle())
            }
            
            Spacer()
        }
    }
}
