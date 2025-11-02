import Foundation
import SwiftUI

class PernConnectionManager: ObservableObject {
    @Published var connections: [PernConnection] = []
    @Published var activeConnectionId: UUID?
    @Published var worlds: [PernWorld] = []
    @Published var characters: [PernCharacter] = []
    @Published var highlightRules: [HighlightRule] = []
    @Published var defaultWorldId: UUID?
    @Published var autoConnectCharacterIds: [UUID] = []
    @Published var fontSize: Double = 12.0
    @Published var iconScale: Double = 1.0
    @Published var isDarkMode: Bool = true
    
    let notificationManager = PernNotificationManager()
    private var notificationObserver: NSObjectProtocol?
    private let keychainManager = PernKeychainManager.shared

    private let userDefaults = UserDefaults.standard
    private let worldsKey = "PernWorlds"
    private let charactersKey = "PernCharacters"
    private let highlightRulesKey = "PernHighlightRules"
    private let defaultWorldKey = "PernDefaultWorld"
    private let autoConnectKey = "PernAutoConnectCharacters"
    private let fontSizeKey = "PernFontSize"
    private let iconScaleKey = "PernIconScale"
    private let darkModeKey = "PernDarkMode"

    init() {
        // Migrate passwords from UserDefaults to Keychain on first launch
        keychainManager.migratePasswordsIfNeeded()
        
        loadData()
        setupDefaultHighlightRules()
        notificationManager.requestNotificationPermission()
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .newMessageReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let userInfo = notification.userInfo,
               let connection = userInfo["connection"] as? String,
               let connectionId = userInfo["connectionId"] as? UUID {
                
                // Only show notification if this is not the currently active connection
                let isActiveConnection = connectionId == self?.activeConnectionId
                
                self?.notificationManager.newMessageReceived(from: connection, isActiveConnection: isActiveConnection)
            }
        }
    }
    
    deinit {
        // Clean up notification observer
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Connection Management
    func addConnection(character: PernCharacter, world: PernWorld) {
        let connection = PernConnection(character: character, world: world)
        connections.append(connection)
        activeConnectionId = connection.id
        connection.connect()
    }
    
    func addConnectionWithoutCharacter(world: PernWorld) {
        // Create a temporary character that will be replaced during connection
        let tempCharacter = PernCharacter(name: "New Character", password: "", worldId: world.id)
        let connection = PernConnection(character: tempCharacter, world: world)
        connection.needsCharacterCreation = true
        connections.append(connection)
        activeConnectionId = connection.id
        connection.connect()
    }
    
    func addGuestConnection(world: PernWorld) {
        // Create a connection without any character information
        let connection = PernConnection(character: nil, world: world)
        connection.isGuestConnection = true
        connections.append(connection)
        activeConnectionId = connection.id
        connection.connect()
    }
    
    func removeConnection(_ connection: PernConnection) {
        connection.disconnect()
        connections.removeAll { $0.id == connection.id }
        if activeConnectionId == connection.id {
            activeConnectionId = connections.first?.id
        }
        
        // Clear badge when disconnecting from a world
        notificationManager.clearBadge()
    }
    
    func setActiveConnection(_ connection: PernConnection) {
        activeConnectionId = connection.id
    }
    
    var activeConnection: PernConnection? {
        connections.first { $0.id == activeConnectionId }
    }
    
    func charactersForWorld(_ world: PernWorld) -> [PernCharacter] {
        print("🔍 Looking for characters for world: \(world.name) (ID: \(world.id))")
        
        // First try to match by world ID (for backwards compatibility)
        var matchingCharacters = characters.filter { $0.worldId == world.id }
        print("🔍 Found \(matchingCharacters.count) characters by world ID")
        
        // If no characters found by ID, try to match by world name
        if matchingCharacters.isEmpty {
            // Find characters that were created for worlds with the same name
            let worldNames = worlds.filter { $0.name == world.name }.map { $0.id }
            matchingCharacters = characters.filter { worldNames.contains($0.worldId) }
            print("🔍 Found \(matchingCharacters.count) characters by world name")
            
            // If still no characters found, try to find characters that might belong to this world
            // by looking for characters that were created for any world with the same name
            if matchingCharacters.isEmpty {
                // This is a fallback - look for characters that might have been created
                // for this world but with a different ID
                matchingCharacters = characters.filter { character in
                    // Check if this character was created for a world with the same name
                    return worlds.contains { $0.name == world.name && $0.id == character.worldId }
                }
                print("🔍 Found \(matchingCharacters.count) characters by fallback matching")
            }
        }
        
        // Update character world IDs to match the current world and save
        var updatedCharacters: [PernCharacter] = []
        var hasUpdates = false
        
        for character in matchingCharacters {
            if character.worldId != world.id {
                print("🔍 Updating character \(character.name) world ID from \(character.worldId) to \(world.id)")
                var updatedCharacter = character
                updatedCharacter.worldId = world.id
                updatedCharacters.append(updatedCharacter)
                hasUpdates = true
            } else {
                updatedCharacters.append(character)
            }
        }
        
        // Update the characters array with the corrected world IDs only if there are actual updates
        if hasUpdates {
            for updatedCharacter in updatedCharacters {
                if let index = characters.firstIndex(where: { $0.id == updatedCharacter.id }) {
                    characters[index] = updatedCharacter
                }
            }
            saveData()
        }
        
        print("🔍 Final result: \(updatedCharacters.count) characters for this world")
        for character in updatedCharacters {
            print("🔍 Character: \(character.name)")
        }
        return updatedCharacters
    }
    
    // MARK: - Data Persistence
    func addWorld(_ world: PernWorld) {
        worlds.append(world)
        saveData()
    }
    
    func saveWorld(_ world: PernWorld) {
        if let index = worlds.firstIndex(where: { $0.id == world.id }) {
            worlds[index] = world
        } else {
            worlds.append(world)
        }
        saveData()
    }
    
    func deleteWorld(_ world: PernWorld) {
        worlds.removeAll { $0.id == world.id }
        saveData()
    }
    
    func removeWorld(_ world: PernWorld) {
        worlds.removeAll { $0.id == world.id }
        saveData()
    }
    
    func addCharacter(_ character: PernCharacter) {
        characters.append(character)
        saveData()
    }
    
    func saveCharacter(_ character: PernCharacter) {
        if let index = characters.firstIndex(where: { $0.id == character.id }) {
            characters[index] = character
        } else {
            characters.append(character)
        }
        saveData()
    }
    
    func deleteCharacter(_ character: PernCharacter) {
        // Delete password from Keychain
        keychainManager.deletePassword(for: character.id)
        characters.removeAll { $0.id == character.id }
        saveData()
    }
    
    func removeCharacter(_ character: PernCharacter) {
        // Delete password from Keychain
        keychainManager.deletePassword(for: character.id)
        characters.removeAll { $0.id == character.id }
        saveData()
    }
    
    func saveHighlightRule(_ rule: HighlightRule) {
        if let index = highlightRules.firstIndex(where: { $0.id == rule.id }) {
            highlightRules[index] = rule
        } else {
            highlightRules.append(rule)
        }
        saveData()
    }
    
    func deleteHighlightRule(_ rule: HighlightRule) {
        highlightRules.removeAll { $0.id == rule.id }
        saveData()
    }
    
    func addHighlightRule(_ rule: HighlightRule) {
        highlightRules.append(rule)
        saveData()
    }
    
    // MARK: - Default World Management
    func setDefaultWorld(_ world: PernWorld?) {
        defaultWorldId = world?.id
        saveData()
    }
    
    var defaultWorld: PernWorld? {
        guard let defaultWorldId = defaultWorldId else { return nil }
        return worlds.first { $0.id == defaultWorldId }
    }
    
    func connectToDefaultWorld() {
        guard let defaultWorld = defaultWorld else { return }
        
        // Try to find a character for this world
        let worldCharacters = charactersForWorld(defaultWorld)
        
        if let character = worldCharacters.first {
            // Connect with the first available character
            addConnection(character: character, world: defaultWorld)
        } else {
            // Connect as guest if no characters available
            addGuestConnection(world: defaultWorld)
        }
    }
    
    // MARK: - Auto-Connect Management
    func toggleAutoConnect(for character: PernCharacter) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("🔄 Toggling auto-connect for character: \(character.name) (ID: \(character.id))")
            if self.autoConnectCharacterIds.contains(character.id) {
                print("🔄 Removing auto-connect for \(character.name)")
                self.autoConnectCharacterIds.removeAll { $0 == character.id }
            } else {
                print("🔄 Adding auto-connect for \(character.name)")
                self.autoConnectCharacterIds.append(character.id)
            }
            print("🔄 Auto-connect IDs after toggle: \(self.autoConnectCharacterIds)")
            self.saveData()
        }
    }
    
    func isAutoConnectEnabled(for character: PernCharacter) -> Bool {
        return autoConnectCharacterIds.contains(character.id)
    }
    
    func autoConnectCharacters() {
        print("🔄 Auto-connecting characters...")
        print("🔄 Auto-connect character IDs: \(autoConnectCharacterIds)")
        print("🔄 Available characters: \(characters.map { "\($0.name) (ID: \($0.id), WorldID: \($0.worldId))" })")
        print("🔄 Available worlds: \(worlds.map { "\($0.name) (ID: \($0.id))" })")
        
        for characterId in autoConnectCharacterIds {
            guard let character = characters.first(where: { $0.id == characterId }) else {
                print("❌ Failed to find character for auto-connect: \(characterId)")
                continue
            }
            
            // Try to find the world by ID first
            var world = worlds.first(where: { $0.id == character.worldId })
            
            // If no world found by ID, try to fix the character's world ID
            if world == nil {
                print("⚠️ Character's world ID (\(character.worldId)) not found, attempting to fix...")
                
                // If there's only one world, assume the character belongs to it
                if worlds.count == 1 {
                    let correctWorld = worlds[0]
                    print("🔧 Fixing character \(character.name) world ID from \(character.worldId) to \(correctWorld.id)")
                    
                    // Update the character's world ID
                    var updatedCharacter = character
                    updatedCharacter.worldId = correctWorld.id
                    saveCharacter(updatedCharacter)
                    
                    world = correctWorld
                } else {
                    print("❌ Skipping auto-connect for \(character.name) - world ID mismatch and multiple worlds available")
                    continue
                }
            }
            
            print("✅ Auto-connecting character: \(character.name) to world: \(world!.name)")
            
            // Check if we already have a connection for this character
            let existingConnection = connections.first { connection in
                connection.character?.id == character.id && connection.world.id == world!.id
            }
            
            if existingConnection == nil {
                print("🔄 Creating new connection for \(character.name)")
                addConnection(character: character, world: world!)
            } else {
                print("🔄 Connection already exists for \(character.name)")
            }
        }
    }
    
    // MARK: - App Settings Management
    func updateFontSize(_ newSize: Double) {
        fontSize = newSize
        saveData()
    }
    
    func toggleDarkMode() {
        isDarkMode.toggle()
        saveData()
    }
    
    private func loadData() {
        if let worldsData = userDefaults.data(forKey: worldsKey),
           let decodedWorlds = try? JSONDecoder().decode([PernWorld].self, from: worldsData) {
            worlds = decodedWorlds
            print("💾 Loaded \(worlds.count) worlds")
        }
        
        if let charactersData = userDefaults.data(forKey: charactersKey),
           let decodedCharacters = try? JSONDecoder().decode([PernCharacter].self, from: charactersData) {
            // Load passwords from Keychain for each character
            characters = decodedCharacters.map { character in
                var updatedCharacter = character
                if let keychainPassword = keychainManager.getPassword(for: character.id) {
                    updatedCharacter.password = keychainPassword
                }
                return updatedCharacter
            }
            print("💾 Loaded \(characters.count) characters")
            for character in characters {
                print("💾 Character: \(character.name) for world: \(character.worldId)")
            }
        }
        
        if let rulesData = userDefaults.data(forKey: highlightRulesKey),
           let decodedRules = try? JSONDecoder().decode([HighlightRule].self, from: rulesData) {
            highlightRules = decodedRules
            print("💾 Loaded \(highlightRules.count) highlight rules")
            for rule in highlightRules {
                print("💾 Rule: '\(rule.pattern)' with color '\(rule.color)' (enabled: \(rule.isEnabled))")
            }
        } else {
            print("💾 No highlight rules found in UserDefaults")
        }
        
        // Load default world ID
        if let defaultWorldIdData = userDefaults.data(forKey: defaultWorldKey),
           let defaultWorldId = try? JSONDecoder().decode(UUID.self, from: defaultWorldIdData) {
            self.defaultWorldId = defaultWorldId
            print("💾 Loaded default world ID: \(defaultWorldId)")
        }
        
        // Load auto-connect character IDs
        if let autoConnectData = userDefaults.data(forKey: autoConnectKey),
           let autoConnectIds = try? JSONDecoder().decode([UUID].self, from: autoConnectData) {
            self.autoConnectCharacterIds = autoConnectIds
            print("💾 Loaded auto-connect character IDs: \(autoConnectIds.count)")
        }
        
        // Load font size
        fontSize = userDefaults.double(forKey: fontSizeKey)
        if fontSize == 0 {
            fontSize = 12.0 // Default font size
        }
        
        // Load icon scale setting
        iconScale = userDefaults.double(forKey: iconScaleKey)
        if iconScale == 0 {
            iconScale = 1.0 // Default icon scale
        }
        
        // Load dark mode setting
        isDarkMode = userDefaults.bool(forKey: darkModeKey)
        if userDefaults.object(forKey: darkModeKey) == nil {
            isDarkMode = true // Default to dark mode
        }
    }
    
    func saveData() {
        if let worldsData = try? JSONEncoder().encode(worlds) {
            userDefaults.set(worldsData, forKey: worldsKey)
            print("💾 Saved \(worlds.count) worlds")
        }
        
        // Save passwords to Keychain and characters to UserDefaults without passwords
        for character in characters {
            if !character.password.isEmpty {
                keychainManager.savePassword(character.password, for: character.id)
            }
        }
        
        // Save characters to UserDefaults with empty passwords (passwords are in Keychain)
        let charactersWithoutPasswords = characters.map { character in
            var characterWithoutPassword = character
            characterWithoutPassword.password = ""
            return characterWithoutPassword
        }
        
        if let charactersData = try? JSONEncoder().encode(charactersWithoutPasswords) {
            userDefaults.set(charactersData, forKey: charactersKey)
            print("💾 Saved \(characters.count) characters")
        }
        
        if let rulesData = try? JSONEncoder().encode(highlightRules) {
            userDefaults.set(rulesData, forKey: highlightRulesKey)
        }
        
        // Save default world ID
        if let defaultWorldId = defaultWorldId,
           let defaultWorldIdData = try? JSONEncoder().encode(defaultWorldId) {
            userDefaults.set(defaultWorldIdData, forKey: defaultWorldKey)
            print("💾 Saved default world ID: \(defaultWorldId)")
        } else {
            userDefaults.removeObject(forKey: defaultWorldKey)
            print("💾 Removed default world ID")
        }
        
        // Save auto-connect character IDs
        if let autoConnectData = try? JSONEncoder().encode(autoConnectCharacterIds) {
            userDefaults.set(autoConnectData, forKey: autoConnectKey)
            print("💾 Saved auto-connect character IDs: \(autoConnectCharacterIds.count)")
        }
        
        // Save font size
        userDefaults.set(fontSize, forKey: fontSizeKey)
        
        // Save icon scale setting
        userDefaults.set(iconScale, forKey: iconScaleKey)
        
        // Save dark mode setting
        userDefaults.set(isDarkMode, forKey: darkModeKey)
    }
    
    private func setupDefaultHighlightRules() {
        if highlightRules.isEmpty {
            highlightRules = [
                HighlightRule(pattern: "You say:", color: "blue"),
                HighlightRule(pattern: "says:", color: "green"),
                HighlightRule(pattern: "Error:", color: "red"),
                HighlightRule(pattern: "Warning:", color: "yellow")
            ]
        }
    }
}
