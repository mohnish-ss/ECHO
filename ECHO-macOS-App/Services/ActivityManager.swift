import Foundation
import SwiftData
import SwiftUI

// MARK: - Data Models

/// Statistics for a single day's activity
struct DailyStats {
    var hours: Double = 0
    var projects: Int = 0
    var files: Int = 0
    var events: Int = 0
}

/// Lightweight capture metadata (no NSImage retained in memory)
struct PendingCapture: Identifiable {
    let id = UUID()
    let timestamp: Date
    let windowSnapshots: [WindowSnapshot]
}

/// A snapshot of a single window's state at capture time
struct WindowSnapshot: Identifiable {
    let id = UUID()
    let appName: String
    let windowTitle: String
    let ocrTextContent: String  // Pre-joined OCR text
    let textCount: Int
    
    /// Key used for deduplication (app + title)
    var deduplicationKey: String {
        "\(appName)_\(windowTitle)"
    }
    
    /// Simple content hash for detecting identical screen contents
    var contentHash: Int {
        ocrTextContent.prefix(200).hashValue
    }
}

// MARK: - Activity Manager

/// Manages activity tracking and statistics
/// 
/// **Backend Integration Guide:**
/// 1. Use `addEvent()` to insert new activity events
/// 2. Call `fetchTodayEvents()` to refresh the event list
/// 3. Access `events` array to display recent activity
/// 4. Access `stats` to display daily statistics
/// 5. Use `isTracking` to control tracking state
/// 6. Use `performScreenCapture()` to trigger OCR and window mapping
@Observable
class ActivityManager {
    // MARK: - Public Properties
    
    /// Array of all events for today
    var events: [Event] = []
    
    /// Calculated statistics for today
    var stats: DailyStats = DailyStats()
    
    /// Currently active file (set by your backend)
    var currentFile: String = ""
    
    /// Currently active project (set by your backend)
    var currentProject: String = ""
    
    /// Whether tracking is currently active
    var isTracking: Bool = false
    
    // OCR-related properties
    /// Latest OCR results from screen capture
    var ocrResults: [OCRResult] = []
    
    /// Latest mapped windows with their contained text
    var mappedWindows: [MappedWindow] = []
    
    /// Latest captured screenshot
    var capturedImage: NSImage?
    
    // Automatic capture properties
    /// Whether automatic capture is currently active
    var isAutoCapturing: Bool = UserDefaults.standard.bool(forKey: "isAutoCapturing") {
        didSet {
            UserDefaults.standard.set(isAutoCapturing, forKey: "isAutoCapturing")
        }
    }
    
    /// Capture interval in seconds (default: 5 seconds, range: 5s - 1min)
    var captureInterval: TimeInterval = 5
    
    /// Whether to automatically generate events from captures (persistent)
    var autoGenerateEvents: Bool {
        get {
            if UserDefaults.standard.object(forKey: "autoGenerateEvents") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "autoGenerateEvents")
        }
        set { UserDefaults.standard.set(newValue, forKey: "autoGenerateEvents") }
    }
    
    // Pending captures (before compilation)
    /// Array of lightweight capture metadata pending compilation
    var pendingCaptures: [PendingCapture] = []
    
    /// Count of pending captures ready to be compiled
    var pendingCount: Int {
        pendingCaptures.count
    }
    
    /// Whether auto-compilation is in progress
    var isCompiling: Bool = false
    
    // MARK: - Private Properties
    
    private var modelContext: ModelContext?
    private let ocrEngine = OCREngine()
    private let windowManager = WindowManager()
    private var captureTask: Task<Void, Never>?
    
    // LLM and project detection
    private var llmService: NativeLLMService?
    private var projectDetectionService: ProjectDetectionService?
    
    // Track recent events to prevent duplicates
    private var recentEventKeys: Set<String> = []
    private let deduplicationWindow: TimeInterval = 300 // 5 minutes
    
    // Auto-compilation thresholds
    private let autoCompileThreshold = 20
    private let autoCompileTimeInterval: TimeInterval = 120 // 2 minutes
    private var firstPendingTimestamp: Date?
    
    // MARK: - Initialization
    
    init() {}
    
    /// Configure the manager with a SwiftData context
    /// - Parameter context: The ModelContext for data persistence
    func configure(with context: ModelContext) {
        self.modelContext = context
        fetchTodayEvents()
        startManualTracking()
        
        // Restore tracking state from UserDefaults
        if isAutoCapturing {
            Task { @MainActor in
                self.startTracking()
            }
        }
        
        // Initialize LLM services
        initializeLLMServices()
    }
    
    /// Initialize LLM and project detection services
    private func initializeLLMServices() {
        llmService = NativeLLMService()
        if let llmService = llmService {
            projectDetectionService = ProjectDetectionService(llmService: llmService)
        }
    }
    
    // MARK: - Tracking Control
    
    /// Start activity tracking
    func startManualTracking() {
        isTracking = true
        // TODO: Backend team - implement your tracking logic here
    }
    
    /// Stop activity tracking
    func stopManualTracking() {
        isTracking = false
        // TODO: Backend team - implement your tracking cleanup here
    }
    
    // MARK: - Event Management (see OCR Methods section for enhanced addEvent)
    
    /// Clear all events and projects from the database (useful for testing/development)
    func clearAllEvents() {
        guard let context = modelContext else {
            print("⚠️ ModelContext not configured")
            return
        }
        
        do {
            try context.delete(model: Event.self)
            try context.delete(model: Project.self)
            events.removeAll()
            recalculateStats()
            print("✅ All events and projects cleared")
        } catch {
            print("❌ Failed to clear data: \(error)")
        }
    }
    
    /// Fetch all events for today from the database
    func fetchTodayEvents() {
        guard let context = modelContext else { return }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = #Predicate<Event> { event in
            event.timestamp >= startOfDay && event.timestamp < endOfDay
        }
        
        let descriptor = FetchDescriptor<Event>(predicate: predicate, sortBy: [SortDescriptor(\.timestamp)])
        
        do {
            events = try context.fetch(descriptor)
            recalculateStats()
        } catch {
            print("❌ Failed to fetch events: \(error)")
        }
    }
    
    // MARK: - Statistics Calculation
    
    /// Recalculate daily statistics based on current events
    private func recalculateStats() {
        if events.isEmpty {
            stats = DailyStats()
            return
        }
        
        // Calculate total active hours
        var totalSeconds: TimeInterval = 0
        if events.count > 1 {
            let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
            
            for i in 0..<sortedEvents.count - 1 {
                let diff = sortedEvents[i+1].timestamp.timeIntervalSince(sortedEvents[i].timestamp)
                // Only count gaps less than 1 hour as continuous work
                if diff < 60 * 60 {
                    totalSeconds += diff
                }
            }
        }
        
        let hours = totalSeconds / 3600.0
        let uniqueProjects = Set(events.map { $0.source }).count
        let uniqueFiles = Set(events.map { $0.text }).count
        
        stats = DailyStats(
            hours: (hours * 10).rounded() / 10,
            projects: uniqueProjects,
            files: uniqueFiles,
            events: events.count
        )
    }
    
    // MARK: - Statistics Calculation
    
    /// Calculate total hours tracked across all events using gap-based active time
    func calculateTotalHours() -> Double {
        guard !events.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        let eventsByDay = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.timestamp)
        }
        
        var totalHours = 0.0
        let maxGap: TimeInterval = 1800 // 30 minutes
        
        for (_, dayEvents) in eventsByDay {
            let sorted = dayEvents.sorted { $0.timestamp < $1.timestamp }
            for i in 1..<sorted.count {
                let gap = sorted[i].timestamp.timeIntervalSince(sorted[i-1].timestamp)
                if gap < maxGap {
                    totalHours += gap / 3600.0
                }
            }
        }
        
        return totalHours
    }
    
    /// Calculate hours worked this week using gap-based active time
    func calculateWeeklyHours() -> Double {
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
            return 0
        }
        
        let weekEvents = events.filter { $0.timestamp >= weekStart }
        let eventsByDay = Dictionary(grouping: weekEvents) { event in
            calendar.startOfDay(for: event.timestamp)
        }
        
        var weeklyHours = 0.0
        let maxGap: TimeInterval = 1800
        
        for (_, dayEvents) in eventsByDay {
            let sorted = dayEvents.sorted { $0.timestamp < $1.timestamp }
            for i in 1..<sorted.count {
                let gap = sorted[i].timestamp.timeIntervalSince(sorted[i-1].timestamp)
                if gap < maxGap {
                    weeklyHours += gap / 3600.0
                }
            }
        }
        
        return weeklyHours
    }
    
    /// Calculate active hours for each day of the current week (Mon=0, Sun=6)
    func calculateDailyHoursThisWeek() -> [Double] {
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
            return Array(repeating: 0, count: 7)
        }
        
        var dailyHours = Array(repeating: 0.0, count: 7)
        let weekEvents = events.filter { $0.timestamp >= weekStart }
        let maxGap: TimeInterval = 1800
        
        let eventsByDay = Dictionary(grouping: weekEvents) { event in
            calendar.startOfDay(for: event.timestamp)
        }
        
        for (dayStart, dayEvents) in eventsByDay {
            // Get weekday index (Mon=0, Sun=6)
            let weekday = calendar.component(.weekday, from: dayStart)
            // Calendar.weekday: 1=Sun, 2=Mon, ... 7=Sat → convert to Mon=0
            let index = weekday == 1 ? 6 : weekday - 2
            
            let sorted = dayEvents.sorted { $0.timestamp < $1.timestamp }
            var hours = 0.0
            for i in 1..<sorted.count {
                let gap = sorted[i].timestamp.timeIntervalSince(sorted[i-1].timestamp)
                if gap < maxGap {
                    hours += gap / 3600.0
                }
            }
            if index >= 0 && index < 7 {
                dailyHours[index] = hours
            }
        }
        
        return dailyHours
    }
    
    /// Calculate consecutive days with activity (work streak)
    func calculateWorkStreak() -> Int {
        let calendar = Calendar.current
        var streak = 0
        var currentDate = calendar.startOfDay(for: Date())
        
        // Get all unique days with events
        let daysWithEvents = Set(events.map { event in
            calendar.startOfDay(for: event.timestamp)
        })
        
        // Count backwards from today
        while daysWithEvents.contains(currentDate) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                break
            }
            currentDate = previousDay
        }
        
        return streak
    }
    
    /// Get events for a specific date
    func getEvents(for date: Date) -> [Event] {
        let calendar = Calendar.current
        return events.filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
    }
    
    // MARK: - Automatic Capture Control
    
    /// Start automatic screen capture at the configured interval
    @MainActor
    func startTracking() {
        guard captureTask == nil else { return }  // Only skip if task is already running
        
        isAutoCapturing = true
        
        captureTask = Task { @MainActor in
            while !Task.isCancelled {
                await self.performAutomaticCapture()
                try? await Task.sleep(nanoseconds: UInt64(self.captureInterval * 1_000_000_000))
            }
        }
        
        print("✅ Tracking started (interval: \(captureInterval)s)")
    }
    
    /// Stop automatic screen capture
    @MainActor
    func stopTracking() {
        guard isAutoCapturing else { return }
        
        isAutoCapturing = false
        captureTask?.cancel()
        captureTask = nil
        
        print("⏹️ Tracking stopped")
    }
    
    /// Update the capture interval and restart timer if active
    @MainActor
    func updateCaptureInterval(_ interval: TimeInterval) {
        captureInterval = interval
        
        if isAutoCapturing {
            stopTracking()
            startTracking()
        }
    }
    
    /// Perform automatic capture and store lightweight metadata for later compilation
    @MainActor
    private func performAutomaticCapture() async {
        await performScreenCapture()
        
        guard !mappedWindows.isEmpty else { return }
        
        // Convert to lightweight snapshots immediately — no NSImage retained
        // Take top 3 windows by text content (not just the primary)
        let topWindows = mappedWindows.prefix(3)
        let snapshots = topWindows.map { mapped in
            WindowSnapshot(
                appName: mapped.window.ownerName,
                windowTitle: mapped.window.windowTitle,
                ocrTextContent: mapped.containedText.map { $0.text }.joined(separator: "\n"),
                textCount: mapped.containedText.count
            )
        }
        
        let capture = PendingCapture(
            timestamp: Date(),
            windowSnapshots: Array(snapshots)
        )
        pendingCaptures.append(capture)
        
        // Track first pending timestamp for auto-compile
        if firstPendingTimestamp == nil {
            firstPendingTimestamp = Date()
        }
        
        print("📸 Capture stored (\(pendingCount) pending, \(snapshots.count) windows)")
        
        // Auto-compile if threshold reached
        let timeSinceFirst = Date().timeIntervalSince(firstPendingTimestamp ?? Date())
        if autoGenerateEvents && (pendingCount >= autoCompileThreshold || timeSinceFirst >= autoCompileTimeInterval) {
            print("⚡ Auto-compile triggered (count: \(pendingCount), elapsed: \(Int(timeSinceFirst))s)")
            compilePendingCaptures()
        }
    }
    
    /// Compile all pending captures into deduplicated events with batched LLM summarization
    @MainActor
    func compilePendingCaptures() {
        Task {
            await compilePendingCapturesAndWait()
        }
    }

    /// Compile any pending OCR captures before a query reads activity context.
    @MainActor
    func prepareActivityContextForQuery() async {
        if isCompiling {
            await waitForCompilation()
        }

        guard autoGenerateEvents, !pendingCaptures.isEmpty else {
            fetchTodayEvents()
            return
        }

        await compilePendingCapturesAndWait()
    }

    @MainActor
    private func compilePendingCapturesAndWait() async {
        guard !pendingCaptures.isEmpty, !isCompiling else {
            if pendingCaptures.isEmpty {
                print("⚠️ No captures to compile")
            }
            return
        }
        
        isCompiling = true
        let capturesToProcess = pendingCaptures
        let totalCount = capturesToProcess.count
        print("🔄 Compiling \(totalCount) captures...")
        
        // Clear immediately to allow new captures during compilation
        pendingCaptures.removeAll()
        firstPendingTimestamp = nil

        // Step 1: Deduplicate — group all window snapshots by key, keep latest per unique state
        let uniqueWindows = deduplicateWindowSnapshots(from: capturesToProcess)
        print("📦 Grouped \(totalCount) captures into \(uniqueWindows.count) unique window states")

        // Step 1.5: Merge similar windows from the same app (e.g. multiple Chrome tabs about the same topic)
        let mergedWindows = mergeSimilarWindows(uniqueWindows)
        if mergedWindows.count < uniqueWindows.count {
            print("🔗 Merged \(uniqueWindows.count) windows → \(mergedWindows.count) (consolidated similar content)")
        }

        // Step 2: Batch LLM summarization — one call for all unique windows
        let summaries = await batchSummarize(windows: mergedWindows)

        // Step 3: Create events from summaries while preserving raw OCR text
        for (index, window) in mergedWindows.enumerated() {
            let summary = index < summaries.count ? summaries[index] : window.windowTitle
            let eventType = determineEventType(for: window.appName)
            let meta = "{\"textCount\":\(window.textCount),\"deduplicated\":true,\"ocrBacked\":true}"

            addEvent(
                source: window.appName,
                type: eventType,
                text: summary,
                meta: meta,
                windowName: window.windowTitle,
                ocrText: String(window.ocrTextContent.prefix(4000)),
                skipRecalculate: true
            )
        }

        if let context = modelContext {
            do {
                try context.save()
            } catch {
                print("❌ Failed to save compiled OCR events: \(error)")
            }
        }

        // Step 4: Project detection
        await detectProjectsForRecentEvents()

        fetchTodayEvents()
        isCompiling = false
        print("✅ Compilation complete! \(totalCount) captures → \(uniqueWindows.count) events")
    }

    @MainActor
    private func waitForCompilation() async {
        while isCompiling {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    // Legacy API compatibility — SidebarView calls this name
    @MainActor
    func compilePendingScreenshots() {
        compilePendingCaptures()
    }
    
    // MARK: - Compilation Helpers
    
    /// Deduplicate window snapshots with dwell-time filtering.
    /// Windows the user stayed on for < 2 captures (~10 seconds) are considered transient tab switches and excluded.
    private func deduplicateWindowSnapshots(from captures: [PendingCapture]) -> [WindowSnapshot] {
        // Track how many captures each window key appeared in (dwell-time proxy)
        var appearanceCount: [String: Int] = [:]
        var latestByKey: [String: WindowSnapshot] = [:]
        var seenContentHashes: Set<Int> = []
        
        // Process in chronological order so later captures overwrite earlier
        for capture in captures.sorted(by: { $0.timestamp < $1.timestamp }) {
            for snapshot in capture.windowSnapshots {
                let key = snapshot.deduplicationKey
                let contentHash = snapshot.contentHash
                
                // Count every appearance (even duplicate content) for dwell-time
                appearanceCount[key, default: 0] += 1
                
                // Skip if we've already seen identical content for this window
                let combinedHash = key.hashValue ^ contentHash
                if seenContentHashes.contains(combinedHash) {
                    continue
                }
                seenContentHashes.insert(combinedHash)
                
                // Keep the latest snapshot per unique key
                latestByKey[key] = snapshot
            }
        }
        
        // Filter out transient windows (appeared in < 2 captures ≈ < 10 seconds)
        let minDwellCount = 2
        let dwellFiltered = latestByKey.filter { key, _ in
            let count = appearanceCount[key] ?? 0
            return count >= minDwellCount
        }
        
        let filteredOut = latestByKey.count - dwellFiltered.count
        if filteredOut > 0 {
            print("🔇 Filtered \(filteredOut) transient window(s) (< \(minDwellCount) captures)")
        }
        
        // Also filter against recent event keys to prevent cross-compile duplicates
        return dwellFiltered.values.filter { snapshot in
            let key = snapshot.deduplicationKey
            if recentEventKeys.contains(key) {
                return false
            }
            // Mark as processed
            recentEventKeys.insert(key)
            // Schedule cleanup
            Task {
                try? await Task.sleep(nanoseconds: UInt64(deduplicationWindow * 1_000_000_000))
                await MainActor.run {
                    _ = recentEventKeys.remove(key)
                }
            }
            return true
        }
    }
    
    /// Merge windows from the same app that have highly similar content.
    /// Uses word-overlap (Jaccard similarity) to detect when multiple windows/tabs are about the same topic.
    private func mergeSimilarWindows(_ windows: [WindowSnapshot]) -> [WindowSnapshot] {
        guard windows.count > 1 else { return windows }
        
        // Group by app name — only merge within the same app
        let byApp = Dictionary(grouping: windows) { $0.appName }
        var result: [WindowSnapshot] = []
        
        for (_, appWindows) in byApp {
            if appWindows.count <= 1 {
                result.append(contentsOf: appWindows)
                continue
            }
            
            // Build clusters of similar windows
            var merged: [Bool] = Array(repeating: false, count: appWindows.count)
            var clusters: [[Int]] = []
            
            for i in 0..<appWindows.count {
                if merged[i] { continue }
                var cluster = [i]
                merged[i] = true
                
                let wordsI = extractWords(from: appWindows[i].ocrTextContent)
                guard wordsI.count >= 3 else {
                    // Too little text to compare — keep as-is
                    clusters.append(cluster)
                    continue
                }
                
                for j in (i+1)..<appWindows.count {
                    if merged[j] { continue }
                    let wordsJ = extractWords(from: appWindows[j].ocrTextContent)
                    guard wordsJ.count >= 3 else { continue }
                    
                    let similarity = jaccardSimilarity(wordsI, wordsJ)
                    if similarity > 0.4 {
                        cluster.append(j)
                        merged[j] = true
                    }
                }
                
                clusters.append(cluster)
            }
            
            // Create merged snapshots from clusters
            for cluster in clusters {
                if cluster.count == 1 {
                    result.append(appWindows[cluster[0]])
                } else {
                    // Merge: combine OCR text, keep longest window title
                    let clusterWindows = cluster.map { appWindows[$0] }
                    let bestTitle = clusterWindows.max(by: { $0.windowTitle.count < $1.windowTitle.count })?.windowTitle ?? ""
                    let combinedText = clusterWindows.map { $0.ocrTextContent }.joined(separator: "\n---\n")
                    let totalTextCount = clusterWindows.reduce(0) { $0 + $1.textCount }
                    
                    result.append(WindowSnapshot(
                        appName: clusterWindows[0].appName,
                        windowTitle: bestTitle,
                        ocrTextContent: combinedText,
                        textCount: totalTextCount
                    ))
                }
            }
        }
        
        return result
    }
    
    /// Extract significant words for similarity comparison
    private func extractWords(from text: String) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 }  // Skip tiny words
        return Set(words)
    }
    
    /// Jaccard similarity: |intersection| / |union|
    private func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }
    
    /// Batch summarize unique windows using a single LLM call
    private func batchSummarize(windows: [WindowSnapshot]) async -> [String] {
        guard let llm = llmService, !windows.isEmpty else {
            // Fallback: use window title as summary
            return windows.map { $0.windowTitle.isEmpty ? $0.appName : $0.windowTitle }
        }
        
        let activities = windows.map { window in
            (appName: window.appName, windowTitle: window.windowTitle, ocrText: window.ocrTextContent)
        }
        
        do {
            let summaries = try await llm.batchSummarizeActivities(activities)
            print("✅ Batch summary complete (\(summaries.count) summaries from 1 LLM call)")
            return summaries
        } catch {
            print("⚠️ Batch LLM summary failed: \(error)")
            // Fallback to window titles
            return windows.map { $0.windowTitle.isEmpty ? $0.appName : $0.windowTitle }
        }
    }
    
    /// Detect and assign projects to recent events.
    private func detectProjectsForRecentEvents() async {
        guard let detectionService = projectDetectionService else {
            print("⚠️ Project detection service not initialized")
            return
        }
        
        // Get events without projects from the last 5 minutes (wider window for batch compile)
        let recentEvents = events.filter { event in
            event.projectName == nil &&
            Date().timeIntervalSince(event.timestamp) < 300
        }
        
        guard !recentEvents.isEmpty else { return }
        
        print("🔍 Detecting projects for \(recentEvents.count) events...")
        
        // Get existing project names once (not per-event)
        let existingProjects = await getExistingProjectNames()
        let existingProjectNames = Set(existingProjects.map { normalizedProjectName($0) })
        let workCategories: Set<String> = ["Coding", "Writing", "Design", "Research"]
        var didUpdateProjects = false
        
        for event in recentEvents {
            let (projectName, category) = await detectionService.detectProject(
                from: event,
                existingProjects: existingProjects
            )

            // Skip non-project classifications
            if projectName == "General" || projectName == "New Project" {
                continue
            }

            let isExistingProject = existingProjectNames.contains(normalizedProjectName(projectName))

            if workCategories.contains(category) || isExistingProject {
                await MainActor.run {
                    event.projectName = projectName
                }
                didUpdateProjects = true

                if !isExistingProject {
                    await createProjectIfNeeded(name: projectName, category: category)
                }
            } else {
                print("🚫 Skipping non-work category \(category): \(projectName)")
            }
        }

        if didUpdateProjects, let context = modelContext {
            do {
                try context.save()
            } catch {
                print("❌ Failed to save project assignments: \(error)")
            }
        }
        
        print("✅ Project detection complete")
    }

    private func normalizedProjectName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    /// Get list of existing project names
    private func getExistingProjectNames() async -> [String] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Project>()
        do {
            let projects = try context.fetch(descriptor)
            return projects.map { $0.name }
        } catch {
            print("❌ Failed to fetch projects: \(error)")
            return []
        }
    }
    
    /// Create a new project with deduplication check
    @MainActor
    func createProject(name: String, description: String = "", color: Color = .blue, category: String? = nil, isAutoCreated: Bool = false) {
        guard let context = modelContext else { return }
        
        // Normalize name for comparison
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Check if project with same normalized name already exists
        let descriptor = FetchDescriptor<Project>()
        do {
            let existingProjects = try context.fetch(descriptor)
            let existsAlready = existingProjects.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName }
            if existsAlready {
                print("⚠️ Project '\(name)' already exists, skipping creation")
                return
            }
        } catch {
            print("❌ Failed to check for existing projects: \(error)")
        }
        
        // Use category color if auto-created, otherwise use provided color
        let colorHex = category != nil ? Project.colorForCategory(category!) : (color.toHex() ?? "#3B82F6")
        
        let project = Project(
            name: name,
            desc: description,
            colorHex: colorHex,
            category: category,
            isAutoCreated: isAutoCreated
        )
        context.insert(project)
        
        do {
            try context.save()
            print("✨ Created new project: \(name) (\(category ?? "no category"))")
        } catch {
            print("❌ Failed to save project: \(error)")
        }
    }
    
    /// Helper to create project only if it doesn't exist (async-safe wrapper)
    private func createProjectIfNeeded(name: String, category: String) async {
        await MainActor.run {
            createProject(name: name, category: category, isAutoCreated: true)
        }
    }
    
    // MARK: - OCR Methods
    
    /// Perform screen capture and OCR analysis
    @MainActor
    func performScreenCapture() async {
        // Capture the main screen
        guard let image = await windowManager.captureMainScreen() else {
            print("❌ Failed to capture screen")
            return
        }
        
        capturedImage = image
        ocrResults = []
        mappedWindows = []
        
        // Get visible windows first since it is now async
        let windows = await windowManager.getVisibleWindows()
        
        // Perform OCR on the captured image
        await withCheckedContinuation { continuation in
            ocrEngine.performOCR(on: image) { [weak self] results in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                self.ocrResults = results
                
                // Map text to windows
                var windowMapping: [UUID: [OCRResult]] = [:]
                
                for textResult in results {
                    let centerX = textResult.bounds.x + textResult.bounds.width / 2
                    let centerY = textResult.bounds.y + textResult.bounds.height / 2
                    let pointInPoints = CGPoint(x: centerX, y: centerY)
                    
                    // Find the topmost window containing this text
                    if let topmostWindow = windows.first(where: { $0.frame.cgRect.contains(pointInPoints) }) {
                        windowMapping[topmostWindow.id, default: []].append(textResult)
                    }
                }
                
                // Create mapped windows
                var tempMapped: [MappedWindow] = []
                for window in windows {
                    let textInWindow = windowMapping[window.id] ?? []
                    if !textInWindow.isEmpty {
                        tempMapped.append(MappedWindow(window: window, containedText: textInWindow))
                    }
                }
                
                self.mappedWindows = tempMapped.sorted { $0.containedText.count > $1.containedText.count }
                
                print("✅ OCR complete: \(results.count) text items, \(tempMapped.count) windows")
                continuation.resume()
            }
        }
    }
    
    /// Process OCR results into events (basic - creates event for each text)
    func processOCRResults() {
        for mapped in mappedWindows {
            for text in mapped.containedText {
                // Create an event for each detected text
                let boundsJSON = "{\"x\":\(text.bounds.x),\"y\":\(text.bounds.y),\"width\":\(text.bounds.width),\"height\":\(text.bounds.height)}"
                
                addEvent(
                    source: mapped.window.ownerName,
                    type: "ocr_detection",
                    text: text.text,
                    meta: nil,
                    windowName: mapped.window.displayName,
                    ocrText: text.text,
                    bounds: boundsJSON,
                    skipRecalculate: true
                )
            }
        }
    }
    
    
    /// Determine event type based on application name
    private func determineEventType(for appName: String) -> String {
        let lowercased = appName.lowercased()
        
        // Coding / Development
        if lowercased.contains("xcode") || lowercased.contains("code") || lowercased.contains("cursor") ||
           lowercased.contains("terminal") || lowercased.contains("iterm") || lowercased.contains("warp") ||
           lowercased.contains("android studio") || lowercased.contains("intellij") ||
           lowercased.contains("sublime") || lowercased.contains("atom") || lowercased.contains("vim") ||
           lowercased.contains("github desktop") || lowercased.contains("tower") ||
           lowercased.contains("postman") || lowercased.contains("insomnia") {
            return "coding"
        }
        
        // Browsing
        if lowercased.contains("safari") || lowercased.contains("chrome") ||
           lowercased.contains("firefox") || lowercased.contains("arc") ||
           lowercased.contains("brave") || lowercased.contains("edge") || lowercased.contains("opera") {
            return "browsing"
        }
        
        // Communication
        if lowercased.contains("slack") || lowercased.contains("teams") || lowercased.contains("zoom") ||
           lowercased.contains("discord") || lowercased.contains("messages") || lowercased.contains("mail") ||
           lowercased.contains("outlook") || lowercased.contains("telegram") || lowercased.contains("whatsapp") ||
           lowercased.contains("facetime") {
            return "communication"
        }
        
        // Design
        if lowercased.contains("figma") || lowercased.contains("sketch") || lowercased.contains("photoshop") ||
           lowercased.contains("illustrator") || lowercased.contains("canva") || lowercased.contains("blender") ||
           lowercased.contains("affinity") || lowercased.contains("pixelmator") {
            return "design"
        }
        
        // Writing / Notes
        if lowercased.contains("notes") || lowercased.contains("notion") || lowercased.contains("obsidian") ||
           lowercased.contains("bear") || lowercased.contains("pages") || lowercased.contains("word") ||
           lowercased.contains("google docs") || lowercased.contains("craft") || lowercased.contains("ulysses") {
            return "writing"
        }
        
        // Entertainment / Media
        if lowercased.contains("spotify") || lowercased.contains("music") || lowercased.contains("youtube") ||
           lowercased.contains("netflix") || lowercased.contains("tv") || lowercased.contains("vlc") ||
           lowercased.contains("podcasts") {
            return "entertainment"
        }
        
        return "app_usage"
    }
    
    /// Enhanced addEvent with OCR support
    func addEvent(source: String, type: String, text: String, meta: String? = nil, windowName: String? = nil, ocrText: String? = nil, bounds: String? = nil, skipRecalculate: Bool = false) {
        let newEvent = Event(
            source: source,
            type: type,
            text: text,
            meta: meta,
            windowName: windowName,
            ocrText: ocrText,
            bounds: bounds
        )
        
        guard let context = modelContext else {
            print("⚠️ ModelContext not configured")
            return
        }
        
        context.insert(newEvent)
        events.append(newEvent)
        if !skipRecalculate {
            recalculateStats()
        }
        
        // Update current state
        currentFile = text
        currentProject = source
    }
}
