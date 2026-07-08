import Foundation

enum AppLogger {
    static func log(_ message: String) {
        FileLogWriter.append(message, to: AppConfig.appLogURL()) { errorMessage in
            NSLog("ImportToPhotos log failed: \(errorMessage)")
        }
    }
}
