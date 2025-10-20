import SwiftUI

struct PernMenuBar: View {
    @ObservedObject var connectionManager: PernConnectionManager
    @EnvironmentObject var notificationManager: PernNotificationManager
    @State private var showingNewConnection = false
    @State private var showingSettings = false

    var body: some View {
        HStack {
            // App Title with unread count
            HStack {
                Text("PernClient")
                    .font(.system(size: connectionManager.fontSize + 4, weight: .bold))
                
                if notificationManager.unreadMessageCount > 0 {
                    Text("\(notificationManager.unreadMessageCount)")
                        .font(.system(size: connectionManager.fontSize - 2, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Circle())
                }
            }

            Spacer()

            // Favorite character quick connect buttons
            FavoriteCharactersView(connectionManager: connectionManager)

            // Connection Status
            if let activeConnection = connectionManager.activeConnection {
                HStack(spacing: 8) {
                    Circle()
                        .fill(activeConnection.isConnected ? .green : (activeConnection.isConnecting ? .yellow : .red))
                        .frame(width: 8 * connectionManager.iconScale, height: 8 * connectionManager.iconScale)

                    Text(activeConnection.isGuestConnection ? 
                         "Guest @ \(activeConnection.world.name)" : 
                         "\(activeConnection.character?.name ?? "Unknown") @ \(activeConnection.world.name)")
                        .font(.system(size: connectionManager.fontSize))
                }
            }

            // Buttons
            Button(action: {
                showingNewConnection = true
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16 * connectionManager.iconScale))
            }
            .buttonStyle(PlainButtonStyle())
            .help("New Connection")

            Button(action: {
                showingSettings = true
            }) {
                Image(systemName: "gear")
                    .font(.system(size: 16 * connectionManager.iconScale))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Settings")
            
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showingNewConnection) {
            PernNewConnectionView(connectionManager: connectionManager)
        }
        .sheet(isPresented: $showingSettings) {
            PernSettingsView(connectionManager: connectionManager)
        }
    }
}

// Separate view for favorite characters to optimize rendering
struct FavoriteCharactersView: View {
    @ObservedObject var connectionManager: PernConnectionManager
    
    var favoriteCharacters: [PernCharacter] {
        connectionManager.characters.filter { $0.isFavorite }
    }
    
    var body: some View {
        if !favoriteCharacters.isEmpty {
            HStack(spacing: 8) {
                ForEach(favoriteCharacters) { character in
                    if let world = connectionManager.worlds.first(where: { $0.id == character.worldId }) {
                        Button(action: {
                            connectionManager.addConnection(character: character, world: world)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12 * connectionManager.iconScale))
                                    .foregroundColor(.yellow)
                                Text(character.name)
                                    .font(.system(size: connectionManager.fontSize - 1))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Quick connect to \(character.name) @ \(world.name)")
                    }
                }
            }
            .padding(.trailing, 8)
        }
    }
}
