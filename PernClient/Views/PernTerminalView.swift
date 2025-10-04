import SwiftUI

struct PernTerminalView: View {
    @ObservedObject var connection: PernConnection
    @ObservedObject var connectionManager: PernConnectionManager
    @FocusState private var isInputFocused: Bool
    @State private var scrollToBottom = false
    
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
                        highlightedText(connection.outputBuffer)
                            .font(.system(size: connectionManager.fontSize, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .id("bottom")
                    }
                }
                .onChange(of: connection.outputBuffer) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: connection.lastActivity) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: connectionManager.highlightRules.count) { _ in
                    // Force re-evaluation of highlighting when rules change
                    print("🔍 Highlight rules changed, forcing re-evaluation")
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
            print("🔄 Terminal view appeared, clearing badge")
            connectionManager.notificationManager.clearBadgeForActiveConnection()
        }
        .onTapGesture {
            // Clear badge when user taps on terminal
            print("🔄 Terminal tapped, clearing badge")
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
    
    private func sendCommand() {
        guard !connection.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        connection.sendCommand(connection.inputText)
        connection.inputText = ""
        
        // Don't clear badge on command send - let user manually clear by switching tabs
    }
    
    // MARK: - Highlighting Functions
    private func highlightedText(_ text: String) -> some View {
        let enabledRules = connectionManager.highlightRules.filter { $0.isEnabled }
        
        print("🔍 Highlighting text with \(enabledRules.count) enabled rules")
        for rule in enabledRules {
            print("🔍 Enabled rule: '\(rule.pattern)' with color '\(rule.color)'")
        }
        
        if enabledRules.isEmpty {
            return AnyView(Text(text))
        } else {
            let attributedString = createAttributedString(from: text, rules: enabledRules)
            return AnyView(Text(AttributedString(attributedString)))
        }
    }
    
    private func createAttributedString(from text: String, rules: [HighlightRule]) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        
        for rule in rules {
            print("🔍 Processing rule: '\(rule.pattern)'")
            do {
                // Check if this is a full-line pattern (starts with ^ and ends with $)
                let isFullLinePattern = rule.pattern.hasPrefix("^") && rule.pattern.hasSuffix("$")
                
                if isFullLinePattern {
                    // For full-line patterns, extract the core pattern (remove ^ and $)
                    let corePattern = String(rule.pattern.dropFirst().dropLast())
                    print("🔍 Full-line pattern detected, core pattern: '\(corePattern)'")
                    
                    // Use the core pattern to find matches anywhere in the text
                    let regex = try NSRegularExpression(pattern: corePattern, options: [.caseInsensitive])
                    let range = NSRange(location: 0, length: text.utf16.count)
                    let matches = regex.matches(in: text, options: [], range: range)
                    
                    print("🔍 Found \(matches.count) matches for core pattern '\(corePattern)'")
                    print("🔍 Text being searched: '\(text.prefix(100))...'")
                    
                    for match in matches.reversed() {
                        let color = colorForRule(rule)
                        
                        // Find the line boundaries and highlight the entire line
                        let lineRange = findLineRange(for: match.range, in: text)
                        attributedString.addAttribute(.foregroundColor, value: NSColor(color), range: lineRange)
                        print("🔍 Highlighting full line: \(lineRange)")
                        let lineText = (text as NSString).substring(with: lineRange)
                        print("🔍 Line text: '\(lineText)'")
                    }
                } else {
                    // For regular patterns, use the pattern as-is
                    let regex = try NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive])
                    let range = NSRange(location: 0, length: text.utf16.count)
                    let matches = regex.matches(in: text, options: [], range: range)
                    
                    print("🔍 Found \(matches.count) matches for '\(rule.pattern)'")
                    print("🔍 Text being searched: '\(text.prefix(100))...'")
                    
                    for match in matches.reversed() {
                        let color = colorForRule(rule)
                        
                        // For partial patterns, highlight only the matched text
                        attributedString.addAttribute(.foregroundColor, value: NSColor(color), range: match.range)
                        let matchedText = (text as NSString).substring(with: match.range)
                        print("🔍 Highlighting partial match: '\(matchedText)'")
                    }
                }
            } catch {
                // If regex fails, treat as literal text
                let escapedPattern = NSRegularExpression.escapedPattern(for: rule.pattern)
                do {
                    let regex = try NSRegularExpression(pattern: escapedPattern, options: [.caseInsensitive])
                    let range = NSRange(location: 0, length: text.utf16.count)
                    let matches = regex.matches(in: text, options: [], range: range)
                    
                    print("🔍 Found \(matches.count) literal matches for '\(rule.pattern)'")
                    for match in matches.reversed() {
                        let color = colorForRule(rule)
                        attributedString.addAttribute(.foregroundColor, value: NSColor(color), range: match.range)
                    }
                } catch {
                    print("Error creating regex for pattern '\(rule.pattern)': \(error)")
                }
            }
        }
        
        return attributedString
    }
    
    private func findLineRange(for matchRange: NSRange, in text: String) -> NSRange {
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
    
    private func colorForRule(_ rule: HighlightRule) -> Color {
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
}

#Preview {
    let connectionManager = PernConnectionManager()
    let world = PernWorld(name: "Test World", hostname: "localhost", port: 7007)
    let character = PernCharacter(name: "TestCharacter", password: "password", worldId: world.id)
    let connection = PernConnection(character: character, world: world)
    
    return PernTerminalView(connection: connection, connectionManager: connectionManager)
        .frame(width: 800, height: 600)
}
