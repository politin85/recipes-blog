import SwiftUI
import UserNotifications

@main
struct RecipesApp: App {
    @State private var app = AppModel()

    init() {
        Theme.registerFonts()
        AudioSetup.configure()
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // The site is Hebrew-only (`<html lang="he" dir="rtl">`), whatever the device language.
        UIView.appearance().semanticContentAttribute = .forceRightToLeft
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he"))
                .preferredColorScheme(.light)
                .tint(Theme.terracotta)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        ZStack {
            NavigationStack(path: $app.path) {
                HomeView()
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: Route.self) { route in
                        Group {
                            switch route {
                            case .recipe(let id): RecipeView(recipeID: id)
                            case .fridge: FridgeView()
                            }
                        }
                        .toolbar(.hidden, for: .navigationBar)
                    }
            }
            DrawerView()
        }
        .task { await app.loadSettings() }
    }
}

// The pages draw their own header, so the system bar is hidden; keep the edge-swipe back gesture working.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
