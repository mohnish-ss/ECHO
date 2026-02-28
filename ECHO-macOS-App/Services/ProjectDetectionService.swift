import Foundation

/// Service for detecting and managing projects from user activity
class ProjectDetectionService {
    private let llmService: LLMService
    
    /// Apps that should never create projects
    private let sourceBlacklist: Set<String> = [
        "finder", "system settings", "system preferences", "systemuiserver",
        "control center", "notification center", "dock", "loginwindow",
        "screencaptureui", "screenshotui", "screenshot",
        "activity monitor", "disk utility", "keychain access",
        "font book", "preview", "textedit", "calculator",
        "app store", "software update", "about this mac"
    ]
    
    /// Path components that are NOT project names
    private let pathBlacklist: Set<String> = [
        "users", "library", "applications", "system", "documents",
        "desktop", "downloads", "developer", "volumes", "private",
        "usr", "bin", "var", "tmp", "etc", "opt", "home",
        "node_modules", "build", "dist", "vendor", ".git",
        "packages", "pods", "carthage", "deriveddata",
        "xcode", "contents", "resources", "frameworks"
    ]
    
    init(llmService: LLMService) {
        self.llmService = llmService
    }
    
    /// Detect project from event using hybrid approach
    func detectProject(from event: Event, existingProjects: [String]) async -> (name: String, category: String) {
        // Try rule-based first (instant)
        if let result = detectFromRules(event, existingProjects: existingProjects) {
            return result
        }
        
        // Fall back to LLM (smart but slower)
        do {
            return try await llmService.classifyProject(event: event, existingProjects: existingProjects)
        } catch {
            print("⚠️ LLM classification failed: \(error)")
            return ("General", "Other")
        }
    }
    
    /// Rule-based detection (fast)
    private func detectFromRules(_ event: Event, existingProjects: [String]) -> (name: String, category: String)? {
        let text = event.text.lowercased()
        let windowName = event.windowName?.lowercased() ?? ""
        let appName = event.source.lowercased()
        
        // Skip blacklisted sources entirely
        if sourceBlacklist.contains(where: { appName.contains($0) }) {
            return ("General", "Other")
        }
        
        // Check existing projects for matches
        for projectName in existingProjects {
            let lowerProject = projectName.lowercased()
            
            // Match by file path
            if text.contains("/\(lowerProject)/") || text.contains("/\(lowerProject)-") {
                return (projectName, "Coding")
            }
            
            // Match by window title
            if windowName.contains(lowerProject) {
                return (projectName, "General") 
            }
        }
        
        // Common patterns for new projects
        if appName.contains("xcode") {
            if let projectName = extractXcodeProject(from: windowName),
               isValidProjectName(projectName) {
                return (projectName, "Coding")
            }
        }
        
        if appName.contains("code") || appName.contains("cursor") || appName.contains("vscode") {
            if let projectName = extractCodeProject(from: text),
               isValidProjectName(projectName) {
                return (projectName, "Coding")
            }
        }
        
        // Check for common project indicators in text
        if let projectName = extractFromPath(text),
           isValidProjectName(projectName) {
             return (projectName, "Coding")
        }
        
        return nil
    }
    
    private func extractXcodeProject(from windowTitle: String) -> String? {
        // "MyProject — Edited" -> "MyProject"
        let components = windowTitle.components(separatedBy: " — ")
        let projectName = components.first?.trimmingCharacters(in: .whitespaces)
        return projectName?.isEmpty == false ? projectName : nil
    }
    
    private func extractCodeProject(from text: String) -> String? {
        // Look for common project folder patterns
        let patterns = [
            #"/([^/]+)/src/"#,
            #"/([^/]+)/lib/"#,
            #"/([^/]+)/app/"#,
            #"/Projects/([^/]+)/"#,
            #"/Documents/([^/]+)/"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let projectName = String(text[range])
                // Filter out common non-project folders
                if !["node_modules", "build", "dist", "vendor"].contains(projectName.lowercased()) {
                    return projectName
                }
            }
        }
        return nil
    }
    
    private func extractFromPath(_ text: String) -> String? {
        let components = text.components(separatedBy: "/")
        
        for component in components {
            if component.count > 2,
               component.first?.isUppercase == true,
               !component.contains(" "),
               !component.contains("."),
               isValidProjectName(component) {
                return component
            }
        }
        
        return nil
    }
    
    /// Validate that a detected name is actually a project and not a system folder
    private func isValidProjectName(_ name: String) -> Bool {
        let lower = name.lowercased()
        
        // Reject blacklisted path names
        if pathBlacklist.contains(lower) { return false }
        
        // Reject very short names (1-2 chars)
        if name.count < 3 { return false }
        
        // Reject if all uppercase and short (likely an acronym/abbreviation)
        if name.count < 5 && name == name.uppercased() { return false }
        
        // Reject common macOS system names
        let systemNames: Set<String> = [
            "macos", "darwin", "apple", "appkit", "uikit", "swiftui",
            "general", "unknown", "untitled", "new project", "configuration"
        ]
        if systemNames.contains(lower) { return false }
        
        return true
    }
}
