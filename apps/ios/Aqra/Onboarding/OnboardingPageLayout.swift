import SwiftUI

/// The onboarding pages' colors.
enum OnboardingPalette {
    static let surface = Color(light: 0xF7F4FB, dark: 0xF7F4FB)
    static let ink = Color(light: 0x241A33, dark: 0x241A33)
    static let inkSoft = Color(light: 0x7B7290, dark: 0x7B7290)
    static let brand = Color(light: 0x5B2D91, dark: 0x5B2D91)
    static let brandDeep = Color(light: 0x3E1D66, dark: 0x3E1D66)
    static let gold = Color(light: 0xE8B64C, dark: 0xE8B64C)
    static let butter = Color(light: 0xFFF1C7, dark: 0xFFF1C7)
    static let peach = Color(light: 0xFFE2CF, dark: 0xFFE2CF)
    static let rose = Color(light: 0xFCDCE7, dark: 0xFCDCE7)
    static let lavender = Color(light: 0xE9DEFA, dark: 0xE9DEFA)
    static let sky = Color(light: 0xDCEBFB, dark: 0xDCEBFB)
    static let mint = Color(light: 0xD8F2E3, dark: 0xD8F2E3)
    static let shadow = Color(light: 0x5B2D91, dark: 0x5B2D91)
}

/// Shared layout for onboarding pages: an animated stage, the page's copy, page dots and a button.
/// Portrait stacks them; landscape puts the copy beside the stage; iPad scales everything up.
struct OnboardingPageLayout<Stage: View, Copy: View>: View {
    var pageCount: Int
    var currentPage: Int
    var buttonTitle: LocalizedStringKey
    var onButton: () -> Void
    /// Shows the «لديّ حساب» link when set.
    var onHaveAccount: (() -> Void)?
    /// Fades the link, dots and button in after the stage's entrance.
    var actionsVisible: Bool
    /// Composed in a ~420×440pt box and scaled to fit.
    @ViewBuilder var stage: () -> Stage
    /// Receives a type scale: 1 on iPhone portrait, larger on iPad, smaller in iPhone landscape.
    @ViewBuilder var copy: (_ scale: CGFloat) -> Copy

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let landscape = size.width > size.height * 1.1
            // iPad-sized space in either orientation.
            let roomy = min(size.width, size.height) >= 600

            VStack(spacing: 0) {
                topBar(large: roomy)
                if landscape {
                    HStack(spacing: roomy ? 48 : 20) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            copy(roomy ? 1.5 : 0.82)
                            actions(compact: !roomy, large: roomy)
                            Spacer(minLength: 0)
                        }
                        .frame(width: min(roomy ? 540 : 400, size.width * 0.48))
                        fittedStage(maxScale: roomy ? 1.4 : 1)
                    }
                    .padding(.horizontal, roomy ? 40 : 12)
                } else {
                    fittedStage(maxScale: roomy ? 1.6 : 1)
                    copy(roomy ? 1.65 : 1)
                        .frame(maxWidth: roomy ? 760 : .infinity)
                        .padding(.horizontal, 18)
                    actions(compact: false, large: roomy)
                        .frame(maxWidth: roomy ? 520 : .infinity)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .fontDesign(.rounded)
        .background(OnboardingPalette.surface.ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }

    private func topBar(large: Bool) -> some View {
        HStack {
            Spacer()
            if let onHaveAccount {
                Button("I have an account", action: onHaveAccount)
                    .font(large ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(OnboardingPalette.brand)
            }
        }
        .frame(minHeight: 22)
        .padding(.horizontal, 24)
        // Clears the window controls iPadOS draws in the top corner of a windowed app.
        .padding(.top, large ? 34 : 6)
        .opacity(actionsVisible ? 1 : 0)
    }

    private func fittedStage(maxScale: CGFloat) -> some View {
        GeometryReader { geometry in
            stage()
                .scaleEffect(min(maxScale, geometry.size.height / 440, geometry.size.width / 420))
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func actions(compact: Bool, large: Bool) -> some View {
        VStack(spacing: compact ? 12 : 20) {
            PageDots(count: pageCount, current: currentPage)
            Button(buttonTitle, action: onButton)
                .buttonStyle(BrandButtonStyle(height: large ? 64 : compact ? 48 : 56, fontSize: large ? 21 : 18))
        }
        .padding(.horizontal, 24)
        .padding(.top, compact ? 14 : 26)
        .padding(.bottom, 8)
        .opacity(actionsVisible ? 1 : 0)
        .offset(y: actionsVisible ? 0 : 24)
    }
}

struct BrandButtonStyle: ButtonStyle {
    var height: CGFloat = 56
    var fontSize: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                LinearGradient(colors: [OnboardingPalette.brand, OnboardingPalette.brandDeep], startPoint: .top, endPoint: .bottom),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: OnboardingPalette.brand.opacity(0.35), radius: 14, y: 8)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
