import SwiftUI
import SwiftData

struct ActionItem: Identifiable {
    let id = UUID()
    let text: String
    let meetingTitle: String
    let meetingID: UUID
    var isCompleted: Bool = false
}

struct ActionItemsView: View {
    @Query private var meetings: [Meeting]
    @State private var actionItems: [ActionItem] = []
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            if isLoading {
                ProgressView("Пошук завдань...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if actionItems.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(actionItems) { item in
                        ActionItemRow(item: item)
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
            
            Button(action: loadActionItems) {
                Label("Оновити", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.xl)
        .background(Theme.Colors.backgroundSecondary.opacity(0.5))
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
    
    private func loadActionItems() {
        isLoading = true
        var items: [ActionItem] = []
        
        for meeting in meetings {
            if let summaryPath = meeting.summaryPath,
               let data = try? Data(contentsOf: URL(fileURLWithPath: summaryPath)),
               let summary = String(data: data, encoding: .utf8) {
                
                let lines = summary.components(separatedBy: CharacterSet.newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
                    // Match markdown checkboxes: - [ ] or - [x]
                    if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") {
                        let text = trimmed.replacingOccurrences(of: "- [ ]", with: "")
                                          .replacingOccurrences(of: "- [x]", with: "")
                                          .trimmingCharacters(in: CharacterSet.whitespaces)
                        if !text.isEmpty {
                            items.append(ActionItem(
                                text: text,
                                meetingTitle: meeting.title,
                                meetingID: meeting.id,
                                isCompleted: trimmed.hasPrefix("- [x]")
                            ))
                        }
                    }
                }
            }
        }
        
        self.actionItems = items
        self.isLoading = false
    }
}

struct ActionItemRow: View {
    let item: ActionItem
    
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isCompleted ? Theme.Colors.success : Theme.Colors.textTertiary)
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundStyle(item.isCompleted ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                    .strikethrough(item.isCompleted)
                
                Text(item.meetingTitle)
                    .font(Theme.Typography.monoCaption)
                    .foregroundStyle(Theme.Colors.accentSecondary)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.lg)
    }
}
