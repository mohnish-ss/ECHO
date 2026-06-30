import SwiftUI

struct DashboardView: View {
    @Bindable var activityManager: ActivityManager
    @State private var selectedDate = Date()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    Text("Today's Summary")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Group {
                        if activityManager.stats.hours > 0 {
                            Text("You spent **\(String(format: "%.1f", activityManager.stats.hours)) hours** working across \(activityManager.stats.projects) projects, tracking \(activityManager.events.count) events.")
                        } else {
                            Text("No activity recorded yet for today.")
                        }
                    }
                    .font(.body)
                    .foregroundStyle(Color.mutedGray)
                    .lineSpacing(4)
                }
                
                // Stats Grid
                HStack(spacing: 16) {
                    StatCard(value: "\(String(format: "%.1f", activityManager.stats.hours)) Hours", label: "Active")
                    StatCard(value: "\(activityManager.stats.projects) Projects", label: "Worked on")
                    StatCard(value: "\(activityManager.stats.files) Files", label: "Edited")
                }
                
                // Activity Timeline
                VStack(alignment: .leading, spacing: 24) {
                    Text("Recent Activity")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    
                    if activityManager.events.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "clock.badge.questionmark")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                            Text("No activity yet")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                            Text("Events will appear here once your backend starts tracking activity")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(activityManager.events.reversed().prefix(50)) { event in
                                TimelineRow(event: event)
                            }
                        }
                    }
                }
            }
            .padding(40)
        }
        .background(Color.contentBackground)
    }
}

struct StatCard: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.mutedGray)
                .textCase(.uppercase)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
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

struct TimelineRow: View {
    let event: Event
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Color.mutedGray)
                .frame(width: 65, alignment: .trailing)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(event.type.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.9))
                Text(event.text)
                    .font(.caption)
                    .foregroundStyle(Color.mutedGray)
            }
            .padding(.leading, 12)
            .padding(.bottom, 30)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 2)
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .shadow(color: .blue.opacity(0.5), radius: 4)
                    .offset(x: -3, y: 5)
            }
        }
    }
}
