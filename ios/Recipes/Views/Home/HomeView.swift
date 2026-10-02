import SwiftUI

@MainActor
@Observable
final class HomeModel {
    enum Phase { case loading, loaded, failed }

    var phase: Phase = .loading
    var recipes: [Recipe] = []
    var filter = RecipeFilter()
    var searchText = ""

    func load() async {
        do {
            recipes = try await API.shared.recipes()
            phase = .loaded
        } catch {
            if recipes.isEmpty { phase = .failed }
        }
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var model = HomeModel()
    @State private var scrolled = false
    @State private var showFilters = false

    private var visible: [Recipe] {
        model.filter.apply(to: model.recipes, favoritesOnly: app.favoritesMode, favorites: app.favorites)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 0) {
                        HomeHero(safeTop: geo.safeAreaInsets.top, remoteURL: app.heroImageURL)
                        main
                        FooterView()
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 10 } action: { _, new in
                    withAnimation(.easeInOut(duration: 0.3)) { scrolled = new }
                }
                .refreshable { await model.load() }
                .ignoresSafeArea(edges: .top)
                .background(Theme.cream)

                HeaderBar(style: scrolled ? .solid(Theme.headerSolid) : .glass)
            }
            .overlay(alignment: .bottomLeading) { filterButton }
        }
        .background(Theme.cream.ignoresSafeArea())
        .sheet(isPresented: $showFilters) {
            FilterSheet(filter: $model.filter, categories: RecipeFilter.categories(in: model.recipes))
        }
        .task { if model.recipes.isEmpty { await model.load() } }
        // 200 ms debounce, like the web search input.
        .task(id: model.searchText) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            model.filter.search = model.searchText.trimmingCharacters(in: .whitespaces)
        }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.bottom, 32)

            sectionHeader
                .padding(.bottom, 24)

            content
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 64)
        .frame(maxWidth: 1200)
        .frame(maxWidth: .infinity)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            TextField("", text: $model.searchText, prompt: Text("חפש מתכון...").foregroundStyle(Theme.inkMuted))
                .font(.rubik(16))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .autocorrectionDisabled()
                .submitLabel(.search)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(.white, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.sandDark, lineWidth: 1.5))
        .shadowSm()
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var sectionHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(app.favoritesMode ? "⭐ מועדפים" : "כל המתכונים")
                .font(.display(25.6))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [Theme.terracotta, Theme.terracottaLight], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 3)
                        .clipShape(Capsule())
                }
            if !visible.isEmpty {
                Text("\(visible.count) מתכונים")
                    .font(.rubik(14.4))
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                viewButton(.grid, icon: "square.grid.2x2.fill", label: "תצוגת כרטיסים")
                viewButton(.list, icon: "list.bullet", label: "תצוגת רשימה")
            }
        }
    }

    private func viewButton(_ mode: ViewMode, icon: String, label: String) -> some View {
        let active = app.viewMode == mode
        return Button {
            app.viewMode = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? .white : Theme.inkMuted)
                .frame(width: 34, height: 34)
                .background(active ? Theme.terracotta : .white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(active ? Theme.terracotta : Theme.sandDark, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            StateBox(spinnerColor: Theme.terracotta, message: "טוען מתכונים...")
        case .failed:
            StateBox(icon: "⚠️", message: "לא הצלחנו לטעון את המתכונים. נסה שוב בעוד רגע.")
        case .loaded:
            let list = visible
            if list.isEmpty {
                StateBox(icon: app.favoritesMode ? "⭐" : "🔍",
                         message: app.favoritesMode ? "עדיין אין מועדפים. לחץ ☆ על מתכון כדי להוסיף." : "לא נמצאו מתכונים תואמים")
            } else {
                recipeList(list)
            }
        }
    }

    private func recipeList(_ list: [Recipe]) -> some View {
        let grid = app.viewMode == .grid
        let spacing: CGFloat = grid ? 20 : 16
        let columns = grid ? [GridItem(.adaptive(minimum: 300), spacing: spacing)] : [GridItem(.flexible())]
        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(groups(list), id: \.recipes.first?.id) { group in
                if model.filter.sort.groupsByDifficulty {
                    groupHeader(group.difficulty, grid: grid)
                }
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(group.recipes) { recipe in
                        card(recipe, grid: grid)
                    }
                }
            }
        }
    }

    /// Runs of consecutive recipes sharing a difficulty (one run when not sorting by difficulty).
    private func groups(_ list: [Recipe]) -> [(difficulty: String?, recipes: [Recipe])] {
        guard model.filter.sort.groupsByDifficulty else { return [(nil, list)] }
        var out: [(difficulty: String?, recipes: [Recipe])] = []
        for recipe in list {
            if let last = out.last, last.difficulty == recipe.difficulty {
                out[out.count - 1].recipes.append(recipe)
            } else {
                out.append((recipe.difficulty, [recipe]))
            }
        }
        return out
    }

    private func card(_ recipe: Recipe, grid: Bool) -> some View {
        // A tap gesture rather than a Button, so the favorite star inside the card stays tappable.
        Group {
            if grid { RecipeGridCard(recipe: recipe) } else { RecipeListCard(recipe: recipe) }
        }
        .onTapGesture { app.openRecipe(recipe.id) }
        .accessibilityAddTraits(.isButton)
    }

    private func groupHeader(_ difficulty: String?, grid: Bool) -> some View {
        Text(difficulty.flatMap { Labels.difficulty[$0] ?? $0 } ?? "ללא רמה")
            .font(.display(grid ? 18.4 : 17.6))
            .foregroundStyle(Theme.inkLight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.sandDark).frame(height: 2) }
            .padding(.top, 8)
    }

    private var filterButton: some View {
        Button {
            showFilters = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 16, weight: .semibold))
                Text("סינון").font(.display(16))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(Theme.terracotta, in: Capsule())
            .shadow(color: Theme.terracotta.opacity(0.45), radius: 8, x: 0, y: 4)
            .overlay(alignment: .topLeading) {
                if model.filter.badgeCount > 0 {
                    Text("\(model.filter.badgeCount)")
                        .font(.rubik(11.2, .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Theme.olive, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .offset(x: -6, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, 24)
        .padding(.bottom, 24)
        .accessibilityLabel("סינון ומיון")
    }
}

/// The cover banner. Like the mobile web layout it shows the middle of the wide image,
/// and it continues under the status bar and the glass header.
struct HomeHero: View {
    let safeTop: CGFloat
    let remoteURL: String?

    private let bannerHeight: CGFloat = 215

    var body: some View {
        ZStack(alignment: .bottom) {
            // Soft fill behind the status bar, taken from the image itself.
            banner
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1.6)
                .blur(radius: 30, opaque: true)
                .clipped()
            banner
                .frame(height: bannerHeight)
                .frame(maxWidth: .infinity)
                .clipped()
        }
        .frame(height: safeTop + Theme.headerHeight - 12 + bannerHeight)
        .clipped()
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder
    private var banner: some View {
        if let remoteURL {
            RemoteImage(urlString: remoteURL, usePosition: false, width: 1600) { localBanner }
        } else {
            localBanner
        }
    }

    private var localBanner: some View {
        Color.clear.overlay(Image("BlogCover").resizable().scaledToFill())
    }
}
