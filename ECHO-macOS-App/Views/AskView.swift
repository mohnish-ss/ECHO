import SwiftUI
import SwiftData

// MARK: - Chat Message Model

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    
    init(id: UUID = UUID(), content: String, isUser: Bool, timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

struct AskView: View {
    @Bindable var activityManager: ActivityManager
    @State private var llmService = LLMService()
    @State private var query: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false
    @State private var ollamaConnected = false
    
    // Persist messages
    @AppStorage("askViewMessages") private var messagesData: Data = Data()
    
    var body: some View {
        Group {
            if messages.isEmpty {
                centeredView
            } else {
                chatView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: messages.isEmpty)
        .task {
            ollamaConnected = await llmService.checkConnection()
            loadMessages()
        }
    }
    
    // MARK: - Centered View (Original Design)
    
    private var centeredView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Connection warning (if needed)
            if !ollamaConnected {
                connectionWarning
                    .padding(.horizontal)
            }
            
            VStack(spacing: 16) {
                Text("Ask ECHO")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Query your activity data using natural language")
                    .foregroundStyle(.secondary)
                
                Spacer().frame(height: 20)
                
                // Sparkles icon
                Image(systemName: "sparkles")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.cyan)
                
                Spacer().frame(height: 20)
                
                Text("What would you like to know?")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Ask questions about your work activity, productivity\npatterns, or time allocation")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer().frame(height: 40)
            
            // Suggested questions
            VStack(spacing: 16) {
                SuggestedQuestionCard(
                    icon: "clock",
                    text: "How many hours did I work today?",
                    iconColor: .blue
                ) {
                    query = "How many hours did I work today?"
                    Task { await sendMessage() }
                }
                
                SuggestedQuestionCard(
                    icon: "folder",
                    text: "What projects did I work on?",
                    iconColor: .blue
                ) {
                    query = "What projects did I work on today?"
                    Task { await sendMessage() }
                }
                
                SuggestedQuestionCard(
                    icon: "chart.bar.xaxis",
                    text: "Summarize my productivity",
                    iconColor: .blue
                ) {
                    query = "Summarize my productivity today"
                    Task { await sendMessage() }
                }
            }
            .frame(maxWidth: 600)
            .padding(.horizontal)
            
            Spacer()
            
            // Input area
            inputArea
                .padding(.horizontal)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Chat View
    
    private var chatView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        // Clear messages to return to centered view
                        messages.removeAll()
                        messagesData = Data() // Clear saved messages
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        
                        // Sparkles in header
                        Image(systemName: "sparkles")
                            .foregroundStyle(.cyan)
                        
                        Text("Ask ECHO")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(ollamaConnected ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(ollamaConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.cardBackground.opacity(0.5))
            
            Divider()
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(groupedMessagesByDay(), id: \.date) { group in
                            // Date header
                            Text(formatDateHeader(group.date))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                            
                            // Messages for this day
                            ForEach(group.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        
                        if isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input area
            inputArea
                .padding()
        }
    }
    
    // MARK: - Shared Components
    
    private var connectionWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text("Ollama not running. Start it to use Ask.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Retry") {
                Task {
                    ollamaConnected = await llmService.checkConnection()
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Ask about your activity...", text: $query, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.cardBackground)
                .cornerRadius(20)
                .disabled(isLoading || !ollamaConnected)
                .onSubmit {
                    Task { await sendMessage() }
                }
            
            Button(action: {
                Task { await sendMessage() }
            }) {
                Image(systemName: isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(ollamaConnected && !query.isEmpty ? Color.blue : Color.gray)
            }
            .buttonStyle(.plain)
            .disabled(query.isEmpty || !ollamaConnected || isLoading)
        }
    }
    
    // MARK: - Functions
    
    private func sendMessage() async {
        guard !query.isEmpty, !isLoading else { return }
        
        let userMessage = ChatMessage(content: query, isUser: true)
        messages.append(userMessage)
        saveMessages()
        
        let currentQuery = query
        query = ""
        isLoading = true
        
        do {
            // Fetch last 7 days of context for the LLM
            let contextEvents = fetchContextEvents()
            let response = try await llmService.queryEvents(currentQuery, events: contextEvents)
            // Strip leading/trailing quotation marks if present
            let cleanedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let assistantMessage = ChatMessage(content: cleanedResponse, isUser: false)
            messages.append(assistantMessage)
            saveMessages()
        } catch {
            let errorMessage = ChatMessage(
                content: "Sorry, I encountered an error: \(error.localizedDescription)",
                isUser: false
            )
            messages.append(errorMessage)
            saveMessages()
        }
        
        isLoading = false
    }
    
    @Environment(\.modelContext) private var modelContext
    
    private func fetchContextEvents() -> [Event] {
        let calendar = Calendar.current
        let endDate = Date()
        // Provide 7 days of history for context
        let startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!
        
        let predicate = #Predicate<Event> { event in
            event.timestamp >= startDate
        }
        let descriptor = FetchDescriptor<Event>(predicate: predicate, sortBy: [SortDescriptor(\.timestamp, order: .reverse)]) // Newest first
        
        do {
            // Limit to reasonable number to prevent token overflow (e.g., 500 recent events)
            // But for now, let's fetch more and let LLMService summarize/truncate if needed
            // LLMService groups by day, so fetching a good chunk is fine.
            var events = try modelContext.fetch(descriptor)
            
            // If we have too many, filter or take the most recent 1000
            if events.count > 1000 {
                events = Array(events.prefix(1000))
            }
            return events
        } catch {
            print("Failed to fetch context events: \(error)")
            return activityManager.events // Fallback to today's events from memory
        }
    }
    
    
    // MARK: - Helper Functions
    
    struct MessageGroup {
        let date: Date
        let messages: [ChatMessage]
    }
    
    private func groupedMessagesByDay() -> [MessageGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: messages) { message in
            calendar.startOfDay(for: message.timestamp)
        }
        
        return grouped.map { MessageGroup(date: $0.key, messages: $0.value) }
            .sorted { $0.date < $1.date }
    }
    
    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let messageDate = calendar.startOfDay(for: date)
        
        if messageDate == today {
            return "Today"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  messageDate == yesterday {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
    
    private func saveMessages() {
        if let encoded = try? JSONEncoder().encode(messages) {
            messagesData = encoded
        }
    }
    
    private func loadMessages() {
        if let decoded = try? JSONDecoder().decode([ChatMessage].self, from: messagesData) {
            messages = decoded
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !message.isUser {
                // AI avatar
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(.cyan)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.cyan.opacity(0.1))
                    )
                    .padding(.top, 4)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                // Render markdown for AI responses, plain text for user
                if message.isUser {
                    Text(message.content)
                        .font(.system(size: 15))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.blue.opacity(0.6))
                        )
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                } else {
                    // AI response with markdown support
                    Text(parseMarkdown(message.content))
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color.subtleBorder, lineWidth: 1)
                                )
                        )
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, message.isUser ? 16 : 4)
            }
            .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
            
            if message.isUser {
                Spacer(minLength: 0)
            }
        }
    }
    
    // Parse markdown to AttributedString
    private func parseMarkdown(_ text: String) -> AttributedString {
        do {
            var attributedString = try AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            
            // Customize the appearance
            for run in attributedString.runs {
                if run.inlinePresentationIntent == .stronglyEmphasized {
                    attributedString[run.range].foregroundColor = .primary
                    attributedString[run.range].font = .system(size: 15, weight: .semibold)
                }
            }
            
            return attributedString
        } catch {
            // Fallback to plain text if markdown parsing fails
            return AttributedString(text)
        }
    }
}

// MARK: - Suggested Question Card

struct SuggestedQuestionCard: View {
    let icon: String
    let text: String
    let iconColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 24)
                
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Color.cardBackground)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.subtleBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
