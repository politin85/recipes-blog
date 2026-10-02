import SwiftUI
import CoreText

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Mirrors the `:root` CSS variables shared by index.html / recipe.html / fridge.html.
enum Theme {
    static let terracotta = Color(hex: 0xC2622F)
    static let terracottaLight = Color(hex: 0xD97B4A)
    static let terracottaPale = Color(hex: 0xF5E2D4)
    static let terracottaDark = Color(hex: 0xA0471E)
    static let olive = Color(hex: 0x6B7A3A)
    static let oliveLight = Color(hex: 0x8A9A50)
    static let oliveDark = Color(hex: 0x4A5828)
    static let sand = Color(hex: 0xF0E4CE)
    static let sandDark = Color(hex: 0xE2CDA8)
    static let cream = Color(hex: 0xFAF6F0)
    static let ink = Color(hex: 0x2C1F14)
    static let inkLight = Color(hex: 0x5A4030)
    static let inkMuted = Color(hex: 0x6B5042)
    static let headerSolid = Color(hex: 0x8B3A1A)
    static let stickyTitle = Color(hex: 0xA2471E, opacity: 0.97)
    static let nutritionBorder = Color(hex: 0xE8DDD0)

    static let radius: CGFloat = 12
    static let radiusLg: CGFloat = 20
    static let headerHeight: CGFloat = 52

    static func registerFonts() {
        for name in ["SecularOne-Regular", "Rubik-Light", "Rubik-Regular", "Rubik-Medium", "Rubik-SemiBold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

enum RubikWeight: String {
    case light = "Rubik-Light"
    case regular = "Rubik-Regular"
    case medium = "Rubik-Medium"
    case semibold = "Rubik-SemiBold"
}

extension Font {
    /// `--font-display` (Secular One)
    static func display(_ size: CGFloat) -> Font { .custom("SecularOne-Regular", fixedSize: size) }
    /// `--font-body` (Rubik)
    static func rubik(_ size: CGFloat, _ weight: RubikWeight = .regular) -> Font {
        .custom(weight.rawValue, fixedSize: size)
    }
}

extension View {
    /// `--shadow-sm: 0 2px 8px rgba(44,31,20,.08)`
    func shadowSm() -> some View { shadow(color: Theme.ink.opacity(0.08), radius: 4, x: 0, y: 2) }
    /// `--shadow-md: 0 6px 24px rgba(44,31,20,.12)`
    func shadowMd() -> some View { shadow(color: Theme.ink.opacity(0.12), radius: 12, x: 0, y: 6) }
    /// `--shadow-lg: 0 16px 48px rgba(44,31,20,.16)`
    func shadowLg() -> some View { shadow(color: Theme.ink.opacity(0.16), radius: 24, x: 0, y: 16) }

    /// Approximates `-webkit-text-stroke: 1px #000` used on the recipe hero text.
    func textStroke(_ color: Color = .black, width: CGFloat = 0.6) -> some View {
        self
            .shadow(color: color, radius: 0, x: width, y: 0)
            .shadow(color: color, radius: 0, x: -width, y: 0)
            .shadow(color: color, radius: 0, x: 0, y: width)
            .shadow(color: color, radius: 0, x: 0, y: -width)
    }
}

enum Labels {
    static let categoryEmoji: [String: String] = [
        "אפייה": "🥐", "עוגות": "🎂", "עוגיות": "🍪", "לחם": "🍞",
        "מרקים": "🍲", "סלטים": "🥗", "עיקריות": "🍽️", "קינוחים": "🍮",
        "חטיפים": "🥨", "שתייה": "🥤", "ארוחת בוקר": "🍳",
    ]
    static let difficulty: [String: String] = ["easy": "קל", "medium": "בינוני", "hard": "מאתגר"]

    static func emoji(for category: String?) -> String {
        category.flatMap { categoryEmoji[$0] } ?? "🍴"
    }
}
