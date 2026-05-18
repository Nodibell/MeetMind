//
//  ContentView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI
import SwiftData

/// Main app view — NavigationSplitView with meeting list sidebar and detail content
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    // Services (injected from app)
    let audioManager: any AudioProvider
    let transcriptionService: any TranscriptionProvider
    let llmService: any LLMProvider
    
    // State
    @State private var selectedMeetingID: UUID?
    @State private var isShowingGlobalSearch = false
    @State private var isShowingActionItems = false
    @State private var isShowingRecording = true
    @State private var isShowingOnboarding = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var dbErrorPresented = false
    
    // ViewModels
    @State private var recordingVM: RecordingViewModel?
    @State private var meetingListVM = MeetingListViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            if dbErrorPresented, let dbError = MeetMindApp.dbInitializationError {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Базу даних було відновлено (скинуто)")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Попередній файл бази даних містив помилки міграції. Створено резервну копію в папці Backups: \(dbError)")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    Button("Зрозуміло") {
                        withAnimation {
                            dbErrorPresented = false
                            MeetMindApp.dbInitializationError = nil
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color.yellow.opacity(0.1))
                .overlay(Rectangle().stroke(Color.yellow.opacity(0.3), lineWidth: 1))
                .transition(.move(edge: .top))
            }
            
            NavigationSplitView(columnVisibility: $columnVisibility) {
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
            dbErrorPresented = MeetMindApp.dbInitializationError != nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .startNewRecording)) { _ in
            isShowingGlobalSearch = false
            isShowingActionItems = false
            isShowingRecording = true
            selectedMeetingID = nil
            recordingVM?.resetForNewRecording()
        }
        .sheet(isPresented: $isShowingOnboarding) {
            OnboardingView(transcriptionService: transcriptionService) {
                isShowingOnboarding = false
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            }
        }
        .onChange(of: selectedMeetingID) { oldID, newID in
            if newID == UUID.globalSearch {
                isShowingGlobalSearch = true
                isShowingActionItems = false
                isShowingRecording = false
            } else if newID == UUID.actionItems {
                isShowingGlobalSearch = false
                isShowingActionItems = true
                isShowingRecording = false
            } else if newID != nil {
                isShowingGlobalSearch = false
                isShowingActionItems = false
                isShowingRecording = false
            }
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        MeetingListView(
            selectedMeetingID: $selectedMeetingID,
            viewModel: meetingListVM,
            onNewRecording: {
                isShowingGlobalSearch = false
                isShowingActionItems = false
                isShowingRecording = true
                selectedMeetingID = nil
                recordingVM?.resetForNewRecording()
            }
        )
    }
    
    // MARK: - Detail Content
    
    @ViewBuilder
    private var detailContent: some View {
        if isShowingGlobalSearch {
            GlobalSearchView(llmService: llmService)
        } else if isShowingActionItems {
            ActionItemsView()
        } else if isShowingRecording && selectedMeetingID == nil {
            // Show recording view
            if let vm = recordingVM {
                RecordingView(viewModel: vm)
                    .onChange(of: vm.state) { oldState, newState in
                        if case .complete = newState {
                            if let meetingID = vm.completedMeetingID {
                                selectedMeetingID = meetingID
                                isShowingRecording = false
                            }
                        }
                    }
            } else {
                ProgressView("Ініціалізація...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.backgroundPrimary)
            }
        } else if let meetingID = selectedMeetingID {
            // Check if this meeting is currently being recorded
            if isShowingRecording || (recordingVM?.state == .recording && recordingVM?.currentMeeting?.id == meetingID) {
                if let vm = recordingVM {
                    RecordingView(viewModel: vm)
                } else {
                    MeetingDetailForID(
                        meetingID: meetingID,
                        llmService: llmService
                    )
                }
            } else {
                // Show meeting detail
                MeetingDetailForID(
                    meetingID: meetingID,
                    llmService: llmService
                )
            }
        } else {
            // Empty state
            welcomeView
        }
    }
    
    // MARK: - Welcome View
    
    private var welcomeView: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            Spacer()
            
            // App icon placeholder
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
                featureRow(icon: "mic.fill", title: "Запис аудіо", subtitle: "Мікрофон або системне аудіо")
                featureRow(icon: "text.quote", title: "Транскрипція", subtitle: "WhisperKit — українська мова")
                featureRow(icon: "brain.head.profile", title: "AI Аналіз", subtitle: "Ollama — резюме та завдання")
                featureRow(icon: "doc.text", title: "Obsidian", subtitle: "Автоматичний експорт нотаток")
            }
            .frame(maxWidth: 320)
            
            Button(action: {
                isShowingRecording = true
                selectedMeetingID = nil
                recordingVM?.resetForNewRecording()
            }) {
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
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !hasCompletedOnboarding {
            isShowingOnboarding = true
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
                    .id(meeting.id) // Force redraw on ID change
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
