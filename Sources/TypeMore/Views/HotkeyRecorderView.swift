import AppKit
import SwiftUI

struct HotkeyRecorderView: NSViewRepresentable {
    var onCapture: (HotkeyDefinition?) -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onCapture = onCapture
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.onCapture = onCapture
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class RecorderNSView: NSView {
    var onCapture: ((HotkeyDefinition?) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCapture?(nil)
            return
        }
        if let hotkey = HotkeyDefinition.from(event: event) {
            onCapture?(hotkey)
        } else {
            NSSound.beep()
        }
    }

    override func flagsChanged(with event: NSEvent) {
    }
}
