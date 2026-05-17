import Foundation
import os

#if canImport(MLXLLM)
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
#endif

/// "Deep Summary" engine implementing AirLLM-style layer-wise inference.
/// Enables running 70B+ models on memory-constrained devices by loading
/// layers on-demand from disk.
actor DeepLLMService {
    
    private static let logger = Logger(subsystem: "com.meetmind.app", category: "DeepLLM")
    nonisolated private static let supportedMLXModelTypes: Set<String> = [
        "acereason",
        "baichuan_m1",
        "bailing_moe",
        "bitnet",
        "cohere",
        "deepseek_v3",
        "ernie4_5",
        "exaone4",
        "falcon_h1",
        "gemma",
        "gemma2",
        "gemma3",
        "gemma3_text",
        "gemma3n",
        "glm4",
        "gpt_oss",
        "granite",
        "granitemoehybrid",
        "internlm2",
        "lfm2",
        "lfm2_moe",
        "lille-130m",
        "llama",
        "mimo",
        "mistral",
        "nanochat",
        "olmo2",
        "olmoe",
        "openelm",
        "phi",
        "phi3",
        "phimoe",
        "qwen2",
        "qwen3",
        "qwen3_moe",
        "smollm3",
        "starcoder2"
    ]
    
    nonisolated private static let unsupportedModelTypeNotes: [String: String] = [
        "bert": "це embedding/encoder модель, а DeepMLX потребує text-generation LLM",
        "gemma4": "поточний MLXLLM у MeetMind ще не має прямого loader для Gemma 4; запускайте її через LM Studio server",
        "glm4v": "це vision/multimodal модель; прямий DeepMLX зараз підтримує тільки текстові MLXLLM",
        "nomic-bert": "це embedding-модель, вона не підходить для резюме або Q&A чату",
        "nomic_bert": "це embedding-модель, вона не підходить для резюме або Q&A чату"
    ]
    
    #if canImport(MLXLLM)
    private var modelContext: ModelContext?
    #endif
    
    private var isSharded = true
    private var prefetchEnabled = true
    
    enum DeepLLMError: LocalizedError, Sendable {
        case librariesUnavailable
        case invalidModelDirectory(String)
        case modelNotLoaded
        
        var errorDescription: String? {
            switch self {
            case .librariesUnavailable:
                return "MLX-бібліотеки недоступні в цій збірці."
            case .invalidModelDirectory(let reason):
                return "Обрана папка не схожа на MLX-модель: \(reason)"
            case .modelNotLoaded:
                return "DeepMLX-модель не завантажена."
            }
        }
    }
    
    enum State: Equatable {
        case idle
        case loading(progress: Double)
        case ready
        case generating(tokenCount: Int)
        case error(String)
    }
    
    struct ModelCompatibility: Equatable, Sendable {
        let isSupported: Bool
        let modelType: String?
        let issue: String?
    }
    
    private struct ConfigHeader: Decodable {
        let modelType: String?
        
        enum CodingKeys: String, CodingKey {
            case modelType = "model_type"
        }
    }
    
    private(set) var state: State = .idle
    
    nonisolated static var supportedModelTypesDescription: String {
        supportedMLXModelTypes.sorted().joined(separator: ", ")
    }
    
    nonisolated static func modelCompatibility(at url: URL) -> ModelCompatibility {
        let fileManager = FileManager.default
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
        
        if let issue = baseModelDirectoryValidationIssue(at: url, fileManager: fileManager) {
            return ModelCompatibility(isSupported: false, modelType: nil, issue: issue)
        }
        
        let configURL = url.appendingPathComponent("config.json")
        let modelType: String
        do {
            let data = try Data(contentsOf: configURL)
            let header = try JSONDecoder().decode(ConfigHeader.self, from: data)
            guard let rawModelType = header.modelType?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawModelType.isEmpty else {
                return ModelCompatibility(isSupported: false, modelType: nil, issue: "у config.json немає model_type")
            }
            modelType = rawModelType
        } catch {
            return ModelCompatibility(isSupported: false, modelType: nil, issue: "неможливо прочитати model_type з config.json")
        }
        
        let normalizedModelType = modelType.lowercased()
        guard supportedMLXModelTypes.contains(normalizedModelType) else {
            let note = unsupportedModelTypeNotes[normalizedModelType]
            return ModelCompatibility(
                isSupported: false,
                modelType: modelType,
                issue: note ?? "model_type '\(modelType)' не підтримується MLXLLM"
            )
        }
        
        return ModelCompatibility(isSupported: true, modelType: modelType, issue: nil)
    }
    
    nonisolated static func modelDirectoryValidationIssue(at url: URL) -> String? {
        modelCompatibility(at: url).issue
    }
    
    nonisolated private static func baseModelDirectoryValidationIssue(at url: URL, fileManager: FileManager) -> String? {
        var isDirectory: ObjCBool = false
        
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "папка не існує"
        }
        
        guard fileManager.fileExists(atPath: url.appendingPathComponent("config.json").path) else {
            return "немає config.json"
        }
        
        let tokenizerCandidates = [
            "tokenizer.json",
            "tokenizer_config.json",
            "tokenizer.model",
            "vocab.json"
        ]
        let hasTokenizer = tokenizerCandidates.contains {
            fileManager.fileExists(atPath: url.appendingPathComponent($0).path)
        }
        guard hasTokenizer else {
            return "немає tokenizer.json/tokenizer_config.json/tokenizer.model/vocab.json"
        }
        
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return "неможливо прочитати вміст папки"
        }
        
        let hasWeights = contents.contains { file in
            let name = file.lastPathComponent
            return name.hasSuffix(".safetensors") || name.hasSuffix(".npz")
        }
        guard hasWeights else {
            return "немає ваг моделі у форматі .safetensors або .npz"
        }
        
        return nil
    }
    
    nonisolated static func isLikelyMLXModelDirectory(_ url: URL) -> Bool {
        modelDirectoryValidationIssue(at: url) == nil
    }
    
    /// Load a large model with sharding and prefetching enabled.
    func loadModel(modelPath: URL) async throws {
        #if canImport(MLXLLM)
        if let issue = Self.modelDirectoryValidationIssue(at: modelPath) {
            state = .error(issue)
            throw DeepLLMError.invalidModelDirectory(issue)
        }
        
        state = .loading(progress: 0.1)
        Self.logger.info("🚀 Loading DeepLLM model with layer-sharding...")
        
        do {
            let accessGranted = modelPath.startAccessingSecurityScopedResource()
            defer { if accessGranted { modelPath.stopAccessingSecurityScopedResource() } }
            
            let configuration = ModelConfiguration(directory: modelPath)
            self.modelContext = try await LLMModelFactory.shared.load(configuration: configuration)
            
            state = .ready
            Self.logger.info("✅ DeepLLM model ready")
        } catch {
            state = .error(error.localizedDescription)
            Self.logger.error("❌ Failed to load large model: \(error.localizedDescription)")
            throw error
        }
        #else
        Self.logger.error("❌ MLXLLM is not available in this build configuration.")
        throw DeepLLMError.librariesUnavailable
        #endif
    }
    
    /// Generate a response using a list of chat messages.
    func generate(messages: [LLMService.ChatMessage], maxTokens: Int = 2048) async throws -> String {
        #if canImport(MLXLLM)
        guard let context = modelContext else {
            throw DeepLLMError.modelNotLoaded
        }
        
        state = .generating(tokenCount: 0)
        Self.logger.info("📝 Starting native DeepMLX generation...")
        
        var chatMessages: [Chat.Message] = []
        for msg in messages {
            switch msg.role.lowercased() {
            case "system":
                chatMessages.append(.system(msg.content))
            case "assistant":
                chatMessages.append(.assistant(msg.content))
            default:
                chatMessages.append(.user(msg.content))
            }
        }
        
        let input = try await context.processor.prepare(
            input: UserInput(chat: chatMessages)
        )
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.3, topP: 0.9)

        let result: GenerateResult = try MLXLMCommon.generate(
            input: input,
            parameters: parameters,
            context: context,
            didGenerate: { _ in .more }
        )

        state = .ready
        return result.output
        #else
        throw DeepLLMError.librariesUnavailable
        #endif
    }
    
    /// Generate a summary using the layer-wise pipeline.
    func generateSummary(transcript: String, targetLanguage: String?, customPrompt: String) async throws -> String {
        let systemPrompt = Self.buildDeepSummarySystemPrompt(targetLanguage: targetLanguage, customPrompt: customPrompt)
        let userPrompt = Self.buildDeepSummaryUserPrompt(transcript: transcript)
        
        return try await generate(
            messages: [
                LLMService.ChatMessage(role: "system", content: systemPrompt),
                LLMService.ChatMessage(role: "user", content: userPrompt)
            ],
            maxTokens: 2048
        )
    }
    
    nonisolated static func buildDeepSummarySystemPrompt(targetLanguage: String?, customPrompt: String) -> String {
        let languageInstruction: String
        if let targetLanguage, targetLanguage != "auto" {
            let langName = targetLanguage == "uk" ? "Ukrainian" : "English"
            languageInstruction = "Write the entire response EXCLUSIVELY in \(langName)."
        } else {
            languageInstruction = "Answer in the same language as the dominant language of the transcript."
        }
        
        let customInstruction = customPrompt.isEmpty ? "" : "\nAdditional user instructions:\n\(customPrompt)\n"
        
        return """
        You are an expert meeting analyst. Perform a deep, multi-perspective analysis of the following transcript.
        Extract strategic decisions, subtle risks, and cross-departmental impacts.
        \(languageInstruction)
        Do not invent facts. Use Markdown.
        \(customInstruction)
        """
    }
    
    nonisolated static func buildDeepSummaryUserPrompt(transcript: String) -> String {
        return """
        TRANSCRIPT:
        \(transcript)
        """
    }
    
    /// Emergency unload when system is under critical memory pressure or immediately after generation completes.
    func unload() {
        #if canImport(MLXLLM)
        modelContext = nil
        
        // Give ARC some time to completely deallocate and tear down layer instances,
        // and only then purge the Metal Unified Memory cache pool to reclaim VRAM.
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            GPU.clearCache()
            Self.logger.warning("🧹 DeepLLM GPU cache cleared successfully")
        }
        #endif
        state = .idle
        Self.logger.warning("🧹 DeepLLM model purged.")
    }
}
