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
