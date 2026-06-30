import Foundation
import CoreGraphics

/// Represents a simple bounding box for recognized text or window frames.
struct AppRect: Equatable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    
    var cgRect: CGRect {
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Information about a single OCR detection.
struct OCRResult: Identifiable {
    let id = UUID()
    let text: String
    let bounds: AppRect // In screen-coordinate style (top-left origin)
}

/// Information about a window on the Mac screen.
struct WindowInfo: Identifiable {
    let id = UUID()
    let ownerName: String // Usually the App name (e.g., "Finder", "Safari")
    let windowTitle: String
    let frame: AppRect
    
    /// A computed property to get a nice display name.
    var displayName: String {
        return "\(ownerName) - \(windowTitle.isEmpty ? "Untitled Window" : windowTitle)"
    }
}

/// A wrapper to hold a window and the text found inside it.
struct MappedWindow: Identifiable {
    let id = UUID()
    let window: WindowInfo
    let containedText: [OCRResult]
}
