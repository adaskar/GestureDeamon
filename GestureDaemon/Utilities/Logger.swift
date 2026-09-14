import Foundation
import os
import os.log

public enum Log {
    private static let logger = Logger(subsystem: "com.user.GestureDaemon", category: "Core")

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        print("[INFO] \(message)")
    }
    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        print("[ERROR] \(message)")
    }
    public static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        #if DEBUG
        print("[DEBUG] \(message)")
        #endif
    }
}

