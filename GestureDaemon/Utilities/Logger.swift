import Foundation
import os
import os.log

public enum Log {
    private static let logger = Logger(subsystem: "com.user.GestureDaemon", category: "Core")
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
        logger.info("\(message, privacy: .public)")
        print("[INFO] \(message)")
        writeToFile("[\(timestamp())] [INFO] \(message)")
    }
    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        print("[ERROR] \(message)")
        writeToFile("[\(timestamp())] [ERROR] \(message)")
    }
    public static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        #if DEBUG
        print("[DEBUG] \(message)")
        writeToFile("[\(timestamp())] [DEBUG] \(message)")
        #endif
    }
}

