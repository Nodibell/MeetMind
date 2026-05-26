//
//  AudioExtractor.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 25.05.2026.
//

import AVFoundation
import Foundation

struct AudioExtractor {
    enum ExtractionError: LocalizedError {
        case failedToCreateSession
        case noAudioTrack
        case exportFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .failedToCreateSession:
                return String(localized: "Не вдалося створити сесію експорту аудіо")
            case .noAudioTrack:
                return String(localized: "У вибраному файлі не знайдено аудіо доріжки")
            case .exportFailed(let reason):
                return String(localized: "Не вдалося експортувати аудіо: \(reason)")
            }
        }
    }
    
    /// Extracts the audio track from a video or audio file and exports it as an M4A file to a target URL.
    static func extractAudio(from inputURL: URL, to outputURL: URL) async throws {
        let asset = AVURLAsset(url: inputURL)
        
        // Check if the asset has an audio track
        let tracks = try await asset.load(.tracks)
        let hasAudio = tracks.contains { $0.mediaType == .audio }
        guard hasAudio else {
            throw ExtractionError.noAudioTrack
        }
        
        // Remove existing output file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        // Create AVAssetExportSession
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ExtractionError.failedToCreateSession
        }
        
        // Export using modern macOS 13+ async/await API
        do {
            try await exportSession.export(to: outputURL, as: .m4a)
            AppLogger.info("Successfully extracted audio from \(inputURL.lastPathComponent) to \(outputURL.lastPathComponent)")
        } catch {
            throw ExtractionError.exportFailed(error.localizedDescription)
        }
    }
}
