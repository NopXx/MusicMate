import Foundation
import ServiceManagement
import OSLog

enum LaunchAtLoginService {
    private static let log = Logger(subsystem: "com.nopxx.musique", category: "LaunchAtLogin")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            log.error("setEnabled(\(enabled, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
