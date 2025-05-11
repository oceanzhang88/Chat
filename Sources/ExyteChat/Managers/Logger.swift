//
//  Logger.swift
//  Chat
//
//  Created by Yangming Zhang on 5/11/25.
//


// LoggerUtil.swift (Create this new file or add to an existing utility file)
import Foundation

struct Logger {
    static private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS" // Customize as needed
        return formatter
    }()

    static func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = dateFormatter.string(from: Date())
        print("\(timestamp) [\(fileName):\(line) \(function)] - \(message)")
    }
}

// Example usage:
// Logger.log("This is a test message.")