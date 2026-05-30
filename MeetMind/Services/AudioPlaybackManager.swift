//
//  AudioPlaybackManager.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 26.05.2026.
//

import Foundation
import AVFoundation
import Observation

/// A modern @Observable manager for playing local meeting audio and observing progress state
@Observable
final class AudioPlaybackManager: NSObject, Sendable {
    static let shared = AudioPlaybackManager()
    
    private let playerLock = NSLock()
    private var _player: AVPlayer?
    private var timeObserverToken: Any?
    
    // Playback state observed by SwiftUI
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var progress: Double = 0
    var currentURL: URL?
    
    private var player: AVPlayer? {
        get { playerLock.withLock { _player } }
        set { playerLock.withLock { _player = newValue } }
    }
    
    override init() {
        super.init()
    }
    
    @MainActor
    func load(url: URL) {
        if currentURL == url { return }
        
        reset()
        currentURL = url
        
        let asset = AVURLAsset(url: url, options: [:])
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        self.player = newPlayer
        
        // Track when playback finishes to auto-reset seek
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        // Load duration asynchronously using modern swift concurrency
        Task { [weak self] in
            guard let self else { return }
            if let durationVal = try? await asset.load(.duration) {
                let seconds = CMTimeGetSeconds(durationVal)
                await MainActor.run {
                    self.duration = seconds.isNaN ? 0 : seconds
                }
            }
        }
        
        setupTimeObserver(newPlayer)
    }
    
    @MainActor
    func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
    }
    
    @MainActor
    func pause() {
        guard let player else { return }
        player.pause()
        isPlaying = false
    }
    
    @MainActor
    func seek(to time: TimeInterval) {
        guard let player else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self else { return }
            if finished {
                Task { @MainActor in
                    self.currentTime = time
                    if self.duration > 0 {
                        self.progress = time / self.duration
                    }
                }
            }
        }
    }
    
    @MainActor
    func reset() {
        pause()
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        NotificationCenter.default.removeObserver(self)
        player = nil
        currentURL = nil
        currentTime = 0
        duration = 0
        progress = 0
    }
    
    @MainActor
    private func setupTimeObserver(_ activePlayer: AVPlayer) {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = activePlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = CMTimeGetSeconds(time)
            Task { @MainActor in
                self.currentTime = seconds.isNaN ? 0 : seconds
                if self.duration > 0 {
                    self.progress = self.currentTime / self.duration
                }
            }
        }
    }
    
    @objc private func playerDidFinishPlaying() {
        Task { @MainActor in
            self.pause()
            self.seek(to: 0)
        }
    }
    
    deinit {
        let activeToken = timeObserverToken
        let activePlayer = player
        if let activeToken, let activePlayer {
            activePlayer.removeTimeObserver(activeToken)
        }
        NotificationCenter.default.removeObserver(self)
    }
}
