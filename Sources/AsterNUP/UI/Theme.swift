import AppKit
import CoreImage
import SwiftUI

/// AsterNUP follows the Mac's own look: the accent colour picked in System Settings › Appearance, system materials,
/// SF Pro, SF Symbols and continuous ("squircle") corners. Everything adapts to light and dark mode.
enum Theme {
    /// The user's accent colour (System Settings › Appearance › Accent colour).
    static var focus: Color { Color(nsColor: .controlAccentColor) }
    static let playing = Color(nsColor: .systemGreen)
    static let danger = Color(nsColor: .systemRed)
    static let warning = Color(nsColor: .systemOrange)

    static func background(_ s: ColorScheme) -> Color { Color(nsColor: .windowBackgroundColor) }
    /// A quiet fill for grouped content (cards, list containers), like System Settings' grouped forms.
    static func card(_ s: ColorScheme) -> Color { s == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04) }
    /// A slightly stronger fill for tiles and unfocused buttons.
    static func tile(_ s: ColorScheme) -> Color { s == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06) }
    static func secondary(_ s: ColorScheme) -> Color { Color(nsColor: .secondaryLabelColor) }
    static func separator(_ s: ColorScheme) -> Color { Color(nsColor: .separatorColor) }

    static let tileRadius: CGFloat = 20
    static let panelRadius: CGFloat = 24
    static let rowRadius: CGFloat = 10

    static func shape(_ r: CGFloat) -> RoundedRectangle { RoundedRectangle(cornerRadius: r, style: .continuous) }
}

// MARK: - Backgrounds

/// An `NSVisualEffectView`, for the window's frosted backdrop.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = blending; v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material; v.blendingMode = blending }
}

/// The focused game's artwork as a soft wash of colour behind the Home screen (like Apple TV's top shelf).
/// The blurred wash is made once per artwork and cached, so nothing is re-blurred per frame.
struct AmbientBackground: View {
    let artwork: String?
    @Environment(\.colorScheme) var scheme
    var body: some View {
        // Sized by its container only: the square artwork must never make the window's content taller.
        Color.clear
            .overlay {
                ZStack {
                    VisualEffectBackground()
                    if let img = AmbientCache.wash(for: artwork) {
                        Image(nsImage: img).resizable().interpolation(.high).scaledToFill()
                            .opacity(scheme == .dark ? 0.42 : 0.30)
                            .transition(.opacity)
                            .id(artwork)
                    }
                    LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor).opacity(0.55)], startPoint: .top, endPoint: .bottom)
                }
            }
            .clipped()
            .animation(.easeInOut(duration: 0.45), value: artwork)
            .ignoresSafeArea()
    }
}

@MainActor
enum AmbientCache {
    private static var cache: [String: NSImage] = [:]
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// The middle of the artwork, shrunk and Gaussian-blurred once (Core Image), then cached.
    static func wash(for path: String?) -> NSImage? {
        guard let path else { return nil }
        if let hit = cache[path] { return hit }
        guard let src = NSImage(contentsOfFile: path),
              let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side: CGFloat = 96
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        // App icons have transparent margins: sample the middle 60%.
        var img = CIImage(cgImage: cg).cropped(to: CGRect(x: w * 0.2, y: h * 0.2, width: w * 0.6, height: h * 0.6))
        img = img.transformed(by: CGAffineTransform(translationX: -w * 0.2, y: -h * 0.2))
            .transformed(by: CGAffineTransform(scaleX: side / (w * 0.6), y: side / (h * 0.6)))
        let blurred = img.clampedToExtent().applyingGaussianBlur(sigma: 14).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        guard let out = context.createCGImage(blurred, from: blurred.extent) else { return nil }
        let wash = NSImage(cgImage: out, size: NSSize(width: side, height: side))
        cache[path] = wash
        return wash
    }
}

// MARK: - Controller glyphs

/// A controller button in hint bars, drawn with SF Symbols where one exists (Ⓐ Ⓑ Ⓧ Ⓨ ⊕ ⊖).
struct ButtonGlyph: View {
    let label: String
    private static let symbols: [String: String] = [
        "A": "a.circle.fill", "B": "b.circle.fill", "X": "x.circle.fill", "Y": "y.circle.fill",
        "+": "plus.circle.fill", "−": "minus.circle.fill", "-": "minus.circle.fill", "L": "l.circle.fill", "R": "r.circle.fill",
        "◀▶": "arrow.left.arrow.right.circle.fill", "▲▼": "arrow.up.arrow.down.circle.fill",
    ]
    var body: some View {
        if let s = Self.symbols[label] {
            Image(systemName: s).font(.system(size: 20)).symbolRenderingMode(.hierarchical).foregroundStyle(.primary)
        } else {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .frame(minWidth: 20, minHeight: 20).padding(.horizontal, 4)
                .background(Capsule().fill(.primary.opacity(0.18)))
        }
    }
}

// MARK: - Focus

/// The keyboard/controller focus indicator: a macOS-style accent ring hugging the shape, with a soft glow.
struct FocusRing: ViewModifier {
    var focused: Bool
    var radius: CGFloat = 10
    var lift = false
    func body(content: Content) -> some View {
        content
            .overlay(Theme.shape(radius + 5).strokeBorder(Theme.focus, lineWidth: focused ? 3 : 0).padding(-5))
            .scaleEffect(focused && lift ? 1.07 : 1)
            .shadow(color: .black.opacity(focused && lift ? 0.30 : 0), radius: 22, y: 14)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: focused)
    }
}

extension View {
    func focusRing(_ f: Bool, radius: CGFloat = 10, lift: Bool = false) -> some View { modifier(FocusRing(focused: f, radius: radius, lift: lift)) }
}

/// An icon in a coloured rounded square, like the icons in System Settings.
struct SettingsIcon: View {
    let systemImage: String
    var color: Color = Theme.focus
    var size: CGFloat = 28
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.shape(size * 0.24).fill(color.gradient))
    }
}

func loadImage(_ path: String?) -> NSImage? { path.flatMap { NSImage(contentsOfFile: $0) } }
