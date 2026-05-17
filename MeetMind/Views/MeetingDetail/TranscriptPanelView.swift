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
    var speakerMetadata: [SpeakerMetadata] = []
    var isLoading: Bool = false
    var translatedText: String? = nil
    var translatedSegments: [UUID: String] = [:]
    var isTranslating: Bool = false
    var onClearTranslation: (() -> Void)? = nil
    var onUpdateSpeakerName: ((String, String) -> Void)? = nil
    var onUpdateSpeakerColor: ((String, Color) -> Void)? = nil
    
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
            } else if let translatedText = translatedText, translatedSegments.isEmpty {
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
                VStack(spacing: 0) {
                    if !translatedSegments.isEmpty {
                        HStack {
                            Label("Переклад активний (таймстампи збережено)", systemImage: "globe")
                                .font(Theme.Typography.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.accentPrimary)
                            
                            Spacer()
                            
                            Button(action: { onClearTranslation?() }) {
                                HStack(spacing: 4) {
                                    Text("Показати оригінал")
                                        .font(Theme.Typography.caption)
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentPrimary.opacity(0.08))
                    }
                    
                    transcriptContent
                }
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
                            translatedText: translatedSegments[segment.id],
                            isHighlighted: segment.id == highlightedSegmentID,
                            searchText: searchText,
                            metadata: speakerMetadata.first(where: { $0.id == segment.speakerID }),
                            onUpdateName: { newName in
                                if let speakerID = segment.speakerID {
                                    onUpdateSpeakerName?(speakerID, newName)
                                }
                            },
                            onUpdateColor: { newColor in
                                if let speakerID = segment.speakerID {
                                    onUpdateSpeakerColor?(speakerID, newColor)
                                }
                            }
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
    var translatedText: String? = nil
    var isHighlighted: Bool = false
    var searchText: String = ""
    var metadata: SpeakerMetadata?
    var onUpdateName: (String) -> Void
    var onUpdateColor: (Color) -> Void
    
    @State private var isEditingSpeaker = false
    @State private var newSpeakerName = ""
    
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
                .fill(isHighlighted ? (metadata?.color ?? Theme.Colors.accentPrimary) : Theme.Colors.borderSubtle)
                .frame(width: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                if segment.speakerID != nil {
                    Button {
                        newSpeakerName = metadata?.name ?? ""
                        isEditingSpeaker = true
                    } label: {
                        Text(metadata?.displayName ?? segment.speakerName ?? segment.speakerID ?? String(localized: "Невідомий"))
                            .font(Theme.Typography.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(metadata?.color ?? Theme.Colors.accentPrimary)
                            .padding(.bottom, 2)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isEditingSpeaker) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Налаштування спікера")
                                .font(.headline)
                            
                            TextField("Ім’я", text: $newSpeakerName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    onUpdateName(newSpeakerName)
                                    isEditingSpeaker = false
                                }
                            
                            ColorPicker("Колір", selection: Binding(
                                get: { metadata?.color ?? Theme.Colors.accentPrimary },
                                set: { onUpdateColor($0) }
                            ))
                            
                            HStack {
                                Button("Скинути") {
                                    onUpdateName("")
                                    isEditingSpeaker = false
                                }
                                .buttonStyle(.link)
                                
                                Spacer()
                                
                                Button("Зберегти") {
                                    onUpdateName(newSpeakerName)
                                    isEditingSpeaker = false
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding()
                        .frame(width: 250)
                    }
                }
                
                Text(translatedText ?? segment.text)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(isHighlighted ? (metadata?.color.opacity(0.08) ?? Theme.Colors.accentPrimary.opacity(0.08)) : .clear)
    }
}


#Preview {
    TranscriptPanelView(segments: [MeetingTranscriptSegment(startTime: TimeInterval(1095), endTime: TimeInterval(1100), text: "Hello!, This is the showcase!")], searchText: .constant("Searching"))
}
