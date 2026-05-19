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
                Circle()
                    .fill(backgroundGradient)
                Circle()
                    .stroke(accentColor.opacity(state == .idle ? 0.28 : 0.9), lineWidth: strokeWidth)
            }

            faceShape
                .fill(faceColor)
                .frame(width: faceSize.width, height: faceSize.height)
                .offset(y: faceOffsetY)

            hairShape
                .fill(primaryColor)
                .frame(width: hairSize.width, height: hairSize.height)
                .offset(y: hairOffsetY)

            glasses
                .stroke(primaryColor, style: StrokeStyle(lineWidth: glassesLineWidth, lineCap: .round, lineJoin: .round))
                .frame(width: glassesSize.width, height: glassesSize.height)
                .offset(y: glassesOffsetY)

            moustache
                .fill(primaryColor)
                .frame(width: moustacheSize.width, height: moustacheSize.height)
                .offset(y: moustacheOffsetY)

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
        case .idle: .blue
        }
    }

    private var primaryColor: Color {
        style == .menuBar ? .primary : Color(red: 0.08, green: 0.10, blue: 0.16)
    }

    private var faceColor: Color {
        style == .menuBar ? .primary.opacity(0.92) : Color(red: 0.93, green: 0.72, blue: 0.58)
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.08, blue: 0.22),
                Color(red: 0.04, green: 0.16, blue: 0.40),
                accentColor.opacity(0.70)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var strokeWidth: CGFloat {
        switch style {
        case .menuBar: 0
        case .hud: 2
        case .header: 2.4
        }
    }

    private var faceSize: CGSize {
        switch style {
        case .menuBar: CGSize(width: 15, height: 13)
        case .hud: CGSize(width: 28, height: 24)
        case .header: CGSize(width: 31, height: 27)
        }
    }

    private var faceOffsetY: CGFloat {
        switch style {
        case .menuBar: 2.4
        case .hud: 4.0
        case .header: 4.6
        }
    }

    private var hairSize: CGSize {
        switch style {
        case .menuBar: CGSize(width: 15, height: 7)
        case .hud: CGSize(width: 28, height: 12)
        case .header: CGSize(width: 31, height: 13)
        }
    }

    private var hairOffsetY: CGFloat {
        switch style {
        case .menuBar: -4.4
        case .hud: -8.8
        case .header: -9.8
        }
    }

    private var glassesSize: CGSize {
        switch style {
        case .menuBar: CGSize(width: 14.6, height: 6.0)
        case .hud: CGSize(width: 27, height: 10)
        case .header: CGSize(width: 30, height: 11)
        }
    }

    private var glassesLineWidth: CGFloat {
        switch style {
        case .menuBar: 1.55
        case .hud: 2.4
        case .header: 2.6
        }
    }

    private var glassesOffsetY: CGFloat {
        switch style {
        case .menuBar: 1.4
        case .hud: 2.8
        case .header: 3.2
        }
    }

    private var moustacheSize: CGSize {
        switch style {
        case .menuBar: CGSize(width: 6.6, height: 2.3)
        case .hud: CGSize(width: 12, height: 4)
        case .header: CGSize(width: 13.5, height: 4.4)
        }
    }

    private var moustacheOffsetY: CGFloat {
        switch style {
        case .menuBar: 6.6
        case .hud: 12
        case .header: 13
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

    private var faceShape: some Shape {
        RoundedRectangle(cornerRadius: style == .menuBar ? 4.2 : 7.5, style: .continuous)
    }

    private var hairShape: some Shape {
        UnevenRoundedRectangle(
            topLeadingRadius: style == .menuBar ? 5 : 8,
            bottomLeadingRadius: 1,
            bottomTrailingRadius: style == .menuBar ? 5 : 8,
            topTrailingRadius: style == .menuBar ? 5 : 8,
            style: .continuous
        )
    }

    private var glasses: some Shape {
        GlassesShape()
    }

    private var moustache: some Shape {
        Capsule()
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

private struct GlassesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lensWidth = rect.width * 0.38
        let lensHeight = rect.height * 0.78
        let y = rect.midY - lensHeight / 2
        let left = CGRect(x: rect.minX, y: y, width: lensWidth, height: lensHeight)
        let right = CGRect(x: rect.maxX - lensWidth, y: y, width: lensWidth, height: lensHeight)
        path.addRoundedRect(in: left, cornerSize: CGSize(width: lensHeight * 0.42, height: lensHeight * 0.42))
        path.addRoundedRect(in: right, cornerSize: CGSize(width: lensHeight * 0.42, height: lensHeight * 0.42))
        path.move(to: CGPoint(x: left.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: right.minX, y: rect.midY))
        return path
    }
}
