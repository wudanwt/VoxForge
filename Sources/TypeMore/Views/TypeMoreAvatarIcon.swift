import SwiftUI

struct TypeMoreAvatarIcon: View {
    enum Style {
        case menuBar
        case hud
        case header
    }

    var state: DictationSessionState
    var style: Style

    var body: some View {
        ZStack {
            if style != .menuBar {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundGradient)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accentColor.opacity(state == .idle ? 0.30 : 0.88), lineWidth: strokeWidth)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 0.8)
                    .padding(2)
            }

            waveBars
                .opacity(style == .menuBar ? 0 : 0.62)

            monogram
                .foregroundStyle(monogramGradient)
                .shadow(color: accentColor.opacity(style == .menuBar ? 0 : 0.72), radius: style == .header ? 4 : 3)

            anvil
                .fill(anvilGradient)
                .frame(width: anvilSize.width, height: anvilSize.height)
                .offset(y: anvilOffsetY)

            forgeGlow

            if style != .menuBar {
                stateBadge
                    .frame(width: badgeSize, height: badgeSize)
                    .offset(x: badgeOffset.x, y: badgeOffset.y)
            } else if state == .recording {
                Circle()
                    .fill(.primary)
                    .frame(width: 3.6, height: 3.6)
                    .offset(x: 6.4, y: -6.4)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("VoxForge 声铸")
    }

    private var accentColor: Color {
        switch state {
        case .recording: .red
        case .processing: .blue
        case .optimizing: .purple
        case .inserting: .blue
        case .readyToSubmit: .green
        case .failed: .red
        case .idle: .cyan
        }
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.04, blue: 0.15),
                Color(red: 0.02, green: 0.12, blue: 0.42),
                Color(red: 0.12, green: 0.03, blue: 0.34)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var monogramGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.77, green: 1.0, blue: 1.0),
                Color(red: 0.35, green: 0.67, blue: 1.0),
                Color(red: 1.0, green: 0.70, blue: 0.28)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var anvilGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.44, green: 0.70, blue: 1.0),
                Color(red: 0.04, green: 0.08, blue: 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cornerRadius: CGFloat {
        switch style {
        case .menuBar: 0
        case .hud: 10
        case .header: 12
        }
    }

    private var strokeWidth: CGFloat {
        switch style {
        case .menuBar: 0
        case .hud: 1.8
        case .header: 2.2
        }
    }

    private var anvilSize: CGSize {
        switch style {
        case .menuBar: CGSize(width: 12, height: 2)
        case .hud: CGSize(width: 33, height: 7)
        case .header: CGSize(width: 36, height: 8)
        }
    }

    private var anvilOffsetY: CGFloat {
        switch style {
        case .menuBar: 7
        case .hud: 15
        case .header: 17
        }
    }

    private var badgeSize: CGFloat {
        switch style {
        case .menuBar: 0
        case .hud: 13
        case .header: 15
        }
    }

    private var badgeOffset: CGPoint {
        switch style {
        case .menuBar: .zero
        case .hud: CGPoint(x: 14, y: -14)
        case .header: CGPoint(x: 16, y: -16)
        }
    }

    private var monogram: some View {
        VoxForgeMonogramShape()
            .frame(width: monogramSize.width, height: monogramSize.height)
            .offset(y: monogramOffsetY)
    }

    private var monogramSize: CGSize {
        switch style {
        case .menuBar: CGSize(width: 16, height: 15)
        case .hud: CGSize(width: 39, height: 34)
        case .header: CGSize(width: 43, height: 38)
        }
    }

    private var monogramOffsetY: CGFloat {
        switch style {
        case .menuBar: -1
        case .hud: -3
        case .header: -4
        }
    }

    private var waveBars: some View {
        HStack(spacing: style == .header ? 3 : 2) {
            ForEach([0.38, 0.62, 0.90, 0.62, 0.38], id: \.self) { scale in
                Capsule()
                    .fill(Color.cyan.opacity(0.85))
                    .frame(width: style == .header ? 3.8 : 3, height: waveHeight * scale)
            }
        }
        .offset(y: style == .header ? 0 : -1)
    }

    private var waveHeight: CGFloat {
        switch style {
        case .menuBar: 0
        case .hud: 31
        case .header: 34
        }
    }

    @ViewBuilder
    private var forgeGlow: some View {
        if style != .menuBar {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.orange.opacity(0.9), .orange.opacity(0.0)],
                        center: .center,
                        startRadius: 1,
                        endRadius: style == .header ? 16 : 13
                    )
                )
                .frame(width: style == .header ? 30 : 25, height: style == .header ? 22 : 18)
                .offset(y: style == .header ? 11 : 10)
        }
    }

    @ViewBuilder
    private var stateBadge: some View {
        ZStack {
            Circle()
                .fill(accentColor)
            Image(systemName: state.hudSymbolName)
                .font(.system(size: style == .hud ? 7 : 8, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

private struct VoxForgeMonogramShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.03, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.30, y: h * 0.06))
        path.addLine(to: CGPoint(x: w * 0.52, y: h * 0.86))
        path.addLine(to: CGPoint(x: w * 0.42, y: h * 1.00))
        path.addLine(to: CGPoint(x: w * 0.30, y: h * 0.87))
        path.closeSubpath()

        path.move(to: CGPoint(x: w * 0.54, y: h * 0.97))
        path.addLine(to: CGPoint(x: w * 0.66, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.98, y: h * 0.04))
        path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.22))
        path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.25))
        path.addLine(to: CGPoint(x: w * 0.67, y: h * 0.42))
        path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.39))
        path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.57))
        path.addLine(to: CGPoint(x: w * 0.63, y: h * 0.60))
        path.addLine(to: CGPoint(x: w * 0.59, y: h * 0.86))
        path.closeSubpath()

        return path
    }
}

private struct AnvilShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.05, y: h * 0.25))
        path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.25))
        path.addLine(to: CGPoint(x: w * 0.98, y: h * 0.48))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.62))
        path.addLine(to: CGPoint(x: w * 0.32, y: h * 0.62))
        path.addLine(to: CGPoint(x: w * 0.18, y: h * 0.50))
        path.closeSubpath()
        path.addRoundedRect(in: CGRect(x: w * 0.28, y: h * 0.58, width: w * 0.42, height: h * 0.28), cornerSize: CGSize(width: h * 0.1, height: h * 0.1))
        return path
    }
}

private extension TypeMoreAvatarIcon {
    var anvil: AnvilShape {
        AnvilShape()
    }
}
