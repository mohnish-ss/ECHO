import SwiftUI

struct SettingsView: View {
    @Bindable var activityManager: ActivityManager
    
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Customize your ECHO experience and tracking preferences")
                        .foregroundStyle(.secondary)
                }
                
                SettingSection(title: "Capture Settings", description: "Configure automatic screenshot and activity tracking") {
                    HStack(spacing: 16) {
                        Image(systemName: "camera.aperture")
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Tracking").fontWeight(.medium)
                            Text("Automatically capture screenshots at regular intervals").font(.caption).foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { activityManager.isAutoCapturing },
                            set: { newValue in
                                if newValue {
                                    activityManager.startTracking()
                                } else {
                                    activityManager.stopTracking()
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                    }
                    .padding(.vertical, 8)
                    
                    Divider().opacity(0.5)
                    
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            Image(systemName: "timer")
                                .font(.title3)
                                .frame(width: 32, height: 32)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Capture Interval").fontWeight(.medium)
                                Text("How often to capture screenshots").font(.caption).foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(formatInterval(activityManager.captureInterval))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        
                        Slider(
                            value: Binding(
                                get: { activityManager.captureInterval },
                                set: { newValue in
                                    Task { @MainActor in
                                        activityManager.updateCaptureInterval(newValue)
                                    }
                                }
                            ),
                            in: 5...60,
                            step: 5
                        )
                        .disabled(!activityManager.isAutoCapturing)
                    }
                    .padding(.vertical, 8)
                    
                    Divider().opacity(0.5)
                    
                    ToggleRow(
                        icon: "doc.text.magnifyingglass",
                        title: "Auto-Generate Events",
                        subtitle: "Create events from captured screenshots",
                        isOn: Binding(
                            get: { activityManager.autoGenerateEvents },
                            set: { activityManager.autoGenerateEvents = $0 }
                        )
                    )
                }
                
                SettingSection(title: "Data Management", description: "Manage your tracked activity data") {
                    HStack(spacing: 16) {
                        Image(systemName: "trash")
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.red)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete All Data").fontWeight(.medium)
                            Text("Permanently remove all tracked events and projects").font(.caption).foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Delete") {
                            showDeleteConfirmation = true
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.red.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .buttonStyle(.plain)
                        .confirmationDialog("Delete All Data?", isPresented: $showDeleteConfirmation) {
                            Button("Delete All Events", role: .destructive) {
                                activityManager.clearAllEvents()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will permanently delete all tracked events. This action cannot be undone.")
                        }
                    }
                    .padding(.vertical, 8)
                }
                
            }
            .padding(30)
        }
    }
    
    private func formatInterval(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else {
            let minutes = Int(seconds / 60)
            return "\(minutes)m"
        }
    }
}

struct SettingSection<Content: View>: View {
    let title: String
    let description: String
    let content: Content
    
    init(title: String, description: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 0) {
                content
            }
            .padding(16)
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
}

struct ToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 32, height: 32)
                .background(Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
        }
        .padding(.vertical, 8)
    }
}
