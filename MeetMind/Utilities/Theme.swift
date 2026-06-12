//
//  Theme.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI

enum Theme {
    // MARK: - Color Palette
    enum Colors {
        private static func dynamicColor(
            light lightNS: NSColor,
            dark darkNS: NSColor
        ) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                if appearance.name == .darkAqua || appearance.name == .vibrantDark {
                    return darkNS
                } else {
                    return lightNS
                }
            })
        }

        // Primary backgrounds
        static let backgroundPrimary = dynamicColor(
            light: NSColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1.0),
            dark: NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
        )
        static let backgroundSecondary = dynamicColor(
            light: NSColor(red: 0.98, green: 0.98, blue: 1.0, alpha: 1.0),
            dark: NSColor(red: 0.11, green: 0.11, blue: 0.16, alpha: 1.0)
        )
        static let backgroundTertiary = dynamicColor(
            light: NSColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1.0),
            dark: NSColor(red: 0.14, green: 0.14, blue: 0.20, alpha: 1.0)
        )
        
        // Surface (cards, panels)
        static let surfacePrimary = dynamicColor(
            light: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
            dark: NSColor(red: 0.16, green: 0.16, blue: 0.22, alpha: 1.0)
        )
        static let surfaceSecondary = dynamicColor(
            light: NSColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0),
            dark: NSColor(red: 0.20, green: 0.20, blue: 0.27, alpha: 1.0)
        )
        static let surfaceHover = dynamicColor(
            light: NSColor(red: 0.92, green: 0.92, blue: 0.95, alpha: 1.0),
            dark: NSColor(red: 0.22, green: 0.22, blue: 0.30, alpha: 1.0)
        )
        
        // Accent gradient
        static let accentPrimary = dynamicColor(
            light: NSColor(red: 0.35, green: 0.30, blue: 0.85, alpha: 1.0),
            dark: NSColor(red: 0.45, green: 0.40, blue: 0.95, alpha: 1.0)
        )
        static let accentSecondary = dynamicColor(
            light: NSColor(red: 0.25, green: 0.45, blue: 0.90, alpha: 1.0),
            dark: NSColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1.0)
        )
        static let accentTertiary = dynamicColor(
            light: NSColor(red: 0.45, green: 0.25, blue: 0.80, alpha: 1.0),
            dark: NSColor(red: 0.55, green: 0.35, blue: 0.90, alpha: 1.0)
        )
        
        // Status colors
        static let recording = dynamicColor(
            light: NSColor(red: 0.95, green: 0.20, blue: 0.30, alpha: 1.0),
            dark: NSColor(red: 1.0, green: 0.27, blue: 0.35, alpha: 1.0)
        )
        static let recordingGlow = dynamicColor(
            light: NSColor(red: 0.95, green: 0.20, blue: 0.30, alpha: 0.3),
            dark: NSColor(red: 1.0, green: 0.27, blue: 0.35, alpha: 0.4)
        )
        static let success = dynamicColor(
            light: NSColor(red: 0.15, green: 0.75, blue: 0.45, alpha: 1.0),
            dark: NSColor(red: 0.20, green: 0.85, blue: 0.55, alpha: 1.0)
        )
        static let warning = dynamicColor(
            light: NSColor(red: 0.90, green: 0.65, blue: 0.15, alpha: 1.0),
            dark: NSColor(red: 1.0, green: 0.75, blue: 0.25, alpha: 1.0)
        )
        static let error = dynamicColor(
            light: NSColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1.0),
            dark: NSColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
        )
        static let processing = dynamicColor(
            light: NSColor(red: 0.30, green: 0.60, blue: 0.90, alpha: 1.0),
            dark: NSColor(red: 0.40, green: 0.70, blue: 1.0, alpha: 1.0)
        )
        
        // Text
        static let textPrimary = dynamicColor(
            light: NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0),
            dark: NSColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)
        )
        static let textSecondary = dynamicColor(
            light: NSColor(red: 0.40, green: 0.40, blue: 0.48, alpha: 1.0),
            dark: NSColor(red: 0.65, green: 0.65, blue: 0.72, alpha: 1.0)
        )
        static let textTertiary = dynamicColor(
            light: NSColor(red: 0.60, green: 0.60, blue: 0.68, alpha: 1.0),
            dark: NSColor(red: 0.45, green: 0.45, blue: 0.52, alpha: 1.0)
        )
        
        // Borders & Dividers
        static let border = dynamicColor(
            light: NSColor(red: 0.85, green: 0.85, blue: 0.90, alpha: 1.0),
            dark: NSColor(red: 0.25, green: 0.25, blue: 0.32, alpha: 1.0)
        )
        static let borderSubtle = dynamicColor(
            light: NSColor(red: 0.90, green: 0.90, blue: 0.95, alpha: 1.0),
            dark: NSColor(red: 0.20, green: 0.20, blue: 0.26, alpha: 1.0)
        )
        
        // Waveform
        static let waveformActive = dynamicColor(
            light: NSColor(red: 0.35, green: 0.30, blue: 0.85, alpha: 1.0),
            dark: NSColor(red: 0.45, green: 0.40, blue: 0.95, alpha: 1.0)
        )
        static let waveformInactive = dynamicColor(
            light: NSColor(red: 0.80, green: 0.80, blue: 0.85, alpha: 1.0),
            dark: NSColor(red: 0.25, green: 0.25, blue: 0.35, alpha: 1.0)
        )
        
        // Tag colors
        static let tagColors: [Color] = [
            Color(nsColor: NSColor(red: 0.45, green: 0.40, blue: 0.95, alpha: 0.25)),
            Color(nsColor: NSColor(red: 0.35, green: 0.75, blue: 0.65, alpha: 0.25)),
            Color(nsColor: NSColor(red: 0.90, green: 0.55, blue: 0.30, alpha: 0.25)),
            Color(nsColor: NSColor(red: 0.80, green: 0.35, blue: 0.55, alpha: 0.25)),
            Color(nsColor: NSColor(red: 0.40, green: 0.65, blue: 0.90, alpha: 0.25)),
        ]
    }
    
    // MARK: - Gradients
    enum Gradients {
        static let accent = LinearGradient(
            colors: [Colors.accentPrimary, Colors.accentSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let accentReversed = LinearGradient(
            colors: [Colors.accentSecondary, Colors.accentPrimary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let recording = LinearGradient(
            colors: [Colors.recording, Colors.recording.opacity(0.8)],
            startPoint: .top,
            endPoint: .bottom
        )
        
        static let surface = LinearGradient(
            colors: [Colors.surfacePrimary, Colors.surfacePrimary.opacity(0.8)],
            startPoint: .top,
            endPoint: .bottom
        )
        
        static let waveform = LinearGradient(
            colors: [Colors.accentPrimary, Colors.accentSecondary.opacity(0.6)],
            startPoint: .bottom,
            endPoint: .top
        )
    }
    
    // MARK: - Typography
    enum Typography {
        static let largeTitle = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let title2 = Font.system(size: 18, weight: .semibold, design: .rounded)
        static let title3 = Font.system(size: 16, weight: .medium, design: .rounded)
        static let headline = Font.system(size: 14, weight: .semibold, design: .default)
        static let body = Font.system(size: 14, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 14, weight: .medium, design: .default)
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let captionMedium = Font.system(size: 12, weight: .medium, design: .default)
        static let footnote = Font.system(size: 11, weight: .regular, design: .default)
        
        // Monospaced (for timestamps, timer, code)
        static let monoLarge = Font.system(size: 32, weight: .light, design: .monospaced)
        static let monoMedium = Font.system(size: 16, weight: .regular, design: .monospaced)
        static let monoSmall = Font.system(size: 12, weight: .regular, design: .monospaced)
        static let monoCaption = Font.system(size: 10, weight: .regular, design: .monospaced)
    }
    
    // MARK: - Spacing
    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let huge: CGFloat = 48
    }
    
    // MARK: - Corner Radius
    enum CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let pill: CGFloat = 100
    }
    
    // MARK: - Shadows
    enum Shadows {
        static let sm = ShadowStyle(color: .black.opacity(0.12), radius: 4, y: 2)
        static let md = ShadowStyle(color: .black.opacity(0.15), radius: 8, y: 4)
        static let lg = ShadowStyle(color: .black.opacity(0.20), radius: 16, y: 8)
        static let glow = ShadowStyle(color: Colors.accentPrimary.opacity(0.3), radius: 20, y: 0)
    }
    
    // MARK: - Animation
    enum Animation {
        static let fast = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.7)
        static let bouncy = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.6)
        static let pulse = SwiftUI.Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)
    }
}

// MARK: - Shadow Style Helper
struct ShadowStyle: Sendable {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
}

// MARK: - View Extensions for Theme
extension View {
    func themeShadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: 0, y: style.y)
    }
    
    func glassBackground(cornerRadius: CGFloat = Theme.CornerRadius.lg) -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
    
    func cardStyle() -> some View {
        self
            .background(Theme.Colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                    .stroke(Theme.Colors.borderSubtle, lineWidth: 0.5)
            )
            .themeShadow(Theme.Shadows.md)
    }
}
