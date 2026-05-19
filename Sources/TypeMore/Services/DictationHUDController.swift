import AppKit
import SwiftUI

@MainActor
final class DictationHUDController {
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(state: DictationSessionState, message: String, preview: String? = nil) {
        hideWorkItem?.cancel()
        ensurePanel()
        guard let panel else { return }
        panel.contentView = NSHostingView(rootView: DictationHUDView(state: state, message: message, preview: preview))
        position(panel)
        panel.orderFrontRegardless()
    }

    func showCompletion(message: String, preview: String? = nil) {
        show(state: .idle, message: message, preview: preview)
        scheduleHide(after: 1.4)
    }

    func showFailure(message: String) {
        show(state: .failed, message: message, preview: nil)
        scheduleHide(after: 2.5)
    }

    func hide() {
        hideWorkItem?.cancel()
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 104),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        self.panel = panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.hide()
            }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

private struct DictationHUDView: View {
    var state: DictationSessionState
    var message: String
    var preview: String?

    var body: some View {
        HStack(spacing: 14) {
            TypeMoreAvatarIcon(state: state, style: .hud)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(state == .idle ? message : state.hudTitle)
                    .font(.headline)
                Text(state == .idle ? "完成" : message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let preview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 360)
        .background(.regularMaterial.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.26), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}
