import Foundation
import SwiftData

@Model
final class SpeakerProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var voiceCentroid: [Float] // For cross-meeting identification
    var createdAt: Date
    var lastSeenAt: Date
    
    init(name: String, colorHex: String, voiceCentroid: [Float]) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.voiceCentroid = voiceCentroid
        self.createdAt = Date()
        self.lastSeenAt = Date()
    }
}
