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

    /// The logo mark alone, on a transparent background, for the website and other artwork.
    @Test func renderArchLogoMark() throws {
        guard let directory = ProcessInfo.processInfo.environment["AQRA_ICON_OUT"] else { return }
        let renderer = ImageRenderer(content: AqraArchLogo(withBackground: false))
        renderer.scale = 1
        renderer.isOpaque = false
        let data = try #require(renderer.uiImage?.pngData())
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("arch-logo-mark.png"))
    }

    /// The splash's logo layers (`LaunchLogoBody`, `LaunchLogoHaze`, `LaunchLogoStars` in the asset catalog), at @2x and @3x.
    @Test func renderLaunchLogo() throws {
        guard let directory = ProcessInfo.processInfo.environment["AQRA_ICON_OUT"] else { return }
        for layer in LaunchLogo.Layer.allCases {
            for scale in [2, 3] {
                let renderer = ImageRenderer(content: LaunchLogo(layer: layer))
                renderer.scale = CGFloat(scale)
                renderer.isOpaque = false
                let data = try #require(renderer.uiImage?.pngData())
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(layer.imageName)@\(scale)x.png"))
            }
        }
    }
}
