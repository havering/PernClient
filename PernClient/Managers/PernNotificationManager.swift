import Foundation
import UserNotifications
import AppKit

class PernNotificationManager: NSObject, ObservableObject {
    @Published var unreadMessageCount = 0
    @Published var isAppActive = true
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    override init() {
        super.init()
        setupNotificationCenter()
        setupAppStateObservers()
        
    }
    
    private func setupNotificationCenter() {
        notificationCenter.delegate = self
    }
    
    private func setupAppStateObservers() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isAppActive = true
            // Clear badge when app becomes active (user returned to the app)
            print("🔄 App became active, clearing badge")
            self?.clearBadgeForActiveConnection()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isAppActive = false
        }
    }
    
    func requestNotificationPermission() {
        // Check current authorization status first
        notificationCenter.getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    // Request permission with explicit badge authorization
                    self.notificationCenter.requestAuthorization(options: [.badge, .alert, .sound]) { granted, error in
                        DispatchQueue.main.async {
                            if granted {
                                print("✅ Notification permission granted")
                            } else if let error = error {
                                print("❌ Notification permission error: \(error)")
                            }
                        }
                    }
                case .denied:
                    print("⚠️ Notification permission denied - user must enable in System Settings > Notifications > PernClient")
                case .authorized:
                    print("✅ Notification permission already granted")
                case .provisional:
                    print("✅ Notification permission granted (provisional)")
                case .ephemeral:
                    print("✅ Notification permission granted (ephemeral)")
                @unknown default:
                    print("⚠️ Unknown notification authorization status")
                }
            }
        }
    }
    
    func newMessageReceived(from connection: String, isActiveConnection: Bool = false) {
        print("🔔 Current unread count before processing: \(unreadMessageCount)")
        
        // Only increment badge if:
        // 1. App is not active (user switched to another app), OR
        // 2. This is not the currently active connection (user is looking at a different tab)
        if !isAppActive || !isActiveConnection {
            unreadMessageCount += 1
            print("🔔 Incrementing badge - unread count is now: \(unreadMessageCount)")
            updateDockBadge()
            forceDockBadgeUpdate() // Force update to ensure it works
        } else {
            print("🔔 User is actively using this connection - skipping badge increment")
        }
    }
    
    private func updateBadge() {
        print("🔔 Updating badge to: \(unreadMessageCount)")
        
        // Method 1: Direct dock tile approach
        NSApplication.shared.dockTile.badgeLabel = unreadMessageCount > 0 ? "\(unreadMessageCount)" : ""
        
        // Method 2: UserNotifications framework approach
        if unreadMessageCount > 0 {
            let content = UNMutableNotificationContent()
            content.badge = NSNumber(value: unreadMessageCount)
            let request = UNNotificationRequest(identifier: "badge-update", content: content, trigger: nil)
            notificationCenter.add(request) { error in
                if let error = error {
                    print("🔔 Badge notification error: \(error)")
                } else {
                    print("🔔 Badge notification set successfully")
                }
            }
        } else {
            notificationCenter.removeAllPendingNotificationRequests()
            notificationCenter.removeAllDeliveredNotifications()
        }
        
        print("🔔 Badge set to: '\(NSApplication.shared.dockTile.badgeLabel ?? "nil")'")
    }
    
    private func updateDockBadge() {
        // Force update dock badge - this should work even without notification permission
        DispatchQueue.main.async {
            print("🔔 Force updating dock badge to: \(self.unreadMessageCount)")
            
            // Ensure the app is active in the dock and has proper activation policy
            NSApplication.shared.setActivationPolicy(.regular)
            
            // Set the badge
            let badgeText = self.unreadMessageCount > 0 ? "\(self.unreadMessageCount)" : ""
            NSApplication.shared.dockTile.badgeLabel = badgeText
            
            // Force a dock tile update with a slight delay to ensure it takes effect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApplication.shared.dockTile.display()
                
                // Debug: Check if the badge was actually set
                let actualBadge = NSApplication.shared.dockTile.badgeLabel
                print("🔔 Dock badge set to: '\(actualBadge ?? "nil")'")
                print("🔔 Dock tile display called")
                print("🔔 App activation policy: \(NSApplication.shared.activationPolicy().rawValue)")
                print("🔔 App is active: \(NSApplication.shared.isActive)")
                print("🔔 Dock tile badge: '\(NSApplication.shared.dockTile.badgeLabel ?? "nil")'")
            }
        }
    }
    
    func clearBadge() {
        print("🔔 Clearing badge - was \(unreadMessageCount)")
        print("🔔 Clear badge called from: \(Thread.callStackSymbols[1])")
        unreadMessageCount = 0
        updateDockBadge()
    }
    
    func clearBadgeForActiveConnection() {
        print("🔔 Clearing badge for active connection - was \(unreadMessageCount)")
        unreadMessageCount = 0
        updateDockBadge()
    }
    
    func forceDockBadgeUpdate() {
        DispatchQueue.main.async {
            let badgeText = self.unreadMessageCount > 0 ? "\(self.unreadMessageCount)" : ""
            
            // Set dock badge without activating the app
            NSApplication.shared.dockTile.badgeLabel = badgeText
            NSApplication.shared.dockTile.display()
            
            // Force dock refresh with a slight delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApplication.shared.dockTile.badgeLabel = badgeText
                NSApplication.shared.dockTile.display()
            }
        }
    }
    
    
    private func clearBadgeInternal() {
        print("🔔 Clearing badge - was \(unreadMessageCount)")
        unreadMessageCount = 0
        updateDockBadge()
    }
    
    private func showNotification(from connection: String) {
        // Check if we have notification permission first
        notificationCenter.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                print("ℹ️ Notifications not authorized, skipping notification")
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = "New Message"
            content.body = "New message from \(connection)"
            content.sound = .default
            content.badge = NSNumber(value: self.unreadMessageCount)
            
            let request = UNNotificationRequest(
                identifier: "pern-message-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            
            self.notificationCenter.add(request) { error in
                if let error = error {
                    print("❌ Failed to show notification: \(error)")
                }
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension PernNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .badge, .sound])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification tap - bring app to front
        NSApplication.shared.activate(ignoringOtherApps: true)
        completionHandler()
    }
}
