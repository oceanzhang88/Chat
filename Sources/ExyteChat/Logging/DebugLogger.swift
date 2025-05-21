import OSLog

extension Logger {
    private static let subsystem = "TranscriptService"
    private static let chatsystem = "OmniSelfChat"
    
    /// Logs related to speech recognition operations and events
    static let transcriber = Logger(subsystem: subsystem, category: "transcriber")
    static let omniSelfChat = Logger(subsystem: chatsystem, category: "chat")
}


/// A wrapper around Logger that handles debug mode checks
struct DebugLogger {
    private let logger: Logger
    nonisolated(unsafe) private static var isEnabled: Bool = true
    
    init(_ logger: Logger, isEnabled: Bool) {
        self.logger = logger
        DebugLogger.isEnabled = isEnabled
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS" // Customize as needed
        return formatter
    }()

    static func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }
        let fileName = (file as NSString).lastPathComponent
        let timestamp = dateFormatter.string(from: Date())
        print("\(timestamp) [\(fileName):\(line) \(function)] - \(message)")
    }
    
    func debug(_ message: @escaping @autoclosure () -> String) {
        guard DebugLogger.isEnabled else { return }
        logger.debug("\(message())")
    }
    
    func error(_ message: @escaping @autoclosure () -> String) {
        // Always log errors, regardless of debug mode
        logger.error("\(message())")
    }
} 
