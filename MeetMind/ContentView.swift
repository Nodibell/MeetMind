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

    // ViewModels
    @State private var recordingVM: RecordingViewModel?
    @State private var meetingListVM = MeetingListViewModel()

    // UI state
    @State private var dbErrorDismissed = false
    @State private var isShowingOnboarding = false

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
        }
        .navigationTitle("")
        .onAppear {
            setupViewModels()
            checkFirstRun()
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
                    guard let id else { return }
                    switch id {
                    case .globalSearch: router.navigate(to: .globalSearch)
                    case .actionItems:  router.navigate(to: .actionItems)
                    default:            router.navigate(to: .meeting(id))
                    }
                }
            ),
            viewModel: meetingListVM,
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
        switch router.current {
        case .globalSearch:
            GlobalSearchView(llmService: llmService)

        case .actionItems:
            ActionItemsView()

        case .recording:
            recordingDetail

        case .meeting(let id):
            MeetingDetailForID(meetingID: id, llmService: llmService)

        case .welcome:
            welcomeView
        }
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
            .frame(maxWidth: 320)

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
        
        Task {
            await recordingVM?.processImportedFile(at: url)
        }
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
}

// MARK: - Meeting Detail Wrapper (loads meeting from ID)

struct MeetingDetailForID: View {
    let meetingID: UUID
    let llmService: any LLMProvider

    @Environment(\.modelContext) private var modelContext
    @Query private var meetings: [Meeting]

    @State private var detailVM: MeetingDetailViewModel?

    init(meetingID: UUID, llmService: any LLMProvider) {
        self.meetingID = meetingID
        self.llmService = llmService

        let predicate = #Predicate<Meeting> { $0.id == meetingID }
        _meetings = Query(filter: predicate)
    }

    var body: some View {
        Group {
            if let meeting = meetings.first ?? findMeetingDirectly() {
                MeetingDetailViewWrapper(meeting: meeting, llmService: llmService)
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
    let llmService: any LLMProvider

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: MeetingDetailViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                MeetingDetailView(viewModel: vm)
            } else {
                Color.clear.onAppear {
                    let vm = MeetingDetailViewModel(meeting: meeting, llmService: llmService)
                    vm.setModelContext(modelContext)
                    viewModel = vm
                }
            }
        }
    }
}
