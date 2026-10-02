import SwiftUI

@main
struct RecipesAdminApp: App {
    @State private var session = AdminSession()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Theme.registerFonts()
        UIView.appearance().semanticContentAttribute = .forceRightToLeft
    }

    var body: some Scene {
        WindowGroup {
            AdminRootView()
                .environment(session)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he"))
                .preferredColorScheme(.light)
                .tint(Theme.terracotta)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { session.lock() }
                }
        }
    }
}

struct AdminRootView: View {
    @Environment(AdminSession.self) private var session

    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()
            if !session.isLoggedIn {
                LoginView()
            } else if session.locked {
                LockedView()
            } else {
                AdminTabs()
            }
        }
        .overlay(alignment: .bottom) { ToastView() }
    }
}

/// Shown while a saved login waits for Face ID / passcode.
struct LockedView: View {
    @Environment(AdminSession.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            Text("🔐").font(.system(size: 48))
            Text("ניהול המתכונים נעול").font(.display(22)).foregroundStyle(Theme.ink)
            Button("פתח נעילה") { Task { await session.unlock() } }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 220)
            Button("התנתק") { session.logout() }
                .font(.rubik(14))
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(32)
        .task { await session.unlock() }
    }
}

struct AdminTabs: View {
    var body: some View {
        TabView {
            NavigationStack { RecipeListView() }
                .tabItem { Label("מתכונים", systemImage: "book") }
            NavigationStack { IngredientManagerView() }
                .tabItem { Label("מצרכים", systemImage: "list.bullet.rectangle") }
            NavigationStack { PantryView() }
                .tabItem { Label("מוצרי יסוד", systemImage: "basket") }
            NavigationStack { SiteSettingsView() }
                .tabItem { Label("הגדרות", systemImage: "gearshape") }
        }
    }
}

struct LoginView: View {
    @Environment(AdminSession.self) private var session
    @State private var password = ""
    @State private var error = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            AdminHeader()
            Spacer()
            VStack(spacing: 14) {
                Text("🔐").font(.system(size: 44))
                Text("כניסת מנהל").font(.display(24)).foregroundStyle(Theme.ink)
                Text("הזן את סיסמת הניהול להמשך").font(.rubik(14.4)).foregroundStyle(Theme.inkMuted)
                SecureField("סיסמה", text: $password)
                    .font(.rubik(16))
                    .multilineTextAlignment(.center)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 16)
                    .background(.white, in: RoundedRectangle(cornerRadius: Theme.radius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.sandDark, lineWidth: 1.5))
                    .accessibilityIdentifier("password")
                Button(busy ? "..." : "כניסה", action: submit)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy)
                if !error.isEmpty {
                    Text(error).font(.rubik(13.6)).foregroundStyle(AdminColors.danger)
                }
            }
            .padding(28)
            .frame(maxWidth: 380)
            .card()
            .padding(20)
            Spacer()
            Spacer()
        }
    }

    private func submit() {
        let pw = password.trimmingCharacters(in: .whitespaces)
        guard !pw.isEmpty, !busy else { return }
        busy = true
        error = ""
        Task {
            do {
                try await session.login(pw)
            } catch AdminAPI.AdminError.unauthorized {
                error = "סיסמה שגויה"
            } catch {
                self.error = "שגיאת רשת — נסה שוב"
            }
            busy = false
        }
    }
}
