//
//  GroupChatView.swift
//  MeetMind
//
//  Created by Developer on 28.05.2026.
//

import SwiftUI
import SwiftData

/// Gorgeous SwiftUI View for chatting with a group of meetings using local RAG
struct GroupChatView: View {
    @Bindable var viewModel: GroupChatViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var chatInputText = ""
    @FocusState private var isChatInputFocused: Bool
    @State private var isShowingAddMeetingsSheet = false
    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]
    
    // Callback to navigate to a specific meeting and jump to a segment
    var onNavigateToMeeting: (UUID, UUID?) -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Column: Group Details & Associated Meetings
            VStack(alignment: .leading, spacing: 16) {
                // Header Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.group.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(2)
                    
                    if let desc = viewModel.group.customDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                Divider()
                
                // Indexing Status & Actions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Векторний індекс")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    if viewModel.isIndexing {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: viewModel.indexingProgress, total: 1.0)
                                .progressViewStyle(.linear)
                            
                            Text(viewModel.indexingStatusText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.shield.fill")
                                .foregroundStyle(.green)
                            Text(viewModel.indexingStatusText.isEmpty ? "Готовий до аналізу" : viewModel.indexingStatusText)
                                .font(.caption)
                            Spacer()
                        }
                        
                        Button(action: {
                            viewModel.indexAllMeetings()
                        }) {
                            Label("Переіндексувати групу", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
                .padding(.horizontal)
                
                Divider()
                
                // Saved Chats (Sessions List)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Збережені чати")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.createNewChatSession()
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.Colors.accentPrimary)
                        }
                        .buttonStyle(.plain)
                        .help("Почати новий чат")
                    }
                    .padding(.horizontal)
                    
                    if viewModel.chatSessions.isEmpty {
                        Text("Немає збережених розмов")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(viewModel.chatSessions) { session in
                                    let isActive = session.id == viewModel.activeSession?.id
                                    
                                    HStack {
                                        Image(systemName: "message.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(isActive ? Theme.Colors.accentPrimary : .secondary)
                                        
                                        Text(session.title)
                                            .font(.body)
                                            .lineLimit(1)
                                            .foregroundStyle(isActive ? .primary : .secondary)
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            viewModel.deleteChatSession(session)
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Видалити розмову")
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .background(isActive ? Color(NSColor.controlBackgroundColor).opacity(0.8) : Color.clear)
                                    .contentShape(Rectangle())
                                    .cornerRadius(6)
                                    .onTapGesture {
                                        viewModel.selectChatSession(session)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(maxHeight: 180)
                    }
                }
                
                Divider()
                
                // Meetings List inside group
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Наради в цій групі (\(viewModel.group.meetings.count))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button(action: {
                            isShowingAddMeetingsSheet = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.Colors.accentPrimary)
                        }
                        .buttonStyle(.plain)
                        .help("Додати або видалити наради")
                    }
                    .padding(.horizontal)
                    
                    if viewModel.group.meetings.isEmpty {
                        VStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 24))
                                .foregroundStyle(.secondary)
                            
                            Text("У цій групі ще немає нарад.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                            
                            Button(action: {
                                isShowingAddMeetingsSheet = true
                            }) {
                                Text("Додати наради")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 24)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.md)
                        .padding(.horizontal)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(viewModel.group.meetings) { meeting in
                                    Button(action: {
                                        onNavigateToMeeting(meeting.id, nil)
                                    }) {
                                        HStack {
                                            Image(systemName: meeting.status.systemImage)
                                                .foregroundStyle(meeting.status == .complete ? .green : .secondary)
                                            VStack(alignment: .leading) {
                                                Text(meeting.title)
                                                    .font(.body)
                                                    .lineLimit(1)
                                                Text(meeting.displayDate)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(8)
                                        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                Spacer()
            }
            .frame(width: 250)
            .background(Theme.Colors.backgroundSecondary.opacity(0.8))
            
            Divider()
            
            // Right Column: Q&A Chat Interface
            VStack(spacing: 0) {
                // Messages List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if viewModel.chatMessages.isEmpty && viewModel.streamingChatResponse.isEmpty && !viewModel.isChatting {
                                emptyStateView
                                    .padding(.top, 80)
                            } else {
                                ForEach(viewModel.chatMessages) { message in
                                    ChatMessageBubbleView(
                                        role: message.role,
                                        content: message.content,
                                        isStreaming: false
                                    )
                                    .footer {
                                        if let sources = message.sources, !sources.isEmpty {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Джерела:")
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                                    .foregroundStyle(.secondary)
                                                
                                                ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                                                    let meetingTitle = viewModel.group.meetings.first(where: { $0.id == source.meetingID })?.title ?? "Нарада"
                                                    
                                                    Button(action: {
                                                        onNavigateToMeeting(source.meetingID, source.segmentID)
                                                    }) {
                                                        HStack(spacing: 4) {
                                                            Text("[\(index + 1)]")
                                                                .fontWeight(.bold)
                                                            Text(meetingTitle)
                                                                .lineLimit(1)
                                                            Image(systemName: "arrow.up.right.square")
                                                                .font(.system(size: 9))
                                                        }
                                                        .font(.caption2)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 3)
                                                        .background(Color.accentColor.opacity(0.1))
                                                        .foregroundStyle(Color.accentColor)
                                                        .cornerRadius(4)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.top, 4)
                                        }
                                    }
                                    .id(message.id)
                                }
                                
                                if viewModel.isChatting && viewModel.streamingChatResponse.isEmpty {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 8) {
                                                ProgressView()
                                                    .controlSize(.small)
                                                Text("ШІ аналізує та формулює відповідь...")
                                                    .font(.body)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color(NSColor.controlBackgroundColor))
                                            .cornerRadius(12)
                                        }
                                        Spacer()
                                    }
                                    .id("thinkingBubble")
                                } else if !viewModel.streamingChatResponse.isEmpty {
                                    ChatMessageBubbleView(
                                        role: "assistant",
                                        content: viewModel.streamingChatResponse,
                                        isStreaming: true
                                    )
                                    .id("streamingResponse")
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.chatMessages.count) { _, _ in
                        withAnimation {
                            if let last = viewModel.chatMessages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.streamingChatResponse) { _, _ in
                        if !viewModel.streamingChatResponse.isEmpty {
                            proxy.scrollTo("streamingResponse", anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.isChatting) { _, isChatting in
                        if isChatting && viewModel.streamingChatResponse.isEmpty {
                            withAnimation {
                                proxy.scrollTo("thinkingBubble", anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Error banner
                if let error = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Button(action: { viewModel.errorMessage = nil }) {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                }
                
                // Input Bar
                HStack(spacing: 12) {
                    Button(action: {
                        viewModel.clearHistory()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .help("Очистити історію чату")
                    
                    TextField("Запитайте про деталі цієї групи нарад...", text: $chatInputText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isChatInputFocused)
                        .onSubmit {
                            submitUserMessage()
                        }
                    
                    if viewModel.isChatting {
                        Button(action: {
                            viewModel.cancelChat()
                        }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: {
                            submitUserMessage()
                        }) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(chatInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
                .background(Theme.Colors.backgroundPrimary)
            }
        }
        .sheet(isPresented: $isShowingAddMeetingsSheet) {
            AddMeetingsSheet(
                group: viewModel.group,
                allMeetings: allMeetings,
                onSave: { selectedIDs in
                    // Update meetings in group
                    for meeting in allMeetings {
                        let shouldBeInGroup = selectedIDs.contains(meeting.id)
                        let isInGroup = viewModel.group.meetings.contains(where: { $0.id == meeting.id })
                        
                        if shouldBeInGroup && !isInGroup {
                            viewModel.group.meetings.append(meeting)
                        } else if !shouldBeInGroup && isInGroup {
                            viewModel.group.meetings.removeAll(where: { $0.id == meeting.id })
                        }
                    }
                    try? modelContext.save()
                    isShowingAddMeetingsSheet = false
                    
                    // Re-index the group to rebuild RAG index
                    viewModel.indexAllMeetings()
                },
                onCancel: {
                    isShowingAddMeetingsSheet = false
                }
            )
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
            viewModel.indexAllMeetings() // Pre-index the group when opening the view
        }
        .onDisappear {
            viewModel.cancelAllTasks()
        }
    }
    
    // MARK: - UI Helper views
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("Запитайте свої наради")
                .font(.headline)
            
            Text("Місцевий ШІ проаналізує всі транскрипти цієї групи за допомогою RAG та надасть консолідовану відповідь.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Спробуйте запитати:")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                
                Text("• Які ключові рішення були прийняті за весь час?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("• Хто відповідальний за реліз продукту?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .cornerRadius(8)
        }
    }
    
    // Markdown rendering helper function has been replaced with the dedicated GroupChatMessageBubbleRow view struct.
    
    private func submitUserMessage() {
        let query = chatInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        
        chatInputText = ""
        Task {
            await viewModel.sendChatMessage(query)
        }
    }
}

// MARK: - AddMeetingsSheet

struct AddMeetingsSheet: View {
    let group: MeetingGroup
    let allMeetings: [Meeting]
    var onSave: (Set<UUID>) -> Void
    var onCancel: () -> Void
    
    @State private var searchText = ""
    @State private var selectedIDs: Set<UUID> = []
    
    init(group: MeetingGroup, allMeetings: [Meeting], onSave: @escaping (Set<UUID>) -> Void, onCancel: @escaping () -> Void) {
        self.group = group
        self.allMeetings = allMeetings
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedIDs = State(initialValue: Set(group.meetings.map { $0.id }))
    }
    
    var filteredMeetings: [Meeting] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return allMeetings
        } else {
            return allMeetings.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Додати наради до групи")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text("Оберіть наради, які ви хочете включити до RAG аналізу")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            // Search Bar & Quick actions
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Пошук нарад за назвою...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                HStack {
                    Button("Вибрати всі") {
                        let ids = filteredMeetings.map { $0.id }
                        selectedIDs.formUnion(ids)
                    }
                    .buttonStyle(.link)
                    .font(Theme.Typography.footnote)
                    
                    Text("|")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(.secondary)
                    
                    Button("Зняти виділення") {
                        let ids = filteredMeetings.map { $0.id }
                        selectedIDs.subtract(ids)
                    }
                    .buttonStyle(.link)
                    .font(Theme.Typography.footnote)
                    
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            
            Divider()
            
            // Meetings List with Checkboxes
            List {
                if filteredMeetings.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("Нарад не знайдено")
                            .font(Theme.Typography.bodyMedium)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredMeetings) { meeting in
                        HStack(spacing: 12) {
                            Toggle("", isOn: Binding(
                                get: { selectedIDs.contains(meeting.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedIDs.insert(meeting.id)
                                    } else {
                                        selectedIDs.remove(meeting.id)
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            
                            Image(systemName: meeting.status.systemImage)
                                .foregroundStyle(meeting.status == .complete ? .green : .secondary)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meeting.title)
                                    .font(Theme.Typography.bodyMedium)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .lineLimit(1)
                                
                                HStack(spacing: 8) {
                                    Text(meeting.displayDate)
                                    if meeting.duration > 0 {
                                        Text("•")
                                        Text(meeting.displayDuration)
                                    }
                                }
                                .font(Theme.Typography.footnote)
                                .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.inset)
            
            Divider()
            
            // Footer Action Buttons
            HStack(spacing: 12) {
                Spacer()
                
                Button("Скасувати") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.regular)
                
                Button("Зберегти") {
                    onSave(selectedIDs)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
            .padding(16)
            .background(Theme.Colors.backgroundSecondary)
        }
        .frame(width: 460, height: 500)
    }
}


