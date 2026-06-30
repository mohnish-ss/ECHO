//
//  ContentView.swift
//  ECHO-macOS-App
//
//  Created by Mohnish on 2026-01-27.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var activityManager = ActivityManager()
    @State private var selection: NavigationItem? = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(activityManager: activityManager, selection: $selection)
                .navigationSplitViewColumnWidth(min: 260, ideal: 260, max: 300)
        } detail: {
            ZStack {
                Color.contentBackground
                    .ignoresSafeArea()
                
                switch selection {
                case .dashboard:
                    DashboardView(activityManager: activityManager)
                case .timeline:
                    TimelineView(activityManager: activityManager)
                case .ask:
                    AskView(activityManager: activityManager)
                case .projects:
                    ProjectsView()
                case .settings:
                    SettingsView(activityManager: activityManager)
                case .profile:
                    ProfileView(activityManager: activityManager)
                case .none:
                    Text("Select an item")
                }
            }
        }
        .onAppear {
            activityManager.configure(with: modelContext)
        }
    }
}

#Preview {
    ContentView()
}
