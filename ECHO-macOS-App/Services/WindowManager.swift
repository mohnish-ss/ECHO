import Foundation
import AppKit
import ScreenCaptureKit
import VideoToolbox

/// This class discovers which windows are currently open on your Mac.
/// IMPORTANT: This requires "Accessibility" permissions in System Settings -> Privacy & Security.
class WindowManager {
    // Keep a strong reference to the collector to prevent it from being deallocated
    // during the asynchronous capture process.
    private var activeCollector: NSObject?
    
    /// Fetches a list of all visible windows from running applications.
    func getVisibleWindows() -> [WindowInfo] {
        var windows: [WindowInfo] = []
        
        // 1. Get window list from Quartz Window Server
        // We filter for on-screen windows only and exclude desktop/system elements
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        for info in windowList {
            // 2. Filter for regular windows (Window Layer 0)
            // Windows with layer > 0 are usually overlays, menus, or tooltips
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            
            // 3. Extract window properties
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? "Unknown App"
            let windowTitle = info[kCGWindowName as String] as? String ?? ""
            
            // 4. Extract frame (stored in a dictionary under kCGWindowBounds)
            if let bounds = info[kCGWindowBounds as String] as? [String: Any],
               let x = bounds["X"] as? CGFloat,
               let y = bounds["Y"] as? CGFloat,
               let width = bounds["Width"] as? CGFloat,
               let height = bounds["Height"] as? CGFloat {
                
                let windowInfo = WindowInfo(
                    ownerName: ownerName,
                    windowTitle: windowTitle,
                    frame: AppRect(x: x, y: y, width: width, height: height)
                )
                windows.append(windowInfo)
            }
        }
        
        return windows
    }
    
    // Helper function to extract a specific attribute from an Accessibility element
    private func getAttribute(_ element: AXUIElement, _ attribute: String) -> Any? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if result == .success {
            return value
        }
        return nil
    }
    
    // Helper function specifically to get the window position and size
    private func getWindowFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        
        // Get Position (Top-Left corner)
        let posResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        // Get Size (Width and Height)
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        
        if posResult == .success, sizeResult == .success {
            var position: CGPoint = .zero
            var size: CGSize = .zero
            
            // Convert the raw Accessibility types back into standard Swift types
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            
            return CGRect(origin: position, size: size)
        }
        
        return nil
    }
    
    // Requires Screen Recording entitlement/permission
    
    /// Captures the primary display as an NSImage using ScreenCaptureKit.
    @MainActor
    func captureMainScreen() async -> NSImage? {
        // Fetch shareable content to identify the main display
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

        // Configure a stream to capture a single frame of the display
        let filter = SCContentFilter(display: mainDisplay, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = false
        configuration.width = mainDisplay.width
        configuration.height = mainDisplay.height
        configuration.showsCursor = false
        configuration.scalesToFit = true

        // Collector to receive a single CGImage frame
        final class OneFrameCollector: NSObject, SCStreamOutput {
            private let completion: (CGImage?) -> Void

            init(completion: @escaping (CGImage?) -> Void) {
                self.completion = completion
            }

            func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
                guard outputType == .screen else { return }
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                
                var cgImageOut: CGImage?
                VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImageOut)
                if let cgImageOut = cgImageOut {
                    completion(cgImageOut)
                }
            }

            func stream(_ stream: SCStream, didStopWithError error: Error) {
                completion(nil)
            }
        }

        // Create the stream
        let stream: SCStream
        do {
            stream = try SCStream(filter: filter, configuration: configuration, delegate: nil)
        } catch {
            print("Error: Failed to create SCStream: \(error)")
            return nil
        }

        // Await one frame with a robust collector
        let cgImage: CGImage? = await withCheckedContinuation { continuation in
            // Use a wrapper to ensure resume is called only once
            var resumed = false
            let safeResume: (CGImage?) -> Void = { image in
                if !resumed {
                    resumed = true
                    continuation.resume(returning: image)
                    self.activeCollector = nil // Release the collector
                }
            }

            let collector = OneFrameCollector { image in
                stream.stopCapture { _ in 
                    if let output = self.activeCollector as? SCStreamOutput {
                        try? stream.removeStreamOutput(output, type: .screen)
                    }
                    safeResume(image)
                }
            }
            
            self.activeCollector = collector
            
            do {
                try stream.addStreamOutput(collector, type: .screen, sampleHandlerQueue: .main)
                stream.startCapture(completionHandler: { error in
                    if let error = error {
                        print("Error starting capture: \(error)")
                        safeResume(nil)
                    }
                })
            } catch {
                print("Error configuring stream output: \(error)")
                safeResume(nil)
            }
        }

        guard let cgImage else { return nil }
        // CRITICAL: Set the size in POINTS (from mainDisplay), not pixels (from cgImage).
        // This ensures the point-to-pixel ratio is handled correctly by AppKit/SwiftUI.
        let size = NSSize(width: CGFloat(mainDisplay.width), height: CGFloat(mainDisplay.height))
        return NSImage(cgImage: cgImage, size: size)
    }
}
