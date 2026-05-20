import AppKit
import Foundation

@MainActor
final class ForegroundApplicationTracker {
    private var lastNonSelfApplication: RunningApplicationInfo?
    private var observer: NSObjectProtocol?

    init(notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        refresh()
        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.record(app)
            }
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func refresh() {
        record(NSWorkspace.shared.frontmostApplication)
    }

    func targetApplication() -> RunningApplicationInfo {
        refresh()
        if let current = RunningApplicationInfo.frontmostExcludingSelf() {
            lastNonSelfApplication = current
            return current
        }
        return lastNonSelfApplication ?? .generic
    }

    private func record(_ app: NSRunningApplication?) {
        guard let app,
              let bundleIdentifier = app.bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            return
        }
        lastNonSelfApplication = RunningApplicationInfo(
            displayName: app.localizedName ?? "Current App",
            bundleIdentifier: bundleIdentifier
        )
    }
}
