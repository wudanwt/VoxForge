import AppKit

enum TypeMoreMenuBarIconFactory {
    static func image(for state: DictationSessionState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = state != .recording && state != .failed
        }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let ink: NSColor = {
            switch state {
            case .recording:
                return .systemRed
            case .failed:
                return .systemRed
            default:
                return .labelColor
            }
        }()

        ink.setFill()
        ink.setStroke()

        let face = NSBezierPath(roundedRect: NSRect(x: 3.0, y: 2.0, width: 12.0, height: 12.0), xRadius: 4.2, yRadius: 4.2)
        face.fill()

        NSColor.clear.setFill()
        let lowerCut = NSBezierPath(rect: NSRect(x: 3.0, y: 2.0, width: 12.0, height: 4.2))
        lowerCut.fill()

        ink.setFill()
        let jaw = NSBezierPath(roundedRect: NSRect(x: 4.2, y: 2.0, width: 9.6, height: 7.0), xRadius: 3.3, yRadius: 3.3)
        jaw.fill()

        let hair = NSBezierPath()
        hair.move(to: NSPoint(x: 3.4, y: 10.9))
        hair.curve(to: NSPoint(x: 6.2, y: 15.0), controlPoint1: NSPoint(x: 3.7, y: 13.1), controlPoint2: NSPoint(x: 4.6, y: 14.4))
        hair.line(to: NSPoint(x: 8.0, y: 13.8))
        hair.line(to: NSPoint(x: 9.4, y: 15.2))
        hair.line(to: NSPoint(x: 10.7, y: 13.7))
        hair.line(to: NSPoint(x: 12.2, y: 14.8))
        hair.curve(to: NSPoint(x: 14.7, y: 10.7), controlPoint1: NSPoint(x: 13.9, y: 14.0), controlPoint2: NSPoint(x: 14.8, y: 12.6))
        hair.close()
        hair.fill()

        let glasses = NSBezierPath()
        glasses.lineWidth = 1.35
        glasses.appendRoundedRect(NSRect(x: 3.7, y: 7.3, width: 4.6, height: 3.2), xRadius: 1.1, yRadius: 1.1)
        glasses.appendRoundedRect(NSRect(x: 9.7, y: 7.3, width: 4.6, height: 3.2), xRadius: 1.1, yRadius: 1.1)
        glasses.move(to: NSPoint(x: 8.3, y: 8.9))
        glasses.line(to: NSPoint(x: 9.7, y: 8.9))
        glasses.stroke()

        let mouth = NSBezierPath(roundedRect: NSRect(x: 6.7, y: 4.3, width: 4.6, height: 1.35), xRadius: 0.7, yRadius: 0.7)
        mouth.fill()

        if state == .recording {
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: 12.8, y: 12.6, width: 4.0, height: 4.0)).fill()
        }

        return image
    }
}
