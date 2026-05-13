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
        GeometryReader { geo in
            let totalBars = min(barCount, levels.count)
            let availableWidth = geo.size.width - CGFloat(max(0, totalBars - 1)) * barSpacing
            let barWidth = max(availableWidth / CGFloat(max(1, totalBars)), 2)
            let centerY = geo.size.height / 2
            let maxBarHeight = geo.size.height * 0.85
            
            HStack(spacing: barSpacing) {
                ForEach(0..<totalBars, id: \.self) { i in
                    let levelIndex = levels.count - totalBars + i
                    let level = (levelIndex >= 0 && levelIndex < levels.count) ? CGFloat(levels[levelIndex]) : 0
                    let barHeight = max(level * maxBarHeight, 4)
                    let opacity = isActive ? (0.5 + level * 0.5) : 0.2
                    let baseColor = isActive ? interpolateColor(level: level) : Theme.Colors.waveformInactive
                    
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(LinearGradient(
                            colors: [baseColor.opacity(opacity), baseColor.opacity(opacity * 0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(width: barWidth, height: barHeight)
                        .shadow(color: isActive && level > 0.1 ? baseColor.opacity(0.3 * level) : .clear, radius: 3)
                        .animation(.spring(response: 0.15, dampingFraction: 0.8, blendDuration: 0.1), value: barHeight)
                        .animation(.spring(response: 0.15, dampingFraction: 0.8, blendDuration: 0.1), value: baseColor)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
        TimelineView(.animation(minimumInterval: 1.0 / Double(AppSettings.shared.waveformFPS))) { timeline in
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
