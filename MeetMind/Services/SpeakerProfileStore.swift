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
    
    func findMatchingProfileWithSuggestion(for centroid: [Float], threshold: Float = 0.85, suggestionThreshold: Float = 0.70) -> (profile: SpeakerProfile?, suggestion: SpeakerProfile?) {
        let profiles = getAllProfiles()
        
        var bestMatch: SpeakerProfile?
        var maxSimilarity: Float = -1.0
        
        var bestSuggestion: SpeakerProfile?
        var maxSuggestionSimilarity: Float = -1.0
        
        for profile in profiles {
            let similarity = cosineSimilarity(centroid, profile.voiceCentroid)
            
            if similarity >= threshold {
                if similarity > maxSimilarity {
                    maxSimilarity = similarity
                    bestMatch = profile
                }
            } else if similarity >= suggestionThreshold {
                if similarity > maxSuggestionSimilarity {
                    maxSuggestionSimilarity = similarity
                    bestSuggestion = profile
                }
            }
        }
        
        if let match = bestMatch {
            Self.logger.info("Found matching speaker: \(match.name) (similarity: \(maxSimilarity))")
            match.lastSeenAt = Date()
            try? context.save()
        } else if let suggestion = bestSuggestion {
            Self.logger.info("Found suggested speaker candidate: \(suggestion.name) (similarity: \(maxSuggestionSimilarity))")
        }
        
        return (bestMatch, bestSuggestion)
    }
    
    func createProfile(name: String, colorHex: String, centroid: [Float]) -> SpeakerProfile {
        let profile = SpeakerProfile(name: name, colorHex: colorHex, voiceCentroid: centroid)
        context.insert(profile)
        try? context.save()
        return profile
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        VectorMath.cosineSimilarity(a, b)
    }
}
