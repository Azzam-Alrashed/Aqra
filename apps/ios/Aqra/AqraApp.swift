import SwiftUI

@main
struct AqraApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    init() {
        AqraFont.registerBundledFonts()
        AccountStore.configure()
    }

    var body: some Scene {
        WindowGroup {
            if hasSeenOnboarding {
                MushafRootView()
            } else {
                OnboardingView { withAnimation { hasSeenOnboarding = true } }
            }
        }
    }
}
