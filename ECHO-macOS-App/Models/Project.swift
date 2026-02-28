import Foundation
import SwiftData

@Model
class Project {
    var id: UUID
    var name: String
    var desc: String
    var colorHex: String // Store as hex string
    var category: String?
    var createdAt: Date
    var isAutoCreated: Bool
    
    init(name: String, desc: String = "", colorHex: String = "#3B82F6", category: String? = nil, isAutoCreated: Bool = false) {
        self.id = UUID()
        self.name = name
        self.desc = desc
        self.colorHex = colorHex
        self.category = category
        self.createdAt = Date()
        self.isAutoCreated = isAutoCreated
    }
    
    // Helper to get color based on category
    static func colorForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "coding", "development": return "#3B82F6" // Blue
        case "communication", "chat": return "#10B981" // Green
        case "entertainment", "media": return "#EF4444" // Red
        case "design": return "#8B5CF6" // Purple
        case "browsing", "research": return "#F59E0B" // Orange
        case "writing": return "#EC4899" // Pink
        default: return "#6B7280" // Gray
        }
    }
    
    // Helper to sanitize project name from bad LLM data
    var displayName: String {
        let raw = name
        
        // If it's short and clean, return it
        if raw.count < 50 && !raw.contains("\n") {
            return raw
        }
        
        // Try to extract "Project: NAME" pattern
        if let range = raw.range(of: "Project: ") {
            let after = raw[range.upperBound...]
            let name = after.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let clean = name.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && clean.count < 50 {
                return clean
            }
        }
        
        // Try to extract JSON "name": "VALUE" pattern
        if let range = raw.range(of: "\"name\": \"") {
            let after = raw[range.upperBound...]
            if let endRange = after.range(of: "\"") {
                let name = String(after[..<endRange.lowerBound])
                if !name.isEmpty && name.count < 50 {
                    return name
                }
            }
        }
        
        // Fallback: If it's just really long text, try to grab the first "sentence" or just truncate
        return String(raw.prefix(30)) + "..."
    }
}
