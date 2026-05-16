import Foundation
import SwiftUI

/// Metadata for a speaker, including custom name and color
struct SpeakerMetadata: Codable, Identifiable, Sendable {
    var id: String // The original speaker ID (e.g. "Speaker 0")
    var name: String? // Custom name provided by user or AI
    var colorHex: String? // Hex color code
    
    var displayName: String {
        if let name = name, !name.isEmpty { return name }
        
        // Localize "Speaker X" if it matches the pattern
        if id.hasPrefix("Speaker "), let range = id.range(of: #"\d+"#, options: .regularExpression) {
            let number = String(id[range])
            return String(localized: "Спікер \(number)")
        }
        
        return id
    }
    
    var color: Color {
        if let hex = colorHex {
            return Color(hex: hex)
        }
        return Theme.Colors.accentPrimary
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String {
        // Ensure we're working with sRGB color space to avoid darkening/shifting
        guard let sRGBColor = NSColor(self).usingColorSpace(.sRGB) else {
            return "7266F2" // Fallback to accentPrimary
        }
        
        let r = Float(sRGBColor.redComponent)
        let g = Float(sRGBColor.greenComponent)
        let b = Float(sRGBColor.blueComponent)
        
        return String(format: "%02X%02X%02X", 
                      max(0, min(255, lroundf(r * 255))), 
                      max(0, min(255, lroundf(g * 255))), 
                      max(0, min(255, lroundf(b * 255))))
    }
}
