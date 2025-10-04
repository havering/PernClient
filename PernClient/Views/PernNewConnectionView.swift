import SwiftUI

struct PernNewConnectionView: View {
    @ObservedObject var connectionManager: PernConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedWorld: PernWorld?
    @State private var selectedCharacter: PernCharacter?
    @State private var connectionType: ConnectionType = .guest
    @State private var showingNewWorld = false
    @State private var showingNewCharacter = false

    enum ConnectionType: String, CaseIterable {
        case guest = "guest"
        case createNew = "createNew"
        case existing = "existing"
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("New Connection")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)
            
            // World Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Select World")
                    .font(.headline)
                
                if connectionManager.worlds.isEmpty {
                    Text("No worlds available. Create a new world first.")
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                } else {
                    Picker("World", selection: $selectedWorld) {
                        Text("Select a world...").tag(nil as PernWorld?)
                        ForEach(connectionManager.worlds) { world in
                            Text(world.name).tag(world as PernWorld?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Button("Add New World") {
                    showingNewWorld = true
                }
                .buttonStyle(.bordered)
            }
            
            // Connection Type Selection
            if let world = selectedWorld {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection Type")
                        .font(.headline)
                    
                    Picker("Connection Type", selection: $connectionType) {
                        Text("🔓 Guest Connection (blank)").tag(ConnectionType.guest)
                        Text("🆕 Create new character during connection").tag(ConnectionType.createNew)
                        Text("👤 Use existing character").tag(ConnectionType.existing)
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    // Help text
                    switch connectionType {
                    case .guest:
                        Text("Connect without character info - follow server prompts (e.g., 'connect guest guest')")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .createNew:
                        Text("You'll create a new character after connecting to the world")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .existing:
                        Text("You'll connect using the selected character")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Character Selection (only for existing character type)
                if connectionType == .existing {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Character")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        let worldCharacters = connectionManager.charactersForWorld(world)
                        
                        if worldCharacters.isEmpty {
                            Text("No characters for this world. Create a new character first.")
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                        } else {
                            Picker("Character", selection: $selectedCharacter) {
                                Text("Select a character...").tag(nil as PernCharacter?)
                                ForEach(worldCharacters) { character in
                                    Text(character.name).tag(character as PernCharacter?)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        
                        Button("Pre-create New Character") {
                            showingNewCharacter = true
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
            } else {
                Text("Select a world first")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            }
            
            Spacer()
            
            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Connect") {
                    connect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedWorld == nil || (connectionType == .existing && selectedCharacter == nil))
            }
        }
        .padding()
        .frame(width: 500, height: 500)
        .sheet(isPresented: $showingNewWorld) {
            PernNewWorldView(connectionManager: connectionManager)
        }
        .sheet(isPresented: $showingNewCharacter) {
            if let world = selectedWorld {
                PernNewCharacterView(connectionManager: connectionManager, world: world)
                    .onDisappear {
                        // Refresh the character list when the sheet is dismissed
                        // This ensures the picker shows newly created characters
                        selectedCharacter = nil
                    }
            }
        }
    }
    
    private func connect() {
        guard let world = selectedWorld else { return }
        
        switch connectionType {
        case .guest:
            connectionManager.addGuestConnection(world: world)
        case .createNew:
            connectionManager.addConnectionWithoutCharacter(world: world)
        case .existing:
            if let character = selectedCharacter {
                connectionManager.addConnection(character: character, world: world)
            }
        }
        dismiss()
    }
}

struct PernNewWorldView: View {
    @ObservedObject var connectionManager: PernConnectionManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var hostname = ""
    @State private var port = "7007"
    @State private var description = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("New World")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 12) {
                TextField("World Name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Hostname", text: $hostname)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Port", text: $port)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Description (Optional)", text: $description, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...6)
            }
            .padding()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Save") {
                    saveWorld()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || hostname.isEmpty || port.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 350)
    }
    
    private func saveWorld() {
        guard let portInt = Int(port) else { return }
        let newWorld = PernWorld(name: name, hostname: hostname, port: portInt, description: description)
        connectionManager.addWorld(newWorld)
        dismiss()
    }
}

struct PernNewCharacterView: View {
    @ObservedObject var connectionManager: PernConnectionManager
    let world: PernWorld
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var password = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("New Character")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("World: \(world.name)")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                TextField("Character Name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Save") {
                    saveCharacter()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || password.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
    }
    
    private func saveCharacter() {
        let newCharacter = PernCharacter(name: name, password: password, worldId: world.id)
        print("💾 Pre-creating character: \(newCharacter.name) for world: \(newCharacter.worldId)")
        connectionManager.addCharacter(newCharacter)
        print("💾 Character pre-created successfully")
        dismiss()
    }
}
