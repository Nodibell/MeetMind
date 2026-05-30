//
//  TranscriptDetailRow.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 29.05.2026.
//

import SwiftUI

/// A row component representing a single transcript segment with timestamp, speaker profile,
/// and highlighted search results.
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
            
            // Vertical speaker color line
            Rectangle()
                .fill(isHighlighted ? (metadata?.color ?? Theme.Colors.accentPrimary) : Theme.Colors.borderSubtle)
                .frame(width: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))
            
            // Text and Speaker
            VStack(alignment: .leading, spacing: 4) {
                if segment.speakerID != nil {
                    HStack(spacing: Theme.Spacing.sm) {
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
                        .help("Натисніть, щоб перейменувати спікера")
                        
                        if let suggestedName = segment.suggestedSpeakerName, metadata?.name == nil {
                            Button {
                                onUpdateName(suggestedName)
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "hand.thumbsup.fill")
                                        .font(.system(size: 9))
                                    Text("На нашу думку, це \(suggestedName)?")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .padding(.horizontal, Theme.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(Theme.Colors.accentPrimary.opacity(0.1))
                                .foregroundStyle(Theme.Colors.accentPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .help("Натисніть, щоб підтвердити пропозицію")
                        }
                    }
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
                
                Text(highlightedText(in: translatedText ?? segment.text, matching: searchText))
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
    
    // MARK: - Search Text Highlighting
    
    private func highlightedText(in fullText: String, matching query: String) -> AttributedString {
        var attributed = AttributedString(fullText)
        attributed.foregroundColor = Theme.Colors.textPrimary
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return attributed }
        
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let range = attributed[searchStart...].range(of: trimmedQuery, options: .caseInsensitive) {
            attributed[range].backgroundColor = Color.yellow.opacity(0.35)
            attributed[range].foregroundColor = Theme.Colors.textPrimary
            // Highlight matching part
            searchStart = range.upperBound
        }
        
        return attributed
    }
}
