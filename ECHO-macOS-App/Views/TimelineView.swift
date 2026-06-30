import SwiftUI
import SwiftData

struct TimelineView: View {
    @Bindable var activityManager: ActivityManager
    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var filter: String = "All"
    
    @Environment(\.modelContext) private var modelContext
    @State private var events: [Event] = []
    
    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }
    
    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }
    
    // Convert Events to TimelineEvents for display
    var timelineEvents: [TimelineEvent] {
        events.map { event in
            TimelineEvent(
                time: event.timestamp.formatted(date: .omitted, time: .shortened),
                duration: "Active",
                appName: event.source,
                title: event.type.replacingOccurrences(of: "_", with: " ").capitalized,
                desc: event.text,
                type: mapEventType(event.type),
                originalEvent: event
            )
        }
    }
    
    func fetchEvents() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = #Predicate<Event> { event in
            event.timestamp >= startOfDay && event.timestamp < endOfDay
        }
        let descriptor = FetchDescriptor<Event>(predicate: predicate, sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        
        do {
            events = try modelContext.fetch(descriptor)
        } catch {
            print("Failed to fetch events: \(error)")
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Timeline")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Chronological view of your daily activities")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Toolbar
            HStack {
                HStack(spacing: 12) {
                    // Date Picker Button
                    Button(action: {
                        showDatePicker.toggle()
                    }) {
                        Label(dateFormatter.string(from: selectedDate), systemImage: "calendar")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.subtleBorder, lineWidth: 1)
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showDatePicker) {
                        DatePicker(
                            "Select Date",
                            selection: $selectedDate,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .padding()
                    }
                    
                    HStack(spacing: 4) {
                        // Previous Day
                        Button(action: {
                            selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                        }) {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.plain)
                        
                        // Today Button
                        Button(action: {
                            selectedDate = Date()
                        }) {
                            Text(isToday ? "Today" : "Today")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isToday ? .blue : .primary)
                        
                        // Next Day
                        Button(action: {
                            selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                        }) {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                Button(action: {}) {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.subtleBorder, lineWidth: 1)
                                )
                        }
                }
                .buttonStyle(.plain)
            }
            
            // List
            ScrollView {
                if timelineEvents.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                            .padding(.top, 60)
                        Text("No events for this day")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text(isToday ? "Enable tracking in Settings to start recording activity" : "No activity recorded for this date")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(timelineEvents) { activity in
                            TimelineRowItem(activity: activity)
                        }
                    }
                    .padding(.top)
                }
            }
        }
        .padding(30)
        .background(Color.contentBackground)
        .onAppear {
            fetchEvents()
        }
        .onChange(of: selectedDate) {
            fetchEvents()
        }
        .onChange(of: activityManager.events) {
            if isToday {
                fetchEvents()
            }
        }
    }
    
    // Map event type strings to TimelineEvent.ActivityType
    private func mapEventType(_ type: String) -> TimelineEvent.ActivityType {
        switch type.lowercased() {
        case "coding", "ocr_detection":
            return .code
        case "browsing":
            return .research
        case "communication":
            return .meeting
        case "design":
            return .design
        case "writing":
            return .design
        case "entertainment":
            return .entertainment
        default:
            return .code
        }
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TimelineRowItem: View {
    let activity: TimelineEvent
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Time
            Text(activity.time)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
                .padding(.top, 14)
            
            // Card
            HStack(spacing: 0) {
                // Colored left bar
                RoundedRectangle(cornerRadius: 12)
                    .fill(activity.color)
                    .frame(width: 4)
                
                VStack(alignment: .leading, spacing: 10) {
                    // Header
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            // App name as primary title
                            Text(activity.appName)
                                .font(.system(size: 15, weight: .semibold))
                            
                            // Event type as colored badge
                            Text(activity.title)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(activity.color.opacity(0.12))
                                .foregroundStyle(activity.color)
                                .clipShape(Capsule())
                            
                            if let project = cleanProjectName {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .font(.caption2)
                                    Text(project)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.caption2)
                            Text(activity.duration)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    // Description
                    if !activity.desc.isEmpty {
                        Text(activity.desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(16)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.subtleBorder, lineWidth: 1)
                    )
            )
        }
    }
    
    // Helper to sanitize project name from bad LLM data
    private var cleanProjectName: String? {
        // Correct logic: For Browsing/Research, the "Project" is essentially the App (e.g. Chrome)
        // The user specifically requested this.
        if activity.type == .research || activity.type == .code {
            // For code, we might want the project, but if the LLM hallucinated the project name
            // as the app name (which happens), or providing nonsense, we might want to be careful.
            // But for Browsing specifically:
            if activity.type == .research {
                return activity.originalEvent?.source
            }
        }
        
        guard let raw = activity.originalEvent?.projectName, !raw.isEmpty else { return nil }
        
        // If it's short and clean, return it
        if raw.count < 50 && !raw.contains("\n") {
            return raw
        }
        
        // Try to extract "Project: NAME" pattern from raw LLM output
        if let range = raw.range(of: "Project: ") {
            let after = raw[range.upperBound...]
            let name = after.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Clean up common markdown artifacts
            let cleanName = name.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanName.isEmpty && cleanName.count < 50 {
                return cleanName
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
        
        return nil
    }
}


struct TimelineEvent: Identifiable {
    let id = UUID()
    let time: String
    let duration: String
    let appName: String
    let title: String
    let desc: String
    let type: ActivityType
    let originalEvent: Event?
    
    enum ActivityType {
        case code, research, meeting, design, entertainment
    }
    
    var color: Color {
        switch type {
        case .code: return .blue
        case .research: return .green
        case .meeting: return .red
        case .design: return .purple
        case .entertainment: return .orange
        }
    }
}
