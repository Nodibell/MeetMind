import ScreenCaptureKit
import Foundation

let semaphore = DispatchSemaphore(value: 0)

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        print("Displays: \(content.displays.count)")
        for display in content.displays {
            print("ID: \(display.displayID), width: \(display.width), height: \(display.height)")
        }
    } catch {
        print("Error: \(error)")
    }
    semaphore.signal()
}

semaphore.wait()
