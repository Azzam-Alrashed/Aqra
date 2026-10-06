import SwiftUI

@main
struct AqraApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    init() {
        AqraFont.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            if hasSeenOnboarding {
                ContentView()
            } else {
                OnboardingView { withAnimation { hasSeenOnboarding = true } }
            }
        }
    }
}
