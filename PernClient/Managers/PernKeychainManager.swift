import Foundation
import Security

/// Manages secure storage of character passwords in the macOS Keychain
class PernKeychainManager {
    static let shared = PernKeychainManager()
    
    private let service = "com.pernclient.characters"
    
    private init() {}
    
    /// Save a password for a character
    /// - Parameters:
    ///   - password: The password to save
    ///   - characterId: The character's UUID
    /// - Returns: True if successful, false otherwise
    @discardableResult
    func savePassword(_ password: String, for characterId: UUID) -> Bool {
        let passwordData = password.data(using: .utf8)!
        let account = characterId.uuidString
        
        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add the new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("🔒 Saved password to Keychain for character: \(characterId)")
            return true
        } else {
            print("❌ Failed to save password to Keychain: \(status)")
            return false
        }
    }
    
    /// Retrieve a password for a character
    /// - Parameter characterId: The character's UUID
    /// - Returns: The password if found, nil otherwise
    func getPassword(for characterId: UUID) -> String? {
        let account = characterId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let password = String(data: data, encoding: .utf8) {
            print("🔒 Retrieved password from Keychain for character: \(characterId)")
            return password
        } else if status == errSecItemNotFound {
            print("🔒 No password found in Keychain for character: \(characterId)")
            return nil
        } else {
            print("❌ Failed to retrieve password from Keychain: \(status)")
            return nil
        }
    }
    
    /// Delete a password for a character
    /// - Parameter characterId: The character's UUID
    /// - Returns: True if successful, false otherwise
    @discardableResult
    func deletePassword(for characterId: UUID) -> Bool {
        let account = characterId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess {
            print("🔒 Deleted password from Keychain for character: \(characterId)")
            return true
        } else if status == errSecItemNotFound {
            print("🔒 No password to delete in Keychain for character: \(characterId)")
            return true // Already deleted
        } else {
            print("❌ Failed to delete password from Keychain: \(status)")
            return false
        }
    }
    
    /// Check if a migration has been performed
    private var hasMigrated: Bool {
        get {
            UserDefaults.standard.bool(forKey: "PernKeychainMigrationComplete")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "PernKeychainMigrationComplete")
        }
    }
    
    /// Migrate passwords from UserDefaults to Keychain
    /// Should be called once on first launch after adding Keychain support
    func migratePasswordsIfNeeded() {
        guard !hasMigrated else {
            print("🔒 Keychain migration already completed")
            return
        }
        
        print("🔒 Starting Keychain migration...")
        
        // Load characters from UserDefaults to get old passwords
        guard let charactersData = UserDefaults.standard.data(forKey: "PernCharacters"),
              let decodedCharacters = try? JSONDecoder().decode([PernCharacter].self, from: charactersData) else {
            print("🔒 No characters found in UserDefaults, skipping migration")
            hasMigrated = true
            return
        }
        
        var migratedCount = 0
        var migratedCharacters: [PernCharacter] = []
        
        for var character in decodedCharacters {
            // Only migrate if the password is not empty
            if !character.password.isEmpty {
                // Save to Keychain
                if savePassword(character.password, for: character.id) {
                    migratedCount += 1
                    // Clear password from in-memory object
                    character.password = ""
                    migratedCharacters.append(character)
                } else {
                    // Failed to migrate, keep password in model for now
                    migratedCharacters.append(character)
                }
            } else {
                // Already empty or placeholder, just add to list
                migratedCharacters.append(character)
            }
        }
        
        // Save characters back to UserDefaults with cleared passwords
        if let updatedCharactersData = try? JSONEncoder().encode(migratedCharacters) {
            UserDefaults.standard.set(updatedCharactersData, forKey: "PernCharacters")
            print("🔒 Saved updated characters to UserDefaults (passwords cleared)")
        }
        
        print("🔒 Migration complete: \(migratedCount) passwords migrated to Keychain")
        hasMigrated = true
    }
}

