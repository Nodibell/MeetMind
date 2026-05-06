//
//  AudioManager.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 06.05.2026.
//

import AVFoundation
import Accelerate
import ScreenCaptureKit
import CoreMedia

/// Manages audio capture from microphone or virtual audio devices
@Observable
final class AudioManager: NSObject, @unchecked Sendable {
    
    // MARK: - Public State
    var isRecording = false
    var elapsedTime: TimeInterval = 0
    var audioLevels: [Float] = Array(repeating: 0, count: Constants.waveformSampleCount)
    var availableDevices: [AudioDevice] = []
    var selectedDeviceID: AudioDeviceID?
    var errorMessage: String?
    var audioSource: AudioSource = .microphone
    
    enum AudioSource: String, Codable, Sendable {
        case microphone
        case system
        case mixed
    }
    
    // MARK: - Audio Buffer for Whisper
    private(set) var accumulatedSamples: [Float] = []
    
    // MARK: - Private
    private var audioEngine: AVAudioEngine?
    private var timer: Timer?
    private var recordingStartTime: Date?
    private var audioFile: AVAudioFile?
    private var currentRecordingURL: URL?
    private var scStream: SCStream?
    
    private let processingQueue = DispatchQueue(label: "com.meetmind.audio", qos: .userInteractive)
    
    // MARK: - Audio Device Model
    struct AudioDevice: Identifiable, Sendable, Hashable {
        let id: AudioDeviceID
        let name: String
        let uid: String
        let isInput: Bool
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
        refreshDevices()
    }
    
    // MARK: - Device Enumeration
    func refreshDevices() {
        availableDevices = Self.enumerateInputDevices()
        
        // Select preferred device or default
        if let preferred = AppSettings.shared.preferredInputDevice,
           let device = availableDevices.first(where: { $0.uid == preferred }) {
            selectedDeviceID = device.id
        } else if let defaultDevice = availableDevices.first {
            selectedDeviceID = defaultDevice.id
        }
    }
    
    func selectDevice(_ device: AudioDevice) {
        selectedDeviceID = device.id
        AppSettings.shared.preferredInputDevice = device.uid
    }
    
    // MARK: - Recording Control
    func startRecording() throws -> URL {
        guard !isRecording else {
            throw AudioError.alreadyRecording
        }
        
        if audioSource == .system {
            return try startSystemAudioRecording()
        }
        
        if audioSource == .mixed {
            // Start system audio first (it's async), then continue with microphone
            let url = try startSystemAudioRecording()
            try startMicrophoneRecording()
            return url
        }
        
        return try startMicrophoneRecording()
    }
    
    @discardableResult
    private func startMicrophoneRecording() throws -> URL {
        errorMessage = nil
        
        // Create recording file
        let filename = "recording_\(Date().filenameDateFormatted)_\(UUID().uuidString.prefix(8)).wav"
        let fileURL = Constants.recordingsDirectory.appendingPathComponent(filename)
        currentRecordingURL = fileURL
        AppLogger.audio("Початок запису у файл: \(fileURL.lastPathComponent)")
        
        // Setup audio engine
        let engine = AVAudioEngine()
        
        // 1. Setup Microphone if needed
        if audioSource == .microphone || audioSource == .mixed {
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            
            // Create converter format (16kHz, mono, Float32 for Whisper)
            guard let whisperFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Constants.whisperSampleRate,
                channels: Constants.whisperChannelCount,
                interleaved: false
            ) else {
                throw AudioError.formatError
            }
            
            // Create audio file for saving
            let audioFile = try AVAudioFile(forWriting: fileURL, settings: inputFormat.settings)
            self.audioFile = audioFile
            
            // Create format converter
            let converter = AVAudioConverter(from: inputFormat, to: whisperFormat)
            
            // Install tap
            inputNode.installTap(onBus: 0, bufferSize: Constants.audioBufferSize, format: inputFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                
                // Write to file
                try? self.audioFile?.write(from: buffer)
                
                // Downsample for Whisper
                self.processingQueue.async {
                    // Calculate RMS for waveform
                    let rms = self.calculateRMS(buffer: buffer)
                    
                    DispatchQueue.main.async {
                        self.audioLevels.removeFirst()
                        self.audioLevels.append(rms)
                    }
                    
                    // Write to file
                    do {
                        try self.audioFile?.write(from: buffer)
                    } catch {
                        AppLogger.error("Помилка запису у файл: \(error)")
                    }
                    
                    // Convert and append to accumulated samples
                    let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * (Constants.whisperSampleRate / inputFormat.sampleRate))
                    guard let convertedBuffer = AVAudioPCMBuffer(
                        pcmFormat: whisperFormat,
                        frameCapacity: frameCount
                    ) else { return }
                    
                    if let converter = converter {
                        var error: NSError?
                        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                            outStatus.pointee = .haveData
                            return buffer
                        }
                        
                        if status == .haveData, let channelData = convertedBuffer.floatChannelData {
                            let samples = Array(UnsafeBufferPointer(
                                start: channelData[0],
                                count: Int(convertedBuffer.frameLength)
                            ))
                            self.accumulatedSamples.append(contentsOf: samples)
                        }
                    }
                }
            }
        }
        
        // 2. Setup System Audio (SCStream) if needed
        if audioSource == .system || audioSource == .mixed {
            // We use a Task because ScreenCaptureKit initialization is async
            Task {
                _ = try? startSystemAudioRecording()
            }
        }
        
        // Reset accumulated samples
        accumulatedSamples = []
        // Start engine if mic is used
        if audioSource == .microphone || audioSource == .mixed {
            try engine.start()
            audioEngine = engine
            AppLogger.audio("Audio Engine (Мікрофон) запущено")
        }
        
        isRecording = true
        recordingStartTime = Date()
        
        // Start timer
        let startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.elapsedTime = Date().timeIntervalSince(startTime)
        }
        
        return fileURL
    }
    
    func stopRecording() -> URL? {
        guard isRecording else { return nil }
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        scStream?.stopCapture()
        scStream = nil
        
        audioFile = nil // This closes the file
        
        timer?.invalidate()
        timer = nil
        
        isRecording = false
        let url = currentRecordingURL
        currentRecordingURL = nil
        
        return url
    }
    
    /// Get the latest chunk of audio samples and clear the buffer
    func consumeAudioChunk() -> [Float] {
        let chunk = accumulatedSamples
        accumulatedSamples = []
        return chunk
    }
    
    /// Get accumulated samples without clearing
    func peekAudioSamples() -> [Float] {
        return accumulatedSamples
    }
    
    // MARK: - RMS Calculation
    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        
        let channelDataValue = channelData.pointee
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        
        var meanSquare: Float = 0
        vDSP_measqv(channelDataValue, 1, &meanSquare, vDSP_Length(count))
        
        let rms = sqrt(meanSquare)
        // Normalize to 0..1 range (roughly)
        return min(rms * 5.0, 1.0)
    }
    
    // MARK: - CoreAudio Device Management
    private static func enumerateInputDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return [] }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }
        
        return deviceIDs.compactMap { Self.getAudioDevice(for: $0) }
    }
    
    private static func getAudioDevice(for deviceID: AudioDeviceID) -> AudioDevice? {
        // Check if device has input channels
        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var inputSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize) == noErr else {
            return nil
        }
        
        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }
        
        guard AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &inputSize, bufferListPointer) == noErr else {
            return nil
        }
        
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
        guard inputChannels > 0 else { return nil }
        
        // Get device name
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)
        
        let deviceName: String
        if let cfName = name?.takeRetainedValue() {
            deviceName = cfName as String
        } else {
            deviceName = "Unknown Device"
        }
        
        // Get device UID
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uid)
        
        let deviceUID: String
        if let cfUID = uid?.takeRetainedValue() {
            deviceUID = cfUID as String
        } else {
            deviceUID = UUID().uuidString
        }
        
        return AudioDevice(
            id: deviceID,
            name: deviceName,
            uid: deviceUID,
            isInput: true
        )
    }
    
    private static func setInputDevice(_ deviceID: AudioDeviceID, for engine: AVAudioEngine) throws {
        let inputNode = engine.inputNode
        let audioUnit = inputNode.audioUnit!
        
        var deviceIDVar = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDVar,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        
        guard status == noErr else {
            throw AudioError.deviceSelectionFailed
        }
    }
    
    // MARK: - System Audio Recording (ScreenCaptureKit)
    
    private func startSystemAudioRecording() throws -> URL {
        let filename = "system_recording_\(Date().filenameDateFormatted)_\(UUID().uuidString.prefix(8)).wav"
        let fileURL = Constants.recordingsDirectory.appendingPathComponent(filename)
        currentRecordingURL = fileURL
        
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    AppLogger.error("Екран для захоплення не знайдено")
                    return
                }
                
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                
                // Minimal video setup - just enough to satisfy the SCStream requirement
                // without triggering the full Screen Recording permission if possible.
                config.width = 2
                config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 10)
                config.showsCursor = false
                
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                
                // Setup file writing for system audio (use 16kHz to match Whisper and save space)
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: Constants.whisperSampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
                self.audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
                
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: processingQueue)
                try await stream.startCapture()
                
                await MainActor.run {
                    self.scStream = stream
                    self.isRecording = true
                    self.recordingStartTime = Date()
                    
                    // Start timer
                    let startTime = Date()
                    self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                        self?.elapsedTime = Date().timeIntervalSince(startTime)
                    }
                    
                    AppLogger.audio("Запис системного звуку запущено")
                }
            } catch {
                Task { @MainActor in
                    AppLogger.error("Помилка відновлення доступу до Obsidian", error: error)
                }
                return
            }
        }
        
        return fileURL
    }
}

// MARK: - SCStreamOutput & SCStreamDelegate
extension AudioManager: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        
        guard let pointer = dataPointer else { return }
        
        let sampleCount = length / MemoryLayout<Float32>.size
        let floatPointer = pointer.withMemoryRebound(to: Float32.self, capacity: sampleCount) { $0 }
        let rawSamples = Array(UnsafeBufferPointer(start: floatPointer, count: sampleCount))
        
        // Simple downsampling if needed (e.g., from 48kHz to 16kHz)
        // For a more robust solution, use AVAudioConverter
        let systemSampleRate: Double = 48000 // Assume 48k for SCKit
        let targetSampleRate: Double = Constants.whisperSampleRate
        
        let ratio = Int(systemSampleRate / targetSampleRate)
        var samples: [Float] = []
        if ratio > 1 {
            for i in stride(from: 0, to: rawSamples.count, by: ratio) {
                samples.append(rawSamples[i])
            }
        } else {
            samples = rawSamples
        }
        
        processingQueue.async {
            // Write downsampled samples to file
            if let audioFile = self.audioFile {
                let pcmFormat = audioFile.processingFormat
                if let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(samples.count)) {
                    buffer.frameLength = buffer.frameCapacity
                    for i in 0..<samples.count {
                        buffer.floatChannelData?[0][i] = samples[i]
                    }
                    try? audioFile.write(from: buffer)
                }
            }
            
            self.accumulatedSamples.append(contentsOf: samples)
            
            if let first = samples.first {
                DispatchQueue.main.async {
                    self.audioLevels.removeFirst()
                    self.audioLevels.append(abs(first))
                }
            }
        }
    }
    
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            AppLogger.error("Стрім зупинено з помилкою", error: error)
        }
    }
}

// MARK: - Errors
enum AudioError: LocalizedError {
    case alreadyRecording
    case formatError
    case deviceSelectionFailed
    case noInputDevice
    case engineStartFailed
    
    var errorDescription: String? {
        switch self {
        case .alreadyRecording: return "Запис вже ведеться"
        case .formatError: return "Помилка формату аудіо"
        case .deviceSelectionFailed: return "Не вдалося вибрати аудіо пристрій"
        case .noInputDevice: return "Аудіо пристрій введення не знайдено"
        case .engineStartFailed: return "Не вдалося запустити аудіо двигун"
        }
    }
}
