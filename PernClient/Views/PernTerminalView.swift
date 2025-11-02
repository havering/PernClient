import SwiftUI

struct PernTerminalView: View {
    @ObservedObject var connection: PernConnection
    @ObservedObject var connectionManager: PernConnectionManager
    @FocusState private var isInputFocused: Bool
    @State private var scrollToBottom = false
    
    // Regex caching for better performance - each connection gets its own cache
    @StateObject private var highlightCache = HighlightCache()
    @State private var lastProcessedTextLength: Int = 0
    @State private var cachedAttributedString: NSAttributedString?
    @State private var cachedTextLength: Int = 0
    @State private var viewId = UUID()
    
    // Performance optimization: debounce scroll updates
    private let scrollDebounceInterval: TimeInterval = 0.1 // Only scroll after 100ms of no updates
    @State private var pendingScrollUpdate: DispatchWorkItem?
    
    var body: some View {
        VStack(spacing: 0) {
            // Connection Status Bar
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(connection.isConnected ? Color.green : (connection.isConnecting ? Color.yellow : Color.red))
                        .frame(width: 8 * connectionManager.iconScale, height: 8 * connectionManager.iconScale)
                    
                    Text(connection.isConnected ? "Connected" : (connection.isConnecting ? "Connecting..." : "Disconnected"))
                        .font(.system(size: connectionManager.fontSize - 2))
                        .foregroundColor(.secondary)
                    
                    if let character = connection.character, !connection.isGuestConnection {
                        Text("• \(character.name)")
                            .font(.system(size: connectionManager.fontSize - 2))
                            .foregroundColor(.secondary)
                    }
                    
                    if connection.isGuestConnection {
                        Text("• Guest")
                            .font(.system(size: connectionManager.fontSize - 2))
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                // Logging Controls
                HStack(spacing: 8) {
                    if connection.isLogging {
                        Button(action: {
                            connection.stopLogging()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 16 * connectionManager.iconScale))
                                    .foregroundColor(.red)
                                Text("Stop Log")
                                    .font(.system(size: connectionManager.fontSize - 2))
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Button(action: {
                            connection.startLogging()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "record.circle")
                                    .font(.system(size: 16 * connectionManager.iconScale))
                                    .foregroundColor(.red)
                                Text("Start Log")
                                    .font(.system(size: connectionManager.fontSize - 2))
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(!connection.isConnected)
                    }
                }
                
                Text(connection.world.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Terminal Output
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TerminalOutputView(
                            text: connection.outputBuffer,
                            fontSize: connectionManager.fontSize,
                            highlightRules: connectionManager.highlightRules,
                            highlightCache: highlightCache,
                            cachedAttributedString: $cachedAttributedString,
                            cachedTextLength: $cachedTextLength,
                            lastProcessedTextLength: $lastProcessedTextLength
                        )
                        .id("bottom")
                    }
                }
                .onAppear {
                    // Scroll to bottom when view appears
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: connection.outputChangeCount) {
                    // Trigger debounced scroll when output buffer changes
                    debounceScrollUpdate(proxy: proxy)
                }
                .onChange(of: connectionManager.highlightRules.count) {
                    // Clear all caches when rules change
                    highlightCache.clearAttributedStringCache()
                    cachedAttributedString = nil
                    cachedTextLength = 0
                    lastProcessedTextLength = 0
                }
                .onTapGesture {
                    // Don't clear badge on click - let user manually clear by switching tabs
                }
            }
            
            Divider()
            
            // Input Area
            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $connection.inputText)
                        .font(.system(size: connectionManager.fontSize, design: .monospaced))
                        .frame(minHeight: 80, maxHeight: 120) // 4-5 lines tall
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .disabled(!connection.isConnected)
                        .focused($isInputFocused)
                        .onChange(of: connection.inputText) {
                            // Check if the last character is a newline (Enter key)
                            if connection.inputText.hasSuffix("\n") {
                                // Remove the newline and send the command
                                connection.inputText = String(connection.inputText.dropLast())
                                sendCommand()
                            }
                        }
                    
                    if connection.inputText.isEmpty {
                        Text("Type command...")
                            .font(.system(size: connectionManager.fontSize, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                
                HStack {
                    Spacer()
                    Button("Send") {
                        sendCommand()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(connection.inputText.isEmpty || !connection.isConnected)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            // Clear badge when user views this terminal
            connectionManager.notificationManager.clearBadgeForActiveConnection()
            
            // Restore focus after a brief delay to allow view to fully render
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
        .onTapGesture {
            // Clear badge when user taps on terminal
            connectionManager.notificationManager.clearBadgeForActiveConnection()
        }
        .onChange(of: connection.isConnected) { _, isConnected in
            // Automatically focus the input when connection is established
            if isConnected {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isInputFocused = true
                }
            }
        }
    }
    
    private func debounceScrollUpdate(proxy: ScrollViewProxy) {
        // Cancel any pending scroll update
        pendingScrollUpdate?.cancel()
        
        // Schedule a new scroll update
        let workItem = DispatchWorkItem {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
        pendingScrollUpdate = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + scrollDebounceInterval, execute: workItem)
    }
    
    private func sendCommand() {
        guard !connection.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let commandToSend = connection.inputText
        
        connection.sendCommand(commandToSend)
        connection.inputText = ""
        
        // Don't clear badge on command send - let user manually clear by switching tabs
    }
    
}

// MARK: - Terminal Output View (Optimized)
struct TerminalOutputView: View {
    let text: String
    let fontSize: CGFloat
    let highlightRules: [HighlightRule]
    let highlightCache: HighlightCache
    @Binding var cachedAttributedString: NSAttributedString?
    @Binding var cachedTextLength: Int
    @Binding var lastProcessedTextLength: Int
    
    @State private var displayedAttributedString: NSAttributedString?
    @State private var isProcessing: Bool = false
    @State private var currentProcessingTask: DispatchWorkItem?
    
    var body: some View {
        Group {
            if let displayed = displayedAttributedString {
                Text(AttributedString(displayed))
            } else {
                // Show plain text immediately while processing highlights
                Text(text)
            }
        }
        .font(.system(size: fontSize, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: text) { _, newText in
            processHighlightsAsync(text: newText)
        }
        .onChange(of: highlightRules.count) {
            // Rules changed, need to reprocess
            displayedAttributedString = nil
            processHighlightsAsync(text: text)
        }
        .onChange(of: cachedAttributedString) { _, newValue in
            // Update displayed string when highlighting completes
            if let newValue = newValue, cachedTextLength == text.count {
                displayedAttributedString = newValue
                isProcessing = false
                currentProcessingTask = nil
            }
        }
        .onAppear {
            processHighlightsAsync(text: text)
        }
        .onDisappear {
            // Cancel any background processing when view disappears
            currentProcessingTask?.cancel()
            currentProcessingTask = nil
            isProcessing = false
        }
    }
    
    private func processHighlightsAsync(text: String) {
        let enabledRules = highlightRules.filter { $0.isEnabled }
        let textLength = text.count
        
        // Fast path: No rules means no processing needed (early return)
        if enabledRules.isEmpty {
            displayedAttributedString = nil
            return
        }
        
        // Fast path: If we already have a cached result for this exact text length, reuse it immediately
        if let cached = cachedAttributedString, cachedTextLength == textLength {
            displayedAttributedString = cached
            return
        }
        
        // Cancel any existing processing task
        if let existingTask = currentProcessingTask {
            existingTask.cancel()
        }
        currentProcessingTask = nil
        
        // Don't start new processing if already processing the same text
        guard !isProcessing || cachedTextLength != textLength else { return }
        isProcessing = true
        
        // Capture current values
        var currentLastProcessed = lastProcessedTextLength
        let currentRules = enabledRules
        
        // Chunk guard: If new text exceeds threshold, force full processing
        let newTextSize = textLength - currentLastProcessed
        let largeChunkThreshold = 100_000 // chars
        if newTextSize > largeChunkThreshold && currentLastProcessed > 0 {
            // Skip incremental processing for very large chunks
            currentLastProcessed = 0 // Force full reprocess instead of incremental
        }
        
        // Capture necessary values for background processing
        let cache = highlightCache
        let finalLastProcessed = currentLastProcessed // Capture for background task
        
        // Process on background thread
        let workItem = DispatchWorkItem {
            // Check if we can do incremental update
            let canDoIncremental = textLength > finalLastProcessed && finalLastProcessed > 0
            
            let result: NSAttributedString
            
            if canDoIncremental {
                // Get the cached base and append new text
                let cacheKey = "attributed-\(finalLastProcessed)"
                
                if let baseAttributed = cache.getCachedAttributedString(for: cacheKey) {
                    // Only process new text
                    let newTextStart = text.index(text.startIndex, offsetBy: finalLastProcessed)
                    let newText = String(text[newTextStart...])
                    
                    if !newText.isEmpty && newText.count < 100000 {
                        result = Self.appendHighlightedText(base: baseAttributed, newText: newText, fullText: text, rules: currentRules, highlightCache: cache)
                        
                        // Cache the result
                        let newCacheKey = "attributed-\(textLength)"
                        cache.cacheAttributedString(result, for: newCacheKey)
                    } else {
                        // Fall back to full processing if incremental is too large
                        result = Self.createAttributedString(from: text, rules: currentRules, highlightCache: cache)
                        let cacheKey = "attributed-\(textLength)"
                        cache.cacheAttributedString(result, for: cacheKey)
                    }
                } else {
                    // No cached base, do full processing
                    result = Self.createAttributedString(from: text, rules: currentRules, highlightCache: cache)
                    let cacheKey = "attributed-\(textLength)"
                    cache.cacheAttributedString(result, for: cacheKey)
                }
            } else {
                // Full processing (first time or rules changed)
                result = Self.createAttributedString(from: text, rules: currentRules, highlightCache: cache)
                let cacheKey = "attributed-\(textLength)"
                cache.cacheAttributedString(result, for: cacheKey)
            }
            
            // Update UI on main thread
            DispatchQueue.main.async {
                // Use the bindings to update state
                // Note: Cancellation check happens via workItem.cancel(), but we update here
                // since the work already completed. If cancelled, we just won't start new work.
                cachedAttributedString = result
                cachedTextLength = textLength
                lastProcessedTextLength = textLength
            }
        }
        
        // Store and execute work item
        currentProcessingTask = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
        
        // Use onChange to update displayed string when cached value changes
        // This is handled by the onChange in the body
    }
    
    // Append and highlight only new text (static for background processing)
    private static func appendHighlightedText(base: NSAttributedString, newText: String, fullText: String, rules: [HighlightRule], highlightCache: HighlightCache) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: base)
        let startOffset = base.length
        
        // Append plain new text
        result.append(NSAttributedString(string: newText))
        
        // Only highlight the new text portion
        let newTextRange = NSRange(location: startOffset, length: newText.utf16.count)
        
        // Apply page message highlighting to new text only
        Self.highlightPageMessagesInRange(in: result, text: fullText, range: newTextRange, highlightCache: highlightCache)
        
        // Apply user rules to new text only
        let textLength = fullText.utf16.count
        for rule in rules {
            if let regex = highlightCache.getRegex(for: rule.pattern) {
                let matches = regex.matches(in: fullText, options: [], range: newTextRange)
                
                let isFullLinePattern = rule.pattern.hasPrefix("^") && rule.pattern.hasSuffix("$")
                
                for match in matches.reversed() {
                    // Validate match range
                    guard match.range.location >= 0, match.range.location < textLength,
                          match.range.location + match.range.length <= textLength else {
                        continue
                    }
                    
                    let color = Self.colorForRule(rule)
                    
                    if isFullLinePattern {
                        let lineRange = Self.findLineRange(for: match.range, in: fullText)
                        // Validate line range
                        if lineRange.location >= 0 && lineRange.location + lineRange.length <= result.length {
                            result.addAttribute(.foregroundColor, value: NSColor(color), range: lineRange)
                        }
                    } else {
                        // Validate match range for attributed string
                        if match.range.location >= 0 && match.range.location + match.range.length <= result.length {
                            result.addAttribute(.foregroundColor, value: NSColor(color), range: match.range)
                        }
                    }
                }
            }
        }
        
        return result
    }
    
    private static func createAttributedString(from text: String, rules: [HighlightRule], highlightCache: HighlightCache) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        let textLength = text.utf16.count
        
        // Automatically highlight page messages in yellow
        Self.highlightPageMessages(in: attributedString, text: text, highlightCache: highlightCache)
        
        for rule in rules {
            // Get or create cached regex
            let regex = highlightCache.getRegex(for: rule.pattern)
            guard let regex = regex else { continue }
            
            // Check if this is a full-line pattern (starts with ^ and ends with $)
            let isFullLinePattern = rule.pattern.hasPrefix("^") && rule.pattern.hasSuffix("$")
            
            let searchRange = NSRange(location: 0, length: textLength)
            let matches = regex.matches(in: text, options: [], range: searchRange)
            
            if isFullLinePattern {
                for match in matches.reversed() {
                    // Validate match range
                    guard match.range.location >= 0, match.range.location < textLength,
                          match.range.location + match.range.length <= textLength else {
                        continue
                    }
                    
                    let color = Self.colorForRule(rule)
                    
                    // Find the line boundaries and highlight the entire line
                    let lineRange = Self.findLineRange(for: match.range, in: text)
                    
                    // Validate line range
                    if lineRange.location >= 0 && lineRange.location + lineRange.length <= attributedString.length {
                        attributedString.addAttribute(.foregroundColor, value: NSColor(color), range: lineRange)
                    }
                }
            } else {
                for match in matches.reversed() {
                    // Validate match range
                    guard match.range.location >= 0, match.range.location < textLength,
                          match.range.location + match.range.length <= textLength else {
                        continue
                    }
                    
                    let color = Self.colorForRule(rule)
                    
                    // For partial patterns, highlight only the matched text
                    if match.range.location >= 0 && match.range.location + match.range.length <= attributedString.length {
                        attributedString.addAttribute(.foregroundColor, value: NSColor(color), range: match.range)
                    }
                }
            }
        }
        
        return attributedString
    }
    
    private static func findLineRange(for matchRange: NSRange, in text: String) -> NSRange {
        let textNSString = text as NSString
        
        // Find the start of the line
        var lineStart = matchRange.location
        while lineStart > 0 && textNSString.character(at: lineStart - 1) != 10 { // 10 is newline
            lineStart -= 1
        }
        
        // Find the end of the line
        var lineEnd = matchRange.location + matchRange.length
        while lineEnd < textNSString.length && textNSString.character(at: lineEnd) != 10 { // 10 is newline
            lineEnd += 1
        }
        
        return NSRange(location: lineStart, length: lineEnd - lineStart)
    }
    
    private static func colorForRule(_ rule: HighlightRule) -> Color {
        switch rule.color.lowercased() {
        // Basic Colors
        case "red": return .red
        case "green": return .green
        case "blue": return .blue
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "cyan": return .cyan
        case "pink": return .pink
        case "white": return .white
        case "black": return .black
        
        // Extended Colors
        case "brown": return .brown
        case "gray": return .gray
        case "indigo": return .indigo
        case "mint": return .mint
        case "teal": return .teal
        case "lime": return Color(red: 0.5, green: 1.0, blue: 0.0)
        case "magenta": return Color(red: 1.0, green: 0.0, blue: 1.0)
        case "navy": return Color(red: 0.0, green: 0.0, blue: 0.5)
        case "olive": return Color(red: 0.5, green: 0.5, blue: 0.0)
        case "maroon": return Color(red: 0.5, green: 0.0, blue: 0.0)
        
        // Bright Colors
        case "brightred": return Color(red: 1.0, green: 0.0, blue: 0.0)
        case "brightgreen": return Color(red: 0.0, green: 1.0, blue: 0.0)
        case "brightblue": return Color(red: 0.0, green: 0.0, blue: 1.0)
        case "brightyellow": return Color(red: 1.0, green: 1.0, blue: 0.0)
        case "brightorange": return Color(red: 1.0, green: 0.5, blue: 0.0)
        case "brightpurple": return Color(red: 1.0, green: 0.0, blue: 1.0)
        case "brightcyan": return Color(red: 0.0, green: 1.0, blue: 1.0)
        case "brightpink": return Color(red: 1.0, green: 0.75, blue: 0.8)
        case "brightwhite": return Color(red: 1.0, green: 1.0, blue: 1.0)
        case "brightblack": return Color(red: 0.0, green: 0.0, blue: 0.0)
        
        // Pastel Colors
        case "lightred": return Color(red: 1.0, green: 0.7, blue: 0.7)
        case "lightgreen": return Color(red: 0.7, green: 1.0, blue: 0.7)
        case "lightblue": return Color(red: 0.7, green: 0.7, blue: 1.0)
        case "lightyellow": return Color(red: 1.0, green: 1.0, blue: 0.7)
        case "lightorange": return Color(red: 1.0, green: 0.8, blue: 0.6)
        case "lightpurple": return Color(red: 0.9, green: 0.7, blue: 1.0)
        case "lightcyan": return Color(red: 0.7, green: 1.0, blue: 1.0)
        case "lightpink": return Color(red: 1.0, green: 0.9, blue: 0.9)
        case "lightgray": return Color(red: 0.8, green: 0.8, blue: 0.8)
        case "lightbrown": return Color(red: 0.8, green: 0.6, blue: 0.4)
        
        default:
            // Handle hex color strings (new format)
            if rule.color.hasPrefix("#") && rule.color.count == 7 {
                let hex = String(rule.color.dropFirst())
                if let hexValue = Int(hex, radix: 16) {
                    let red = Double((hexValue >> 16) & 0xFF) / 255.0
                    let green = Double((hexValue >> 8) & 0xFF) / 255.0
                    let blue = Double(hexValue & 0xFF) / 255.0
                    return Color(red: red, green: green, blue: blue)
                }
            }
            
            // Handle RGB color strings like "rgb(255,128,64)"
            if rule.color.hasPrefix("rgb(") && rule.color.hasSuffix(")") {
                let rgbString = String(rule.color.dropFirst(4).dropLast(1))
                let components = rgbString.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if components.count == 3 {
                    return Color(red: Double(components[0]) / 255.0,
                                green: Double(components[1]) / 255.0,
                                blue: Double(components[2]) / 255.0)
                }
            }
            return .primary
        }
    }
    
    private static func highlightPageMessages(in attributedString: NSMutableAttributedString, text: String, highlightCache: HighlightCache) {
        highlightPageMessagesInRange(in: attributedString, text: text, range: NSRange(location: 0, length: text.utf16.count), highlightCache: highlightCache)
    }
    
    private static func highlightPageMessagesInRange(in attributedString: NSMutableAttributedString, text: String, range: NSRange, highlightCache: HighlightCache) {
        // Validate range bounds
        let textLength = text.utf16.count
        guard range.location >= 0, range.length >= 0, range.location <= textLength else {
            return
        }
        
        // Clamp range to text bounds
        let clampedLocation = min(range.location, textLength)
        let clampedLength = min(range.length, textLength - clampedLocation)
        let validRange = NSRange(location: clampedLocation, length: clampedLength)
        
        // Pattern to match page messages - both incoming and outgoing
        let pagePatterns = [
            // Incoming page: "Hashiren pages, \"message\""
            "\\b\\w+\\s+pages,\\s+\"[^\"]*\"",
            // Outgoing page: "You paged Hashiren with: message"
            "You paged \\w+ with: .*",
            // Alternative page format: "You paged Hashiren with: Michelina pages, \"message\""
            "You paged \\w+ with: \\w+ pages, \"[^\"]*\""
        ]
        
        for pattern in pagePatterns {
            // Use cached regex
            if let regex = highlightCache.getRegex(for: pattern) {
                let matches = regex.matches(in: text, options: [], range: validRange)
                
                for match in matches.reversed() {
                    // Validate match range before processing
                    guard match.range.location >= 0, match.range.location < textLength,
                          match.range.location + match.range.length <= textLength else {
                        continue
                    }
                    
                    // Find the line boundaries and highlight the entire line
                    let lineRange = Self.findLineRange(for: match.range, in: text)
                    
                    // Validate line range before applying attribute
                    if lineRange.location >= 0 && lineRange.location + lineRange.length <= attributedString.length {
                        attributedString.addAttribute(.foregroundColor, value: NSColor.yellow, range: lineRange)
                    }
                }
            }
        }
    }
}

// MARK: - Highlight Cache System
class HighlightCache: ObservableObject {
    private var regexCache: [String: NSRegularExpression] = [:]
    private var attributedStringCache: [String: NSAttributedString] = [:]
    private let cacheQueue = DispatchQueue(label: "com.pernclient.regexcache", attributes: .concurrent)
    var rulesHash: String = ""
    private let maxCacheSize = 50 // Limit cache to prevent unbounded growth
    
    func getRegex(for pattern: String) -> NSRegularExpression? {
        // Check cache first (thread-safe read)
        return cacheQueue.sync {
            if let cached = regexCache[pattern] {
                return cached
            }
            
            // Not cached, create new regex
            do {
                // Try as regex first
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                
                // Cache it (thread-safe write)
                cacheQueue.async(flags: .barrier) { [weak self] in
                    self?.regexCache[pattern] = regex
                }
                
                return regex
            } catch {
                // If regex fails, try as literal
                do {
                    let escapedPattern = NSRegularExpression.escapedPattern(for: pattern)
                    let regex = try NSRegularExpression(pattern: escapedPattern, options: [.caseInsensitive])
                    
                    cacheQueue.async(flags: .barrier) { [weak self] in
                        self?.regexCache[pattern] = regex
                    }
                    
                    return regex
                } catch {
                    return nil
                }
            }
        }
    }
    
    func getCachedAttributedString(for key: String) -> NSAttributedString? {
        return cacheQueue.sync {
            return attributedStringCache[key]
        }
    }
    
    func cacheAttributedString(_ attributedString: NSAttributedString, for key: String) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Limit cache size to prevent unbounded growth
            if self.attributedStringCache.count >= self.maxCacheSize {
                // Remove oldest entries (simple FIFO)
                let keysToRemove = Array(self.attributedStringCache.keys.prefix(10))
                keysToRemove.forEach { self.attributedStringCache.removeValue(forKey: $0) }
            }
            
            self.attributedStringCache[key] = attributedString
        }
    }
    
    func clearAttributedStringCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.attributedStringCache.removeAll()
        }
    }
    
    func clearCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.regexCache.removeAll()
            self?.attributedStringCache.removeAll()
        }
    }
}

#Preview {
    let connectionManager = PernConnectionManager()
    let world = PernWorld(name: "Test World", hostname: "localhost", port: 7007)
    let character = PernCharacter(name: "TestCharacter", password: "password", worldId: world.id)
    let connection = PernConnection(character: character, world: world)
    
    return PernTerminalView(connection: connection, connectionManager: connectionManager)
        .frame(width: 800, height: 600)
}

