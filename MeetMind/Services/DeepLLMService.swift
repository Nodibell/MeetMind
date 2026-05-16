import Foundation
import os

#if canImport(MLX)
import MLX
import MLXLLM
#endif

/// "Deep Summary" engine implementing AirLLM-style layer-wise inference.
/// Enables running 70B+ models on memory-constrained devices by loading
/// layers on-demand from disk.
actor DeepLLMService {
    
    private static let logger = Logger(subsystem: "com.meetmind.app", category: "DeepLLM")
    
    #if canImport(MLX)
    private var model: MLXLLM.Model?
    private var tokenizer: MLXLLM.Tokenizer?
    #endif
    
    private var isSharded = true
    private var prefetchEnabled = true
    
    enum State {
        case idle
        case loading(progress: Double)
        case ready
        case generating(tokenCount: Int)
        case error(String)
    }
    
    private(set) var state: State = .idle
    
    /// Load a large model with sharding and prefetching enabled.
    func loadModel(modelPath: URL) async throws {
        #if canImport(MLX)
        state = .loading(progress: 0.1)
        Self.logger.info("🚀 Loading DeepLLM model with layer-sharding...")
        
        do {
            let config = ModelConfiguration(
                modelPath: modelPath,
                loadSharded: true,
                prefetchLayers: prefetchEnabled
            )
            
            self.model = try await MLXLLM.loadModel(configuration: config) { progress in
                // Progress update logic
            }
            
            self.tokenizer = try await MLXLLM.loadTokenizer(configuration: config)
            
            state = .ready
            Self.logger.info("✅ DeepLLM model ready (sharding: \(self.isSharded), prefetch: \(self.prefetchEnabled))")
        } catch {
            state = .error(error.localizedDescription)
            Self.logger.error("❌ Failed to load large model: \(error.localizedDescription)")
            throw error
        }
        #else
        Self.logger.error("❌ MLX is not available in this build configuration.")
        throw NSError(domain: "DeepLLM", code: 404, userInfo: [NSLocalizedDescriptionKey: "MLX libraries not found. Deep Summary requires MLX backend."])
        #endif
    }
    
    /// Generate a summary using the layer-wise pipeline.
    func generateSummary(transcript: String) async throws -> String {
        #if canImport(MLX)
        guard let model = model, let tokenizer = tokenizer else {
            throw NSError(domain: "DeepLLM", code: 404, userInfo: [NSLocalizedDescriptionKey: "DeepLLM Model not loaded"])
        }
        
        state = .generating(tokenCount: 0)
        Self.logger.info("📝 Starting Deep Summary generation (Layer-wise pipeline)...")
        
        let prompt = buildDeepSummaryPrompt(transcript: transcript)
        var fullResponse = ""
        
        let stream = MLXLLM.generate(
            prompt: prompt,
            model: model,
            tokenizer: tokenizer,
            maxTokens: 2048,
            temp: 0.3,
            prefetch: prefetchEnabled
        )
        
        for try await token in stream {
            fullResponse += token
        }
        
        state = .ready
        return fullResponse
        #else
        throw NSError(domain: "DeepLLM", code: 404, userInfo: [NSLocalizedDescriptionKey: "MLX libraries not found."])
        #endif
    }
    
    private func buildDeepSummaryPrompt(transcript: String) -> String {
        return """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>
        You are an expert meeting analyst. Perform a deep, multi-perspective analysis of the following transcript.
        Extract strategic decisions, subtle risks, and cross-departmental impacts.
        <|eot_id|><|start_header_id|>user<|end_header_id|>
        TRANSCRIPT:
        \(transcript)
        <|eot_id|><|start_header_id|>assistant<|end_header_id|>
        """
    }
    
    /// Emergency unload when system is under critical memory pressure.
    func unload() {
        #if canImport(MLX)
        model = nil
        tokenizer = nil
        #endif
        state = .idle
        Self.logger.warning("🧹 DeepLLM model purged due to memory pressure.")
    }
}
