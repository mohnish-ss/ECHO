import Foundation
import MLXLMCommon
import MLXHuggingFace

/// Native LLM Service using Apple's MLX for 100% on-device inference without external tools like Ollama.
@Observable
class NativeLLMService {
    var isProcessing = false
    var lastError: String?
    
    // The specific model we want to pull from HuggingFace
    private let modelID = "mlx-community/Llama-3.2-3B-Instruct-4bit"
    
    // We keep the model and tokenizer in memory once loaded
    private var modelContainer: ModelContainer?
    
    /// Loads the model into memory. Downloads it from HuggingFace on the first run.
    private func loadModelIfNeeded() async throws -> ModelContainer {
        if let container = modelContainer { return container }
        
        let config = ModelConfiguration(id: modelID)
        let container = try await loadModelContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: config
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
    
    /// Classify activity into project with category
    func classifyProject(event: Event, existingProjects: [String]) async throws -> (name: String, category: String) {
        let existingList = existingProjects.isEmpty ? "None yet" : existingProjects.joined(separator: ", ")
        
        let safeContent = event.text.prefix(500).replacingOccurrences(of: "\n", with: " ")
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
    
    // MARK: - Formatting Helpers
    
    private let systemPrompt = """
    You are ECHO, a deeply integrated, highly intelligent personal productivity assistant. 
    Your entire purpose is to help the user understand how they spend their time on their computer, answer questions about their past activity, and recall information they've seen.
    
    You will be provided with a log of the user's computer activity. Each event represents a snapshot of what was on their screen.
    Use this data to answer their questions precisely and concisely.
    If you don't know the answer based on the activity data, politely state that you cannot find that information in the recent logs.
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
        context += "Today's date: \(formatDate(Date()))\n\n"
        
        for date in sortedDays {
            guard let dayEvents = groupedEvents[date] else { continue }
            
            let activeTime = calculateDuration(events: dayEvents)
            let formattedDuration = formatDuration(activeTime)
            
            context += "=== \(formatDate(date)) ===\n"
            context += "Active Time: \(formattedDuration)\n"
            context += "Events: \(dayEvents.count)\n"
            
            context += "\nEvent Log:\n"
            for event in dayEvents.prefix(50) {
                let time = timeFormatter.string(from: event.timestamp)
                let app = event.source
                let window = event.windowName ?? ""
                let desc = event.text.prefix(80).replacingOccurrences(of: "\n", with: " ")
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
