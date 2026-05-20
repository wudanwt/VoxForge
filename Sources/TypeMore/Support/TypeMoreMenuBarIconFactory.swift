import AppKit

enum TypeMoreMenuBarIconFactory {
    static func image(for state: DictationSessionState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = state != .recording && state != .failed && state != .readyToSubmit
        }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let ink: NSColor = {
            switch state {
            case .recording, .failed:
                return .systemRed
            case .readyToSubmit:
                return .systemGreen
            case .processing, .inserting:
                return .systemBlue
            case .optimizing:
                return .systemPurple
            case .idle:
                return .labelColor
            }
        }()

        ink.setFill()
        ink.setStroke()

        let vPath = NSBezierPath()
        vPath.move(to: NSPoint(x: 2.5, y: 14.3))
        vPath.line(to: NSPoint(x: 5.0, y: 14.3))
        vPath.line(to: NSPoint(x: 8.7, y: 4.2))
        vPath.line(to: NSPoint(x: 7.1, y: 2.1))
        vPath.line(to: NSPoint(x: 5.6, y: 4.0))
        vPath.close()
        vPath.fill()

        let fPath = NSBezierPath()
        fPath.move(to: NSPoint(x: 9.0, y: 3.0))
        fPath.line(to: NSPoint(x: 11.1, y: 14.1))
        fPath.line(to: NSPoint(x: 16.2, y: 14.7))
        fPath.line(to: NSPoint(x: 15.2, y: 12.7))
        fPath.line(to: NSPoint(x: 12.0, y: 12.2))
        fPath.line(to: NSPoint(x: 11.6, y: 9.8))
        fPath.line(to: NSPoint(x: 15.0, y: 10.2))
        fPath.line(to: NSPoint(x: 14.0, y: 8.3))
        fPath.line(to: NSPoint(x: 11.2, y: 8.0))
        fPath.line(to: NSPoint(x: 10.5, y: 4.1))
        fPath.close()
        fPath.fill()

        let anvil = NSBezierPath(roundedRect: NSRect(x: 3.8, y: 1.2, width: 10.6, height: 2.0), xRadius: 0.7, yRadius: 0.7)
        anvil.fill()

        let wave = NSBezierPath()
        wave.lineWidth = 1.4
        wave.lineCapStyle = .round
        wave.move(to: NSPoint(x: 1.3, y: 8.7))
        wave.line(to: NSPoint(x: 2.5, y: 8.7))
        wave.move(to: NSPoint(x: 15.5, y: 8.7))
        wave.line(to: NSPoint(x: 16.7, y: 8.7))
        wave.stroke()

        if state == .recording || state == .failed || state == .readyToSubmit {
            ink.setFill()
            NSBezierPath(ovalIn: NSRect(x: 13.4, y: 13.0, width: 4.0, height: 4.0)).fill()
        }

        return image
    }
}
