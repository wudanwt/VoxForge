import AppKit
import SwiftUI

@MainActor
final class DictationHUDController {
    enum Placement {
        case bottomCenter
        case sideToast
        case bottomIcon

        var size: NSSize {
            switch self {
            case .bottomCenter:
                NSSize(width: 360, height: 104)
            case .sideToast:
                NSSize(width: 280, height: 84)
            case .bottomIcon:
                NSSize(width: 58, height: 58)
            }
        }
    }

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(
        state: DictationSessionState,
        message: String,
        preview: String? = nil,
        placement: Placement = .bottomCenter
    ) {
        hideWorkItem?.cancel()
        ensurePanel()
        guard let panel else { return }
        panel.setContentSize(placement.size)
        panel.contentView = NSHostingView(rootView: DictationHUDView(
            state: state,
            message: message,
            preview: preview,
            placement: placement
        ))
        position(panel, placement: placement)
        panel.orderFront(nil)
    }

    func showCompletion(message: String, preview: String? = nil) {
        show(state: .idle, message: message, preview: nil, placement: .sideToast)
        scheduleHide(after: 1.1)
    }

    func showReadyToSubmit(message: String) {
        show(state: .readyToSubmit, message: message, preview: nil, placement: .bottomIcon)
        scheduleHide(after: 1.1)
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
        let panel = NonActivatingHUDPanel(
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

    private func position(_ panel: NSPanel, placement: Placement) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x: CGFloat
        let y: CGFloat
        switch placement {
        case .bottomCenter:
            x = frame.midX - size.width / 2
            y = frame.minY + 24
        case .sideToast:
            x = frame.maxX - size.width - 24
            y = frame.maxY - size.height - 72
        case .bottomIcon:
            x = frame.midX - size.width / 2
            y = frame.minY + 24
        }
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

private final class NonActivatingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct DictationHUDView: View {
    var state: DictationSessionState
    var message: String
    var preview: String?
    var placement: DictationHUDController.Placement

    private var titleColor: Color {
        Color(red: 0.96, green: 0.98, blue: 1.0)
    }

    private var messageColor: Color {
        Color(red: 0.78, green: 0.86, blue: 0.96)
    }

    private var previewColor: Color {
        Color(red: 0.58, green: 0.88, blue: 1.0)
    }

    private var hudFill: Color {
        Color(red: 0.08, green: 0.10, blue: 0.13).opacity(0.82)
    }

    var body: some View {
        if placement == .bottomIcon {
            Image(systemName: state.hudSymbolName)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: placement.size.width, height: placement.size.height)
                .background(.regularMaterial.opacity(0.68), in: Circle())
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.30), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                .accessibilityLabel(message)
        } else {
        HStack(spacing: placement == .sideToast ? 10 : 14) {
            TypeMoreAvatarIcon(state: state, style: .hud)
                .frame(width: placement == .sideToast ? 34 : 42, height: placement == .sideToast ? 34 : 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(state == .idle ? message : state.hudTitle)
                    .font(placement == .sideToast ? .subheadline.weight(.semibold) : .headline)
                    .foregroundStyle(titleColor)
                Text(state == .idle ? "完成" : message)
                    .font(placement == .sideToast ? .caption : .callout)
                    .foregroundStyle(messageColor)
                    .lineLimit(1)
                if placement == .bottomCenter, let preview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(previewColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, placement == .sideToast ? 14 : 18)
        .padding(.vertical, placement == .sideToast ? 12 : 14)
        .frame(width: placement.size.width, height: placement.size.height)
        .background(.regularMaterial.opacity(placement == .sideToast ? 0.64 : 0.72), in: RoundedRectangle(cornerRadius: placement == .sideToast ? 16 : 18))
        .background(hudFill, in: RoundedRectangle(cornerRadius: placement == .sideToast ? 16 : 18))
        .overlay(
            RoundedRectangle(cornerRadius: placement == .sideToast ? 16 : 18)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.56, green: 0.88, blue: 1.0).opacity(0.42),
                            Color.white.opacity(0.18),
                            Color(red: 1.0, green: 0.22, blue: 0.34).opacity(0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
    }
}
