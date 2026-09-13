import SwiftUI

/// Shown over a card whose full-size image is still coming down from iCloud.
///
/// The ring is driven by the real `PHImageRequestOptions` progress handler rather than a
/// spinner, because an iCloud original on a poor connection can take long enough that an
/// indeterminate spinner looks like a hang.
struct CloudDownloadBadge: View {

    private let progress: Double

    init(progress: Double) {
        self.progress = progress
    }

    private var clampedProgress: Double {
        guard progress.isFinite else { return 0 }
        if progress < 0 { return 0 }
        if progress > 1 { return 1 }
        return progress
    }

    private var ringDiameter: CGFloat { 38 }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Theme.hairline, lineWidth: 4)

                Circle()
                    .trim(from: 0, to: CGFloat(clampedProgress))
                    .stroke(
                        Theme.yellow,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    // Trimming starts at three o'clock, which reads as "stuck" for the
                    // first quarter of the download.
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: ringDiameter, height: ringDiameter)

            Text(Strings.iCloudDownloading)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.deepBlue.opacity(0.82))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.iCloudDownloading)
    }
}
