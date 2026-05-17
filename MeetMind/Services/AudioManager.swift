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
import os

/// Manages audio capture from microphone or virtual audio devices
@Observable
final class AudioManager: NSObject, AudioProvider, @unchecked Sendable {

    // MARK: - Public State
    var isRecording = false
    nonisolated var isPaused: Bool {
        get { isPausedAtomic.withLock { $0 } }
        set { isPausedAtomic.withLock { $0 = newValue } }
    }
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
    private var waveformTimer: Timer?
    private var currentRMS: Float = 0

    private let audioPipelineQueue = DispatchQueue(
        label: Constants.audioPipelineQueueLabel,
        qos: .userInteractive
    )

    // MARK: - Keep-Alive Watchdog
    private var keepAliveTimer: DispatchSourceTimer?
    private let lastBufferTimestamp = OSAllocatedUnfairLock(initialState: CFAbsoluteTimeGetCurrent())
    private let isPausedAtomic = OSAllocatedUnfairLock(initialState: false)
    private var streamConfiguration: SCStreamConfiguration?
    private var streamFilter: SCContentFilter?
    private var reconnectionRetryCount = 0

    // MARK: - Memory Pressure
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    var onCriticalMemoryPressure: (() -> Void)?

    // MARK: - Audio Device Model
    struct AudioDevice: Identifiable, Sendable, Hashable {
        let id: AudioDeviceID
        let name: String
        let uid: String
        let isInput: Bool
    }

    struct DisplayInfo: Identifiable, Hashable, Sendable {
        let id: CGDirectDisplayID
        let name: String
    }

    struct SystemAudioSourceInfo: Identifiable, Hashable, Sendable {
        enum Kind: String, Sendable {
            case display
            case window
        }

        let id: String
        let kind: Kind
        let title: String
        let subtitle: String
        let displayID: CGDirectDisplayID?
        let windowID: CGWindowID?
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
    func startRecording() async throws -> URL {
        guard !isRecording else {
            throw AudioError.alreadyRecording
        }

        errorMessage = nil
        elapsedTime = 0
        accumulatedSamples = []

        switch audioSource {
        case .microphone:
            return try startMicrophoneRecording()
        case .system:
            return try await startSystemAudioRecording()
        case .mixed:
            let url = try startMicrophoneRecording()
            try await startSystemAudioRecording(fileURL: url, ownsRecordingState: false)
            return url
        }
    }

    @discardableResult
    private func startMicrophoneRecording() throws -> URL {
        errorMessage = nil

        // Create recording file
        let filename = "recording_\(Date().filenameDateFormatted)_\(UUID().uuidString.prefix(8)).wav"
        let fileURL = Constants.recordingsDirectory.appendingPathComponent(filename)
        currentRecordingURL = fileURL
        AppLogger.audio("Starting recording to file: \(fileURL.lastPathComponent)")

        // Setup audio engine
        let engine = AVAudioEngine()

        // 1. Setup Microphone if needed
        if audioSource == .microphone || audioSource == .mixed {
            if let selectedDeviceID {
                try Self.setInputDevice(selectedDeviceID, for: engine)
            }

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

            // Save the same 16 kHz mono stream that Whisper receives.
            let audioFile = try AVAudioFile(forWriting: fileURL, settings: whisperFormat.settings)
            self.audioFile = audioFile

            // Create format converter
            let converter = AVAudioConverter(from: inputFormat, to: whisperFormat)

            // Install tap
            inputNode.installTap(onBus: 0, bufferSize: Constants.audioBufferSize, format: inputFormat) { [weak self] buffer, time in
                guard let self = self else { return }

                // Downsample for Whisper
                self.audioPipelineQueue.async {
                    guard !self.isPaused else { return }
                    // Calculate RMS for waveform
                    let rms = self.calculateRMS(buffer: buffer)

                    DispatchQueue.main.async {
                        self.currentRMS = rms
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

                            do {
                                try self.audioFile?.write(from: convertedBuffer)
                            } catch {
                                AppLogger.error("Error writing to file: \(error)")
                            }
                        }
                    }
                }
            }
        }

        // Start engine if mic is used
        if audioSource == .microphone || audioSource == .mixed {
            try engine.start()
            audioEngine = engine
            AppLogger.audio("Audio Engine (Microphone) started")
        }

        isRecording = true
        recordingStartTime = Date()

        // Start timer
        let startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, !self.isPaused else { return }
            self.elapsedTime = Date().timeIntervalSince(startTime) - self.accumulatedPausedTime
        }
        
        // Start waveform visual timer
        let fps = AppSettings.shared.waveformFPS
        let interval = 1.0 / Double(fps)
        waveformTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.audioLevels.removeFirst()
            self.audioLevels.append(self.currentRMS)
        }

        return fileURL
    }

    func pauseRecording() {
        guard isRecording && !isPaused else { return }
        isPaused = true
        pausedAt = Date()
        AppLogger.audio("Recording paused")
    }

    func resumeRecording() {
        guard isRecording && isPaused else { return }
        if let pausedAt = pausedAt {
            accumulatedPausedTime += Date().timeIntervalSince(pausedAt)
        }
        isPaused = false
        self.pausedAt = nil
        AppLogger.audio("Recording resumed")
    }

    private var pausedAt: Date?
    private var accumulatedPausedTime: TimeInterval = 0

    func stopRecording() -> URL? {
        guard isRecording else { return nil }
        
        isPaused = false
        pausedAt = nil
        accumulatedPausedTime = 0

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        if let stream = scStream {
            Task {
                try? await stream.stopCapture()
            }
        }
        scStream = nil
        stopKeepAliveMonitor()
        stopMemoryPressureMonitoring()

        audioFile = nil // This closes the file

        timer?.invalidate()
        timer = nil
        waveformTimer?.invalidate()
        waveformTimer = nil

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

    func getAvailableDisplays() async throws -> [DisplayInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.displays.enumerated().map { index, display in
            let name = "Екран \(index + 1) (\(Int(display.width))x\(Int(display.height)))"
            return DisplayInfo(id: display.displayID, name: name)
        }
    }

    func getAvailableSystemAudioSources() async throws -> [SystemAudioSourceInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        // Only windows from regular apps (shown in Dock).
        // Filters out: CursorUIViewService, AutoFill panels, App Icon Windows, etc.
        let regularBundleSet = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap(\.bundleIdentifier)
        )

        let displays = content.displays.enumerated().map { index, display in
            SystemAudioSourceInfo(
                id: "display:\(display.displayID)",
                kind: .display,
                title: "Display \(index + 1)",
                subtitle: "\(Int(display.width))×\(Int(display.height))",
                displayID: display.displayID,
                windowID: nil
            )
        }

        let windows = content.windows
            .filter { window in
                guard window.windowLayer == 0,
                      window.frame.width >= 100,
                      window.frame.height >= 100,
                      window.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier
                else { return false }
                let bundleID = window.owningApplication?.bundleIdentifier ?? ""
                return regularBundleSet.contains(bundleID)
            }
            .prefix(60)
            .map { window in
                let appName = window.owningApplication?.applicationName ?? "Unknown"
                let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayTitle = (title?.isEmpty == false && title != appName)
                    ? "\(appName) — \(title!)"
                    : appName
                return SystemAudioSourceInfo(
                    id: "window:\(window.windowID)",
                    kind: .window,
                    title: displayTitle,
                    subtitle: appName,
                    displayID: nil,
                    windowID: window.windowID
                )
            }

        return displays + windows
    }

    @discardableResult
    private func startSystemAudioRecording(fileURL existingURL: URL? = nil, ownsRecordingState: Bool = true) async throws -> URL {
        let fileURL: URL
        if let existingURL {
            fileURL = existingURL
        } else {
            let filename = "system_recording_\(Date().filenameDateFormatted)_\(UUID().uuidString.prefix(8)).wav"
            fileURL = Constants.recordingsDirectory.appendingPathComponent(filename)
        }
        currentRecordingURL = fileURL

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter = try makeSystemAudioContentFilter(from: content)

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = Int(Constants.whisperSampleRate)
        config.channelCount = Int(Constants.whisperChannelCount)
        config.excludesCurrentProcessAudio = true

        // Enable microphone capture on macOS 15+ to support mixed system+mic recording
        if #available(macOS 15.0, *) {
            config.captureMicrophone = true
        }

        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        config.showsCursor = false

        AppLogger.audio("SCStream config: sampleRate=\(config.sampleRate), channels=\(config.channelCount), excludesSelf=\(config.excludesCurrentProcessAudio)")

        let stream = SCStream(filter: filter, configuration: config, delegate: self)

        if audioFile == nil {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Constants.whisperSampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
        }

        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioPipelineQueue)
        try await stream.startCapture()

        scStream = stream
        self.streamConfiguration = config
        self.streamFilter = filter
        reconnectionRetryCount = 0

        // Start keep-alive watchdog
        startKeepAliveMonitor(stream: stream, configuration: config)
        // Start memory pressure monitoring
        startMemoryPressureMonitoring()

        if ownsRecordingState {
            isRecording = true
            recordingStartTime = Date()

            let startTime = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, !self.isPaused else { return }
                self.elapsedTime = Date().timeIntervalSince(startTime) - self.accumulatedPausedTime
            }
            
            // Start waveform visual timer
            let fps = AppSettings.shared.waveformFPS
            let interval = 1.0 / Double(fps)
            waveformTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.audioLevels.removeFirst()
                self.audioLevels.append(self.currentRMS)
            }
        }

        AppLogger.audio("System audio capture started")
        return fileURL
    }

    private func makeSystemAudioContentFilter(from content: SCShareableContent) throws -> SCContentFilter {
        let preferredID = AppSettings.shared.preferredSystemAudioSourceID

        // Window capture
        if let preferredID,
           preferredID.hasPrefix("window:"),
           let rawID = UInt32(preferredID.replacingOccurrences(of: "window:", with: "")),
           let window = content.windows.first(where: { $0.windowID == rawID }) {
            return SCContentFilter(desktopIndependentWindow: window)
        }

        // Display capture
        if let preferredID,
           preferredID.hasPrefix("display:"),
           let rawID = UInt32(preferredID.replacingOccurrences(of: "display:", with: "")),
           let display = content.displays.first(where: { $0.displayID == rawID }) {
            return SCContentFilter(display: display, excludingWindows: [])
        }

        // Auto — first available display
        guard let display = content.displays.first else {
            throw AudioError.noSystemAudioSource
        }
        return SCContentFilter(display: display, excludingWindows: [])
    }
}

// MARK: - SCStreamOutput & SCStreamDelegate
extension AudioManager: SCStreamOutput, SCStreamDelegate {

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio && !isPaused else { return }
        
        // Update keep-alive atomic timestamp
        lastBufferTimestamp.withLock { $0 = CFAbsoluteTimeGetCurrent() }

        // Extract audio buffer list with retained block buffer (zero-copy from CMSampleBuffer)
        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            AppLogger.audioError("CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer failed: \(status)")
            return
        }

        // Read format description for actual sample rate and channel layout
        var actualSampleRate: Double = 48000.0
        var channelCount: UInt32 = 1
        if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
            actualSampleRate = asbd.pointee.mSampleRate
            channelCount = asbd.pointee.mChannelsPerFrame
        }

        // Extract raw float pointer from the first audio buffer
        let audioBuffer = audioBufferList.mBuffers
        guard let rawData = audioBuffer.mData else { return }
        let totalSamples = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float32>.size
        let floatPointer = rawData.assumingMemoryBound(to: Float32.self)

        // Safe copy of audio data before jumping to the pipeline queue
        let rawSamples = Array(UnsafeBufferPointer(start: floatPointer, count: totalSamples))
        let currentChannelCount = channelCount
        let currentSampleRate = actualSampleRate

        audioPipelineQueue.async { [weak self] in
            guard let self else { return }

            // Step 1: Mono downmix (if multi-channel)
            var monoSamples: [Float]
            if currentChannelCount > 1 {
                let frames = rawSamples.count / Int(currentChannelCount)
                monoSamples = [Float](repeating: 0, count: frames)
                for ch in 0..<Int(currentChannelCount) {
                    for i in 0..<frames {
                        monoSamples[i] += rawSamples[i * Int(currentChannelCount) + ch]
                    }
                }
                var divisor = Float(currentChannelCount)
                vDSP_vsdiv(monoSamples, 1, &divisor, &monoSamples, 1, vDSP_Length(frames))
            } else {
                monoSamples = rawSamples
            }

            // Step 2: Resample to 16kHz if needed using vDSP
            let samples: [Float]
            if abs(currentSampleRate - Constants.whisperSampleRate) < 1.0 {
                samples = monoSamples
            } else {
                let ratio = Constants.whisperSampleRate / actualSampleRate
                let outputLength = Int(Double(monoSamples.count) * ratio)
                guard outputLength > 0 else { return }

                var output = [Float](repeating: 0, count: outputLength)
                // Use vDSP linear interpolation for resampling
                var control = (0..<outputLength).map { Float(Double($0) / ratio) }
                vDSP_vlint(monoSamples, &control, 1, &output, 1, vDSP_Length(outputLength), vDSP_Length(monoSamples.count))
                samples = output
            }

            // Step 3: Write to file
            if let audioFile = self.audioFile {
                let pcmFormat = audioFile.processingFormat
                if let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(samples.count)) {
                    buffer.frameLength = buffer.frameCapacity
                    if let channelData = buffer.floatChannelData {
                        samples.withUnsafeBufferPointer { src in
                            channelData[0].update(from: src.baseAddress!, count: samples.count)
                        }
                    }
                    try? audioFile.write(from: buffer)
                }
            }

            // Step 4: Accumulate for WhisperKit
            self.accumulatedSamples.append(contentsOf: samples)

            // Step 5: RMS for waveform visualization
            if !samples.isEmpty {
                var meanSquare: Float = 0
                vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(samples.count))
                let rms = min(sqrt(meanSquare) * 5.0, 1.0)
                DispatchQueue.main.async {
                    self.currentRMS = rms
                }
            }
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        AppLogger.streamWatchdogError("SCStream stopped with error", error: error)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.errorMessage = "Stream error: \(error.localizedDescription)"
            self.attemptStreamReconnection()
        }
    }
}

// MARK: - Keep-Alive Watchdog & Memory Pressure
extension AudioManager {

    /// Start a high-precision timer that checks for stream stalls every 5 seconds.
    fileprivate func startKeepAliveMonitor(stream: SCStream, configuration: SCStreamConfiguration) {
        stopKeepAliveMonitor()

        let timer = DispatchSource.makeTimerSource(queue: audioPipelineQueue)
        timer.schedule(
            deadline: .now() + Constants.keepAliveIntervalSeconds,
            repeating: Constants.keepAliveIntervalSeconds,
            leeway: .milliseconds(100)
        )
        timer.setEventHandler { [weak self] in
            guard let self, self.isRecording else { return }
            let lastTime = self.lastBufferTimestamp.withLock { $0 }
            let elapsed = CFAbsoluteTimeGetCurrent() - lastTime

            if elapsed > Constants.streamStallThresholdSeconds {
                AppLogger.streamWatchdog(
                    "Stream stall detected: \(String(format: "%.1f", elapsed))s since last buffer. Refreshing configuration."
                )
                Task { [weak self] in
                    guard let self, let stream = self.scStream else { return }
                    do {
                        try await stream.updateConfiguration(configuration)
                        AppLogger.streamWatchdog("Configuration refresh successful.")
                    } catch {
                        AppLogger.streamWatchdogError("Configuration refresh failed", error: error)
                    }
                }
            }
        }
        timer.resume()
        keepAliveTimer = timer
        AppLogger.streamWatchdog("Keep-alive monitor started (interval: \(Constants.keepAliveIntervalSeconds)s)")
    }

    fileprivate func stopKeepAliveMonitor() {
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
    }

    /// Exponential backoff reconnection for SCStream errors (up to 3 retries).
    fileprivate func attemptStreamReconnection() {
        guard reconnectionRetryCount < Constants.maxStreamReconnectionRetries else {
            AppLogger.streamWatchdogError("Max reconnection retries (\(Constants.maxStreamReconnectionRetries)) exhausted.")
            return
        }

        reconnectionRetryCount += 1
        let delay = Constants.reconnectionBaseDelaySeconds * pow(2.0, Double(reconnectionRetryCount - 1))
        AppLogger.streamWatchdog(
            "Scheduling reconnection attempt \(reconnectionRetryCount)/\(Constants.maxStreamReconnectionRetries) in \(delay)s"
        )

        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard self.isRecording else { return }

            try? await self.scStream?.stopCapture()
            self.scStream = nil
            self.stopKeepAliveMonitor()

            do {
                try await self.startSystemAudioRecording(
                    fileURL: self.currentRecordingURL,
                    ownsRecordingState: false
                )
                AppLogger.streamWatchdog("Reconnection attempt \(self.reconnectionRetryCount) succeeded.")
            } catch {
                AppLogger.streamWatchdogError("Reconnection attempt \(self.reconnectionRetryCount) failed", error: error)
                self.attemptStreamReconnection()
            }
        }
    }

    /// Monitor OS memory pressure. On `.critical`, invoke the model-unloading callback.
    fileprivate func startMemoryPressureMonitoring() {
        stopMemoryPressureMonitoring()

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            let event = source.data
            if event.contains(.critical) {
                AppLogger.systemHealth("CRITICAL memory pressure — triggering model unload.")
                self?.onCriticalMemoryPressure?()
            } else if event.contains(.warning) {
                AppLogger.systemHealth("WARNING memory pressure detected.")
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    fileprivate func stopMemoryPressureMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
    }
}

// MARK: - Errors
enum AudioError: LocalizedError {
    case alreadyRecording
    case formatError
    case deviceSelectionFailed
    case noInputDevice
    case noSystemAudioSource
    case engineStartFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording: return "Запис вже ведеться"
        case .formatError: return "Помилка формату аудіо"
        case .deviceSelectionFailed: return "Не вдалося вибрати аудіо пристрій"
        case .noInputDevice: return "Аудіо пристрій введення не знайдено"
        case .noSystemAudioSource: return "Джерело системного аудіо не знайдено"
        case .engineStartFailed: return "Не вдалося запустити аудіо двигун"
        }
    }
}
