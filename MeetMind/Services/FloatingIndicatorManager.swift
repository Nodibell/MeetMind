import SwiftUI
import AppKit
import Combine

@MainActor
final class FloatingIndicatorManager {
    static let shared = FloatingIndicatorManager()
    
    private var window: NSPanel?
    private var indicatorState = IndicatorState()
    
    private init() {}
    
    class IndicatorState: ObservableObject {
        @Published var isActiveSpeech = false
        @Published var isPaused = false
        @Published var speakerName: String?
        @Published var elapsedTime: TimeInterval = 0
        @Published var lastTranscript: String?
        
        var onPause: (() -> Void)?
        var onResume: (() -> Void)?
        var onStop: (() -> Void)?
        var onHide: (() -> Void)?
    }
    
    func show(isActiveSpeech: Bool, speakerName: String?) {
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 80),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.hasShadow = false // Remove shadow to eliminate any potential "frame" artifacts
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            
            indicatorState.isActiveSpeech = isActiveSpeech
            indicatorState.speakerName = speakerName
            
            let contentView = NSHostingView(rootView: RecordingIndicatorView(state: indicatorState))
            panel.contentView = contentView
            
            if let screen = NSScreen.main {
                let x = screen.visibleFrame.maxX - 300
                let y = screen.visibleFrame.maxY - 100
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
            
            self.window = panel
        }
        
        update(isActiveSpeech: isActiveSpeech, speakerName: speakerName)
        window?.orderFrontRegardless()
    }
    
    func update(
        isActiveSpeech: Bool,
        isPaused: Bool = false,
        speakerName: String?,
        elapsedTime: TimeInterval = 0,
        lastTranscript: String? = nil,
        onPause: (() -> Void)? = nil,
        onResume: (() -> Void)? = nil,
        onStop: (() -> Void)? = nil,
        onHide: (() -> Void)? = nil
    ) {
        indicatorState.isActiveSpeech = isActiveSpeech
        indicatorState.isPaused = isPaused
        indicatorState.speakerName = speakerName
        indicatorState.elapsedTime = elapsedTime
        indicatorState.lastTranscript = lastTranscript
        
        if let onPause { indicatorState.onPause = onPause }
        if let onResume { indicatorState.onResume = onResume }
        if let onStop { indicatorState.onStop = onStop }
        if let onHide { indicatorState.onHide = onHide }
    }
    
    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}
