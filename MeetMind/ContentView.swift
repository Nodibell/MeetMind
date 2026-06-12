//
//  ContentView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Main app view — NavigationSplitView with meeting list sidebar and detail content.
/// Navigation state is owned by `AppRouter`; this view is responsible only for layout.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    // Services (injected from app)
    let audioManager: any AudioProvider
    let transcriptionService: any TranscriptionProvider
    let llmService: any LLMProvider

    // DB diagnostic state (passed from PersistenceController via MeetMindApp)
    let dbError: String?
    let dbBackupCreated: Bool

    // Navigation
    @State private var router = AppRouter()
    
    // LLM state for global status badge
    @State private var llmState: LLMServiceState = .idle

    // ViewModels
    @State private var recordingVM: RecordingViewModel?
    @State private var meetingListVM = MeetingListViewModel()

    // UI state
    @State private var dbErrorDismissed = false
    @State private var isShowingOnboarding = false
    @State private var isDroppingFile = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            dbBanner
            NavigationSplitView(columnVisibility: $router.columnVisibility) {
                sidebar
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            } detail: {
                detailContent
            }
            .toolbar {
                ToolbarItem(placement: .status) {
                    LLMStatusBadge(
                        provider: AppSettings.shared.llmProvider,
                        modelName: AppSettings.shared.llmProvider == .deepMLX
                            ? AppSettings.shared.deepMLXModelPath?.lastPathComponent
                            : (AppSettings.shared.llmProvider == .appleIntelligence ? nil : AppSettings.shared.llmModel),
                        isGenerating: llmState == .generating
                    )
                }
            }
        }
        .navigationTitle("")
        .onAppear {
            setupViewModels()
            checkFirstRun()
            
            // Listen to LLM Service state changes to update the badge pulsing state
            Task {
                let initialState = await llmService.state
                await MainActor.run {
                    self.llmState = initialState
                }
                
                await llmService.setOnStateChanged { @Sendable newState in
                    Task { @MainActor in
                        self.llmState = newState
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startNewRecording)) { _ in
            router.startNewRecording()
            recordingVM?.resetForNewRecording()
        }
        .sheet(isPresented: $isShowingOnboarding) {
            OnboardingView(transcriptionService: transcriptionService) {
                isShowingOnboarding = false
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                recordingVM?.refreshSystemAudioSources(forcePrompt: false)
            }
            .environment(\.locale, .init(identifier: AppSettings.shared.appLanguage))
        }
        // Drag-and-drop file support using onDrop (compatible with macOS Finder)
        .onDrop(of: [.fileURL, .url], isTargeted: Binding(
            get: { isDroppingFile },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDroppingFile = newValue
                }
            }
        )) { providers in
            guard let provider = providers.first else { return false }
            
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let data = item as? Data {
                        if let url = URL(dataRepresentation: data, relativeTo: nil) {
                            handleDroppedFile(at: url)
                        }
                    } else if let url = item as? URL {
                        handleDroppedFile(at: url)
                    }
                }
                return true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                    if let url = item as? URL {
                        handleDroppedFile(at: url)
                    }
                }
                return true
            }
            return false
        }
        .overlay {
            if isDroppingFile {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.white)
                        Text("Перетягніть для транскрипції")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(40)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
        }
    }

    // MARK: - DB Error Banner

    @ViewBuilder
    private var dbBanner: some View {
        if let error = dbError, !dbErrorDismissed {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Базу даних було відновлено (скинуто)")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(dbBackupCreated
                         ? "Попередній файл містив помилки міграції. Резервну копію збережено в папці Backups. (\(error))"
                         : "Виникла помилка бази даних. (\(error))")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                Button("Зрозуміло") {
                    withAnimation { dbErrorDismissed = true }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color.yellow.opacity(0.1))
            .overlay(Rectangle().stroke(Color.yellow.opacity(0.3), lineWidth: 1))
            .transition(.move(edge: .top))
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        MeetingListView(
            selectedMeetingID: Binding(
                get: { router.selectedMeetingID },
                set: { id in
                    DispatchQueue.main.async {
                        if let id {
                            if id == .globalSearch {
                                router.navigate(to: .globalSearch)
                            } else if id == .actionItems {
                                router.navigate(to: .actionItems)
                            } else if isGroup(id) {
                                router.navigate(to: .groupChat(id))
                            } else {
                                router.navigate(to: .meeting(id, highlightedSegmentID: nil))
                            }
                        } else {
                            // Allow deselection to welcome screen so navigation never gets locked
                            router.navigate(to: .welcome)
                        }
                    }
                }
            ),
            viewModel: meetingListVM,
            recordingVM: recordingVM,
            onNewRecording: {
                router.startNewRecording()
                recordingVM?.resetForNewRecording()
            },
            onImportFile: {
                importFile()
            }
        )
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 0) {
            // Background transcription banner — visible from any screen while processing
            if let vm = recordingVM, !router.isShowingRecording {
                backgroundProcessingBanner(vm: vm)
            }

            switch router.current {
            case .globalSearch:
                GlobalSearchView(llmService: llmService)

            case .actionItems:
                ActionItemsView()

            case .recording:
                recordingDetail

            case .meeting(let id, let segmentID):
                MeetingDetailForID(
                    meetingID: id,
                    highlightedSegmentID: segmentID,
                    llmService: llmService,
                    transcriptionService: transcriptionService
                )

            case .groupChat(let id):
                GroupChatViewForID(groupID: id, llmService: llmService) { meetingID, segmentID in
                    router.navigate(to: .meeting(meetingID, highlightedSegmentID: segmentID))
                }

            case .welcome:
                welcomeView
            }
        }
    }

    @ViewBuilder
    private func backgroundProcessingBanner(vm: RecordingViewModel) -> some View {
        if vm.state == .preparing || vm.state == .extracting || vm.state == .transcribing || vm.state == .summarizing {
            processingBannerRow(
                icon: currentStageIcon(for: vm.state),
                label: currentStageLabel(for: vm.state, vm: vm),
                progress: vm.overallProgress,
                vm: vm
            )
        } else {
            EmptyView()
        }
    }
    
    private func currentStageIcon(for state: RecordingViewModel.RecordingState) -> String {
        switch state {
        case .preparing: return "cpu"
        case .extracting: return "arrow.down.circle"
        case .transcribing: return "text.viewfinder"
        case .summarizing: return "sparkles"
        default: return "hourglass"
        }
    }
    
    private func currentStageLabel(for state: RecordingViewModel.RecordingState, vm: RecordingViewModel) -> String {
        switch state {
        case .preparing: return String(localized: "Підготовка...")
        case .extracting: return vm.importProgressStage.isEmpty ? String(localized: "Вилучення аудіо...") : vm.importProgressStage
        case .transcribing: return vm.transcriptionProgressText.isEmpty ? String(localized: "Транскрипція...") : vm.transcriptionProgressText
        case .summarizing: return String(localized: "Генерація резюме...")
        default: return String(localized: "Обробка...")
        }
    }

    private func processingBannerRow(
        icon: String,
        label: String,
        progress: Double?,
        vm: RecordingViewModel
    ) -> some View {
        Button {
            router.startNewRecording()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accentPrimary)

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                if let progress {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(Theme.Colors.accentPrimary)
                        .frame(maxWidth: 100)

                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.Colors.accentPrimary)
                        .frame(width: 32, alignment: .trailing)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(Theme.Colors.accentPrimary)
                        .frame(maxWidth: 80)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Text("Переглянути")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Theme.Colors.accentPrimary)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .background(Theme.Colors.accentPrimary.opacity(0.07))
        .overlay(alignment: .bottom) {
            Divider().background(Theme.Colors.accentPrimary.opacity(0.2))
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var recordingDetail: some View {
        if let vm = recordingVM {
            RecordingView(viewModel: vm)
                .onChange(of: vm.state) { _, newState in
                    if case .complete = newState, let meetingID = vm.completedMeetingID {
                        router.navigateAfterRecordingComplete(meetingID: meetingID)
                    }
                }
        } else {
            ProgressView("Ініціалізація...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.backgroundPrimary)
        }
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.Colors.accentPrimary.opacity(0.2),
                                Theme.Colors.accentSecondary.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(Theme.Gradients.accent)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text("MeetMind")
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("AI-помічник для нарад")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            VStack(spacing: Theme.Spacing.md) {
                featureRow(icon: "mic.fill",            title: "Запис аудіо",    subtitle: "Мікрофон або системне аудіо")
                featureRow(icon: "text.quote",          title: "Транскрипція",   subtitle: "WhisperKit — українська мова")
                featureRow(icon: "brain.head.profile",  title: "AI Аналіз",      subtitle: "Ollama — резюме та завдання")
                featureRow(icon: "doc.text",            title: "Obsidian",       subtitle: "Автоматичний експорт нотаток")
            }
            .frame(width: 260)

            Button {
                router.startNewRecording()
                recordingVM?.resetForNewRecording()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "mic.fill")
                    Text("Почати запис")
                }
                .font(Theme.Typography.bodyMedium)
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Gradients.accent)
                .clipShape(Capsule())
                .shadow(color: Theme.Colors.accentPrimary.opacity(0.3), radius: 12, y: 4)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.backgroundPrimary)
    }

    private func featureRow(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Colors.accentPrimary)
                .frame(width: 32, height: 32)
                .background(Theme.Colors.accentPrimary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(subtitle)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Spacer()
        }
    }

    // MARK: - Setup

    private func checkFirstRun() {
        guard !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else { return }
        isShowingOnboarding = true
    }
    
    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        let extensions = ["wav", "mp3", "m4a", "flac", "aac", "mp4", "mov", "m4v", "mkv", "avi"]
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        router.startNewRecording()
        recordingVM?.processImportedFile(at: url)
    }

    private func handleDroppedFile(at url: URL) {
        let supportedExtensions: Set<String> = ["wav", "mp3", "m4a", "flac", "aac", "mp4", "mov", "m4v", "mkv", "avi", "caf", "opus", "ogg"]
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else { return }
        
        router.startNewRecording()
        recordingVM?.processImportedFile(at: url)
    }

    private func setupViewModels() {
        if recordingVM == nil {
            let vm = RecordingViewModel(
                audioManager: audioManager,
                transcriptionService: transcriptionService,
                llmService: llmService
            )
            vm.setModelContext(modelContext)
            recordingVM = vm
        }
        meetingListVM.setModelContext(modelContext)
    }

    private func isGroup(_ id: UUID) -> Bool {
        let descriptor = FetchDescriptor<MeetingGroup>(predicate: #Predicate { $0.id == id })
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count > 0
    }
}

// MARK: - Meeting Detail Wrapper (loads meeting from ID)

struct MeetingDetailForID: View {
    let meetingID: UUID
    let highlightedSegmentID: UUID?
    let llmService: any LLMProvider
    let transcriptionService: any TranscriptionProvider

    @Environment(\.modelContext) private var modelContext
    @Query private var meetings: [Meeting]

    init(meetingID: UUID, highlightedSegmentID: UUID?, llmService: any LLMProvider, transcriptionService: any TranscriptionProvider) {
        self.meetingID = meetingID
        self.highlightedSegmentID = highlightedSegmentID
        self.llmService = llmService
        self.transcriptionService = transcriptionService

        let predicate = #Predicate<Meeting> { $0.id == meetingID }
        _meetings = Query(filter: predicate)
    }

    var body: some View {
        Group {
            if let meeting = meetings.first ?? findMeetingDirectly() {
                MeetingDetailViewWrapper(meeting: meeting, highlightedSegmentID: highlightedSegmentID, llmService: llmService, transcriptionService: transcriptionService)
                    .id(meeting.id)
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Завантаження наради...")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.backgroundPrimary)
            }
        }
    }

    private func findMeetingDirectly() -> Meeting? {
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingID })
        return try? modelContext.fetch(descriptor).first
    }
}

struct MeetingDetailViewWrapper: View {
    let meeting: Meeting
    let highlightedSegmentID: UUID?
    let llmService: any LLMProvider
    let transcriptionService: any TranscriptionProvider

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: MeetingDetailViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                MeetingDetailView(viewModel: vm)
            } else {
                Color.clear.onAppear {
                    let vm = MeetingDetailViewModel(meeting: meeting, llmService: llmService, transcriptionService: transcriptionService)
                    vm.setModelContext(modelContext)
                    vm.highlightedSegmentID = highlightedSegmentID
                    viewModel = vm
                }
            }
        }
        .onChange(of: highlightedSegmentID) { _, newID in
            viewModel?.highlightedSegmentID = newID
        }
    }
}

// MARK: - Group Chat Wrapper (loads group from ID)

struct GroupChatViewForID: View {
    let groupID: UUID
    let llmService: any LLMProvider
    var onNavigateToMeeting: (UUID, UUID?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var groups: [MeetingGroup]

    init(groupID: UUID, llmService: any LLMProvider, onNavigateToMeeting: @escaping (UUID, UUID?) -> Void) {
        self.groupID = groupID
        self.llmService = llmService
        self.onNavigateToMeeting = onNavigateToMeeting

        let predicate = #Predicate<MeetingGroup> { $0.id == groupID }
        _groups = Query(filter: predicate)
    }

    var body: some View {
        Group {
            if let group = groups.first ?? findGroupDirectly() {
                GroupChatViewWrapper(group: group, llmService: llmService, onNavigateToMeeting: onNavigateToMeeting)
                    .id(group.id)
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Завантаження групи...")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.backgroundPrimary)
            }
        }
    }

    private func findGroupDirectly() -> MeetingGroup? {
        let descriptor = FetchDescriptor<MeetingGroup>(predicate: #Predicate { $0.id == groupID })
        return try? modelContext.fetch(descriptor).first
    }
}

struct GroupChatViewWrapper: View {
    let group: MeetingGroup
    let llmService: any LLMProvider
    var onNavigateToMeeting: (UUID, UUID?) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: GroupChatViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                GroupChatView(viewModel: vm, onNavigateToMeeting: onNavigateToMeeting)
            } else {
                Color.clear.onAppear {
                    let vm = GroupChatViewModel(group: group, llmService: llmService)
                    vm.setModelContext(modelContext)
                    viewModel = vm
                }
            }
        }
    }
}
