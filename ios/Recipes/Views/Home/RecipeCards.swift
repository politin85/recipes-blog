import SwiftUI

struct MetaItem: View {
    let icon: String
    let text: String
    var fontSize: CGFloat = 13.1

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: fontSize - 1))
            Text(text).font(.rubik(fontSize))
        }
        .foregroundStyle(Theme.inkLight)
    }
}

/// `.list-card`: thumbnail on the reading-start side, text beside it.
struct RecipeListCard: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 0) {
            RemoteImage(urlString: recipe.imageUrl, width: 400) {
                EmojiPlaceholder(emoji: Labels.emoji(for: recipe.category), size: 35)
            }
            .frame(width: 100)
            .frame(maxHeight: .infinity)
            .background(Theme.sand)
            .clipped()
            .overlay(alignment: .topLeading) {
                FavoriteButton(recipeID: recipe.id).padding(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.display(16.8))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                if let description = recipe.description, !description.isEmpty {
                    Text(description)
                        .font(.rubik(13.3))
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                FlowLayout(spacing: 12, lineSpacing: 6) {
                    if let category = recipe.category, !category.isEmpty {
                        Text(category)
                            .font(.rubik(11.5, .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                            .background(Theme.terracotta, in: Capsule())
                    }
                    if recipe.totalMinutes > 0 {
                        MetaItem(icon: "clock", text: "\(recipe.totalMinutes) דק'", fontSize: 12.8)
                    }
                    if let difficulty = recipe.difficulty {
                        DifficultyBadge(difficulty: difficulty)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 96)
        .fixedSize(horizontal: false, vertical: true)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .shadowSm()
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

/// `.recipe-card`: large photo on top, body below.
struct RecipeGridCard: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(urlString: recipe.imageUrl, width: 1000) {
                EmojiPlaceholder(emoji: Labels.emoji(for: recipe.category), size: 56)
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .background(Theme.sand)
            .clipped()
            .overlay(alignment: .topLeading) {
                if let category = recipe.category, !category.isEmpty {
                    Text(category)
                        .font(.rubik(12, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .background(Theme.terracotta.opacity(0.92), in: Capsule())
                        .padding(12)
                }
            }
            .overlay(alignment: .topTrailing) {
                FavoriteButton(recipeID: recipe.id).padding(8)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(recipe.title)
                    .font(.display(18.4))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, 8)

                if let description = recipe.description, !description.isEmpty {
                    Text(description)
                        .font(.rubik(14.1))
                        .foregroundStyle(Theme.inkMuted)
                        .lineSpacing(5)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if !recipe.tags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(recipe.tags.prefix(3)), id: \.self) { TagChip(text: $0) }
                    }
                    .padding(.top, 16)
                }

                HStack(spacing: 16) {
                    if recipe.totalMinutes > 0 {
                        MetaItem(icon: "clock", text: "\(recipe.totalMinutes) דק'")
                    }
                    if let servings = recipe.servings, servings > 0 {
                        MetaItem(icon: "person.2", text: "\(servings)")
                    }
                    Spacer(minLength: 0)
                    if let difficulty = recipe.difficulty {
                        DifficultyBadge(difficulty: difficulty)
                    }
                }
                .padding(.top, 16)
                .overlay(alignment: .top) { Rectangle().fill(Theme.sand).frame(height: 1) }
                .padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
        .shadowSm()
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
    }
}
