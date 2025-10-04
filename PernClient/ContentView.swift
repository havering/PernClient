//
//  ContentView.swift
//  PernClient
//
//  Created by Diana O’Haver on 9/10/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var connectionManager = PernConnectionManager()

    var body: some View {
        VStack(spacing: 0) {
            PernMenuBar(connectionManager: connectionManager)
            Divider()
            PernConnectionTabsView(connectionManager: connectionManager)
        }
        .preferredColorScheme(connectionManager.isDarkMode ? .dark : .light)
        .environmentObject(connectionManager.notificationManager)
        .onAppear {
            // Auto-connect to selected characters on app startup
            connectionManager.autoConnectCharacters()
        }
    }
}

#Preview {
    ContentView()
}
