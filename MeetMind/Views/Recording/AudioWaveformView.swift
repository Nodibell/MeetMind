//
//  AudioWaveformView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI

/// Real-time audio waveform visualization using Canvas
struct AudioWaveformView: View {
    let levels: [Float]
    var isActive: Bool = true
    var barCount: Int = 60
    var barSpacing: CGFloat = 2
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let totalBars = min(barCount, levels.count)
                guard totalBars > 0 else { return }
                
                let availableWidth = size.width - CGFloat(totalBars - 1) * barSpacing
                let barWidth = max(availableWidth / CGFloat(totalBars), 2)
                let centerY = size.height / 2
                let maxBarHeight = size.height * 0.85
                
                for i in 0..<totalBars {
                    let levelIndex = levels.count - totalBars + i
                    guard levelIndex >= 0, levelIndex < levels.count else { continue }
                    
                    let level = CGFloat(levels[levelIndex])
                    let barHeight = max(level * maxBarHeight, 3)
                    
                    let x = CGFloat(i) * (barWidth + barSpacing)
                    let y = centerY - barHeight / 2
                    
                    let rect = RoundedRectangle(cornerRadius: barWidth / 2)
                        .path(in: CGRect(x: x, y: y, width: barWidth, height: barHeight))
                    
                    // Gradient based on level
                    let opacity = isActive ? (0.4 + level * 0.6) : 0.2
                    let color = isActive
                        ? interpolateColor(level: level)
                        : Theme.Colors.waveformInactive
                    
                    context.fill(rect, with: .color(color.opacity(opacity)))
                }
            }
        }
    }
    
    private func interpolateColor(level: CGFloat) -> Color {
        if level > 0.7 {
            return Theme.Colors.accentTertiary
        } else if level > 0.3 {
            return Theme.Colors.accentPrimary
        } else {
            return Theme.Colors.accentSecondary
        }
    }
}

/// Idle waveform animation (breathing bars when not recording)
struct IdleWaveformView: View {
    @State private var phase: Double = 0
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let barCount = 40
                let barSpacing: CGFloat = 3
                let availableWidth = size.width - CGFloat(barCount - 1) * barSpacing
                let barWidth = max(availableWidth / CGFloat(barCount), 2)
                let centerY = size.height / 2
                
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                for i in 0..<barCount {
                    let normalizedPos = Double(i) / Double(barCount)
                    let wave = sin(normalizedPos * .pi * 3 + time * 2) * 0.3 + 0.15
                    let barHeight = max(CGFloat(wave) * size.height, 3)
                    
                    let x = CGFloat(i) * (barWidth + barSpacing)
                    let y = centerY - barHeight / 2
                    
                    let rect = RoundedRectangle(cornerRadius: barWidth / 2)
                        .path(in: CGRect(x: x, y: y, width: barWidth, height: barHeight))
                    
                    let color = Theme.Colors.accentPrimary.opacity(0.2 + wave * 0.3)
                    context.fill(rect, with: .color(color))
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Active Waveform")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
        
        AudioWaveformView(
            levels: (0..<100).map { _ in Float.random(in: 0...1) },
            isActive: true
        )
        .frame(height: 80)
        
        Text("Idle Waveform")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
        
        IdleWaveformView()
            .frame(height: 80)
    }
    .padding()
    .background(Theme.Colors.backgroundPrimary)
}
