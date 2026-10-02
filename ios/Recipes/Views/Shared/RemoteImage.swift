import SwiftUI

/// CSS `object-fit: cover` with `object-position: x% y%`, optionally followed by
/// `transform: scale(zoom)` around the same point — how the web applies `#pos=`.
struct CoverImage: View {
    let image: UIImage
    var position: ImagePosition?
    var applyZoom = true

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let scale = max(size.width / max(image.size.width, 1), size.height / max(image.size.height, 1))
            let w = image.size.width * scale
            let h = image.size.height * scale
            let px = (position?.x ?? 50) / 100
            let py = (position?.y ?? 50) / 100
            Image(uiImage: image)
                .resizable()
                .frame(width: w, height: h)
                .offset(x: (size.width - w) * px, y: (size.height - h) * py)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .scaleEffect(applyZoom ? (position?.zoom ?? 1) : 1, anchor: UnitPoint(x: px, y: py))
        }
        .clipped()
        // Percentages are physical (left → right) in CSS regardless of text direction.
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// Loads a recipe/step image URL (honouring its `#pos=` fragment) and shows a placeholder until it arrives.
struct RemoteImage<Placeholder: View>: View {
    let urlString: String?
    var usePosition = true
    var applyZoom = true
    var width: Int = 1000
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    private var url: URL? { urlString.flatMap { ImageURL.optimized($0, width: width) } }

    var body: some View {
        ZStack {
            if let image {
                CoverImage(image: image,
                           position: usePosition ? urlString.flatMap(ImagePosition.init(urlString:)) : nil,
                           applyZoom: applyZoom)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            image = ImageLoader.shared.cached(url)
            if image == nil { image = await ImageLoader.shared.load(url) }
        }
    }
}

/// Emoji on the sand → pale gradient, shown for recipes without a photo.
struct EmojiPlaceholder: View {
    let emoji: String
    var size: CGFloat = 56

    var body: some View {
        LinearGradient(colors: [Theme.sand, Theme.terracottaPale], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Text(emoji).font(.system(size: size)))
    }
}
