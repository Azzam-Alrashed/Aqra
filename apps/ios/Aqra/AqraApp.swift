import SwiftUI

@main
struct AqraApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var launch = LaunchState()

    init() {
        AqraFont.registerBundledFonts()
        AccountStore.configure()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasSeenOnboarding {
                    MushafRootView()
                } else if launch.showsScreen {
                    OnboardingView { withAnimation { hasSeenOnboarding = true } }
                }
                if !launch.isFinished {
                    LaunchSplash(launch: launch, isReady: !hasSeenOnboarding || launch.isReady, playsLogo: hasSeenOnboarding)
                }
            }
            .environment(launch)
            .readsSystemColorScheme()
            // Text follows the reader's size up to Accessibility 2; past it, the composed screens would come apart.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }
}
