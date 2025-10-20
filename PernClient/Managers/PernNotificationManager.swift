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
        // Only increment badge if:
        // 1. App is not active (user switched to another app), OR
        // 2. This is not the currently active connection (user is looking at a different tab)
        if !isAppActive || !isActiveConnection {
            unreadMessageCount += 1
            updateDockBadge()
        }
    }
    
    private func updateDockBadge() {
        // Update on main thread if needed
        let updateBlock = {
            // Set the badge
            let badgeText = self.unreadMessageCount > 0 ? "\(self.unreadMessageCount)" : ""
            NSApplication.shared.dockTile.badgeLabel = badgeText
            NSApplication.shared.dockTile.display()
            
            // Clean up old notification requests
            if self.unreadMessageCount == 0 {
                self.notificationCenter.removeAllPendingNotificationRequests()
                self.notificationCenter.removeAllDeliveredNotifications()
            }
        }
        
        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async(execute: updateBlock)
        }
    }
    
    func clearBadge() {
        unreadMessageCount = 0
        updateDockBadge()
    }
    
    func clearBadgeForActiveConnection() {
        unreadMessageCount = 0
        updateDockBadge()
    }
    
    func forceDockBadgeUpdate() {
        // Simplified - just call updateDockBadge
        updateDockBadge()
    }
    
    
    private func clearBadgeInternal() {
        unreadMessageCount = 0
        updateDockBadge()
    }
    
    private func showNotification(from connection: String) {
        // Check if we have notification permission first
        notificationCenter.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = "New Message"
            content.body = "New message from \(connection)"
            content.sound = .default
            content.badge = NSNumber(value: self.unreadMessageCount)
            
            // Use fixed identifier to replace previous notification instead of accumulating
            let request = UNNotificationRequest(
                identifier: "pern-message-notification",
                content: content,
                trigger: nil
            )
            
            self.notificationCenter.add(request) { error in
                // Silently handle errors
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
