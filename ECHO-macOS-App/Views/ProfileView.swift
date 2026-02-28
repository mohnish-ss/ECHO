import SwiftUI

struct ProfileView: View {
    // Persistent profile data
    @AppStorage("userName") private var userName = "John Doe"
    @AppStorage("userTitle") private var userTitle = "Full-Stack Developer"
    @AppStorage("userEmail") private var userEmail = "john@example.com"
    @State private var showingEditProfile = false
    
    // Temporary state for editing
    @State private var editName = ""
    @State private var editTitle = ""
    @State private var editEmail = ""
    
    // Activity manager for real stats
    @Bindable var activityManager: ActivityManager
    
    private let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    
    // Calculate real statistics from events
    var totalHoursTracked: String {
        let hours = activityManager.calculateTotalHours()
        if hours >= 1 {
            return String(format: "%.0fh", hours)
        } else {
            return String(format: "%.0fm", hours * 60)
        }
    }
    
    var activeStreak: String {
        let days = activityManager.calculateWorkStreak()
        return "\(days) day\(days == 1 ? "" : "s")"
    }
    
    var weeklyHours: String {
        let hours = activityManager.calculateWeeklyHours()
        if hours >= 1 {
            return String(format: "%.1f", hours)
        } else {
            return String(format: "%.0f min", hours * 60)
        }
    }
    
    var dailyHours: [Double] {
        activityManager.calculateDailyHoursThisWeek()
    }
    
    var userInitials: String {
        let components = userName.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "JD"
    }
    
    /// Which weekday index is today (Mon=0, Sun=6)
    var todayIndex: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 1 ? 6 : weekday - 2
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Card
                HStack(spacing: 20) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Text(userInitials)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(userName)
                            .font(.title)
                            .fontWeight(.bold)
                        Text(userTitle)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 16) {
                            Label(userEmail, systemImage: "envelope")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
                    
                    Spacer()
                    
                    Button("Edit Profile") {
                        editName = userName
                        editTitle = userTitle
                        editEmail = userEmail
                        showingEditProfile = true
                    }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.subtleBorder, lineWidth: 1)
                                )
                        )
                        .buttonStyle(.plain)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.subtleBorder, lineWidth: 1)
                        )
                )
                
                // Stats Row
                HStack(spacing: 20) {
                    ProfileStatCard(icon: "clock", value: totalHoursTracked, label: "Total Time Tracked", color: .blue)
                    ProfileStatCard(icon: "flame", value: activeStreak, label: "Active Streak", color: .orange)
                }
                
                // Weekly Graph — real data
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("This Week")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Text("\(weeklyHours) hours total")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    let maxHours = max(dailyHours.max() ?? 1, 1)
                    
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(0..<7, id: \.self) { index in
                            let hours = dailyHours[index]
                            let barHeight = max(hours / maxHours * 100, hours > 0 ? 8 : 4)
                            let isToday = index == todayIndex
                            let isPast = index <= todayIndex
                            
                            VStack(spacing: 8) {
                                // Hours label
                                if hours > 0 {
                                    Text(hours >= 1 ? String(format: "%.1fh", hours) : String(format: "%.0fm", hours * 60))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(isToday ? .blue : .secondary)
                                }
                                
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isToday ? Color.blue : (isPast && hours > 0 ? Color.blue.opacity(0.5) : Color.gray.opacity(0.15)))
                                    .frame(height: barHeight)
                                
                                Text(dayLabels[index])
                                    .font(.caption)
                                    .fontWeight(isToday ? .semibold : .regular)
                                    .foregroundStyle(isToday ? .blue : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 140)
                    .padding(.top, 10)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.subtleBorder, lineWidth: 1)
                        )
                )
                
                // Top Apps This Week
                VStack(alignment: .leading, spacing: 16) {
                    Text("Top Apps This Week")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    let topApps = calculateTopAppsThisWeek()
                    
                    if topApps.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "app.dashed")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("No app usage recorded this week")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 20)
                            Spacer()
                        }
                    } else {
                        let maxCount = topApps.first?.count ?? 1
                        
                        ForEach(topApps, id: \.name) { app in
                            HStack(spacing: 12) {
                                Text(app.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(width: 120, alignment: .leading)
                                
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.blue.opacity(0.5))
                                        .frame(width: max(geo.size.width * CGFloat(app.count) / CGFloat(maxCount), 4))
                                }
                                .frame(height: 20)
                                
                                Text("\(app.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }
                    }
                }
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
            .padding(30)
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileSheet(
                name: $editName,
                title: $editTitle,
                email: $editEmail,
                onSave: {
                    userName = editName
                    userTitle = editTitle
                    userEmail = editEmail
                    showingEditProfile = false
                },
                onCancel: {
                    showingEditProfile = false
                }
            )
        }
    }
    
    private func calculateTopAppsThisWeek() -> [(name: String, count: Int)] {
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
            return []
        }
        
        let weekEvents = activityManager.events.filter { $0.timestamp >= weekStart }
        var appCounts: [String: Int] = [:]
        for event in weekEvents {
            appCounts[event.source, default: 0] += 1
        }
        
        return appCounts.sorted { $0.value > $1.value }.prefix(5).map { (name: $0.key, count: $0.value) }
    }
}

struct ProfileStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.1))
                .clipShape(Circle())
                .foregroundStyle(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
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



