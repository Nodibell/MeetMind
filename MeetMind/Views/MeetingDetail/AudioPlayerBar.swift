//
//  AudioPlayerBar.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 29.05.2026.
//

import SwiftUI

/// Premium audio playback control bar for playing meeting recordings.
struct AudioPlayerBar: View {
    let audioURL: URL
    @State private var playbackManager = AudioPlaybackManager.shared
    @State private var isScrubbing = false
    @State private var dragProgress: Double = 0
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Play/Pause Button
            Button(action: {
                playbackManager.load(url: audioURL)
                if playbackManager.isPlaying {
                    playbackManager.pause()
                } else {
                    playbackManager.play()
                }
            }) {
                Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Theme.Colors.accentPrimary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            // Current Time
            Text(playbackManager.currentTime.formattedTimestamp)
                .font(Theme.Typography.monoCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 40, alignment: .trailing)
            
            // Timeline scrubber track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.Colors.borderSubtle.opacity(0.4))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.Colors.accentPrimary)
                        .frame(width: geo.size.width * (isScrubbing ? dragProgress : playbackManager.progress), height: 6)
                    
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .shadow(radius: 1)
                        .offset(x: (geo.size.width - 12) * (isScrubbing ? dragProgress : playbackManager.progress))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            let ratio = max(0, min(1, value.location.x / geo.size.width))
                            dragProgress = ratio
                        }
                        .onEnded { value in
                            let ratio = max(0, min(1, value.location.x / geo.size.width))
                            playbackManager.load(url: audioURL)
                            playbackManager.seek(to: ratio * playbackManager.duration)
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 20)
            
            // Duration Time
            Text(playbackManager.duration.formattedTimestamp)
                .font(Theme.Typography.monoCaption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: 40, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surfacePrimary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.CornerRadius.md).stroke(Theme.Colors.border.opacity(0.1), lineWidth: 0.5))
        .onAppear {
            playbackManager.load(url: audioURL)
        }
    }
}
