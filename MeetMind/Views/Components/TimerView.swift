//
//  TimerView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI

/// Elapsed time display with monospaced font
struct TimerView: View {
    let elapsedTime: TimeInterval
    var style: TimerStyle = .large
    
    enum TimerStyle {
        case large, medium, compact
    }
    
    var body: some View {
        Text(elapsedTime.formattedDuration)
            .font(timerFont)
            .foregroundStyle(Theme.Colors.textPrimary)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(Theme.Animation.fast, value: elapsedTime)
    }
    
    private var timerFont: Font {
        switch style {
        case .large: return Theme.Typography.monoLarge
        case .medium: return Theme.Typography.monoMedium
        case .compact: return Theme.Typography.monoSmall
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        TimerView(elapsedTime: 3661, style: .large)
        TimerView(elapsedTime: 125, style: .medium)
        TimerView(elapsedTime: 42, style: .compact)
    }
    .padding()
    .background(Theme.Colors.backgroundPrimary)
}
