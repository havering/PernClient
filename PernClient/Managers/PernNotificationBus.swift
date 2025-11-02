import Foundation
import Combine

/// Deterministic notification system using Combine publishers for testability
/// Bridges to NotificationCenter for system notifications when needed
///
/// Example usage in tests:
/// ```swift
/// let bus = PernNotificationBus.shared
/// var unreadCount = 0
/// let expectation = XCTestExpectation(description: "Message received")
///
/// let cancellable = bus.newMessageReceived
///     .sink { event in
///         unreadCount += 1
///         XCTAssertEqual(event.connection, "TestCharacter @ TestWorld")
///         expectation.fulfill()
///     }
///
/// bus.postNewMessage(NewMessageEvent(...))
/// wait(for: [expectation], timeout: 1.0)
/// XCTAssertEqual(unreadCount, 1)
/// ```
class PernNotificationBus {
    static let shared = PernNotificationBus()
    
    private init() {}
    
    /// Publisher for new messages received
    private let _newMessageReceived = PassthroughSubject<NewMessageEvent, Never>()
    
    /// Public publisher for new messages - allows testing without NotificationCenter
    var newMessageReceived: AnyPublisher<NewMessageEvent, Never> {
        _newMessageReceived.eraseToAnyPublisher()
    }
    
    /// Post a new message event
    /// Also posts to NotificationCenter for backwards compatibility with existing code
    func postNewMessage(_ event: NewMessageEvent) {
        // Send to Combine publisher for deterministic testing
        _newMessageReceived.send(event)
        
        // Bridge to NotificationCenter for system notifications
        NotificationCenter.default.post(
            name: .newMessageReceived,
            object: nil,
            userInfo: [
                "connection": event.connection,
                "connectionId": event.connectionId,
                "message": event.message
            ]
        )
    }
}

/// Event structure for new messages
struct NewMessageEvent {
    let connection: String
    let connectionId: UUID
    let message: String
}

