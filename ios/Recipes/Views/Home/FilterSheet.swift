import SwiftUI

/// The "סינון ומיון" bottom sheet. Changes are drafted and only applied on "החל".
struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: RecipeFilter
    let categories: [String]

    @State private var draft = RecipeFilter()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("סינון ומיון").font(.display(17.6)).foregroundStyle(Theme.ink)
                Spacer()
                Button { dismiss() } label: {
                    Text("✕").font(.system(size: 19)).foregroundStyle(Theme.inkMuted).padding(.horizontal, 8).padding(.vertical, 4)
                }
                .accessibilityLabel("סגור")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.sand).frame(height: 1) }

            ScrollView {
                VStack(spacing: 16) {
                    group("קטגוריה", selection: $draft.category,
                          options: [("", "הכל")] + categories.map { ($0, $0) })
                    group("רמת קושי", selection: $draft.difficulty,
                          options: [("", "הכל"), ("easy", "קל"), ("medium", "בינוני"), ("hard", "מאתגר")])
                    group("זמן הכנה", selection: $draft.timeRange,
                          options: RecipeFilter.TimeRange.allCases.map { ($0, $0.label) })
                    group("מיון", selection: $draft.sort,
                          options: RecipeFilter.Sort.allCases.map { ($0, $0.label) })
                }
                .padding(20)
            }

            HStack(spacing: 12) {
                Button {
                    let search = draft.search
                    draft = RecipeFilter()
                    draft.search = search
                } label: {
                    Text("נקה הכל")
                        .font(.rubik(15.2, .medium))
                        .foregroundStyle(Theme.inkLight)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.sandDark, lineWidth: 1.5))
                }
                Button {
                    filter = draft
                    dismiss()
                } label: {
                    Text("החל")
                        .font(.rubik(15.2, .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.terracotta, in: RoundedRectangle(cornerRadius: Theme.radius))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(alignment: .top) { Rectangle().fill(Theme.sand).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .background(.white)
        .presentationDetents([.height(520), .large])
        .presentationCornerRadius(Theme.radiusLg)
        .presentationBackground(.white)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear { draft = filter }
    }

    private func group<Value: Hashable>(_ label: String, selection: Binding<Value>, options: [(Value, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.rubik(13.1, .semibold))
                .foregroundStyle(Theme.inkLight)
            Menu {
                Picker(label, selection: selection) {
                    ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
                }
            } label: {
                HStack {
                    Text(options.first { $0.0 == selection.wrappedValue }?.1 ?? "")
                        .font(.rubik(15.2))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.white, in: RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.sandDark, lineWidth: 1.5))
                .contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
