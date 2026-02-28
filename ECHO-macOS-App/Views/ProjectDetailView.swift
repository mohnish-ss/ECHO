import SwiftUI
import SwiftData

struct ProjectDetailView: View {
    let project: Project
    var onBack: (() -> Void)?
    @Query private var events: [Event]
    @Environment(\.dismiss) private var dismiss
    
    init(project: Project, onBack: (() -> Void)? = nil) {
        self.project = project
        self.onBack = onBack
        // Filter events for this project
        let projectName = project.name
        _events = Query(filter: #Predicate<Event> { event in
            event.projectName == projectName
        }, sort: \Event.timestamp, order: .reverse)
    }
    
    // Stats calculation
    var totalHours: Double {
        guard !events.isEmpty else { return 0 }
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        if let first = sorted.first, let last = sorted.last {
            return last.timestamp.timeIntervalSince(first.timestamp) / 3600.0
        }
        return 0
    }
    
    var uniqueFiles: Int {
        let files = Set(events.map { $0.text })
        return files.count
    }
    
    var projectColor: Color {
        Color(hex: project.colorHex) ?? .blue
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // Back Button
                if onBack != nil {
                    Button(action: {
                        onBack?()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.cardBackground)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.subtleBorder, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
                }

                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(projectColor.opacity(0.1))
                                    .frame(width: 48, height: 48)
                                Image(systemName: getCategoryIcon(project.category))
                                    .foregroundStyle(projectColor)
                                    .font(.title3)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) { // Align name and category badge
                                    Text(project.displayName)
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                    
                                    if let category = project.category {
                                        Text(category)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(projectColor.opacity(0.1))
                                            .foregroundStyle(projectColor)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        
                        if !project.desc.isEmpty {
                            Text(project.desc)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                        
                        Text("Created \(project.createdAt.formatted(date: .long, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    Spacer()
                }
                
                // Stats Grid
                HStack(spacing: 20) {
                    DetailStatCard(value: String(format: "%.1fh", totalHours), label: "Total Time", icon: "clock.fill", color: projectColor)
                    DetailStatCard(value: "\(uniqueFiles)", label: "Files Touched", icon: "doc.fill", color: .orange)
                    DetailStatCard(value: "\(events.count)", label: "Total Events", icon: "chart.bar.fill", color: .purple)
                }
                
                Divider()
                
                // Recent Activity
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recent Activity")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if events.isEmpty {
                        Text("No activity recorded yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(events) { event in
                                ProjectEventRow(event: event)
                            }
                        }
                    }
                }
            }
            .padding(30)
        }
        .background(Color.contentBackground)
    }
    
    func getCategoryIcon(_ category: String?) -> String {
        guard let category = category else { return "folder.fill" }
        switch category.lowercased() {
        case "coding", "development": return "hammer.fill"
        case "communication", "chat": return "bubble.left.and.bubble.right.fill"
        case "entertainment", "media": return "play.rectangle.fill"
        case "design": return "paintbrush.fill"
        case "browsing", "research": return "safari.fill"
        case "writing": return "pencil.and.outline"
        default: return "folder.fill"
        }
    }
}

struct DetailStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.subtleBorder, lineWidth: 1)
                )
        )
    }
}

struct ProjectEventRow: View {
    let event: Event
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: getIcon(for: event.source))
                .font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.subtleBorder, lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.source)
                        .font(.headline)
                    if let window = event.windowName {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(window)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(event.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.cardBackground.opacity(0.5))
        )
    }
    
    func getIcon(for source: String) -> String {
        switch source.lowercased() {
        case let s where s.contains("xcode"): return "hammer.fill"
        case let s where s.contains("chrome") || s.contains("safari"): return "safari.fill"
        case let s where s.contains("terminal") || s.contains("iterm"): return "terminal.fill"
        case let s where s.contains("slack") || s.contains("discord"): return "bubble.left.and.bubble.right.fill"
        default: return "macwindow"
        }
    }
}
