import SwiftUI

struct PernConnectionTabsView: View {
    @ObservedObject var connectionManager: PernConnectionManager
    @State private var showingNewConnection = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(connectionManager.connections) { connection in
                        PernConnectionTab(
                            connection: connection,
                            connectionManager: connectionManager,
                            isActive: connection.id == connectionManager.activeConnectionId,
                            onSelect: {
                                connectionManager.setActiveConnection(connection)
                                // Clear the notification badge when user switches to a connection
                                connectionManager.notificationManager.clearBadgeForActiveConnection()
                            },
                            onClose: {
                                connectionManager.removeConnection(connection)
                            }
                        )
                    }
                    Button(action: {
                        showingNewConnection = true
                    }) {
                        Image(systemName: "plus.circle")
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("New Connection")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Tab Content
            if let activeConnection = connectionManager.activeConnection {
                PernTerminalView(connection: activeConnection, connectionManager: connectionManager)
            } else {
                Text("No active connection. Click '+' to add a new one.")
                    .font(.system(size: connectionManager.fontSize))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingNewConnection) {
            PernNewConnectionView(connectionManager: connectionManager)
        }
    }
}

struct PernConnectionTab: View {
    @ObservedObject var connection: PernConnection
    @ObservedObject var connectionManager: PernConnectionManager
    var isActive: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack {
            // Connection type indicator
            Image(systemName: connection.isGuestConnection ? "person.crop.circle" : "person.fill")
                .foregroundColor(connection.isGuestConnection ? .orange : .blue)
                .font(.system(size: 12 * connectionManager.iconScale))
            
            Text(connection.isGuestConnection ? "Guest" : (connection.character?.name ?? "New Character"))
                .font(.system(size: connectionManager.fontSize))
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(5)
                .onTapGesture(perform: onSelect)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12 * connectionManager.iconScale))
                    .foregroundColor(.gray)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 4)
    }
}
