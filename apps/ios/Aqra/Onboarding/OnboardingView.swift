import SwiftUI

/// First-launch onboarding: swipeable pages (3–4 in total when complete).
struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0
    private let pageCount = 2

    var body: some View {
        ZStack {
            // The pager doesn't paint the safe areas itself; the surface behind it does.
            OnboardingPalette.surface.ignoresSafeArea()
            TabView(selection: $page) {
                // TODO: route "I have an account" to sign-in once it exists.
                AqraWelcomeView(pageCount: pageCount, onBegin: { withAnimation { page = 1 } }, onHaveAccount: onFinish)
                    .tag(0)
                ManazilPageView(pageCount: pageCount, currentPage: 1, isActive: page == 1, onContinue: onFinish)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Extend the pager under the home indicator; each page still lays out inside the safe area.
            .ignoresSafeArea(edges: .bottom)
        }
    }
}
