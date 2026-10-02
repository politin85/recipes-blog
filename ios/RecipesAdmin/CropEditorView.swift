import SwiftUI

/// "כוונון תמונה": drag to move, pinch or use the slider to zoom. Saves the result
/// as the `#pos=x,y,zoom` fragment the site reads.
struct CropEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var url: String

    @State private var image: UIImage?
    @State private var crop = CropState()
    @State private var dragStart: CGSize?
    @State private var zoomStart: CGFloat?
    @State private var viewport: CGSize = .zero
    @State private var restored = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("כוונון תמונה").font(.display(17.6)).foregroundStyle(Theme.ink)
                Spacer()
                Text("גרור להזזה • צביטה לזום").font(.rubik(12.8)).foregroundStyle(Theme.inkMuted)
            }

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Color(hex: 0x111111)
                    if let image {
                        let size = crop.displayedSize(image: image.size, viewport: geo.size)
                        let origin = crop.origin(image: image.size, viewport: geo.size)
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: size.width, height: size.height)
                            .offset(x: origin.x, y: origin.y)
                    } else {
                        ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .gesture(drag(in: geo.size))
                .simultaneousGesture(pinch(in: geo.size))
                .onAppear { viewport = geo.size; restore() }
                .onChange(of: geo.size) { _, size in viewport = size; restore() }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            // Offsets are physical, like the CSS percentages.
            .environment(\.layoutDirection, .leftToRight)

            HStack(spacing: 12) {
                Text("זום").font(.rubik(13.1)).foregroundStyle(Theme.inkLight)
                Slider(value: Binding(get: { crop.zoom }, set: { setZoom($0) }), in: 1...3)
                    .tint(Theme.terracotta)
                    .environment(\.layoutDirection, .leftToRight)
                Text("\(Int((crop.zoom * 100).rounded()))%")
                    .font(.rubik(13.1).monospacedDigit())
                    .frame(minWidth: 44)
                Button("איפוס") { crop = CropState() }
                    .buttonStyle(PillButtonStyle(fontSize: 12.5, horizontalPadding: 12, verticalPadding: 4))
            }

            HStack(spacing: 12) {
                Button("ביטול") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("אישור ✓") { apply() }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.olive))
                    .disabled(image == nil)
            }
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .presentationBackground(.white)
        .environment(\.layoutDirection, .rightToLeft)
        .task {
            guard let remote = ImageURL.optimized(url, width: 1600) else { return }
            image = await ImageLoader.shared.load(remote)
            restore()
        }
    }

    /// Positions the image from the URL's existing `#pos=` once both the image and the viewport are known.
    private func restore() {
        guard !restored, let image, viewport.width > 0 else { return }
        crop = CropState(position: ImagePosition(urlString: url), image: image.size, viewport: viewport)
        restored = true
    }

    private func setZoom(_ zoom: CGFloat) {
        crop.zoom = min(3, max(1, zoom))
        if let image { crop.clamp(image: image.size, viewport: viewport) }
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard let image else { return }
                let start = dragStart ?? crop.offset
                dragStart = start
                crop.offset = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                crop.clamp(image: image.size, viewport: size)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func pinch(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? crop.zoom
                zoomStart = start
                setZoom(start * value.magnification)
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func apply() {
        guard let image else { return }
        url = CropState.url(base: url, position: crop.position(image: image.size, viewport: viewport))
        dismiss()
    }
}
