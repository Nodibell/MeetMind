import Foundation
import SwiftData
import os

@MainActor
final class SpeakerProfileStore {
    static let shared = SpeakerProfileStore()
    
    private let modelContainer: ModelContainer
    private let context: ModelContext
    
    private static let logger = Logger(subsystem: "com.meetmind.app", category: "SpeakerProfileStore")
    
    private init() {
        do {
            modelContainer = try ModelContainer(for: SpeakerProfile.self)
            context = modelContainer.mainContext
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
    }
    
    func getAllProfiles() -> [SpeakerProfile] {
        let descriptor = FetchDescriptor<SpeakerProfile>(sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }
    
    func findMatchingProfile(for centroid: [Float], threshold: Float = 0.85) -> SpeakerProfile? {
        let profiles = getAllProfiles()
        
        var bestMatch: SpeakerProfile?
        var maxSimilarity: Float = -1.0
        
        for profile in profiles {
            let similarity = cosineSimilarity(centroid, profile.voiceCentroid)
            if similarity > threshold && similarity > maxSimilarity {
                maxSimilarity = similarity
                bestMatch = profile
            }
        }
        
        if let match = bestMatch {
            Self.logger.info("Found matching speaker: \(match.name) (similarity: \(maxSimilarity))")
            match.lastSeenAt = Date()
            try? context.save()
        }
        
        return bestMatch
    }
    
    func createProfile(name: String, colorHex: String, centroid: [Float]) -> SpeakerProfile {
        let profile = SpeakerProfile(name: name, colorHex: colorHex, voiceCentroid: centroid)
        context.insert(profile)
        try? context.save()
        return profile
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denom = sqrt(normA) * sqrt(normB)
        return denom == 0 ? 0 : dotProduct / denom
    }
}
