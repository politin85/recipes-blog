import SwiftUI

enum Route: Hashable {
    case recipe(Int)
    case fridge
}

enum ViewMode: String { case grid, list }

struct VoiceOption: Identifiable {
    let id: String
    let label: String
    static let all = [
        VoiceOption(id: "he-IL-Wavenet-A", label: "קול נשי א"),
        VoiceOption(id: "he-IL-Wavenet-B", label: "קול זכר א"),
        VoiceOption(id: "he-IL-Wavenet-C", label: "קול נשי ב"),
        VoiceOption(id: "he-IL-Wavenet-D", label: "קול זכר ב"),
    ]
}

struct SoundOption: Identifiable {
    let id: String
    let label: String
    static let all = [
        SoundOption(id: "bell", label: "פעמון"),
        SoundOption(id: "beep", label: "ביפ"),
        SoundOption(id: "melody", label: "מלודיה"),
    ]
}

/// App-wide state: navigation, the drawer, and what the website keeps in localStorage
/// (same keys: recipeFavorites, recipeViewMode, ttsVoice, timerSound).
@MainActor
@Observable
final class AppModel {
    var path: [Route] = []
    var drawerOpen = false
    var favoritesMode = false

    var favorites: [Int] {
        didSet { UserDefaults.standard.set(favorites, forKey: "recipeFavorites") }
    }
    var viewMode: ViewMode {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "recipeViewMode") }
    }
    var ttsVoice: String {
        didSet { UserDefaults.standard.set(ttsVoice, forKey: "ttsVoice") }
    }
    var timerSound: String {
        didSet { UserDefaults.standard.set(timerSound, forKey: "timerSound") }
    }

    var siteName = "מתכונים מחושבים"
    var heroImageURL: String?

    init() {
        let defaults = UserDefaults.standard
        favorites = (defaults.array(forKey: "recipeFavorites") as? [Int]) ?? []
        viewMode = ViewMode(rawValue: defaults.string(forKey: "recipeViewMode") ?? "") ?? .list
        ttsVoice = defaults.string(forKey: "ttsVoice") ?? "he-IL-Wavenet-A"
        timerSound = defaults.string(forKey: "timerSound") ?? "bell"
        #if DEBUG
        applyDebugLaunchArguments()
        #endif
    }

    #if DEBUG
    /// Lets a debug build open straight onto a screen, e.g. `-route recipe/23`, `-route fridge`,
    /// `-drawer`, `-favorites` (used for simulator screenshots).
    private func applyDebugLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-route"), args.indices.contains(i + 1) {
            let route = args[i + 1]
            if route == "fridge" {
                path = [.fridge]
            } else if route.hasPrefix("recipe/"), let id = Int(route.dropFirst("recipe/".count)) {
                path = [.recipe(id)]
            }
        }
        if args.contains("-drawer") { drawerOpen = true }
        if args.contains("-favorites") { favoritesMode = true }
    }
    #endif

    func isFavorite(_ id: Int) -> Bool { favorites.contains(id) }

    func toggleFavorite(_ id: Int) {
        if let idx = favorites.firstIndex(of: id) { favorites.remove(at: idx) } else { favorites.append(id) }
    }

    func loadSettings() async {
        guard let settings = try? await API.shared.settings() else { return }
        if let name = settings["site_name"], !name.isEmpty { siteName = name }
        let hero = [settings["main_image_url"], settings["hero_image_url"], settings["hero_image"]]
            .compactMap { $0 }.first { !$0.isEmpty }
        if let hero { heroImageURL = ImageURL.base(hero) }
    }

    // MARK: Navigation (the drawer links and the logo)

    func showAllRecipes() {
        favoritesMode = false
        path = []
        drawerOpen = false
    }

    func showFavorites() {
        favoritesMode = true
        path = []
        drawerOpen = false
    }

    func showFridge() {
        if path.last != .fridge { path = [.fridge] }
        drawerOpen = false
    }

    func openRecipe(_ id: Int) {
        path.append(.recipe(id))
    }
}
