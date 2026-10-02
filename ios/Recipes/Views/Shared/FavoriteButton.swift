import SwiftUI

/// The ⭐ / ☆ circle on recipe cards.
struct FavoriteButton: View {
    @Environment(AppModel.self) private var app
    let recipeID: Int

    var body: some View {
        let isFav = app.isFavorite(recipeID)
        Button {
            app.toggleFavorite(recipeID)
        } label: {
            Text(isFav ? "⭐" : "☆")
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
                .background(isFav ? Color(hex: 0xFFF3CD) : Color.white.opacity(0.85), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFav ? "הסר ממועדפים" : "הוסף למועדפים")
    }
}
