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
    let audioManager: AudioManager
    let transcriptionService: TranscriptionService
    let llmService: LLMService
    
    // State
    @State private var selectedMeetingID: UUID?
    @State private var isShowingRecording = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    // ViewModels
    @State private var recordingVM: RecordingViewModel?
    @State private var meetingListVM = MeetingListViewModel()
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            detailContent
        }
        .navigationTitle("")
        .onAppear {
            setupViewModels()
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        MeetingListView(
            selectedMeetingID: $selectedMeetingID,
            viewModel: meetingListVM,
            onNewRecording: {
                isShowingRecording = true
                selectedMeetingID = nil
                recordingVM?.resetForNewRecording()
            }
        )
    }
    
    // MARK: - Detail Content
    
    @ViewBuilder
    private var detailContent: some View {
        if isShowingRecording && selectedMeetingID == nil {
            // Show recording view
            if let vm = recordingVM {
                RecordingView(viewModel: vm)
                    .onChange(of: vm.state) { oldState, newState in
                        if case .complete = newState {
                            // After recording completes, show the meeting detail
                            // The meeting was already saved to SwiftData
                        }
                    }
            } else {
                ProgressView("Ініціалізація...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.backgroundPrimary)
            }
        } else if let meetingID = selectedMeetingID {
            // Show meeting detail
            MeetingDetailForID(
                meetingID: meetingID,
                llmService: llmService
            )
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
    
    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
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
    let llmService: LLMService
    
    @Environment(\.modelContext) private var modelContext
    @Query private var meetings: [Meeting]
    
    @State private var detailVM: MeetingDetailViewModel?
    
    var body: some View {
        if let meeting = meetings.first(where: { $0.id == meetingID }) {
            if let vm = detailVM, vm.meeting.id == meetingID {
                MeetingDetailView(viewModel: vm)
            } else {
                Color.clear.onAppear {
                    let vm = MeetingDetailViewModel(meeting: meeting, llmService: llmService)
                    vm.setModelContext(modelContext)
                    detailVM = vm
                }
            }
        } else {
            Text("Нараду не знайдено")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.backgroundPrimary)
        }
    }
}
