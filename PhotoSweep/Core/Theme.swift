import SwiftUI

/// The app's entire visual vocabulary.
///
/// Colours are declared as explicit sRGB components. There is deliberately no
/// `Color(hex:)` helper anywhere in this project: hand-rolled bit manipulation is
/// exactly the kind of plausible-looking code that silently produces the wrong
/// colour and cannot be spotted by reading it.
enum Theme {

    // MARK: - Palette

    /// #396CB5
    static let lightBlue = Color(.sRGB, red: 0.2235, green: 0.4235, blue: 0.7098, opacity: 1)
    /// #24438D
    static let mainBlue = Color(.sRGB, red: 0.1412, green: 0.2627, blue: 0.5529, opacity: 1)
    /// #29304A
    static let darkBlue = Color(.sRGB, red: 0.1608, green: 0.1882, blue: 0.2902, opacity: 1)
    /// #151825
    static let deepBlue = Color(.sRGB, red: 0.0824, green: 0.0941, blue: 0.1451, opacity: 1)
    /// #F9D035
    static let yellow = Color(.sRGB, red: 0.9765, green: 0.8157, blue: 0.2078, opacity: 1)
    /// #009E73 — keep, save, confirm.
    static let green = Color(.sRGB, red: 0.0000, green: 0.6196, blue: 0.4510, opacity: 1)
    /// #FF0000 — bin, delete, cancel.
    static let red = Color(.sRGB, red: 1.0000, green: 0.0000, blue: 0.0000, opacity: 1)

    /// A slightly desaturated red for large fills, where #FF0000 vibrates against dark blue.
    static let redSoft = Color(.sRGB, red: 0.8824, green: 0.1137, blue: 0.1686, opacity: 1)

    // MARK: - Semantic

    static let screenBackground = deepBlue
    static let surface = darkBlue
    static let surfaceRaised = Color(.sRGB, red: 0.2000, green: 0.2314, blue: 0.3412, opacity: 1)
    static let cardBackground = Color(.sRGB, red: 0.1176, green: 0.1373, blue: 0.2118, opacity: 1)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary = Color.white.opacity(0.45)

    static let hairline = Color.white.opacity(0.10)

    static let keep = green
    static let bin = red
    static let accent = yellow

    // MARK: - Gradients

    static let backgroundGradient = LinearGradient(
        colors: [mainBlue.opacity(0.55), deepBlue, deepBlue],
        startPoint: .top,
        endPoint: .bottom
    )

    static let keepWash = LinearGradient(
        colors: [green.opacity(0.45), green.opacity(0.0)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let binWash = LinearGradient(
        colors: [redSoft.opacity(0.0), redSoft.opacity(0.45)],
        startPoint: .leading,
        endPoint: .trailing
    )

    // MARK: - Metrics

    static let cardCornerRadius: CGFloat = 26
    static let controlCornerRadius: CGFloat = 16
    static let tileCornerRadius: CGFloat = 12

    static let screenPadding: CGFloat = 20
    static let stackSpacing: CGFloat = 16

    /// Minimum tappable edge, per Apple's Human Interface Guidelines.
    static let minimumTapTarget: CGFloat = 44
}

// MARK: - Reusable surfaces

/// The standard full-screen background. Applied once per screen, never nested.
struct ScreenBackground: View {
    var body: some View {
        Theme.backgroundGradient
            .ignoresSafeArea()
    }
}

/// A raised panel used for grouped content (settings rows, summary blocks).
struct PanelBackground: ViewModifier {
    var cornerRadius: CGFloat = Theme.controlCornerRadius

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func panel(cornerRadius: CGFloat = Theme.controlCornerRadius) -> some View {
        modifier(PanelBackground(cornerRadius: cornerRadius))
    }
}

/// The app's primary button shape. `role` drives the colour so that no call site
/// ever hard-codes green or red.
struct PrimaryButtonStyle: ButtonStyle {
    enum Role {
        case positive
        case destructive
        case neutral
        case quiet
    }

    var role: Role = .positive
    var fullWidth: Bool = true

    private var fill: Color {
        switch role {
        case .positive: return Theme.green
        case .destructive: return Theme.red
        case .neutral: return Theme.lightBlue
        case .quiet: return Theme.surfaceRaised
        }
    }

    private var foreground: Color {
        switch role {
        case .positive, .destructive, .neutral: return .white
        case .quiet: return Theme.textPrimary
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 52)
            .padding(.horizontal, fullWidth ? 0 : 22)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.78 : 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
