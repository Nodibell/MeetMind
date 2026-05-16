import SwiftUI
import AppKit

@MainActor
final class FloatingIndicatorManager {
    static let shared = FloatingIndicatorManager()
    
    private var window: NSPanel?
    
    private init() {}
    
    func show(isActiveSpeech: Bool, speakerName: String?) {
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
                styleMask: [.nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            
            let contentView = NSHostingView(rootView: RecordingIndicatorView(isActiveSpeech: isActiveSpeech, speakerName: speakerName))
            panel.contentView = contentView
            
            // Position in top-right corner by default
            if let screen = NSScreen.main {
                let x = screen.visibleFrame.maxX - 220
                let y = screen.visibleFrame.maxY - 80
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
            
            self.window = panel
        }
        
        update(isActiveSpeech: isActiveSpeech, speakerName: speakerName)
        window?.orderFrontRegardless()
    }
    
    func update(isActiveSpeech: Bool, speakerName: String?) {
        guard let window = window else { return }
        let contentView = NSHostingView(rootView: RecordingIndicatorView(isActiveSpeech: isActiveSpeech, speakerName: speakerName))
        window.contentView = contentView
    }
    
    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}
