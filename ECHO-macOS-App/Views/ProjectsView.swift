import SwiftUI
import SwiftData

struct ProjectsView: View {
    @Query private var projects: [Project]
    @Query private var events: [Event]
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingAddProject = false
    @State private var selectedProject: Project?
    @State private var newProjectName = ""
    @State private var newProjectDescription = ""
    @State private var newProjectColor: Color = .blue
    
    // Calculate statistics from real data
    var totalHours: Int {
        var total = 0.0
        for project in projects {
            total += calculateHours(for: project)
        }
        return Int(total)
    }
    
    var totalCommits: Int {
        // Placeholder - would need git integration
        return 0
    }
    
    var body: some View {
        Group {
            if let project = selectedProject {
                ProjectDetailView(project: project, onBack: {
                    selectedProject = nil
                })
            } else {
                projectsListContent
            }
        }
        .padding(30)
        .sheet(isPresented: $showingAddProject) {
            AddProjectSheet(
                projectName: $newProjectName,
                projectDescription: $newProjectDescription,
                projectColor: $newProjectColor,
                onAdd: {
                    addProject()
                },
                onCancel: {
                    showingAddProject = false
                    resetForm()
                }
            )
        }
    }
    
    private var projectsListContent: some View {
        VStack(alignment: .leading, spacing: 30) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Projects")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Track time and activity across your different projects")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: {
                    showingAddProject = true
                }) {
                    Label("New Project", systemImage: "plus")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            Capsule()
                                .fill(Color.blue.opacity(0.5))
                                .glassEffect()
                        }
                }
                .buttonStyle(.plain)
            }
            
            // Stats Grid
            HStack(spacing: 20) {
                ProjectStatCard(value: "\(totalHours)h", label: "Total Hours")
                ProjectStatCard(value: "\(projects.count)", label: "Active Projects")
                ProjectStatCard(value: "\(totalCommits)", label: "Total Commits")
            }
            
            // Projects List
            ScrollView {
                if projects.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                        .padding(.top, 60)
                        Text("No projects yet")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("Projects will be auto-created as you work, or click 'New Project'")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 16) {
                        ForEach(projects) { project in
                            Button {
                                selectedProject = project
                            } label: {
                                ProjectRowItem(
                                    project: project,
                                    hours: calculateHours(for: project),
                                    files: calculateFiles(for: project),
                                    eventCount: eventsCount(for: project)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
    }
    
    private func addProject() {
        let colorHex = newProjectColor.toHex() ?? "#3B82F6"
        let newProject = Project(
            name: newProjectName,
            desc: newProjectDescription,
            colorHex: colorHex,
            isAutoCreated: false
        )
        modelContext.insert(newProject)
        showingAddProject = false
        resetForm()
    }
    
    private func resetForm() {
        newProjectName = ""
        newProjectDescription = ""
        newProjectColor = .blue
    }
    
    // Calculate hours for a project from its events
    private func calculateHours(for project: Project) -> Double {
        let projectEvents = events.filter { $0.projectName == project.name }
        guard !projectEvents.isEmpty else { return 0 }
        
        let sorted = projectEvents.sorted { $0.timestamp < $1.timestamp }
        if let first = sorted.first, let last = sorted.last {
            return last.timestamp.timeIntervalSince(first.timestamp) / 3600.0
        }
        return 0
    }
    
    // Calculate unique files for a project
    private func calculateFiles(for project: Project) -> Int {
        let projectEvents = events.filter { $0.projectName == project.name }
        let uniqueFiles = Set(projectEvents.map { $0.text })
        return uniqueFiles.count
    }
    
    // Count events for a project
    private func eventsCount(for project: Project) -> Int {
        return events.filter { $0.projectName == project.name }.count
    }
}

struct ProjectStatCard: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 32, weight: .bold))
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
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

struct ProjectRowItem: View {
    let project: Project
    let hours: Double
    let files: Int
    let eventCount: Int
    
    var projectColor: Color {
        Color(hex: project.colorHex) ?? .blue
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Colored accent bar
            RoundedRectangle(cornerRadius: 16)
                .fill(projectColor)
                .frame(width: 4)
            
            HStack(alignment: .top, spacing: 16) {
                // Larger colored dot with icon
                ZStack {
                    Circle()
                        .fill(projectColor.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: getCategoryIcon(project.category))
                        .foregroundStyle(projectColor)
                        .font(.system(size: 18))
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(project.displayName)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                
                                if let category = project.category {
                                    Text(category)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(projectColor.opacity(0.1))
                                        .foregroundStyle(projectColor)
                                        .clipShape(Capsule())
                                }
                            }
                            
                            if !project.desc.isEmpty {
                                Text(project.desc)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            if project.isAutoCreated {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                        .font(.caption2)
                                    Text("Auto-created")
                                        .font(.caption2)
                                }
                                .foregroundStyle(projectColor)
                            }
                        }
                        Spacer()
                    }
                    
                    // Stats
                    HStack(spacing: 24) {
                        Label(String(format: "%.1fh", hours), systemImage: "clock.fill")
                        Label("\(files) files", systemImage: "doc.fill")
                        Label("\(eventCount) events", systemImage: "calendar")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(projectColor.opacity(0.2), lineWidth: 1)
                )
        )
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

// Remove old ProjectItem struct
// Add Color extension for hex support
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
    
    func toHex() -> String? {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return nil
        }
        
        let r = Int(components[0] * 255.0)
        let g = Int(components[1] * 255.0)
        let b = Int(components[2] * 255.0)
        
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Add Project Sheet

struct AddProjectSheet: View {
    @Binding var projectName: String
    @Binding var projectDescription: String
    @Binding var projectColor: Color
    let onAdd: () -> Void
    let onCancel: () -> Void
    
    let availableColors: [Color] = [.blue, .green, .purple, .orange, .red, .pink, .yellow, .cyan]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Project")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            
            Divider()
            
            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Project Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Project Name")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("Enter project name", text: $projectName)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.subtleBorder, lineWidth: 1)
                                    )
                            )
                    }
                    
                    // Project Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("Enter project description", text: $projectDescription, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.subtleBorder, lineWidth: 1)
                                    )
                            )
                    }
                    
                    // Color Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Project Color")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        HStack(spacing: 12) {
                            ForEach(availableColors, id: \.self) { color in
                                Circle()
                                    .fill(color)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: projectColor == color ? 3 : 0)
                                    )
                                    .onTapGesture {
                                        projectColor = color
                                    }
                            }
                        }
                    }
                }
                .padding(24)
            }
            
            Divider()
            
            // Footer Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.subtleBorder, lineWidth: 1)
                        )
                )
                .buttonStyle(.plain)
                
                Spacer()
                
                Button("Add Project") {
                    onAdd()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(projectName.isEmpty)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(projectName.isEmpty ? Color.gray.opacity(0.3) : Color.blue.opacity(0.5))
                        .glassEffect()
                }
                .buttonStyle(.plain)
                .opacity(projectName.isEmpty ? 0.5 : 1.0)
            }
            .padding(24)
        }
        .frame(width: 500, height: 450)
        .background(Color.contentBackground)
    }
}
