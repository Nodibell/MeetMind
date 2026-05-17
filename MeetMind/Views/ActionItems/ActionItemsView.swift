import SwiftUI
import SwiftData

struct ActionItem: Identifiable {
    let id: UUID // Use the meeting ID + text hash or similar to identify unique tasks if needed, but for now meetingID + text is enough
    var text: String
    let meetingTitle: String
    let meetingID: UUID
    var isCompleted: Bool
    var assignee: String?
}

struct ActionItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var meetings: [Meeting]
    @State private var actionItems: [ActionItem] = []
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
    
    private var filteredItems: [ActionItem] {
        if hideCompleted {
            return actionItems.filter { !$0.isCompleted }
        }
        return actionItems
    }
    
    private func deleteTask(_ item: ActionItem) {
        // Find the meeting
        guard let meeting = meetings.first(where: { $0.id == item.meetingID }),
              let url = meeting.summaryURL else { return }
        
        do {
            let summary = try String(contentsOf: url, encoding: .utf8)
            
            let lines = summary.components(separatedBy: CharacterSet.newlines)
            var newLines: [String] = []
            var found = false
            
            let targetCheck = item.isCompleted ? "- [x]" : "- [ ]"
            
            for line in lines {
                if !found && line.contains(targetCheck) && line.contains(item.text) {
                    found = true
                    // Skip this line
                } else {
                    newLines.append(line)
                }
            }
            
            let newSummary = newLines.joined(separator: "\n")
            try newSummary.write(to: url, atomically: true, encoding: .utf8)
            
            // Refresh UI
            loadActionItems()
            
        } catch {
            AppLogger.error("Failed to delete task", error: error)
        }
    }
    
    private func loadActionItems() {
        isLoading = true
        var items: [ActionItem] = []
        
        for meeting in meetings {
            if let url = meeting.summaryURL,
               let summary = try? String(contentsOf: url, encoding: .utf8) {
                
                let lines = summary.components(separatedBy: CharacterSet.newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
                    if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") {
                        let isDone = trimmed.hasPrefix("- [x]")
                        var text = trimmed.replacingOccurrences(of: "- [ ]", with: "")
                                          .replacingOccurrences(of: "- [x]", with: "")
                                          .trimmingCharacters(in: CharacterSet.whitespaces)
                        
                        // Extract assignee (e.g. "(Name)" or "@Name" at the end)
                        var assignee: String? = nil
                        let regexAssignee = try? NSRegularExpression(pattern: #"\(([^)]+)\)$|@(\w+)$"#, options: [])
                        if let match = regexAssignee?.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
                            if let range = Range(match.range(at: 1), in: text) ?? Range(match.range(at: 2), in: text) {
                                assignee = String(text[range])
                                text = text.replacingCharacters(in: Range(match.range, in: text)!, with: "").trimmingCharacters(in: CharacterSet.whitespaces)
                            }
                        }
                        
                        if !text.isEmpty {
                            items.append(ActionItem(
                                id: UUID(),
                                text: text,
                                meetingTitle: meeting.title,
                                meetingID: meeting.id,
                                isCompleted: isDone,
                                assignee: assignee
                            ))
                        }
                    }
                }
            }
        }
        
        self.actionItems = items
        self.isLoading = false
    }
    
    private func toggleTask(_ item: ActionItem) {
        // Find the meeting
        guard let meeting = meetings.first(where: { $0.id == item.meetingID }),
              let url = meeting.summaryURL else { return }
        
        do {
            var summary = try String(contentsOf: url, encoding: .utf8)
            
            // Very simple replacement logic: find the line that contains this task and toggle checkbox
            let oldCheck = item.isCompleted ? "- [x]" : "- [ ]"
            let newCheck = item.isCompleted ? "- [ ]" : "- [x]"
            
            // We need to be careful with matching to avoid false positives. 
            // We search for the specific line.
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
            
            // Refresh UI
            loadActionItems()
            
        } catch {
            AppLogger.error("Failed to toggle task", error: error)
        }
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
    let item: ActionItem
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
