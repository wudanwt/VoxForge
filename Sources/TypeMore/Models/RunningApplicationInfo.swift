import AppKit
import Foundation

struct RunningApplicationInfo: Codable, Hashable {
    var displayName: String
    var bundleIdentifier: String

    static func frontmost() -> RunningApplicationInfo {
        let app = NSWorkspace.shared.frontmostApplication
        return RunningApplicationInfo(
            displayName: app?.localizedName ?? "Current App",
            bundleIdentifier: app?.bundleIdentifier ?? "*"
        )
    }
}
