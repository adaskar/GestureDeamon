import Foundation
import os
import os.log

public enum LogLevel: Int, Comparable {
    case none = 0
    case error = 1
    case info = 2
    case debug = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    public static func fromString(_ str: String?) -> LogLevel {
        switch str?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "debug": return .debug
        case "info": return .info
        case "error", "err": return .error
        case "none", "off", "disabled": return .none
        default: return .info
        }
    }
}

public enum Log {
    public static var isEnabled: Bool = false
    public static var currentLevel: LogLevel = .info

    private static let logger = Logger(subsystem: "com.guru.GestureDaemon", category: "Core")
    private static let logFileQueue = DispatchQueue(label: "com.guru.GestureDaemon.logFileQueue")
    private static let logURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".config/GestureDaemon")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("daemon.log")
    }()

    private static func writeToFile(_ line: String) {
        logFileQueue.async {
            guard let data = (line + "\n").data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        }
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private static func timestamp() -> String {
        return isoFormatter.string(from: Date())
    }

    public static func info(_ message: String) {
        guard isEnabled && currentLevel >= .info else { return }
        logger.info("\(message, privacy: .public)")
        print("[INFO] \(message)")
        fflush(stdout)
        writeToFile("[\(timestamp())] [INFO] \(message)")
    }

    public static func error(_ message: String) {
        guard isEnabled && currentLevel >= .error else { return }
        logger.error("\(message, privacy: .public)")
        print("[ERROR] \(message)")
        fflush(stdout)
        writeToFile("[\(timestamp())] [ERROR] \(message)")
    }

    public static func debug(_ message: String) {
        guard isEnabled && currentLevel >= .debug else { return }
        logger.debug("\(message, privacy: .public)")
        print("[DEBUG] \(message)")
        fflush(stdout)
        writeToFile("[\(timestamp())] [DEBUG] \(message)")
    }
}
