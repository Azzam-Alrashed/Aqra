import SwiftUI

@main
struct AqraApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var launch = LaunchState()

    init() {
        AqraFont.registerBundledFonts()
        AccountStore.configure()
        #if DEBUG
        AccountStore.resetForUITests()
        #endif
        Diagnostics.shared.start()
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
            // The app's own screens are light (docs/SRS.md A-23), chrome included: the status bar, tab bar, alerts,
            // menus and pickers. The Mushaf and the revision, opened over them, prefer the system's scheme instead.
            .preferredColorScheme(.light)
            .readsSystemColorScheme()
            // Text follows the reader's size up to Accessibility 2; past it, the composed screens would come apart.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }
}
