import SwiftUI

/// The four-page explanation shown once, before the rehearsal.
///
/// There is deliberately no Skip button. Right-to-bin is the opposite of what a decade of
/// dating apps has trained people's thumbs to expect, and the person who skips the
/// explanation is precisely the person who bins a holiday photo on their very first card.
/// Four taps is a cheap price for that not happening.
@MainActor
struct OnboardingView: View {

    let model: AppModel
    var onFinished: () -> Void

    /// Index of the visible page. Plain `Int` tags, because a page carousel is the one
    /// place where an integer really is the identity.
    @State private var selection: Int = 0

    private static let lastPageIndex = 3

    private var isLastPage: Bool { selection >= Self.lastPageIndex }

    var body: some View {
        ZStack {
            ScreenBackground()

            VStack(spacing: 0) {
                TabView(selection: $selection) {

                    OnboardingPageContent(
                        systemImage: "rectangle.stack",
                        tint: Theme.lightBlue,
                        title: Strings.onboardingTitle1,
                        message: Strings.onboardingBody1
                    )
                    .tag(0)

                    OnboardingPageContent(
                        systemImage: nil,
                        tint: Theme.yellow,
                        title: Strings.onboardingTitle2,
                        message: Strings.onboardingBody2,
                        showsDirectionDiagram: true
                    )
                    .tag(1)

                    OnboardingPageContent(
                        systemImage: "arrow.uturn.backward",
                        tint: Theme.green,
                        title: Strings.onboardingTitle3,
                        message: Strings.onboardingBody3
                    )
                    .tag(2)

                    OnboardingPageContent(
                        systemImage: "trash",
                        tint: Theme.yellow,
                        title: Strings.onboardingTitle4,
                        message: Strings.onboardingBody4
                    )
                    .tag(3)
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button(isLastPage ? Strings.onboardingBegin : Strings.onboardingContinue) {
                    if isLastPage {
                        onFinished()
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selection += 1
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle(role: isLastPage ? .positive : .neutral))
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, Theme.stackSpacing)
                .padding(.bottom, Theme.screenPadding)
            }
        }
    }
}

// MARK: - One page

/// A single onboarding page.
///
/// The body copy is scrollable rather than scaled down, so a long paragraph at a large
/// Dynamic Type size is still readable instead of being squeezed into illegibility.
private struct OnboardingPageContent: View {

    let systemImage: String?
    let tint: Color
    let title: String
    let message: String
    var showsDirectionDiagram: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {

                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }

                if showsDirectionDiagram {
                    SwipeDirectionDiagram()
                }

                Text(title)
                    .font(.title.bold())
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 44)
            // Clears the paging dots, which float over the bottom of the TabView.
            .padding(.bottom, 64)
        }
    }
}

// MARK: - The direction picture

/// Page two shows the directions instead of only stating them.
///
/// This is the one genuinely counter-intuitive thing about the app, and a sentence read
/// once is a much weaker teacher than a picture of a card with a green arrow on its left
/// and a red arrow on its right.
private struct SwipeDirectionDiagram: View {

    var body: some View {
        HStack(spacing: 12) {
            marker(systemImage: "arrow.left", text: Strings.keep, tint: Theme.keep)
            cardMock
            marker(systemImage: "arrow.right", text: Strings.bin, tint: Theme.bin)
        }
        .accessibilityElement(children: .combine)
    }

    private var cardMock: some View {
        RoundedRectangle(cornerRadius: Theme.tileCornerRadius, style: .continuous)
            .fill(Theme.surfaceRaised)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.tileCornerRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            }
            .frame(width: 104, height: 140)
            .accessibilityHidden(true)
    }

    private func marker(systemImage: String, text: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
            Text(text)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
    }
}
