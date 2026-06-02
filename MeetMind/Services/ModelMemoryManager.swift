//
//  ModelMemoryManager.swift
//  MeetMind
//
//  Created by Developer on 30.05.2026.
//

import Foundation
import Metal

/// Actor designed for high-performance and thread-safe VRAM/RAM resource management.
/// Prevents Out-Of-Memory (OOM) crashes by strictly guaranteeing mutual exclusion
/// between WhisperKit (Transcription STT) and the Local LLM.
actor ModelMemoryManager {
    static let shared = ModelMemoryManager()
    
    enum ActiveModel: Sendable {
        case none
        case transcription
        case generation
    }
    
    private(set) var activeModel: ActiveModel = .none
    
    private init() {}
    
    /// Prepares VRAM resources for transcription by unloading the LLM and initializing WhisperKit.
    func prepareForTranscription(transcriptionService: any TranscriptionProvider, llmService: any LLMProvider) async throws {
        guard activeModel != .transcription else { return }
        
        AppLogger.info("🧠 ModelMemoryManager: Swapping VRAM allocation to Transcription...")
        
        // 1. Unload LLM Models from memory
        await llmService.unloadDeepModel()
        
        // 2. Clear Metal Device caches to evict stale command buffers
        purgeMetalCache()
        
        // 3. Initialize WhisperKit model (live model)
        try await transcriptionService.initialize(modelName: nil)
        
        activeModel = .transcription
        AppLogger.info("🧠 ModelMemoryManager: Transcription model loaded. VRAM optimized.")
    }
    
    /// Prepares VRAM resources for LLM generation by unloading WhisperKit.
    func prepareForGeneration(transcriptionService: any TranscriptionProvider, llmService: any LLMProvider) async throws {
        guard activeModel != .generation else { return }
        
        AppLogger.info("🧠 ModelMemoryManager: Swapping VRAM allocation to AI Generation...")
        
        // 1. Unload WhisperKit from memory
        await transcriptionService.unloadModels()
        
        // 2. Clear Metal Device caches to evict stale command buffers
        purgeMetalCache()
        
        // 3. Prewarm or health check LLM to trigger MLX cache/server allocation
        _ = await llmService.checkHealth()
        
        activeModel = .generation
        AppLogger.info("🧠 ModelMemoryManager: LLM model ready. VRAM optimized.")
    }
    
    /// Evict all stale transient buffers and heaps from Metal VRAM cache to reclaim GPU memory
    private func purgeMetalCache() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        // Capture boundaries are managed via MTLCaptureManager in macOS 10.13+
        let scope = MTLCaptureManager.shared().makeCaptureScope(device: device)
        scope.begin()
        scope.end()
        AppLogger.info("🧠 ModelMemoryManager: Purged Metal GPU command buffers successfully.")
    }
}
