import SwiftUI

struct PernSettingsView: View {
    @ObservedObject var connectionManager: PernConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingNewRule = false
    @State private var editingRule: HighlightRule?
    @State private var editingWorld: PernWorld?
    @State private var editingCharacter: PernCharacter?
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and close button
            HStack {
                Text("Settings")
                    .font(.system(size: connectionManager.fontSize + 8, weight: .bold))
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 20)

            // Tab Selection
            Picker("Settings", selection: $selectedTab) {
                Text("Highlight Rules").tag(0)
                Text("Worlds").tag(1)
                Text("Characters").tag(2)
                Text("Accessibility").tag(3)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 20)

            // Content based on selected tab
            Group {
                switch selectedTab {
                case 0:
                    highlightRulesView
                case 1:
                    worldsView
                case 2:
                    charactersView
                case 3:
                    accessibilityView
                default:
                    highlightRulesView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 500)
        .sheet(isPresented: $showingNewRule) {
            PernHighlightRuleEditor(connectionManager: connectionManager, rule: $editingRule) {
                editingRule = nil
            }
        }
        .sheet(item: $editingWorld) { world in
            PernWorldEditor(connectionManager: connectionManager, world: world) {
                editingWorld = nil
            }
        }
        .sheet(item: $editingCharacter) { character in
            PernCharacterEditor(connectionManager: connectionManager, character: character) {
                editingCharacter = nil
            }
        }
    }

    private var highlightRulesView: some View {
        VStack(spacing: 0) {
            if connectionManager.highlightRules.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "paintbrush.pointed")
                        .font(.system(size: 48 * connectionManager.iconScale))
                        .foregroundColor(.secondary)
                    
                    Text("No Highlight Rules")
                        .font(.system(size: connectionManager.fontSize + 4, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text("Create your first highlight rule to customize how text appears in your terminal.")
                        .font(.system(size: connectionManager.fontSize))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            } else {
                List {
                    ForEach(connectionManager.highlightRules) { rule in
                        HStack(spacing: 16) {
                            // Color indicator
                            Circle()
                                .fill(colorForRule(rule))
                                .frame(width: 20 * connectionManager.iconScale, height: 20 * connectionManager.iconScale)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                                )
                            
                            // Pattern text
                            Text(rule.pattern)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            // Toggle
                            Toggle("", isOn: .constant(rule.isEnabled))
                                .onChange(of: rule.isEnabled) {
                                    if let index = connectionManager.highlightRules.firstIndex(where: { $0.id == rule.id }) {
                                        connectionManager.highlightRules[index].isEnabled.toggle()
                                        connectionManager.saveHighlightRule(connectionManager.highlightRules[index])
                                    }
                                }
                            
                            // Edit and Delete buttons
                            HStack(spacing: 8) {
                                Button("Edit") {
                                    editingRule = rule
                                    showingNewRule = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button("Delete") {
                                    connectionManager.deleteHighlightRule(rule)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onDelete(perform: deleteHighlightRule)
                }
                .listStyle(.inset)
            }
            
            // Add button
            HStack {
                Spacer()
                Button(action: {
                    editingRule = nil
                    showingNewRule = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Add New Rule")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Spacer()
            }
            .padding(.top, 20)
            .padding(.bottom, 20)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private func deleteHighlightRule(at offsets: IndexSet) {
        for index in offsets {
            let rule = connectionManager.highlightRules[index]
            connectionManager.deleteHighlightRule(rule)
        }
    }

    private func colorForRule(_ rule: HighlightRule) -> Color {
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
        
        // Handle legacy named colors
        switch rule.color.lowercased() {
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
        case "gray", "grey": return .gray
        default: return .white
        }
    }

    private var worldsView: some View {
        VStack(spacing: 0) {
            if connectionManager.worlds.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "globe")
                        .font(.system(size: 48 * connectionManager.iconScale))
                        .foregroundColor(.secondary)
                    
                    Text("No Worlds")
                        .font(.system(size: connectionManager.fontSize + 4, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text("Add your first world to start connecting to MUD servers.")
                        .font(.system(size: connectionManager.fontSize))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            } else {
                List {
                    ForEach(connectionManager.worlds) { world in
                        HStack(spacing: 16) {
                            Image(systemName: "globe")
                                .font(.system(size: 24 * connectionManager.iconScale))
                                .foregroundColor(.accentColor)
                                .frame(width: 30 * connectionManager.iconScale)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(world.name)
                                    .font(.system(size: connectionManager.fontSize + 2, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Text("\(world.hostname):\(String(world.port))")
                                    .font(.system(size: connectionManager.fontSize))
                                    .foregroundColor(.secondary)
                                
                                if !world.description.isEmpty {
                                    Text(world.description)
                                        .font(.system(size: connectionManager.fontSize - 2))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 8) {
                                Button("Edit") {
                                    editingWorld = world
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button("Delete") {
                                    connectionManager.deleteWorld(world)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onDelete(perform: deleteWorld)
                }
                .listStyle(.inset)
            }
            
            // Add button
            HStack {
                Spacer()
                Button(action: {
                    // Add new world functionality
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Add New World")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Spacer()
            }
            .padding(.top, 20)
            .padding(.bottom, 20)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private func deleteWorld(at offsets: IndexSet) {
        for index in offsets {
            let world = connectionManager.worlds[index]
            connectionManager.deleteWorld(world)
        }
    }

    private var charactersView: some View {
        VStack(spacing: 0) {
            if connectionManager.characters.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 48 * connectionManager.iconScale))
                        .foregroundColor(.secondary)
                    
                    Text("No Characters")
                        .font(.system(size: connectionManager.fontSize + 4, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text("Add your first character to connect to worlds with saved credentials.")
                        .font(.system(size: connectionManager.fontSize))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            } else {
                List {
                    ForEach(connectionManager.characters) { character in
                        HStack(spacing: 16) {
                            Image(systemName: "person.circle")
                                .font(.system(size: 24 * connectionManager.iconScale))
                                .foregroundColor(.accentColor)
                                .frame(width: 30 * connectionManager.iconScale)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(character.name)
                                    .font(.system(size: connectionManager.fontSize + 2, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                if let world = connectionManager.worlds.first(where: { $0.id == character.worldId }) {
                                    Text("World: \(world.name)")
                                        .font(.system(size: connectionManager.fontSize))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 8) {
                                Button("Edit") {
                                    editingCharacter = character
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button("Delete") {
                                    connectionManager.deleteCharacter(character)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onDelete(perform: deleteCharacter)
                }
                .listStyle(.inset)
            }
            
            // Add button
            HStack {
                Spacer()
                Button(action: {
                    // Add new character functionality
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Add New Character")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Spacer()
            }
            .padding(.top, 20)
            .padding(.bottom, 20)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private func deleteCharacter(at offsets: IndexSet) {
        for index in offsets {
            let character = connectionManager.characters[index]
            connectionManager.deleteCharacter(character)
        }
    }
    
    private var accessibilityView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Accessibility Settings")
                        .font(.system(size: connectionManager.fontSize + 4, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Customize the app's appearance to make it easier to use")
                        .font(.system(size: connectionManager.fontSize))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                
                // Icon Scale Setting
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Icon Size")
                            .font(.system(size: connectionManager.fontSize + 2, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(Int(connectionManager.iconScale * 100))%")
                            .font(.system(size: connectionManager.fontSize))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 16) {
                        Text("Small")
                            .font(.system(size: connectionManager.fontSize - 2))
                            .foregroundColor(.secondary)
                        
                        Slider(value: $connectionManager.iconScale, in: 0.5...2.0, step: 0.1)
                            .onChange(of: connectionManager.iconScale) { _, _ in
                                connectionManager.saveData()
                            }
                        
                        Text("Large")
                            .font(.system(size: connectionManager.fontSize - 2))
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Adjust the size of icons throughout the app. Larger icons are easier to see for users with vision difficulties.")
                        .font(.system(size: connectionManager.fontSize - 2))
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Font Size Setting
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Font Size")
                            .font(.system(size: connectionManager.fontSize + 2, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(Int(connectionManager.fontSize))pt")
                            .font(.system(size: connectionManager.fontSize))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 16) {
                        Text("Small")
                            .font(.system(size: connectionManager.fontSize - 2))
                            .foregroundColor(.secondary)
                        
                        Slider(value: $connectionManager.fontSize, in: 8...24, step: 1)
                            .onChange(of: connectionManager.fontSize) { _, _ in
                                connectionManager.saveData()
                            }
                        
                        Text("Large")
                            .font(.system(size: connectionManager.fontSize - 2))
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Adjust the size of text in the terminal and throughout the app.")
                        .font(.system(size: connectionManager.fontSize - 2))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
    }
}

struct PernHighlightRuleEditor: View {
    @ObservedObject var connectionManager: PernConnectionManager
    @Environment(\.dismiss) private var dismiss
    @Binding var rule: HighlightRule?
    var onDismiss: () -> Void

    @State private var pattern: String
    @State private var selectedColor: Color
    @State private var isEnabled: Bool

    init(connectionManager: PernConnectionManager, rule: Binding<HighlightRule?>, onDismiss: @escaping () -> Void) {
        self.connectionManager = connectionManager
        self._rule = rule
        self.onDismiss = onDismiss
        
        // Initialize with empty values - we'll update them in onAppear
        _pattern = State(initialValue: "")
        _selectedColor = State(initialValue: .white)
        _isEnabled = State(initialValue: true)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(rule == nil ? "New Highlight Rule" : "Edit Highlight Rule")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Divider()
            
            // Content section
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pattern")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("Enter text pattern to highlight", text: $pattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Color")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 16) {
                        // Color preview
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedColor)
                                .frame(width: 50 * connectionManager.iconScale, height: 50 * connectionManager.iconScale)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                            )
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ColorPicker("Choose a color for this highlight rule", selection: $selectedColor)
                                .font(.body)
                            
                            Text("This color will be used to highlight matching text in your terminal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Toggle("Enabled", isOn: $isEnabled)
                            .font(.headline)
                        
                        Spacer()
                    }
                    
                    Text("When enabled, this rule will highlight matching text in your terminal")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Bottom section with save button
            Divider()
            
            HStack {
                Spacer()
                
                Button("Save") {
                    saveRule()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(pattern.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600, height: 500)
        .onAppear {
            // Populate fields when the view appears
            if let rule = rule {
                pattern = rule.pattern
                selectedColor = colorFromString(rule.color)
                isEnabled = rule.isEnabled
            }
        }
    }

    private func saveRule() {
        let colorString = stringFromColor(selectedColor)
        if var existingRule = rule {
            existingRule.pattern = pattern
            existingRule.color = colorString
            existingRule.isEnabled = isEnabled
            connectionManager.saveHighlightRule(existingRule)
        } else {
            let newRule = HighlightRule(pattern: pattern, color: colorString, isEnabled: isEnabled)
            connectionManager.saveHighlightRule(newRule)
        }
        dismiss()
        onDismiss()
    }

    private func colorFromString(_ colorString: String) -> Color {
        // Handle hex color strings (new format)
        if colorString.hasPrefix("#") && colorString.count == 7 {
            let hex = String(colorString.dropFirst())
            if let hexValue = Int(hex, radix: 16) {
                let red = Double((hexValue >> 16) & 0xFF) / 255.0
                let green = Double((hexValue >> 8) & 0xFF) / 255.0
                let blue = Double(hexValue & 0xFF) / 255.0
                return Color(red: red, green: green, blue: blue)
            }
        }
        
        // Handle legacy named colors
        switch colorString.lowercased() {
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
        case "gray", "grey": return .gray
        default: return .white
        }
    }
    
    private func stringFromColor(_ color: Color) -> String {
        // Convert Color to a hex string representation
        // This allows us to store any color selection
        let uiColor = NSColor(color)
        let red = Int(uiColor.redComponent * 255)
        let green = Int(uiColor.greenComponent * 255)
        let blue = Int(uiColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

struct PernWorldEditor: View {
    @ObservedObject var connectionManager: PernConnectionManager
    let world: PernWorld
    let onDismiss: () -> Void
    
    @State private var name: String
    @State private var hostname: String
    @State private var port: String
    @State private var description: String
    
    init(connectionManager: PernConnectionManager, world: PernWorld, onDismiss: @escaping () -> Void) {
        self.connectionManager = connectionManager
        self.world = world
        self.onDismiss = onDismiss
        _name = State(initialValue: world.name)
        _hostname = State(initialValue: world.hostname)
        _port = State(initialValue: String(world.port))
        _description = State(initialValue: world.description)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit World")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Name")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("Enter world name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Hostname")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("Enter hostname", text: $hostname)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Port")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("Enter port number", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Description")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("Enter description (optional)", text: $description)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                
                Spacer()
                
                // Save button
                HStack {
                    Spacer()
                    
                    Button("Save Changes") {
                        saveWorld()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || hostname.isEmpty || port.isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 500)
    }
    
    private func saveWorld() {
        guard let portInt = Int(port) else { return }
        
        // Create a new world with the same ID by copying the existing world and updating its properties
        var updatedWorld = world
        updatedWorld.name = name
        updatedWorld.hostname = hostname
        updatedWorld.port = portInt
        updatedWorld.description = description
        
        connectionManager.saveWorld(updatedWorld)
        onDismiss()
    }
}

struct PernCharacterEditor: View {
    @ObservedObject var connectionManager: PernConnectionManager
    let character: PernCharacter
    let onDismiss: () -> Void
    
    @State private var name: String
    @State private var password: String
    @State private var selectedWorldId: UUID
    @State private var isAutoConnect: Bool
    
    init(connectionManager: PernConnectionManager, character: PernCharacter, onDismiss: @escaping () -> Void) {
        self.connectionManager = connectionManager
        self.character = character
        self.onDismiss = onDismiss
        _name = State(initialValue: character.name)
        _password = State(initialValue: character.password)
        _selectedWorldId = State(initialValue: character.worldId)
        _isAutoConnect = State(initialValue: connectionManager.isAutoConnectEnabled(for: character))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Character")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Character Name")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("Enter character name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Password")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    SecureField("Enter password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("World")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Picker("Select World", selection: $selectedWorldId) {
                        ForEach(connectionManager.worlds) { world in
                            Text(world.name).tag(world.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Auto-Connect")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Toggle("", isOn: $isAutoConnect)
                    }
                    
                    Text("Automatically connect to this world when the app starts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Save button
                HStack {
                    Spacer()
                    
                    Button("Save Changes") {
                        saveCharacter()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || password.isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 500)
    }
    
    private func saveCharacter() {
        // Create a new character with the same ID by copying the existing character and updating its properties
        var updatedCharacter = character
        updatedCharacter.name = name
        updatedCharacter.password = password
        updatedCharacter.worldId = selectedWorldId
        
        connectionManager.saveCharacter(updatedCharacter)
        
        // Handle auto-connect setting
        if isAutoConnect {
            if !connectionManager.isAutoConnectEnabled(for: updatedCharacter) {
                connectionManager.toggleAutoConnect(for: updatedCharacter)
            }
        } else {
            if connectionManager.isAutoConnectEnabled(for: updatedCharacter) {
                connectionManager.toggleAutoConnect(for: updatedCharacter)
            }
        }
        
        onDismiss()
    }
}

