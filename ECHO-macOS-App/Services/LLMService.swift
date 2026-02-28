import Foundation

/// LLM Service using local Ollama for privacy and zero cost
@Observable
class LLMService {
    private let baseURL = "http://localhost:11434"
    var isProcessing = false
    var lastError: String?
    
    // Default model - can be changed to llama3.1:70b for better quality
    private let model = "llama3.1"
    
    /// Query events with natural language
    func queryEvents(_ question: String, events: [Event]) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        let context = formatEventsAsContext(events)
        let prompt = """
        \(systemPrompt)
        
        --- BEGIN ACTIVITY DATA ---
        \(context)
        --- END ACTIVITY DATA ---
        
        User: \(question)
        ECHO:
        """
        
        return try await generate(prompt: prompt, maxTokens: 800)
    }
    
    /// Classify activity into project with category
    func classifyProject(event: Event, existingProjects: [String]) async throws -> (name: String, category: String) {
        let existingList = existingProjects.isEmpty ? "None yet" : existingProjects.joined(separator: ", ")
        
        let prompt = """
        Classify this computer activity into a Project and Category.

        Activity:
        - App: \(event.source)
        - Window: \(event.windowName ?? "Unknown")
        - Content: \(event.text.prefix(500))

        Existing Projects: \(existingList)

        ## WHAT IS A PROJECT?
        A project is a sustained piece of work the user is actively building or studying. Examples:
        - A coding project (e.g. "Project-Echo", "Portfolio Site", "Weather App")
        - A university course assignment (e.g. "CISC 327 Assignment", "Software Specs Lab")
        - A research or writing project (e.g. "Thesis Draft", "Blog Post")
        - A design project (e.g. "App Redesign", "Logo Design")

        ## WHAT IS NOT A PROJECT?
        - General web browsing, social media, news reading → NOT a project
        - Watching YouTube/Netflix/Spotify → NOT a project
        - System settings, Finder, calculators → NOT a project
        - Quick Google searches or Stack Overflow lookups (unless clearly part of a bigger project visible in the window title) → NOT a project
        - Communication (Slack, Discord, email) → NOT a project on its own

        ## Categories
        Coding, Communication, Entertainment, Browsing, Design, Writing, Research, Other

        ## Instructions
        1. If the activity matches an existing project, use that EXACT name.
        2. If it's a genuinely new project, create a concise 1-3 word name.
        3. If it's NOT a project (general browsing, entertainment, system tasks), set is_project to false.

        Return strictly valid JSON:
        {
          "is_project": true,
          "name": "Project Name",
          "category": "Category"
        }
        """
        
        let response = try await generate(prompt: prompt, maxTokens: 150)
        
        // Extract JSON
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rangeStart = jsonString.firstIndex(of: "{"),
           let rangeEnd = jsonString.lastIndex(of: "}") {
            jsonString = String(jsonString[rangeStart...rangeEnd])
        }
        
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String,
              let category = json["category"] as? String else {
            return ("General", "Other")
        }
        
        // If the LLM says it's not a project, return General
        if let isProject = json["is_project"] as? Bool, !isProject {
            return ("General", "Other")
        }
        
        return (name, category)
    }
    
    /// Summarize raw OCR text into meaningful context
    func summarizeScreenContent(text: String, appName: String) async throws -> String {
        guard !text.isEmpty else { return "" }
        
        let prompt = """
        Summarize this raw screen text into a concise 1-sentence description of what the user is working on.
        
        App: \(appName)
        Raw Text:
        \(text.prefix(1000))
        
        Rules:
        - Output ONLY the 1-sentence summary.
        - NO conversational filler (e.g. "Here is the summary", "The user is").
        - START directly with the verb or subject (e.g. "Editing file", "Watching video").
        - Max 10 words.
        """
        
        return try await generate(prompt: prompt, maxTokens: 30)
    }
    
    /// Batch summarize multiple window activities in a single LLM call
    /// Returns an array of summaries in the same order as the input
    func batchSummarizeActivities(_ activities: [(appName: String, windowTitle: String, ocrText: String)]) async throws -> [String] {
        guard !activities.isEmpty else { return [] }
        
        // For a single activity, use the existing method
        if activities.count == 1 {
            let single = activities[0]
            let summary = try await summarizeScreenContent(text: single.ocrText, appName: single.appName)
            return [summary]
        }
        
        // Build a numbered list of activities
        var activityList = ""
        for (index, activity) in activities.enumerated() {
            let truncatedText = String(activity.ocrText.prefix(300))
            activityList += "\(index + 1). [App: \(activity.appName)] Window: \(activity.windowTitle)\n   Text: \(truncatedText)\n\n"
        }
        
        let prompt = """
        Summarize each of these \(activities.count) application activities into a brief description (max 10 words each).

        Activities:
        \(activityList)
        
        Rules:
        - Output ONLY a JSON array of strings, one summary per activity.
        - START each summary directly with a verb or subject (e.g. "Editing file", "Browsing docs").
        - NO conversational filler.
        - Return exactly \(activities.count) summaries.
        
        Example output: ["Editing Swift file in Xcode", "Reading Stack Overflow answers"]
        """
        
        let response = try await generate(prompt: prompt, maxTokens: activities.count * 30)
        
        // Try to parse as JSON array
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rangeStart = trimmed.firstIndex(of: "["),
           let rangeEnd = trimmed.lastIndex(of: "]") {
            let jsonString = String(trimmed[rangeStart...rangeEnd])
            if let data = jsonString.data(using: .utf8),
               let summaries = try? JSONSerialization.jsonObject(with: data) as? [String],
               summaries.count == activities.count {
                return summaries
            }
        }
        
        // Fallback: if batch parsing fails, fall back to individual calls
        var fallbackSummaries: [String] = []
        for activity in activities {
            let summary = (try? await summarizeScreenContent(text: activity.ocrText, appName: activity.appName))
                ?? (activity.windowTitle.isEmpty ? activity.appName : activity.windowTitle)
            fallbackSummaries.append(summary)
        }
        return fallbackSummaries
    }
    
    /// Generate text using Ollama
    private func generate(prompt: String, maxTokens: Int = 500) async throws -> String {
        let url = URL(string: "\(baseURL)/api/generate")!
        
        let requestBody: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": 0.3,
                "num_predict": maxTokens,
                "top_p": 0.9
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LLMError.requestFailed
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw LLMError.invalidResponse
        }
        
        return responseText
    }
    
    /// Check if Ollama is running
    func checkConnection() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            return false
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    private func formatEventsAsContext(_ events: [Event]) -> String {
        guard !events.isEmpty else {
            return "[DATA]\nNo events recorded yet.\n[/DATA]"
        }
        
        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        
        // Group events by day
        let groupedEvents = Dictionary(grouping: sortedEvents) { event in
            calendar.startOfDay(for: event.timestamp)
        }
        
        let sortedDays = groupedEvents.keys.sorted()
        
        var context = "[DATA]\n"
        context += "Today's date: \(formatDate(Date()))\n\n"
        
        for date in sortedDays {
            guard let dayEvents = groupedEvents[date] else { continue }
            
            let activeTime = calculateDuration(events: dayEvents)
            let formattedDuration = formatDuration(activeTime)
            
            // App usage breakdown
            var appCounts: [String: Int] = [:]
            for event in dayEvents {
                appCounts[event.source, default: 0] += 1
            }
            let topApps = appCounts.sorted { $0.value > $1.value }.prefix(5)
            
            // Project breakdown
            var projectCounts: [String: Int] = [:]
            for event in dayEvents {
                if let project = event.projectName, !project.isEmpty {
                    projectCounts[project, default: 0] += 1
                }
            }
            let topProjects = projectCounts.sorted { $0.value > $1.value }.prefix(5)
            
            // Day header
            context += "=== \(formatDate(date)) ===\n"
            context += "Active Time: \(formattedDuration)\n"
            context += "Events: \(dayEvents.count)\n"
            
            if !topApps.isEmpty {
                context += "Apps: \(topApps.map { "\($0.key)(\($0.value))" }.joined(separator: ", "))\n"
            }
            if !topProjects.isEmpty {
                context += "Projects: \(topProjects.map { "\($0.key)(\($0.value))" }.joined(separator: ", "))\n"
            }
            
            // Individual event log (capped at 50 per day)
            context += "\nEvent Log:\n"
            for event in dayEvents.prefix(50) {
                let time = timeFormatter.string(from: event.timestamp)
                let app = event.source
                let window = event.windowName ?? ""
                let desc = event.text.prefix(80)
                let project = event.projectName ?? ""
                
                context += "  [\(time)] \(app)"
                if !window.isEmpty { context += " | \(window)" }
                if !project.isEmpty { context += " | proj:\(project)" }
                context += " — \(desc)\n"
            }
            if dayEvents.count > 50 {
                context += "  ... and \(dayEvents.count - 50) more events\n"
            }
            context += "\n"
        }
        
        context += "[/DATA]"
        return context
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    /// Calculate active work time by summing gaps between consecutive events.
    /// Only gaps shorter than 30 minutes count as active time.
    private func calculateDuration(events: [Event]) -> TimeInterval {
        guard events.count > 1 else { return 0 }
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var activeTime: TimeInterval = 0
        let maxGap: TimeInterval = 1800 // 30 minutes
        
        for i in 1..<sorted.count {
            let gap = sorted[i].timestamp.timeIntervalSince(sorted[i-1].timestamp)
            if gap < maxGap {
                activeTime += gap
            }
        }
        return activeTime
    }
    
    /// Format time interval into human-readable string
    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        } else {
            return "\(minutes)m"
        }
    }
    
    private var systemPrompt: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .none
        let todayStr = dateFormatter.string(from: Date())
        
        return """
        You are ECHO, a productivity assistant built into a macOS app that tracks the user's screen activity.
        Today is \(todayStr).
        
        ## CONTEXT
        You have access to the user's activity data — which apps they used, what windows were open, what was on screen, and when. Use this to answer their questions naturally, like a personal assistant who was watching over their shoulder.
        
        The data includes a pre-calculated time value per day (shown as "Active Time" in the data) — use this number directly for any "how long did I work" questions. Do NOT try to calculate time yourself.
        
        ## CRITICAL RULES
        1. NEVER mention internal terms like "events", "captures", "Active Time", "Event Log", "OCR", or "data block" in your response. The user doesn't know how the system works — just answer naturally.
        2. NEVER invent activities, apps, files, or times that aren't in the data.
        3. If you don't have data for something, say "I don't have that recorded" — don't guess.
        4. "today" = \(todayStr). "yesterday" = the day before.
        
        ## HOW TO ANSWER
        - **Duration questions** ("how long did I work?"): State the time, then break down where it was spent (which apps, which projects). Don't mention event counts.
        - **Activity questions** ("what was I doing?"): Describe the actual work — files edited, pages visited, tools used. Group by activity, not by raw timestamp.
        - **Specific time questions** ("what was I doing at 3pm?"): Find the closest matching entries and describe them.
        - **Productivity questions** ("how productive was I?"): Give a qualitative assessment based on time distribution across apps and projects.
        
        ## RESPONSE STYLE
        - Lead with a direct answer, then add useful detail.
        - Describe activities in terms the user understands: "editing Swift files in Xcode", not "3 coding events detected."
        - Use **bold** for app names, project names, and time values.
        - Be warm, specific, and helpful. No generic filler.
        - Aim for 50-120 words. Go longer only if the user asks for detail.
        
        ## EXAMPLES
        
        User: How long did I work today?
        ECHO: You put in about **3 hours 40 minutes** today. Most of that was development work — you spent roughly 2 hours in **Xcode** working on the **Project-Echo** codebase, about an hour in **Chrome** (looks like Stack Overflow and GitHub), and a quick stretch in **Slack** around midday.
        
        User: What was I working on this afternoon?
        ECHO: After lunch you were deep in code:
        - **1:15–2:30 PM**: Editing **ActivityManager.swift** and **LLMService.swift** in **Xcode**
        - **2:35–2:50 PM**: Looking up SwiftData documentation on **Stack Overflow**
        - **2:55–3:10 PM**: Testing the app and checking the timeline view
        Solid focused session! 💪
        
        User: Did I use Slack today?
        ECHO: No **Slack** activity today. The only messaging I see is a quick check of **Messages** around 11:30 AM.
        
        User: Summarize my productivity this week.
        ECHO: You've been consistently active this week, averaging about **3–4 hours** of focused work per day. **Xcode** has been your main tool, with most time spent on the **Project-Echo** codebase. Tuesday was your most productive day at **5h 12m**, while Thursday was lighter at **1h 45m**. You've been in a strong development groove — mostly coding with occasional research breaks in Chrome.
        """
    }
}

enum LLMError: LocalizedError {
    case requestFailed
    case invalidResponse
    case ollamaNotRunning
    
    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Failed to connect to Ollama. Make sure Ollama is running."
        case .invalidResponse:
            return "Received invalid response from Ollama."
        case .ollamaNotRunning:
            return "Ollama is not running. Please start Ollama first."
        }
    }
}
