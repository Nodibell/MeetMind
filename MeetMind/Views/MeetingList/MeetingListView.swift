//
//  MeetingListView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Sidebar meeting list with search and management
struct MeetingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    @Query(sort: \MeetingGroup.createdAt, order: .reverse) private var groups: [MeetingGroup]
    
    @Binding var selectedMeetingID: UUID?
    @Bindable var viewModel: MeetingListViewModel
    var onNewRecording: () -> Void
    var onImportFile: () -> Void

    @State private var meetingToDelete: Meeting?
    @State private var isShowingCreateGroup = false
    @State private var newGroupName = ""
    @State private var newGroupDesc = ""
    
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
                
                // Import button
                Button(action: onImportFile) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Colors.accentPrimary)
                }
                .buttonStyle(.plain)
                .help("Імпортувати аудіо/відео")
                
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

                Section(header:
                    HStack(alignment: .center, spacing: 4) {
                        Text("Групи нарад (RAG)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                        Spacer()
                        Button(action: {
                            newGroupName = ""
                            newGroupDesc = ""
                            isShowingCreateGroup = true
                        }) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(Theme.Colors.accentPrimary)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 10)
                        .offset(y: -1)
                        .help("Створити нову групу")
                    }
                    .padding(.vertical, 1)
                ) {
                    if groups.isEmpty {
                        Text("Немає груп")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groups) { group in
                            Button(action: {
                                selectedMeetingID = group.id
                            }) {
                                Label {
                                    HStack {
                                        Text(group.name)
                                            .font(Theme.Typography.body)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(group.meetings.count)")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                            .clipShape(Capsule())
                                    }
                                } icon: {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .tag(group.id)
                            .contextMenu {
                                Button("Видалити групу", role: .destructive) {
                                    deleteGroup(group)
                                }
                            }
                            .onDrop(of: [.text], isTargeted: nil) { providers in
                                handleMeetingDrop(to: group, providers: providers)
                            }
                        }
                    }
                }

                Section("Наради") {
                    if filteredMeetings.isEmpty {
                        Text("Тут нічого немає")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredMeetings) { meeting in
                            Button(action: {
                                selectedMeetingID = meeting.id
                            }) {
                                MeetingRowView(meeting: meeting)
                            }
                            .buttonStyle(.plain)
                            .tag(meeting.id)
                            .onDrag {
                                NSItemProvider(object: meeting.id.uuidString as NSString)
                            }
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
        .sheet(isPresented: $isShowingCreateGroup) {
            createGroupSheet
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
                meeting.tags.contains(where: { $0.localizedCaseInsensitiveContains(viewModel.searchText) }) ||
                meeting.transcriptSegments.contains(where: { $0.text.localizedCaseInsensitiveContains(viewModel.searchText) })
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
    
    // MARK: - Group Management
    
    private func createGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let group = MeetingGroup(
            name: trimmed,
            customDescription: newGroupDesc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newGroupDesc
        )
        modelContext.insert(group)
        try? modelContext.save()
        
        isShowingCreateGroup = false
        selectedMeetingID = group.id
    }
    
    private func deleteGroup(_ group: MeetingGroup) {
        if selectedMeetingID == group.id {
            selectedMeetingID = nil
        }
        modelContext.delete(group)
        try? modelContext.save()
    }
    
    private func handleMeetingDrop(to group: MeetingGroup, providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: "public.text", options: nil) { item, error in
            guard let data = item as? Data,
                  let uuidString = String(data: data, encoding: .utf8),
                  let meetingUUID = UUID(uuidString: uuidString) else { return }
            
            Task { @MainActor in
                let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingUUID })
                if let meeting = try? modelContext.fetch(descriptor).first {
                    if !group.meetings.contains(where: { $0.id == meeting.id }) {
                        group.meetings.append(meeting)
                        meeting.groups.append(group)
                        try? modelContext.save()
                    }
                }
            }
        }
        return true
    }
    
    // MARK: - Create Group Sheet
    
    private var createGroupSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Нова група нарад (RAG)")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Text("Об’єднайте кілька нарад, щоб задавати питання по всій базі знань одночасно.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Назва")
                    .font(.caption)
                    .fontWeight(.semibold)
                TextField("Наприклад: Проєкт Альфа", text: $newGroupName)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Опис (необов’язково)")
                    .font(.caption)
                    .fontWeight(.semibold)
                TextField("Опишіть тематику цієї групи нарад...", text: $newGroupDesc)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Spacer()
                Button("Скасувати") {
                    isShowingCreateGroup = false
                }
                .buttonStyle(.bordered)
                
                Button("Створити") {
                    createGroup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .padding()
        .frame(width: 320)
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
