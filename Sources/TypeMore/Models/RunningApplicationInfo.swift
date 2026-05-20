import AppKit
import Foundation

struct RunningApplicationInfo: Codable, Hashable {
    var displayName: String
    var bundleIdentifier: String

    static let generic = RunningApplicationInfo(displayName: "Current App", bundleIdentifier: "*")

    static func frontmost() -> RunningApplicationInfo {
        let app = NSWorkspace.shared.frontmostApplication
        return RunningApplicationInfo(
            displayName: app?.localizedName ?? "Current App",
            bundleIdentifier: app?.bundleIdentifier ?? "*"
        )
    }

    static func frontmostExcludingSelf() -> RunningApplicationInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = app.bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            return nil
        }
        return RunningApplicationInfo(
            displayName: app.localizedName ?? "Current App",
            bundleIdentifier: bundleIdentifier
        )
    }
}
