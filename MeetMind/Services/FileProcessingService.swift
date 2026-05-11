//
//  FileProcessingService.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import Foundation

/// Watches a folder for new audio recordings and processes them automatically
actor FileProcessingService {
    
    // MARK: - State
    private var processedFiles: Set<String> = [] // SHA-256 hashes
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var isWatching = false
    
    private let transcriptionService: TranscriptionService
    private let llmService: LLMService
    
    var onFileProcessed: (@Sendable (String, MeetingTranscriptDocument, String) -> Void)?
    var onError: (@Sendable (String, Error) -> Void)?
    
    // MARK: - Initialization
    
    init(transcriptionService: TranscriptionService, llmService: LLMService) {
        self.transcriptionService = transcriptionService
        self.llmService = llmService
        Task {
            await loadManifest()
        }
    }
    
    // MARK: - Watch Folder
    
    func startWatching(folder: URL) {
        guard !isWatching else { return }
        
        let fileDescriptor = open(folder.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .utility)
        )
        
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task {
                await self.scanFolder(folder)
            }
        }
        
        source.setCancelHandler {
            close(fileDescriptor)
        }
        
        source.resume()
        fileMonitor = source
        isWatching = true
        
        // Initial scan
        Task {
            await scanFolder(folder)
        }
    }
    
    func stopWatching() {
        fileMonitor?.cancel()
        fileMonitor = nil
        isWatching = false
    }
    
    // MARK: - Scan & Process
    
    private func scanFolder(_ folder: URL) async {
        let fm = FileManager.default
        
        guard let contents = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        let audioFiles = contents.filter { url in
            Constants.supportedAudioExtensions.contains(url.pathExtension.lowercased())
        }
        
        for file in audioFiles {
            await processFileIfNew(file)
        }
    }
    
    private func processFileIfNew(_ fileURL: URL) async {
        // Lightweight file identity: path + size + creation date (avoids loading entire file into RAM)
        guard let identity = fileIdentity(for: fileURL) else { return }

        guard !processedFiles.contains(identity) else { return }

        do {
            // Transcribe
            let transcript = try await transcriptionService.transcribeFile(at: fileURL)

            // Summarize
            let summary = try await llmService.generateSummary(transcript: transcript.fullText)

            // Mark as processed
            processedFiles.insert(identity)
            saveManifest()

            // Notify
            onFileProcessed?(fileURL.lastPathComponent, transcript, summary)
        } catch {
            onError?(fileURL.lastPathComponent, error)
        }
    }

    /// Returns a lightweight unique identifier for a file using its metadata (no file reads)
    private func fileIdentity(for url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              let created = attrs[.creationDate] as? Date else { return nil }
        return "\(url.path)|\(size)|\(Int(created.timeIntervalSince1970))"
    }
    
    // MARK: - Process Single File
    
    func processFile(at url: URL) async throws -> (MeetingTranscriptDocument, String) {
        let transcript = try await transcriptionService.transcribeFile(at: url)
        let summary = try await llmService.generateSummary(transcript: transcript.fullText)

        // Mark as processed using lightweight identity
        if let identity = fileIdentity(for: url) {
            processedFiles.insert(identity)
            saveManifest()
        }

        return (transcript, summary)
    }
    
    // MARK: - Manifest Persistence
    
    private func loadManifest() {
        let manifestURL = Constants.appSupportDirectory.appendingPathComponent(Constants.processedFilesManifest)
        guard let data = try? Data(contentsOf: manifestURL),
              let hashes = try? JSONDecoder().decode(Set<String>.self, from: data) else { return }
        processedFiles = hashes
    }
    
    private func saveManifest() {
        let manifestURL = Constants.appSupportDirectory.appendingPathComponent(Constants.processedFilesManifest)
        guard let data = try? JSONEncoder().encode(processedFiles) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
