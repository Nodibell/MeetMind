import SwiftUI
import SwiftData

struct ActionItemUI: Identifiable {
    let id: UUID
    var text: String
    let meetingTitle: String
    let meetingID: UUID
    var isCompleted: Bool
    var assignee: String?
}

struct ActionItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var meetings: [Meeting]
    @State private var actionItems: [ActionItemUI] = []
    @State private var isLoading = true
    @State private var hideCompleted = false
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            if isLoading {
                ProgressView("Пошук завдань...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredItems.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredItems) { item in
                        ActionItemRow(item: item) {
                            toggleTask(item)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTask(item)
                            } label: {
                                Label("Видалити", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Theme.Colors.backgroundPrimary)
        .onAppear {
            loadActionItems()
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Завдання")
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text("Автоматично витягнуті з усіх нарад")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            Spacer()
            
            HStack(spacing: Theme.Spacing.md) {
                Button(action: { hideCompleted.toggle() }) {
                    Label(hideCompleted ? "Показати виконані" : "Приховати виконані", 
                          systemImage: hideCompleted ? "eye" : "eye.slash")
                }
                .buttonStyle(.bordered)
                .foregroundStyle(hideCompleted ? Theme.Colors.accentPrimary : Theme.Colors.textSecondary)
                
                Button(action: loadActionItems) {
                    Label("Оновити", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.xl)
        .background(Theme.Colors.backgroundSecondary.opacity(0.5))
    }
    
    private var filteredItems: [ActionItemUI] {
        hideCompleted ? actionItems.filter { !$0.isCompleted } : actionItems
    }
    
    private func deleteTask(_ item: ActionItemUI) {
        guard let meeting = meetings.first(where: { $0.id == item.meetingID }) else { return }
        let repo = MeetingRepository(context: modelContext)
        
        // 1. Delete from database
        if let dbItem = meeting.actionItems.first(where: { $0.id == item.id }) {
            modelContext.delete(dbItem)
            repo.trySave()
        }
        
        // 2. Delete from markdown file
        if let url = meeting.summaryURL {
            do {
                let summary = try String(contentsOf: url, encoding: .utf8)
                let targetCheck = item.isCompleted ? "- [x]" : "- [ ]"
                let newLines = summary
                    .components(separatedBy: CharacterSet.newlines)
                    .filter { !($0.contains(targetCheck) && $0.contains(item.text)) }
                try newLines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
                
            } catch {
                AppLogger.error("Failed to delete task in markdown file", error: error)
            }
        }
        
        // Refresh UI
        loadActionItems()
    }
    
    private func loadActionItems() {
        isLoading = true
        let repo = MeetingRepository(context: modelContext)
        var items: [ActionItemUI] = []
        
        for meeting in meetings {
            // Sync structured entities via repository (uses ParseSummaryUseCase internally)
            try? repo.syncStructuredEntities(for: meeting)
            
            for item in meeting.actionItems {
                items.append(ActionItemUI(
                    id: item.id,
                    text: item.text,
                    meetingTitle: meeting.title,
                    meetingID: meeting.id,
                    isCompleted: item.isCompleted,
                    assignee: item.assignee
                ))
            }
        }
        
        self.actionItems = items
        self.isLoading = false
    }
    
    private func toggleTask(_ item: ActionItemUI) {
        // Find the meeting
        guard let meeting = meetings.first(where: { $0.id == item.meetingID }) else { return }
        
        // 1. Update database
        if let dbItem = meeting.actionItems.first(where: { $0.id == item.id }) {
            dbItem.isCompleted.toggle()
            try? modelContext.save()
        }
        
        // 2. Update markdown file
        if let url = meeting.summaryURL {
            do {
                var summary = try String(contentsOf: url, encoding: .utf8)
                
                let oldCheck = item.isCompleted ? "- [x]" : "- [ ]"
                let newCheck = item.isCompleted ? "- [ ]" : "- [x]"
                
                let lines = summary.components(separatedBy: CharacterSet.newlines)
                var newLines: [String] = []
                var found = false
                
                for line in lines {
                    if !found && line.contains(oldCheck) && line.contains(item.text) {
                        newLines.append(line.replacingOccurrences(of: oldCheck, with: newCheck))
                        found = true
                    } else {
                        newLines.append(line)
                    }
                }
                
                summary = newLines.joined(separator: "\n")
                try summary.write(to: url, atomically: true, encoding: .utf8)
                
            } catch {
                AppLogger.error("Failed to toggle task in markdown file", error: error)
            }
        }
        
        // Refresh UI
        loadActionItems()
    }
    
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "checklist.checked")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("Завдань не знайдено")
                .font(Theme.Typography.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("Додайте списки завдань у резюме нарад")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ActionItemRow: View {
    let item: ActionItemUI
    let onToggle: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? Theme.Colors.success : Theme.Colors.textTertiary)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.text)
                        .font(Theme.Typography.bodyMedium)
                        .foregroundStyle(item.isCompleted ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                        .strikethrough(item.isCompleted)
                    
                    if let assignee = item.assignee {
                        Text(assignee)
                            .font(Theme.Typography.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.accentPrimary.opacity(0.2))
                            .foregroundStyle(Theme.Colors.accentPrimary)
                            .clipShape(Capsule())
                    }
                }
                
                Text(item.meetingTitle)
                    .font(Theme.Typography.monoCaption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.lg)
    }
}
