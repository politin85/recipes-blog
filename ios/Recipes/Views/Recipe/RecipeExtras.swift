import SwiftUI

struct NotesCard: View {
    @Bindable var model: RecipeModel
    let notes: [RecipeNote]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "he_IL")
        f.dateFormat = "d.M.yyyy"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeading(title: "הערות אישיות")

            ForEach(notes) { note in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.noteText)
                            .font(.rubik(14.4))
                            .foregroundStyle(Theme.ink)
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                        if let date = note.createdAt {
                            Text(Self.dateFormatter.string(from: date))
                                .font(.rubik(12))
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                    Spacer(minLength: 8)
                    Button {
                        Task { await model.deleteNote(note) }
                    } label: {
                        Text("✕").font(.system(size: 16)).foregroundStyle(Theme.inkMuted).padding(2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("מחק")
                }
                .padding(16)
                .background(Theme.sand, in: RoundedRectangle(cornerRadius: Theme.radius))
                .padding(.bottom, 12)
            }

            HStack(alignment: .bottom, spacing: 12) {
                TextField("", text: $model.noteDraft,
                          prompt: Text("הוסף הערה...").foregroundStyle(Theme.inkMuted.opacity(0.7)), axis: .vertical)
                    .font(.rubik(14.4))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3, reservesSpace: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.white, in: RoundedRectangle(cornerRadius: Theme.radius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.sandDark, lineWidth: 1.5))

                Button {
                    Task { await model.addNote() }
                } label: {
                    Text("שמור")
                        .font(.rubik(14.4))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.terracotta, in: RoundedRectangle(cornerRadius: Theme.radius))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, notes.isEmpty ? 0 : 4)
        }
        .padding(24)
        .card()
    }
}

struct NutritionCard: View {
    let nutrition: Nutrition

    var body: some View {
        let hasPer100 = nutrition.hasPer100
        VStack(alignment: .leading, spacing: 0) {
            Text(nutrition.perServings.map { "ערכים תזונתיים (למנה אחת מתוך \($0))" } ?? "ערכים תזונתיים למנה")
                .font(.display(17.6))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 16)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                if hasPer100 {
                    GridRow {
                        Text("")
                        Text("למנה").gridColumnAlignment(.center)
                        Text("ל-100 גרם").gridColumnAlignment(.trailing)
                    }
                    .font(.rubik(12, .medium))
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.bottom, 4)
                    Rectangle().fill(Theme.nutritionBorder).frame(height: 2)
                }
                ForEach(Array(nutrition.rows.enumerated()), id: \.element.id) { index, row in
                    GridRow {
                        Text(row.label)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(row.value) \(row.unit)")
                            .font(.rubik(14, .medium))
                            .foregroundStyle(Theme.inkLight)
                        if hasPer100 {
                            Text("\(nutrition.per100(row)) \(row.unit)")
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                    .font(.rubik(14))
                    .padding(.vertical, 8)
                    if index < nutrition.rows.count - 1 {
                        Rectangle().fill(Theme.nutritionBorder).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 12)

            Text("על בסיס נתוני USDA FoodData Central")
                .font(.rubik(12))
                .foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        .padding(24)
        .background(Theme.cream, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.nutritionBorder, lineWidth: 1.5))
    }
}

/// "מתכונים נוספים": the horizontal snap gallery of related recipes.
struct RelatedSection: View {
    @Environment(AppModel.self) private var app
    let recipes: [Recipe]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("מתכונים נוספים")
                .font(.display(20.8))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(recipes) { recipe in
                        card(recipe)
                            .containerRelativeFrame(.horizontal) { width, _ in width * 0.7 - 8 }
                            .onTapGesture { app.openRecipe(recipe.id) }
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 16)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private func card(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Related cards use the raw image, without the crop position.
            RemoteImage(urlString: recipe.imageUrl, usePosition: false, width: 600) {
                Theme.terracottaPale.overlay(Text(Labels.emoji(for: recipe.category)).font(.system(size: 32)))
            }
            .frame(height: 100)
            .frame(maxWidth: .infinity)
            .background(Theme.terracottaPale)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.rubik(14.4, .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                if recipe.totalMinutes > 0 {
                    Text("⏱ \(recipe.totalMinutes) דק'")
                        .font(.rubik(12.5))
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.sand)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}
