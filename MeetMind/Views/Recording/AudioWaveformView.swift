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
                    let barHeight = max(level * maxBarHeight, 4)
                    
                    let x = CGFloat(i) * (barWidth + barSpacing)
                    let y = centerY - barHeight / 2
                    
                    let rectPath = RoundedRectangle(cornerRadius: barWidth / 2)
                        .path(in: CGRect(x: x, y: y, width: barWidth, height: barHeight))
                    
                    let opacity = isActive ? (0.5 + level * 0.5) : 0.2
                    let baseColor = isActive
                        ? interpolateColor(level: level)
                        : Theme.Colors.waveformInactive
                    
                    // 1. Draw Glow (Outer)
                    if isActive && level > 0.1 {
                        var glowContext = context
                        glowContext.addFilter(.blur(radius: 3))
                        glowContext.fill(rectPath, with: .color(baseColor.opacity(0.3 * level)))
                    }
                    
                    // 2. Draw Bar with Gradient
                    let gradient = Gradient(colors: [
                        baseColor.opacity(opacity),
                        baseColor.opacity(opacity * 0.7)
                    ])
                    context.fill(rectPath, with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: x, y: y),
                        endPoint: CGPoint(x: x, y: y + barHeight)
                    ))
                }
            }
        }
    }
    
    private func interpolateColor(level: CGFloat) -> Color {
        // Smooth transition from Blue to Purple to Pink
        if level > 0.8 {
            return Color(red: 0.9, green: 0.3, blue: 0.8) // Pink/Magenta
        } else if level > 0.4 {
            return Theme.Colors.accentPrimary // Bright Blue
        } else {
            return Theme.Colors.accentSecondary.opacity(0.8) // Teal/Cyan
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
