import SwiftUI

/// A thin progress capsule for the deck.
///
/// The bar is deliberately silent to VoiceOver: the same progress is announced as a
/// spoken "n of m" elsewhere, and two announcements of the same fact is noise.
struct SweepProgressBar: View {

    private let progress: Double

    /// The width actually drawn. Kept separate from `progress` so the change can be
    /// animated explicitly with `withAnimation`, rather than by an implicit modifier.
    @State private var displayed: Double = 0

    init(progress: Double) {
        self.progress = progress
    }

    /// A non-finite or out-of-range value would hand `frame(width:)` a NaN and draw
    /// nothing at all, so clamping happens here rather than at every call site.
    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        if value < 0 { return 0 }
        if value > 1 { return 1 }
        return value
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Theme.hairline)

                Capsule(style: .continuous)
                    .fill(Theme.yellow)
                    .frame(width: max(0, proxy.size.width * CGFloat(displayed)))
            }
        }
        .frame(height: 6)
        .onAppear {
            displayed = Self.clamp(progress)
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeOut(duration: 0.25)) {
                displayed = Self.clamp(newValue)
            }
        }
        .accessibilityHidden(true)
    }
}
