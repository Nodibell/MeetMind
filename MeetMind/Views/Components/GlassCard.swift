//
//  GlassCard.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI

/// Reusable glassmorphism container with subtle border and shadow
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.CornerRadius.lg
    var padding: CGFloat = Theme.Spacing.lg
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        content()
            .padding(padding)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}

/// Solid card variant (no glassmorphism)
struct SolidCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.CornerRadius.lg
    var padding: CGFloat = Theme.Spacing.lg
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        content()
            .padding(padding)
            .background(Theme.Colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.Colors.borderSubtle, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
    }
}

#Preview {
    VStack(spacing: 20) {
        GlassCard {
            VStack(alignment: .leading) {
                Text("Glass Card")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("With glassmorphism effect")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        
        SolidCard {
            VStack(alignment: .leading) {
                Text("Solid Card")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Without glassmorphism")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    .padding()
    .background(Theme.Colors.backgroundPrimary)
}
