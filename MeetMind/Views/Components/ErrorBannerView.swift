//
//  ErrorBannerView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import SwiftUI

/// Dismissible error/info banner with icon, message, and optional action
struct ErrorBannerView: View {
    let message: String
    var style: BannerStyle = .error
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?
    
    enum BannerStyle {
        case error, warning, info, success
        
        var icon: String {
            switch self {
            case .error: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .error: return Theme.Colors.error
            case .warning: return Theme.Colors.warning
            case .info: return Theme.Colors.processing
            case .success: return Theme.Colors.success
            }
        }
    }
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: style.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(style.color)
            
            Text(message)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Theme.Typography.captionMedium)
                        .foregroundStyle(style.color)
                }
                .buttonStyle(.plain)
            }
            
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(style.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(style.color.opacity(0.25), lineWidth: 0.5)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#Preview {
    VStack(spacing: 12) {
        ErrorBannerView(
            message: "Ollama не запущено. Виконайте 'ollama serve'.",
            style: .error,
            actionTitle: "Retry",
            action: {},
            onDismiss: {}
        )
        
        ErrorBannerView(
            message: "Модель завантажується...",
            style: .info,
            onDismiss: {}
        )
        
        ErrorBannerView(
            message: "Експортовано в Obsidian!",
            style: .success,
            onDismiss: {}
        )
    }
    .padding()
    .background(Theme.Colors.backgroundPrimary)
}
