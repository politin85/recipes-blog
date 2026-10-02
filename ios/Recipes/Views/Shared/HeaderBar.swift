import SwiftUI

/// "מתכונים <span>מחושבים</span>": first word white, the rest sand.
struct LogoText: View {
    let name: String
    var size: CGFloat

    var body: some View {
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        (Text(parts.first ?? "").foregroundStyle(.white)
            + Text(parts.count > 1 ? " " + parts[1] : "").foregroundStyle(Theme.sand))
            .font(.display(size))
            .lineLimit(1)
    }
}

/// The fixed top bar: hamburger on the reading-start side, logo on the other.
struct HeaderBar: View {
    enum Style { case glass, solid(Color) }

    @Environment(AppModel.self) private var app
    var style: Style
    var showsBack = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                app.drawerOpen = true
            } label: {
                Text("☰")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("תפריט")

            if showsBack {
                Button {
                    if !app.path.isEmpty { app.path.removeLast() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward").font(.system(size: 14, weight: .semibold))
                        Text("חזרה").font(.rubik(14.4))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(height: 40)
                    .contentShape(Rectangle())
                }
            }

            Spacer(minLength: 8)

            Button {
                app.showAllRecipes()
            } label: {
                LogoText(name: app.siteName, size: 19.2)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .frame(height: Theme.headerHeight)
        .background {
            Group {
                switch style {
                case .glass:
                    Color.white.opacity(0.12)
                case .solid(let color):
                    color.shadow(color: Theme.ink.opacity(0.2), radius: 6, x: 0, y: 2)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
    }
}
