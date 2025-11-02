import Foundation
import Network
import Darwin
import AppKit

extension Notification.Name {
    static let newMessageReceived = Notification.Name("newMessageReceived")
}

// MARK: - Output Ring Buffer
/// Efficient ring buffer for output storage that avoids quadratic string concatenation
final class OutputRing {
    private var lines = [String]()
    private let maxBytes: Int
    private var currentBytes = 0
    
    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }
    
    func append(_ chunk: String) {
        // Split into lines but keep newlines in the output
        let lineParts = chunk.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" })
        
        for (index, part) in lineParts.enumerated() {
            let line = String(part) + (index < lineParts.count - 1 ? "\n" : "")
            lines.append(line)
            currentBytes += line.utf8.count
            
            // Trim old lines if we exceed the limit
            while currentBytes > maxBytes && !lines.isEmpty {
                let removed = lines.removeFirst()
                currentBytes -= removed.utf8.count
            }
        }
    }
    
    var fullText: String {
        lines.joined()
    }
    
    var lineCount: Int {
        lines.count
    }
}

// MARK: - Pern Connection Models
class PernConnection: ObservableObject, Identifiable {
    let id = UUID()
    @Published var isConnected = false
    @Published var isConnecting = false
    var lastActivity = Date() // Not @Published - no need to trigger view updates
    
    // Configurable buffer limit - 0 means unlimited (use with caution on long sessions)
    var maxOutputBufferSize: Int = 500_000 // Default: ~10,000 lines (500KB)
    
    // Use ring buffer for efficient output storage
    private let outputRing: OutputRing
    
    // Computed property for reading the buffer - no @Published needed
    var outputBuffer: String {
        outputRing.fullText
    }
    
    // Publish change counter to trigger scroll updates  
    @Published var outputChangeCount: Int = 0
    
    @Published var inputText = ""
    @Published var needsCharacterCreation = false
    @Published var isGuestConnection = false
    @Published var isLogging = false

    var character: PernCharacter?
    var world: PernWorld
    var connection: NWConnection?
    private var socketFD: Int32 = -1
    private var logFileHandle: FileHandle?
    private var keepaliveTimer: Timer?
    private let keepaliveInterval: TimeInterval = 300.0 // Send keepalive every 5 minutes
    private var readSource: DispatchSourceRead?
    private let logQueue = DispatchQueue(label: "com.pernclient.log", qos: .utility)
    
    init(character: PernCharacter?, world: PernWorld, maxOutputBufferSize: Int = 500_000) {
        self.character = character
        self.world = world
        self.maxOutputBufferSize = maxOutputBufferSize
        self.outputRing = OutputRing(maxBytes: maxOutputBufferSize)
    }
    
    deinit {
        stopKeepalive() // Safety net to ensure timer cleanup
    }
    
    private func startKeepalive() {
        stopKeepalive() // Stop any existing timer
        
        // Use a common RunLoop mode timer to survive system sleep
        let timer = Timer(timeInterval: keepaliveInterval, repeats: true) { [weak self] _ in
            self?.sendKeepalive()
        }
        
        // Always add to main runloop for safety
        RunLoop.main.add(timer, forMode: .common)
        keepaliveTimer = timer
        print("🔄 Keepalive timer started (every \(keepaliveInterval) seconds)")
    }
    
    private func stopKeepalive() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        print("🔄 Keepalive timer stopped")
    }
    
    private func sendKeepalive() {
        guard isConnected else {
            print("🔄 Not connected, stopping keepalive")
            stopKeepalive()
            return
        }
        
        // Send a simple space character as keepalive (many MUDs ignore spaces)
        // This is a common keepalive technique that won't interfere with gameplay
        print("🔄 Sending keepalive")
        sendCommand(" ")
    }
    
    func connect() {
        guard !isConnecting else { return }
        
        print("🔌 Attempting to connect to \(world.hostname):\(world.port)")
        isConnecting = true
        
        // Create the endpoint
        let host = NWEndpoint.Host(world.hostname)
        let port = NWEndpoint.Port(integerLiteral: UInt16(world.port))
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        
        // Use TCP - Network framework handles keepalive automatically
        connection = NWConnection(to: endpoint, using: .tcp)
        
        connection?.stateUpdateHandler = { [weak self] state in
            print("🔍 Connection state changed: \(state)")
            switch state {
                   case .ready:
                       print("✅ Connection established to \(self?.world.hostname ?? "unknown")")
                       DispatchQueue.main.async {
                           self?.isConnected = true
                           self?.isConnecting = false
                           self?.startReceiving()
                           // Start application-level keepalive for extra assurance
                           self?.startKeepalive()
                           
                           // Auto-login if we have character credentials and it's not a guest connection
                           if let character = self?.character, 
                              !character.name.isEmpty && 
                              !character.password.isEmpty && 
                              !(self?.isGuestConnection ?? false) {
                               print("🔐 Auto-logging in as \(character.name)")
                               self?.sendCommand("connect \(character.name) \(character.password)")
                           }
                       }
            case .failed(let error):
                print("❌ Connection failed: \(error)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.isConnecting = false
                }
                // Try alternative connection method
                self?.tryAlternativeConnection()
            case .cancelled:
                print("🚫 Connection cancelled")
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.isConnecting = false
                }
            case .preparing:
                print("⏳ Connection preparing...")
            case .waiting(let error):
                print("⏰ Connection waiting: \(error)")
                // If we're waiting with a timeout error, try alternative connection
                let errorString = String(describing: error)
                if errorString.contains("rawValue: 60") || errorString.contains("Operation timed out") {
                    print("🔄 Timeout detected, trying alternative connection...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self?.tryAlternativeConnection()
                    }
                }
            @unknown default:
                print("❓ Unknown connection state: \(state)")
            }
        }
        
        print("🚀 Starting connection...")
        // Try using the main queue
        connection?.start(queue: .main)
    }
    
    private func tryAlternativeConnection() {
        print("🔄 Trying alternative connection method...")
        
        // Cancel the current connection
        connection?.cancel()
        
        // Wait a moment before retrying
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            
            // Try a different Network framework approach
            self.tryAlternativeNetworkConnection()
        }
    }
    
    private func tryAlternativeNetworkConnection() {
        print("🔌 Trying BSD socket connection (bypassing Network framework)...")
        
        // Try using BSD sockets directly instead of Network framework
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        if socketFD == -1 {
            print("❌ Failed to create socket, errno: \(errno)")
            return
        }
        print("✅ Socket created successfully, FD: \(socketFD)")
        
        // Set socket options
        var optval: Int32 = 1
        
        // Enable TCP keepalive to prevent disconnections during sleep/wake cycles
        setsockopt(socketFD, SOL_SOCKET, SO_KEEPALIVE, &optval, socklen_t(MemoryLayout<Int32>.size))
        print("✅ TCP keepalive enabled")
        
        // Disable SIGPIPE signals
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &optval, socklen_t(MemoryLayout<Int32>.size))
        
        // Keep socket in blocking mode for simplicity
        print("✅ Socket set to blocking mode")
        
        // Get host address
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        
        var result: UnsafeMutablePointer<addrinfo>?
        print("🔍 Resolving hostname: \(self.world.hostname):\(self.world.port)")
        let status = getaddrinfo(self.world.hostname, "\(self.world.port)", &hints, &result)
        
        if status != 0 {
            print("❌ Failed to resolve hostname: \(self.world.hostname), status: \(status)")
            close(socketFD)
            return
        }
        
        guard let addr = result else {
            print("❌ No address found")
            close(socketFD)
            return
        }
        print("✅ Hostname resolved successfully")
        
        // Connect (blocking)
        print("🔗 Attempting blocking socket connection...")
        let connectResult = Darwin.connect(socketFD, addr.pointee.ai_addr, addr.pointee.ai_addrlen)
        freeaddrinfo(result)
        
        if connectResult == -1 {
            print("❌ Failed to connect via socket, errno: \(errno)")
            close(socketFD)
            return
        } else {
            print("✅ Socket connection successful!")
        }
        
        // Store the socket file descriptor
        self.socketFD = socketFD
        
        DispatchQueue.main.async {
            self.isConnected = true
            self.isConnecting = false
            self.startReceivingFromSocket()
            // Start application-level keepalive for extra assurance
            self.startKeepalive()
            
            // Auto-login if we have character credentials and it's not a guest connection
            if let character = self.character, 
               !character.name.isEmpty && 
               !character.password.isEmpty && 
               !self.isGuestConnection {
                print("🔐 Auto-logging in as \(character.name)")
                self.sendCommand("connect \(character.name) \(character.password)")
            }
        }
    }
    
    func disconnect() {
        stopKeepalive() // Stop keepalive timer (may not be running)
        stopSocketReceiving() // Stop dispatch source reading
        if socketFD != -1 {
            close(socketFD)
            socketFD = -1
        }
        connection?.cancel()
        isConnected = false
        isConnecting = false
        stopLogging()
    }
    
    // MARK: - Logging Methods
    func startLogging() {
        guard !isLogging else { return }
        
        // Prompt user to choose log file location
        let savePanel = NSSavePanel()
        savePanel.title = "Choose Log File Location"
        
        // Create filename with character name and datetime stamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        
        let characterName = character?.name ?? "Guest"
        let sanitizedCharacterName = characterName.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "*", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "<", with: "_")
            .replacingOccurrences(of: ">", with: "_")
            .replacingOccurrences(of: "|", with: "_")
        
        savePanel.nameFieldStringValue = "\(sanitizedCharacterName)_\(timestamp).txt"
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        
        savePanel.begin { [weak self] (result: NSApplication.ModalResponse) in
            guard let self = self else { return }
            
            if result == .OK, let url = savePanel.url {
                self.startLoggingToFile(at: url)
            }
        }
    }
    
    private func startLoggingToFile(at url: URL) {
        do {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
            logFileHandle = try FileHandle(forWritingTo: url)
            isLogging = true
            print("📝 Started logging to: \(url.path)")
        } catch {
            print("❌ Failed to start logging: \(error)")
        }
    }
    
    func stopLogging() {
        guard isLogging else { return }
        
        logFileHandle?.closeFile()
        logFileHandle = nil
        isLogging = false
        print("📝 Stopped logging")
    }
    
    func sendCommand(_ command: String) {
        guard isConnected else { return }
        
        let fullCommand = command + "\n"
        let data = fullCommand.data(using: .utf8)!
        
        if socketFD != -1 {
            // Send via socket
            let bytesSent = data.withUnsafeBytes { bytes in
                send(socketFD, bytes.bindMemory(to: UInt8.self).baseAddress!, data.count, 0)
            }
            
            if bytesSent == -1 {
                // Socket send failed
            }
        } else if let connection = connection {
            // Send via Network framework
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    // Network send failed
                }
            })
        }
        
        lastActivity = Date()
    }
    
    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                let text = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    self?.appendToOutputBuffer(text)
                    self?.lastActivity = Date()
                    
                    // Log the received data if logging is enabled
                    if self?.isLogging == true {
                        self?.logToFile(text)
                    }
                    
                    // Notify about new message
                    self?.notifyNewMessage(text)
                }
            }
            
            if let error = error {
                print("Receive error: \(error)")
            }
            
            if !isComplete {
                self?.startReceiving()
            }
        }
    }
    
    private func startReceivingFromSocket() {
        guard socketFD != -1 else { return }
        
        // Stop any existing read source
        stopSocketReceiving()
        
        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: .global(qos: .userInitiated))
        readSource = source
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(self.socketFD, &buffer, buffer.count)
            
            if bytesRead > 0 {
                let text = String(decoding: buffer.prefix(bytesRead), as: UTF8.self)
                
                DispatchQueue.main.async {
                    self.appendToOutputBuffer(text)
                    self.lastActivity = Date()
                    
                    if self.isLogging {
                        self.logToFile(text)
                    }
                    
                    self.notifyNewMessage(text)
                }
            } else if bytesRead == 0 {
                // Connection closed by server
                print("Socket connection closed by server")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.isConnecting = false
                }
            } else {
                // Error reading from socket
                let error = errno
                print("❌ Socket read error: \(error)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.isConnecting = false
                }
            }
        }
        
        source.setCancelHandler {
            // Cleanup happens in disconnect()
        }
        
        source.resume()
        print("✅ Socket read source started")
    }
    
    private func stopSocketReceiving() {
        readSource?.cancel()
        readSource = nil
        print("✅ Socket read source stopped")
    }
    
    private func logToFile(_ text: String) {
        guard let logFileHandle = logFileHandle else { return }
        
        if let data = text.data(using: .utf8) {
            logQueue.async {
                logFileHandle.write(data)
            }
        }
    }
    
    private func appendToOutputBuffer(_ newText: String) {
        outputRing.append(newText)
        
        // Trigger view update and scroll without regenerating the full string
        outputChangeCount += 1
    }
    
    private func notifyNewMessage(_ text: String) {
        // Only notify for meaningful messages (not empty or just whitespace)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // Post to deterministic notification bus (also bridges to NotificationCenter)
        let event = NewMessageEvent(
            connection: isGuestConnection ? "Guest @ \(world.name)" : "\(character?.name ?? "Unknown") @ \(world.name)",
            connectionId: id,
            message: text
        )
        PernNotificationBus.shared.postNewMessage(event)
    }
}

struct PernCharacter: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var password: String
    var worldId: UUID
    var isFavorite: Bool
    
    // Custom coding keys to handle backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, name, password, worldId, isFavorite
    }

    init(name: String, password: String, worldId: UUID, isFavorite: Bool = false) {
        self.id = UUID()
        self.name = name
        self.password = password
        self.worldId = worldId
        self.isFavorite = isFavorite
    }
    
    // Custom decoder to handle missing isFavorite field in old data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        password = try container.decode(String.self, forKey: .password)
        worldId = try container.decode(UUID.self, forKey: .worldId)
        // Default to false if isFavorite doesn't exist in saved data
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}

struct PernWorld: Identifiable, Codable, Hashable {
    let id = UUID()
    var name: String
    var hostname: String
    var port: Int
    var description: String

    init(name: String, hostname: String, port: Int = 7007, description: String = "") {
        self.name = name
        self.hostname = hostname
        self.port = port
        self.description = description
    }
}

// MARK: - Highlight Rules
struct HighlightRule: Identifiable, Codable {
    let id = UUID()
    var pattern: String
    var color: String
    var isEnabled: Bool

    init(pattern: String, color: String, isEnabled: Bool = true) {
        self.pattern = pattern
        self.color = color
        self.isEnabled = isEnabled
    }
}
