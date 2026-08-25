# ECHO

ECHO is a native macOS productivity-tracking application built with SwiftUI and SwiftData. It captures on-screen work context, extracts text with Apple Vision OCR, compiles the captures into structured activity events, and uses a local MLX language model to summarize activity, classify projects, and answer questions about recent work.

## How It Works

ECHO's activity pipeline is fully integrated into the macOS app:

1. **Capture** — Periodically captures screen and active-window context.
2. **OCR** — Uses Apple Vision to extract text visible in captured windows.
3. **Compile** — Batches captures, filters duplicate/transient activity, and turns OCR-backed context into activity events.
4. **Analyze** — Runs a 4-bit Llama 3.2 3B model locally through Apple's MLX stack for activity summaries, project classification, and natural-language queries.
5. **Persist** — Stores structured activity and project data locally with SwiftData.

No Ollama daemon or external inference server is required. The model is downloaded from Hugging Face on first use and inference runs locally through MLX.

## Features

- **Automatic Activity Capture** — Periodic screen capture with active-window metadata
- **Apple Vision OCR** — Extracts text from captured application windows
- **MLX On-Device Inference** — Native local inference with Llama 3.2 3B 4-bit
- **Smart Compilation** — Batches captures and reduces duplicate or transient activity before persistence
- **Project Detection** — Uses rule-based detection first, then MLX-backed classification when needed
- **Ask ECHO** — Queries up to seven days of captured activity using natural language
- **Activity Dashboard** — Daily productivity statistics and recent work context
- **Timeline** — Chronological view of structured activity events
- **Projects** — Groups activity into detected work and study projects
- **Profile & Stats** — Weekly hours, top apps, and activity streaks

## Technology

- **UI & Persistence:** Swift, SwiftUI, SwiftData
- **Computer Vision / OCR:** Apple Vision
- **Local AI:** Apple MLX, `mlx-swift`, `mlx-swift-lm`
- **Model:** Llama 3.2 3B 4-bit via the MLX model registry
- **Model Distribution:** Hugging Face
- **Window Context:** macOS window APIs and Accessibility permissions

## Requirements

- Apple Silicon Mac for MLX inference
- macOS 15.0+
- Xcode 16.0+
- Internet access the first time the model is downloaded

## Getting Started

1. Clone the repository.
2. Open `ECHO-macOS-App.xcodeproj` in Xcode.
3. Allow Swift Package Manager to resolve the MLX and Hugging Face dependencies.
4. Build and run the macOS target.
5. Grant Screen Recording and Accessibility permissions when prompted.
6. Open **Ask ECHO** or trigger an ML-backed workflow to download the local model on first use.

## Permissions

ECHO uses two macOS permissions to capture useful work context:

1. **Screen Recording** — Required for screenshots used by the OCR pipeline.
2. **Accessibility** — Required for application/window context used to map OCR text to visible work.

If macOS resets permissions after rebuilding the app, re-enable them in **System Settings → Privacy & Security**.

## Project Structure

```text
ECHO-macOS-App/
├── Models/
│   ├── Event.swift                    # SwiftData activity event model
│   ├── Project.swift                  # Project model
│   └── OCRModels.swift                # OCR/window mapping models
├── Services/
│   ├── ActivityManager.swift          # Capture, compilation, event processing, and stats
│   ├── NativeLLMService.swift         # MLX model loading, generation, summarization, and queries
│   ├── OCREngine.swift                # Apple Vision OCR
│   ├── ProjectDetectionService.swift  # Rule-based + MLX-backed project classification
│   └── WindowManager.swift            # Window enumeration and mapping
├── Views/
│   ├── ContentView.swift
│   ├── DashboardView.swift
│   ├── TimelineView.swift
│   ├── AskView.swift                  # Natural-language activity queries
│   ├── ProjectsView.swift
│   ├── ProjectDetailView.swift
│   ├── ProfileView.swift
│   └── SettingsView.swift
└── Assets.xcassets/
```

## Local LLM Implementation

`NativeLLMService` loads `LLMRegistry.llama3_2_3B_4bit` using MLX's model factory and Hugging Face tokenizer/model loading utilities. The service keeps the model container in memory after loading and is used for:

- OCR-backed activity summarization
- Project/category classification
- Natural-language questions over captured activity history

The current implementation does not depend on Ollama.
