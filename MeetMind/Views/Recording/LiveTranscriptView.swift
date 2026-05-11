//
//  LiveTranscriptView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI

/// Auto-scrolling live transcript panel with timestamp badges
struct LiveTranscriptView: View {
    let segments: [MeetingTranscriptSegment]
    var isLive: Bool = true
    
    @State private var scrollProxy: ScrollViewProxy?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: isLive ? "waveform" : "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(isLive ? Theme.Colors.accentPrimary : Theme.Colors.textTertiary)
                
                Text(isLive ? "Живий транскрипт" : "Транскрипт")
                    .font(Theme.Typography.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                Spacer()
                
                if !segments.isEmpty {
                    Text("\(segments.count) сегментів")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            
            Divider()
                .background(Theme.Colors.borderSubtle)
            
            // Transcript content
            if segments.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                                MeetingTranscriptSegmentRow(segment: segment, isLatest: index == segments.count - 1 && isLive)
                                    .id(segment.id)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                                        removal: .opacity
                                    ))
                            }
                        }
                        .padding(Theme.Spacing.md)
                    }
                    .onChange(of: segments.count) { _, _ in
                        if isLive, let lastID = segments.last?.id {
                            withAnimation(Theme.Animation.standard) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .background(Theme.Colors.backgroundSecondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderSubtle, lineWidth: 0.5)
        )
    }
    
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            if isLive {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(Theme.Colors.textTertiary)
                
                Text("Очікування на мовлення...")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            } else {
                Image(systemName: "text.bubble")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.Colors.textTertiary)
                
                Text("Транскрипт буде тут після запису")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxl)
    }
}

// MARK: - Segment Row

struct MeetingTranscriptSegmentRow: View {
    let segment: MeetingTranscriptSegment
    var isLatest: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            // Timestamp badge
            Text(segment.startTime.formattedTimestamp)
                .font(Theme.Typography.monoCaption)
                .foregroundStyle(Theme.Colors.accentSecondary)
                .frame(width: 42, alignment: .trailing)
                .padding(.top, 2)
            
            // Separator line
            Rectangle()
                .fill(Theme.Colors.borderSubtle)
                .frame(width: 1)
                .padding(.vertical, 2)
            
            // Text
            if isLatest {
                TypewriterTextView(fullText: segment.text, isStreaming: true, delayMilliseconds: 15)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(segment.text)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .opacity(isLatest ? 1.0 : 0.85)
    }
}

#Preview {
    LiveTranscriptView(
        segments: [
            MeetingTranscriptSegment(startTime: 0, endTime: 5, text: "Привіт, давайте почнемо нараду."),
            MeetingTranscriptSegment(startTime: 5, endTime: 12, text: "Сьогодні обговоримо архітектуру нового проєкту."),
            MeetingTranscriptSegment(startTime: 12, endTime: 20, text: "Пропоную використовувати SwiftUI для інтерфейсу."),
        ],
        isLive: true
    )
    .frame(width: 400, height: 300)
    .background(Theme.Colors.backgroundPrimary)
}
