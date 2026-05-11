//
//  MeetingRowView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI

/// Individual meeting row in the sidebar list
struct MeetingRowView: View {
    let meeting: Meeting
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // Title row
            HStack(spacing: Theme.Spacing.sm) {
                Text(meeting.title)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                
                Spacer()
                
                statusDot
            }
            
            // Metadata row
            HStack(spacing: Theme.Spacing.md) {
                Text(meeting.date.relativeFormatted)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.textTertiary)
                
                if meeting.duration > 0 {
                    Text(meeting.displayDuration)
                        .font(Theme.Typography.monoCaption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                Spacer()
                
                if meeting.isExportedToObsidian {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.success.opacity(0.7))
                        .help("Експортовано в Obsidian")
                }
            }
            
            // Tags
            if !meeting.tags.isEmpty {
                HStack(spacing: Theme.Spacing.xxs) {
                    ForEach(meeting.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .padding(.horizontal, Theme.Spacing.xs)
                            .padding(.vertical, 1)
                            .background(tag.tagColor.opacity(0.3))
                            .clipShape(Capsule())
                    }
                    
                    if meeting.tags.count > 3 {
                        Text("+\(meeting.tags.count - 3)")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(isHovered ? Theme.Colors.surfaceHover.opacity(0.3) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
        .onHover { isHovered = $0 }
    }
    
    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }
    
    private var statusColor: Color {
        switch meeting.status {
        case .recording: return Theme.Colors.recording
        case .transcribing, .summarizing: return Theme.Colors.processing
        case .complete: return Theme.Colors.success
        case .error: return Theme.Colors.error
        }
    }
}
