//
//  MeetingListView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI
import SwiftData

/// Sidebar meeting list with search and management
struct MeetingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    
    @Binding var selectedMeetingID: UUID?
    @Bindable var viewModel: MeetingListViewModel
    var onNewRecording: () -> Void

    @State private var meetingToDelete: Meeting?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Наради")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                // Sort Menu
                Menu {
                    Picker("Сортування", selection: $viewModel.sortOption) {
                        ForEach(MeetingListViewModel.SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Сортування")
                
                // New recording button
                Button(action: onNewRecording) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.Colors.accentPrimary)
                }
                .buttonStyle(.plain)
                .help("Новий запис")
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            
            Divider()
                .background(Theme.Colors.borderSubtle)
            
            // Meeting list
            List(selection: $selectedMeetingID) {
                Section("Smart") {
                    Label("Глобальний запит", systemImage: "magnifyingglass")
                        .tag(UUID.globalSearch)
                    
                    Label("Завдання (Action Items)", systemImage: "checklist")
                        .tag(UUID.actionItems)
                }

                Section("Наради") {
                    if filteredMeetings.isEmpty {
                        Text("Тут нічого немає")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredMeetings) { meeting in
                            MeetingRowView(meeting: meeting)
                                .tag(meeting.id)
                                .contextMenu {
                                    Button("Видалити", role: .destructive) {
                                        meetingToDelete = meeting
                                    }
                                }
                        }
                    }
                }
            }
        }
        .background(Theme.Colors.backgroundSecondary)
        .searchable(text: $viewModel.searchText, prompt: "Пошук нарад...")
        .onAppear {
            viewModel.setModelContext(modelContext)
        }
        .alert("Видалити нараду?", isPresented: Binding(
            get: { meetingToDelete != nil },
            set: { if !$0 { meetingToDelete = nil } }
        )) {
            Button("Скасувати", role: .cancel) { meetingToDelete = nil }
            Button("Видалити", role: .destructive) {
                if let m = meetingToDelete {
                    if selectedMeetingID == m.id { selectedMeetingID = nil }
                    viewModel.deleteMeeting(m)
                    meetingToDelete = nil
                }
            }
        } message: {
            if let m = meetingToDelete {
                Text("Нарада «\(m.title)» буде видалена разом з аудіозаписом і транскриптом. Цю дію не можна скасувати.")
            }
        }
    }
    
    // MARK: - Filtered Meetings
    
    private var filteredMeetings: [Meeting] {
        let result: [Meeting]
        if viewModel.searchText.isEmpty {
            result = meetings
        } else {
            result = meetings.filter { meeting in
                meeting.title.localizedCaseInsensitiveContains(viewModel.searchText) ||
                meeting.tags.contains(where: { $0.localizedCaseInsensitiveContains(viewModel.searchText) })
            }
        }
        
        return result.sorted { m1, m2 in
            switch viewModel.sortOption {
            case .date:
                return m1.date > m2.date
            case .title:
                return m1.title.localizedCompare(m2.title) == .orderedAscending
            case .duration:
                return m1.duration > m2.duration
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            
            Image(systemName: "waveform.circle")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Colors.accentPrimary.opacity(0.6), Theme.Colors.accentSecondary.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: Theme.Spacing.xs) {
                Text("Немає нарад")
                    .font(Theme.Typography.bodyMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                Text("Натисніть + щоб почати запис")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
