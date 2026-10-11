import SwiftUI

@main
struct AqraApp: App {
    @UIApplicationDelegateAdaptor(AqraAppDelegate.self) private var delegate
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var launch = LaunchState()

    init() {
        AqraFont.registerBundledFonts()
        AccountStore.configure()
        #if DEBUG
        AccountStore.resetForUITests()
        #endif
        Diagnostics.shared.start()
        RecitationTranscriber.unloadsWhenIdle()
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

/// The app delegate, for the one thing SwiftUI has no hook for: the speech model's background download, which the
/// system may relaunch the app to finish (see `RecitationModel`).
final class AqraAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == RecitationModel.sessionIdentifier else { return }
        RecitationModel.backgroundEventsHandled = completionHandler
        // Making the model's session again lets the system hand it the events.
        _ = RecitationModel.shared
    }
}
