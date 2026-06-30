# ECHO

ECHO is a macOS productivity tracking application built with SwiftUI that monitors your activity, tracks time spent across projects, and provides intelligent insights through OCR and local LLM analysis.

## Features

- **Activity Dashboard** — Real-time view of your daily productivity stats
- **Timeline View** — Detailed timeline of your work sessions with app-level detail
- **Screen Capture & OCR** — Automatic screenshots with Apple Vision text extraction
- **Smart Compilation** — Deduplicates, filters transient events, and merges similar content
- **Project Detection** — Automatically classifies work into coding, academic, and research projects
- **Ask ECHO** — Chat with a local LLM (Ollama) about your activity history
- **Profile & Stats** — Weekly breakdown, top apps, active streak tracking

## Getting Started

1. Open `ECHO-macOS-App.xcodeproj` in Xcode
2. Build and run (⌘R)
3. Grant permissions when prompted (see below)

## Requirements

- macOS 15.0+
- Xcode 16.0+
- [Ollama](https://ollama.com) running locally (for Ask ECHO)

## Permissions

The app needs two macOS permissions:

1. **Screen Recording** — System Settings → Privacy & Security → Screen Recording → Enable ECHO
2. **Accessibility** — System Settings → Privacy & Security → Accessibility → Enable ECHO

> **Tip:** If permissions reset after rebuilding, disable App Sandbox in Xcode (Target → Signing & Capabilities → remove App Sandbox), then clean build (⌘⇧K).

## Project Structure

```
ECHO-macOS-App/
├── Models/
│   ├── Event.swift              # Core event data model (SwiftData)
│   ├── Project.swift            # Project data model
│   └── OCRModels.swift          # OCR text recognition models
├── Services/
│   ├── ActivityManager.swift    # Main orchestrator — capture, compile, stats
│   ├── LLMService.swift         # Ollama integration & chat
│   ├── OCREngine.swift          # Apple Vision OCR
│   ├── ProjectDetectionService.swift  # Project classification
│   └── WindowManager.swift      # Window enumeration & mapping
├── Views/
│   ├── ContentView.swift        # Root navigation
│   ├── SidebarView.swift        # Sidebar + theme colors
│   ├── DashboardView.swift      # Activity dashboard
│   ├── TimelineView.swift       # Event timeline
│   ├── AskView.swift            # LLM chat interface
│   ├── ProjectsView.swift       # Project list
│   ├── ProjectDetailView.swift  # Individual project detail
│   ├── ProfileView.swift        # User profile + weekly stats
│   ├── SettingsView.swift       # App settings
│   └── EditProfileSheet.swift   # Profile edit modal
└── Assets.xcassets/             # App icons and images
```

## Starting Ollama

```bash
ollama serve                  # Start the server
ollama pull llama3.2:3b       # Pull the model (first time only)
```

## License

MIT License
