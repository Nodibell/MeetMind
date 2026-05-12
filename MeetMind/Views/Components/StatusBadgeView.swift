//
//  StatusBadgeView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI

/// Animated recording indicator — pulsing red dot with glow
struct StatusBadgeView: View {
    let status: MeetingStatus
    @State private var isPulsing = false
    
    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: glowColor, radius: isPulsing ? 8 : 3)
                .scaleEffect(isPulsing ? 1.15 : 1.0)
                .animation(isAnimated ? Theme.Animation.pulse : .default, value: isPulsing)
            
            Text(LocalizedStringKey(status.displayName))
                .font(Theme.Typography.captionMedium)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(statusColor.opacity(0.12))
        .clipShape(Capsule())
        .onAppear {
            if isAnimated {
                isPulsing = true
            }
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .recording: return Theme.Colors.recording
        case .transcribing: return Theme.Colors.processing
        case .summarizing: return Theme.Colors.accentPrimary
        case .complete: return Theme.Colors.success
        case .error: return Theme.Colors.error
        }
    }
    
    private var glowColor: Color {
        statusColor.opacity(0.5)
    }
    
    private var isAnimated: Bool {
        status == .recording || status == .transcribing || status == .summarizing
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusBadgeView(status: .recording)
        StatusBadgeView(status: .transcribing)
        StatusBadgeView(status: .summarizing)
        StatusBadgeView(status: .complete)
        StatusBadgeView(status: .error)
    }
    .padding()
    .background(Theme.Colors.backgroundPrimary)
}
