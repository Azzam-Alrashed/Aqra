import SwiftUI
import Testing
@testable import Aqra

/// Renders the app icon (the arch logo) to PNG when `AQRA_ICON_OUT` names an output directory.
/// Run with `TEST_RUNNER_AQRA_ICON_OUT=<dir> xcodebuild test …`; skipped otherwise.
@MainActor
struct AppIconRenderTests {
    @Test func renderArchLogo() throws {
        guard let directory = ProcessInfo.processInfo.environment["AQRA_ICON_OUT"] else { return }
        let renderer = ImageRenderer(content: AqraArchLogo(markScale: 1.15))
        renderer.scale = 1
        let data = try #require(renderer.uiImage?.pngData())
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("arch-logo.png"))
    }
}
