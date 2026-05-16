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
        @Published var speakerName: String?
    }
    
    func show(isActiveSpeech: Bool, speakerName: String?) {
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 220, height: 70),
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
                let x = screen.visibleFrame.maxX - 240
                let y = screen.visibleFrame.maxY - 90
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
            
            self.window = panel
        }
        
        update(isActiveSpeech: isActiveSpeech, speakerName: speakerName)
        window?.orderFrontRegardless()
    }
    
    func update(isActiveSpeech: Bool, speakerName: String?) {
        indicatorState.isActiveSpeech = isActiveSpeech
        indicatorState.speakerName = speakerName
    }
    
    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}
