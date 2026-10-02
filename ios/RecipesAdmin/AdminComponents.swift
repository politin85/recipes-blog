import PhotosUI
import SwiftUI

enum AdminColors {
    static let danger = Color(hex: 0xC0392B)
    static let warningBackground = Color(hex: 0xFFF8E1)
    static let warningBorder = Color(hex: 0xF59E0B)
}

/// Top bar: "ניהול" badge and the site logo.
struct AdminHeader: View {
    var body: some View {
        HStack {
            Text("ניהול")
                .font(.rubik(12, .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.white.opacity(0.2), in: Capsule())
            Spacer()
            LogoMark()
        }
        .padding(.horizontal, 16)
        .frame(height: Theme.headerHeight)
        .background(Theme.terracotta.ignoresSafeArea(edges: .top))
    }
}

struct LogoMark: View {
    var body: some View {
        (Text("מתכונים").foregroundStyle(.white) + Text(" מחושבים").foregroundStyle(Theme.sand))
            .font(.display(19.2))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.terracotta

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rubik(15.2, .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(color, in: RoundedRectangle(cornerRadius: Theme.radius))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rubik(14.4, .medium))
            .foregroundStyle(Theme.inkLight)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(.white, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.sandDark, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Small filled button used for tools and per-section saves.
struct ToolButtonStyle: ButtonStyle {
    var color: Color = Theme.olive

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rubik(13.6, .medium))
            .foregroundStyle(.white)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background(color, in: RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.rubik(13.1, .semibold))
            .foregroundStyle(Theme.inkLight)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.rubik(15.2))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.sandDark, lineWidth: 1.5))
    }
}

extension View {
    func fieldBox() -> some View { modifier(FieldBox()) }
}

/// A labelled single-line or multi-line text field.
struct AdminField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var lines = 1
    var keyboard: UIKeyboardType = .default
    var leftToRight = false

    var body: some View {
        VStack(spacing: 6) {
            if !label.isEmpty { FieldLabel(text: label) }
            Group {
                if lines > 1 {
                    TextField(placeholder, text: $text, axis: .vertical).lineLimit(lines...max(lines, 12))
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .keyboardType(keyboard)
            .multilineTextAlignment(leftToRight ? .trailing : .leading)
            .environment(\.layoutDirection, leftToRight ? .leftToRight : .rightToLeft)
            .autocorrectionDisabled(keyboard != .default || leftToRight)
            .textInputAutocapitalization(leftToRight ? .never : nil)
            .fieldBox()
        }
    }
}

/// "── title ──────── [+ הוסף]"
struct SectionDivider<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.display(16.8)).foregroundStyle(Theme.ink)
            Rectangle().fill(Theme.sand).frame(height: 2)
            trailing()
        }
        .padding(.top, 8)
    }
}

extension SectionDivider where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

struct ToastView: View {
    @Environment(AdminSession.self) private var session

    var body: some View {
        Group {
            if let toast = session.toast {
                Text(toast.message)
                    .font(.rubik(14.4, .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(color(toast.kind), in: Capsule())
                    .shadowMd()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(3))
                        if session.toast?.id == toast.id { session.toast = nil }
                    }
                    .accessibilityIdentifier("toast")
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.toast)
    }

    private func color(_ kind: AdminSession.Toast.Kind) -> Color {
        switch kind {
        case .success: Theme.olive
        case .error: AdminColors.danger
        case .info: Theme.ink
        }
    }
}

/// Picks a photo, uploads it to Cloudinary and hands back the URL.
struct ImageUploadButton<Label: View>: View {
    @Environment(AdminSession.self) private var session
    let onUploaded: (String) -> Void
    @ViewBuilder var label: (Bool) -> Label

    @State private var item: PhotosPickerItem?
    @State private var uploading = false

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            label(uploading)
        }
        .disabled(uploading)
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            item = nil
            uploading = true
            Task {
                defer { uploading = false }
                guard let raw = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: raw),
                      let data = AdminAPI.uploadData(for: image) else {
                    session.show("לא ניתן לקרוא את התמונה", .error)
                    return
                }
                do {
                    let url = try await AdminAPI.uploadImage(data)
                    session.show("התמונה הועלתה בהצלחה ✓")
                    onUploaded(url)
                } catch {
                    session.show("שגיאה בהעלאת התמונה", .error)
                }
            }
        }
    }
}

/// Image preview with upload, URL field and the position editor.
struct ImageField: View {
    @Binding var url: String
    var height: CGFloat = 200
    var placeholder = "📷\nלחץ לבחירת תמונה"
    var showsURLField = true
    var allowsPositioning = true

    @State private var cropping = false

    var body: some View {
        VStack(spacing: 8) {
            ImageUploadButton { uploaded in
                url = uploaded
                if allowsPositioning { cropping = true }
            } label: { uploading in
                ZStack {
                    if url.isEmpty {
                        Theme.sand.opacity(0.5)
                        Text(placeholder)
                            .font(.rubik(13.6))
                            .foregroundStyle(Theme.inkMuted)
                            .multilineTextAlignment(.center)
                    } else {
                        RemoteImage(urlString: url, usePosition: allowsPositioning, width: 1200) { Theme.sand }
                    }
                    if uploading {
                        Color.white.opacity(0.6)
                        ProgressView()
                    }
                }
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(Theme.sandDark, style: StrokeStyle(lineWidth: 1.5, dash: url.isEmpty ? [6, 4] : [])))
            }

            if showsURLField {
                AdminField(label: "", text: $url, placeholder: "https://res.cloudinary.com/...", keyboard: .URL, leftToRight: true)
            }

            if !url.isEmpty {
                HStack(spacing: 8) {
                    if allowsPositioning {
                        Button("⊕ כוון מיקום תמונה") { cropping = true }
                            .buttonStyle(PillButtonStyle(fontSize: 12.8, verticalPadding: 6))
                    }
                    Button("✕ הסר") { url = "" }
                        .buttonStyle(PillButtonStyle(foreground: AdminColors.danger, fontSize: 12.8, verticalPadding: 6))
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $cropping) {
            CropEditorView(url: $url)
        }
    }
}
