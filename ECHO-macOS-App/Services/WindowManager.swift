import Foundation
import AppKit
import ScreenCaptureKit

/// This class discovers which windows are currently open on your Mac.
/// Requires Screen Recording entitlement/permission.
class WindowManager {
    
    /// Fetches a list of all visible windows from running applications using ScreenCaptureKit.
    func getVisibleWindows() async -> [WindowInfo] {
        guard let content = try? await SCShareableContent.current else {
            return []
        }
        
        var windows: [WindowInfo] = []
        for window in content.windows {
            // Filter out off-screen, tiny, or system elements
            guard window.isOnScreen, window.frame.width > 50, window.frame.height > 50 else { continue }
            guard let app = window.owningApplication else { continue }
            
            let windowInfo = WindowInfo(
                ownerName: app.applicationName,
                windowTitle: window.title ?? "",
                frame: AppRect(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y,
                    width: window.frame.width,
                    height: window.frame.height
                )
            )
            windows.append(windowInfo)
        }
        return windows
    }
    
    /// Captures the primary display as an NSImage using ScreenCaptureKit.
    @MainActor
    func captureMainScreen() async -> NSImage? {
        guard let content = try? await SCShareableContent.current else {
            print("Error: Unable to fetch shareable content.")
            return nil
        }

        // Resolve the system main screen's display ID and match it to SCDisplay
        let mainDisplayID: CGDirectDisplayID? = {
            if let screen = NSScreen.main,
               let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                return CGDirectDisplayID(number.uint32Value)
            }
            return nil
        }()

        let mainDisplay: SCDisplay? = {
            if let id = mainDisplayID {
                return content.displays.first { $0.displayID == id }
            }
            return content.displays.first
        }()

        guard let mainDisplay else {
            print("Error: No displays available for capture.")
            return nil
        }

        let filter = SCContentFilter(display: mainDisplay, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = mainDisplay.width
        configuration.height = mainDisplay.height
        configuration.showsCursor = false
        configuration.scalesToFit = true

        guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else {
            print("Error: Failed to capture image via SCScreenshotManager")
            return nil
        }

        // CRITICAL: Set the size in POINTS (from mainDisplay), not pixels (from cgImage).
        // This ensures the point-to-pixel ratio is handled correctly by AppKit/SwiftUI.
        let size = NSSize(width: CGFloat(mainDisplay.width), height: CGFloat(mainDisplay.height))
        return NSImage(cgImage: cgImage, size: size)
    }
}
