import SwiftUI

/// The slide-in menu from the reading-start edge, with the settings section.
struct DrawerView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack(alignment: .leading) {
            if app.drawerOpen {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { app.drawerOpen = false }
                    .transition(.opacity)

                panel
                    .frame(width: 280)
                    .frame(maxHeight: .infinity)
                    .background(Theme.cream.ignoresSafeArea())
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Theme.sandDark).frame(width: 1).ignoresSafeArea()
                    }
                    .shadowLg()
                    .transition(.move(edge: .leading))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.3), value: app.drawerOpen)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                LogoText(name: app.siteName, size: 17.6)
                Spacer()
                Button {
                    app.drawerOpen = false
                } label: {
                    Text("✕").font(.system(size: 20)).foregroundStyle(.white).padding(.horizontal, 8)
                }
                .accessibilityLabel("סגור")
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 64)
            .background(Theme.terracotta.ignoresSafeArea(edges: .top))

            VStack(spacing: 0) {
                navItem("🔍 כל המתכונים", current: app.path.isEmpty && !app.favoritesMode) { app.showAllRecipes() }
                navItem("⭐ מועדפים", current: app.path.isEmpty && app.favoritesMode) { app.showFavorites() }
                navItem("🥦 מתכון לפי מצרכים", current: app.path.last == .fridge) { app.showFridge() }
            }
            .padding(.vertical, 8)

            Spacer(minLength: 0)

            settings
        }
        .buttonStyle(.plain)
    }

    private func navItem(_ title: String, current: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.rubik(15.2, current ? .medium : .regular))
                .foregroundStyle(current ? Theme.terracotta : Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
        }
    }

    private var settings: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 12) {
            Text("הגדרות")
                .font(.display(13.6))
                .foregroundStyle(Theme.inkMuted)

            settingsRow("🎙 קול הקראה") {
                Picker("קול הקראה", selection: $app.ttsVoice) {
                    ForEach(VoiceOption.all) { Text($0.label).tag($0.id) }
                }
            } current: {
                VoiceOption.all.first { $0.id == app.ttsVoice }?.label ?? ""
            }

            settingsRow("🔔 צליל התראה") {
                Picker("צליל התראה", selection: $app.timerSound) {
                    ForEach(SoundOption.all) { Text($0.label).tag($0.id) }
                }
            } current: {
                SoundOption.all.first { $0.id == app.timerSound }?.label ?? ""
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.sandDark).frame(height: 1) }
        .onChange(of: app.timerSound) { _, sound in SoundPlayer.shared.play(sound) }
    }

    private func settingsRow<P: View>(_ label: String, @ViewBuilder picker: () -> P, current: () -> String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.rubik(14))
                .foregroundStyle(Theme.inkLight)
                .lineLimit(1)
            Spacer(minLength: 0)
            Menu {
                picker()
            } label: {
                HStack(spacing: 6) {
                    Text(current()).font(.rubik(12.8))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Theme.inkLight)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.white, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.sandDark, lineWidth: 1.5))
            }
        }
    }
}
