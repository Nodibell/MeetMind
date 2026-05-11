//
//  TranscriptPanelView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI

/// Full transcript panel with timestamps, search, and text selection
struct TranscriptPanelView: View {
    let segments: [MeetingTranscriptSegment]
    @Binding var searchText: String
    var isLoading: Bool = false
    var translatedText: String? = nil
    var isTranslating: Bool = false
    var onClearTranslation: (() -> Void)? = nil
    
    @State private var highlightedSegmentID: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Транскрипт", systemImage: "text.quote")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: true, vertical: false)
                
                Spacer()
                
                // Search
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    
                    TextField("Пошук...", text: $searchText)
                        .font(Theme.Typography.caption)
                        .textFieldStyle(.plain)
                        .frame(width: 120)
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(Theme.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            
            Divider()
                .background(Theme.Colors.borderSubtle)
            
            // Content
            if isLoading {
                loadingState
            } else if isTranslating {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Перекладаємо...")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let translatedText = translatedText {
                ScrollView {
                    VStack(alignment: .leading) {
                        HStack {
                            Label("Переклад", systemImage: "globe")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.accentPrimary)
                            Spacer()
                            Button(action: { onClearTranslation?() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, Theme.Spacing.sm)
                        
                        Text(translatedText)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .textSelection(.enabled)
                    }
                    .padding(Theme.Spacing.lg)
                }
            } else if segments.isEmpty {
                emptyState
            } else {
                transcriptContent
            }
        }
        .background(Theme.Colors.backgroundSecondary.opacity(0.3))
    }
    
    // MARK: - Content
    
    private var transcriptContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(segments) { segment in
                        TranscriptDetailRow(
                            segment: segment,
                            isHighlighted: segment.id == highlightedSegmentID,
                            searchText: searchText
                        )
                        .id(segment.id)
                        .onTapGesture {
                            withAnimation(Theme.Animation.fast) {
                                highlightedSegmentID = segment.id
                            }
                        }
                        
                        Divider()
                            .background(Theme.Colors.borderSubtle.opacity(0.5))
                            .padding(.leading, 60)
                    }
                }
                .padding(.vertical, Theme.Spacing.sm)
            }
        }
    }
    
    private var loadingState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.accentPrimary)
            Text("Завантаження транскрипту...")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("Транскрипт відсутній")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Detail Row

struct TranscriptDetailRow: View {
    let segment: MeetingTranscriptSegment
    var isHighlighted: Bool = false
    var searchText: String = ""
    
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            // Timestamp
            VStack(alignment: .trailing, spacing: 2) {
                Text(segment.startTime.formattedTimestamp)
                    .font(Theme.Typography.monoCaption)
                    .foregroundStyle(Theme.Colors.accentSecondary)
                
                Text(segment.endTime.formattedTimestamp)
                    .font(Theme.Typography.monoCaption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .frame(width: 45, alignment: .trailing)
            .fixedSize(horizontal: true, vertical: false)
            
            // Vertical line
            Rectangle()
                .fill(isHighlighted ? Theme.Colors.accentPrimary : Theme.Colors.borderSubtle)
                .frame(width: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                if let speaker = segment.speakerID {
                    Text(speaker.replacingOccurrences(of: "Speaker ", with: "Диктор "))
                        .font(Theme.Typography.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Colors.accentPrimary)
                        .padding(.bottom, 2)
                }
                
                Text(segment.text)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(isHighlighted ? Theme.Colors.accentPrimary.opacity(0.08) : .clear)
    }
}
