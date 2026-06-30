import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Native LLM Service using Apple's MLX for 100% on-device inference without external tools like Ollama.
@Observable
class NativeLLMService {
    var isProcessing = false
    var lastError: String?
    
    // The specific model we want to pull from HuggingFace.
    private let modelConfiguration = LLMRegistry.llama3_2_3B_4bit
    
    // We keep the model and tokenizer in memory once loaded
    private var modelContainer: ModelContainer?
    
    /// Loads the model into memory. Downloads it from HuggingFace on the first run.
    private func loadModelIfNeeded() async throws -> ModelContainer {
        if let container = modelContainer { return container }
        
        let container = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: modelConfiguration
        ) { progress in
            // You can optionally broadcast this progress to the UI later!
            print("Downloading Llama 3.2: \(Int(progress.fractionCompleted * 100))%")
        }
        
        self.modelContainer = container
        return container
    }
    
    /// Generates text using the native MLX model
    private func generate(prompt: String, maxTokens: Int = 800) async throws -> String {
        let container = try await loadModelIfNeeded()
        
        // Create a ChatSession to manage generation
        var params = GenerateParameters()
        params.maxTokens = maxTokens
        let session = ChatSession(container, generateParameters: params)
        
        // Note: Llama-3.2 has a specific instruction format, but ChatSession usually handles 
        // applying the chat template if you pass it structured messages. For raw prompts, respond(to:) works great.
        let response = try await session.respond(to: prompt)
        return response
    }

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

    /// Compatibility API for views that used to check an Ollama daemon.
    /// The native MLX service has no external server connection to probe.
    func checkConnection() async -> Bool {
        true
    }

    /// Summarize multiple captured window activities in one model call.
    func batchSummarizeActivities(_ activities: [(appName: String, windowTitle: String, ocrText: String)]) async throws -> [String] {
        guard !activities.isEmpty else { return [] }

        isProcessing = true
        defer { isProcessing = false }

        let fallbackSummaries = activities.map { activity in
            fallbackSummary(
                appName: activity.appName,
                windowTitle: activity.windowTitle,
                ocrText: activity.ocrText
            )
        }

        let activityList = activities.enumerated().map { index, activity in
            """
            \(index + 1).
            App: \(activity.appName)
            Window: \(activity.windowTitle.isEmpty ? "Unknown" : activity.windowTitle)
            OCR: \(activity.ocrText.prefix(800).replacingOccurrences(of: "\n", with: " "))
            """
        }.joined(separator: "\n\n")

        let prompt = """
        Convert each OCR-backed screen capture into a concise productivity activity label.

        Rules:
        - Return strictly valid JSON only.
        - The JSON must be an object with a "summaries" array.
        - The array must contain exactly \(activities.count) strings in the same order.
        - Each summary should be 4-12 words.
        - Use the OCR text as the main evidence. Prefer concrete files, pages, code symbols, documents, assignments, tickets, or project names visible in OCR.
        - Do not summarize as a generic app action when OCR reveals the real task.
        - If OCR is empty or unreadable, use the window title and app as the fallback.
        - Do not invent work that is not visible in the OCR, window title, or app.

        Activities:
        \(activityList)

        JSON:
        """

        let response = try await generate(prompt: prompt, maxTokens: max(120, activities.count * 40))
        return parseSummaries(from: response, expectedCount: activities.count) ?? fallbackSummaries
    }
    
    /// Classify activity into project with category
    func classifyProject(event: Event, existingProjects: [String]) async throws -> (name: String, category: String) {
        let existingList = existingProjects.isEmpty ? "None yet" : existingProjects.joined(separator: ", ")
        
        let combinedContent = [event.text, event.ocrText ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let safeContent = combinedContent.prefix(900).replacingOccurrences(of: "\n", with: " ")
        let prompt = """
        Classify this computer activity into a Project and Category.

        Activity:
        - App: \(event.source)
        - Window: \(event.windowName ?? "Unknown")
        - Content: \(safeContent)

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

    private struct ActivitySummariesResponse: Decodable {
        let summaries: [String]
    }

    private func parseSummaries(from response: String, expectedCount: Int) -> [String]? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        if let objectStart = trimmed.firstIndex(of: "{"),
           let objectEnd = trimmed.lastIndex(of: "}") {
            let jsonString = String(trimmed[objectStart...objectEnd])
            if let data = jsonString.data(using: .utf8),
               let payload = try? JSONDecoder().decode(ActivitySummariesResponse.self, from: data),
               payload.summaries.count == expectedCount {
                return payload.summaries.map(cleanSummary)
            }
        }

        if let arrayStart = trimmed.firstIndex(of: "["),
           let arrayEnd = trimmed.lastIndex(of: "]") {
            let jsonString = String(trimmed[arrayStart...arrayEnd])
            if let data = jsonString.data(using: .utf8),
               let summaries = try? JSONDecoder().decode([String].self, from: data),
               summaries.count == expectedCount {
                return summaries.map(cleanSummary)
            }
        }

        let lineSummaries = trimmed
            .components(separatedBy: .newlines)
            .map(cleanNumberedSummaryLine)
            .filter { !$0.isEmpty }

        if lineSummaries.count >= expectedCount {
            return Array(lineSummaries.prefix(expectedCount))
        }

        return nil
    }

    private func cleanSummary(_ summary: String) -> String {
        summary
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private func cleanNumberedSummaryLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.replacingOccurrences(
            of: #"^\s*[-*]?\s*\d+[\).:-]?\s*"#,
            with: "",
            options: .regularExpression
        )
        return cleanSummary(cleaned)
    }

    private func fallbackSummary(appName: String, windowTitle: String, ocrText: String) -> String {
        let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }

        let text = ocrText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return String(text.prefix(120))
        }

        return appName
    }
    
    // MARK: - Formatting Helpers
    
    private let systemPrompt = """
    You are ECHO, a local productivity analyst. Your job is to answer questions about the user's computer productivity using only the provided activity log.

    The activity log is built from screenshots, OCR text, active apps, window titles, timestamps, and project labels. Treat OCR snippets as primary evidence because they show what was actually visible on screen.

    Response rules:
    - Stay grounded in the activity data. Do not infer facts that are not supported by app, window, project, timestamp, summary, or OCR evidence.
    - For productivity questions, mention concrete evidence: times, apps, projects, windows, and OCR-visible task names when available.
    - Prefer useful synthesis over generic encouragement: identify focused work, context switching, likely distractions, long gaps, repeated apps, and visible deliverables.
    - If the data is sparse, say exactly what is missing, such as "I only have one OCR-backed event" or "I do not see enough screenshots to estimate that."
    - If the answer is not in the logs, say you cannot find it in the captured activity data.
    - Keep answers concise unless the user asks for a detailed breakdown.
    """
    
    private func formatEventsAsContext(_ events: [Event]) -> String {
        guard !events.isEmpty else {
            return "[DATA]\nNo events recorded yet.\n[/DATA]"
        }
        
        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        
        let groupedEvents = Dictionary(grouping: sortedEvents) { event in
            calendar.startOfDay(for: event.timestamp)
        }
        
        let sortedDays = groupedEvents.keys.sorted()
        
        var context = "[DATA]\n"
        let ocrBackedCount = sortedEvents.filter { event in
            guard let ocrText = event.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !ocrText.isEmpty
        }.count

        context += "Today's date: \(formatDate(Date()))\n"
        context += "Total events: \(sortedEvents.count)\n"
        context += "OCR-backed screenshot events: \(ocrBackedCount)\n\n"
        
        for date in sortedDays {
            guard let dayEvents = groupedEvents[date] else { continue }
            
            let activeTime = calculateDuration(events: dayEvents)
            let formattedDuration = formatDuration(activeTime)
            
            context += "=== \(formatDate(date)) ===\n"
            context += "Active Time: \(formattedDuration)\n"
            context += "Events: \(dayEvents.count)\n"
            context += "OCR-backed Events: \(dayEvents.filter { ($0.ocrText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }.count)\n"
            
            context += "\nEvent Log:\n"
            for event in dayEvents.prefix(50) {
                let time = timeFormatter.string(from: event.timestamp)
                let app = event.source
                let window = event.windowName ?? ""
                let desc = event.text.prefix(140).replacingOccurrences(of: "\n", with: " ")
                let ocrSnippet = event.ocrText?
                    .prefix(360)
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let project = event.projectName ?? ""
                
                context += "  [\(time)] \(app)"
                if !window.isEmpty { context += " | \(window)" }
                if !project.isEmpty { context += " | proj:\(project)" }
                context += " | type:\(event.type)"
                context += " | summary: \(desc)\n"
                if let ocrSnippet, !ocrSnippet.isEmpty, ocrSnippet != desc {
                    context += "    OCR evidence: \(ocrSnippet)\n"
                }
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
    
    private func calculateDuration(events: [Event]) -> TimeInterval {
        guard events.count > 1 else { return 0 }
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var activeTime: TimeInterval = 0
        let maxGap: TimeInterval = 1800
        
        for i in 1..<sorted.count {
            let gap = sorted[i].timestamp.timeIntervalSince(sorted[i-1].timestamp)
            if gap < maxGap {
                activeTime += gap
            }
        }
        return activeTime
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
