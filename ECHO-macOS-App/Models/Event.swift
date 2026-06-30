import Foundation
import SwiftData

@Model
final class Event {
    var timestamp: Date
    var source: String
    var type: String
    var text: String
    var meta: String? // JSON string
    
    // OCR-related fields
    var windowName: String? // Name of the window where event occurred
    var ocrText: String? // Detected text snippet
    var bounds: String? // JSON string of bounding box data
    
    // Project relationship
    var projectName: String? // Link to project
    
    init(timestamp: Date = Date(), source: String, type: String, text: String, meta: String? = nil, windowName: String? = nil, ocrText: String? = nil, bounds: String? = nil, projectName: String? = nil) {
        self.timestamp = timestamp
        self.source = source
        self.type = type
        self.text = text
        self.meta = meta
        self.windowName = windowName
        self.ocrText = ocrText
        self.bounds = bounds
        self.projectName = projectName
    }
}

