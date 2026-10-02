import SwiftUI

/// CSS `display:flex; flex-wrap:wrap; gap`.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat?

    private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0, x + size.width > maxWidth {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((i, size))
            x += size.width + spacing
        }
        return rows.filter { !$0.isEmpty }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(subviews, maxWidth: maxWidth)
        let gap = lineSpacing ?? spacing
        let height = rows.map { $0.map(\.size.height).max() ?? 0 }.reduce(0, +) + gap * CGFloat(max(0, rows.count - 1))
        let width = rows.map { $0.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(0, $0.count - 1)) }.max() ?? 0
        return CGSize(width: proposal.width == nil ? width : min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let gap = lineSpacing ?? spacing
        var y = bounds.minY
        for row in rows(subviews, maxWidth: bounds.width) {
            let rowHeight = row.map(\.size.height).max() ?? 0
            var x = bounds.minX
            for item in row {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (rowHeight - item.size.height) / 2),
                    proposal: ProposedViewSize(width: min(item.size.width, bounds.width), height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += rowHeight + gap
        }
    }
}

/// The spinning ring used in the web's `.state-box`.
struct Spinner: View {
    var color: Color = Theme.terracotta
    var size: CGFloat = 40
    @State private var spinning = false

    var body: some View {
        Circle()
            .stroke(Theme.sandDark, lineWidth: 3)
            .overlay(Circle().trim(from: 0, to: 0.25).stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round)))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

struct StateBox: View {
    var icon: String?
    var spinnerColor: Color?
    var message: String
    var detail: String?

    var body: some View {
        VStack(spacing: 16) {
            if let spinnerColor { Spinner(color: spinnerColor, size: spinnerColor == Theme.olive ? 36 : 40) }
            if let icon { Text(icon).font(.system(size: 48)) }
            VStack(spacing: 4) {
                Text(message).font(.rubik(16.8))
                if let detail { Text(detail).font(.rubik(13.5)) }
            }
            .multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.inkMuted)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
        .padding(.horizontal, 32)
    }
}

struct DifficultyBadge: View {
    let difficulty: String

    private var colors: (bg: Color, fg: Color) {
        switch difficulty {
        case "easy": (Color(hex: 0xE8F5E9), Color(hex: 0x2E7D32))
        case "medium": (Color(hex: 0xFFF8E1), Color(hex: 0xF57F17))
        case "hard": (Color(hex: 0xFFEBEE), Color(hex: 0xC62828))
        default: (.clear, Theme.inkLight)
        }
    }

    var body: some View {
        if let label = Labels.difficulty[difficulty] {
            Text(label)
                .font(.rubik(12.5, .semibold))
                .foregroundStyle(colors.fg)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(colors.bg, in: Capsule())
        }
    }
}

struct TagChip: View {
    let text: String
    var fontSize: CGFloat = 12
    var horizontalPadding: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.rubik(fontSize))
            .foregroundStyle(Theme.inkLight)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 4)
            .background(Theme.sand, in: Capsule())
    }
}

struct FooterView: View {
    var body: some View {
        Text("מתכונים מחושבים  |  המטבח פוגש טכנולוגיה  |  ניר פוליטי  © 2026")
            .font(.rubik(13.6))
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(Theme.ink)
    }
}

/// White rounded card with the small shadow (`.card`).
struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.radiusLg
    func body(content: Content) -> some View {
        content
            .background(.white, in: RoundedRectangle(cornerRadius: radius))
            .shadowSm()
    }
}

extension View {
    func card(radius: CGFloat = Theme.radiusLg) -> some View { modifier(CardBackground(radius: radius)) }
}

/// `.card-heading`: bottom rule plus the terracotta bar on the reading-start side.
struct CardHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.display(17.6))
            .foregroundStyle(Theme.ink)
            .padding(.leading, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.terracotta).frame(width: 3) }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.sand).frame(height: 2) }
            .padding(.bottom, 20)
    }
}

/// Outlined pill button (`.open-all-btn`, `.step-tts-btn`, …).
struct PillButtonStyle: ButtonStyle {
    var fill: Color = .white
    var border: Color = Theme.sandDark
    var foreground: Color = Theme.inkLight
    var fontSize: CGFloat = 13.3
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rubik(fontSize))
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(border, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
