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
    var isTranscribing: Bool = false
    var transcriptionProgress: Double = 0.0
    var transcriptionStatusText: String = ""
    var audioURL: URL? = nil
    var initialHighlightedSegmentID: UUID? = nil
    var onClearTranslation: (() -> Void)? = nil
    var onUpdateSpeakerName: ((String, String) -> Void)? = nil
    var onUpdateSpeakerColor: ((String, Color) -> Void)? = nil
    var onRetranscribe: (() -> Void)? = nil
    
    @State private var highlightedSegmentID: UUID?
    @State private var activeSegmentID: UUID?
    
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
            if isTranscribing {
                transcribingProgressState
            } else if isLoading {
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
                    
                    if let audioURL {
                        AudioPlayerBar(audioURL: audioURL)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.bottom, Theme.Spacing.md)
                            .padding(.top, Theme.Spacing.xs)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .background(Theme.Colors.backgroundSecondary.opacity(0.3))
        .onAppear {
            if let initialHighlightedSegmentID {
                highlightedSegmentID = initialHighlightedSegmentID
            }
            let time = AudioPlaybackManager.shared.currentTime
            activeSegmentID = segments.first(where: { time >= $0.startTime && time <= $0.endTime })?.id
        }
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
                            isHighlighted: segment.id == highlightedSegmentID || segment.id == activeSegmentID,
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
                            if let audioURL {
                                AudioPlaybackManager.shared.load(url: audioURL)
                                AudioPlaybackManager.shared.seek(to: segment.startTime)
                                AudioPlaybackManager.shared.play()
                            }
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
            .onAppear {
                if let initialHighlightedSegmentID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(initialHighlightedSegmentID, anchor: .center)
                        }
                    }
                }
            }
            .onChange(of: highlightedSegmentID) { _, newID in
                if let newID {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
            .onChange(of: activeSegmentID) { _, newID in
                if let newID, AudioPlaybackManager.shared.isPlaying {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
            .onChange(of: AudioPlaybackManager.shared.currentTime) { _, newTime in
                let newActiveID = segments.first(where: { newTime >= $0.startTime && newTime <= $0.endTime })?.id
                if activeSegmentID != newActiveID {
                    activeSegmentID = newActiveID
                }
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
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            
            Image(systemName: "doc.text")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Colors.textTertiary)
            
            Text("Транскрипт відсутній")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textTertiary)
            
            if let onRetranscribe {
                Button(action: onRetranscribe) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.badge.plus")
                        Text("Транскрибувати файл")
                    }
                    .font(Theme.Typography.captionMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Gradients.accent)
                    .clipShape(Capsule())
                    .shadow(color: Theme.Colors.accentPrimary.opacity(0.2), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var transcribingProgressState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accentPrimary.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.Gradients.accent)
            }
            
            VStack(spacing: Theme.Spacing.xs) {
                Text(transcriptionStatusText.isEmpty ? String(localized: "Оновлення транскрипту...") : transcriptionStatusText)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                ProgressView(value: transcriptionProgress)
                    .progressViewStyle(.linear)
                    .tint(Theme.Colors.accentPrimary)
                    .frame(width: 200)
                
                Text(String(format: "%.0f%%", transcriptionProgress * 100))
                    .font(Theme.Typography.monoCaption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    TranscriptPanelView(segments: [MeetingTranscriptSegment(startTime: TimeInterval(1095), endTime: TimeInterval(1100), text: "Hello!, This is the showcase!")], searchText: .constant("Searching"))
}
