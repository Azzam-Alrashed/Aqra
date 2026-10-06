import SwiftUI
import Testing
@testable import Aqra

/// Renders the welcome screen at iPhone and iPad sizes in both orientations
/// when `AQRA_SNAPSHOT_OUT` names an output directory; skipped otherwise.
@MainActor
struct WelcomeSnapshotTests {
    private static let sizes: [(name: String, size: CGSize)] = [
        ("iphone-portrait", CGSize(width: 402, height: 874)),
        ("iphone-landscape", CGSize(width: 874, height: 402)),
        ("ipad-portrait", CGSize(width: 1032, height: 1376)),
        ("ipad-landscape", CGSize(width: 1376, height: 1032)),
    ]

    @Test func renderWelcomeLayouts() throws {
        guard let directory = ProcessInfo.processInfo.environment["AQRA_SNAPSHOT_OUT"] else { return }
        AqraFont.registerBundledFonts()
        for (name, size) in Self.sizes {
            let view = AqraWelcomeView(startsComplete: true, onBegin: {})
                .frame(width: size.width, height: size.height)
                .environment(\.locale, Locale(identifier: "ar"))
                .environment(\.layoutDirection, .rightToLeft)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let data = try #require(renderer.uiImage?.pngData())
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("welcome-\(name).png"))

            let manazil = ManazilPageView(pageCount: 4, currentPage: 1, isActive: false, startsComplete: true, onContinue: {})
                .frame(width: size.width, height: size.height)
                .environment(\.locale, Locale(identifier: "ar"))
                .environment(\.layoutDirection, .rightToLeft)
            let manazilRenderer = ImageRenderer(content: manazil)
            manazilRenderer.scale = 2
            let manazilData = try #require(manazilRenderer.uiImage?.pngData())
            try manazilData.write(to: URL(fileURLWithPath: directory).appendingPathComponent("manazil-\(name).png"))

            let features = FeaturesPageView(pageCount: 4, currentPage: 2, isActive: false, startsComplete: true, onContinue: {})
                .frame(width: size.width, height: size.height)
                .environment(\.locale, Locale(identifier: "ar"))
                .environment(\.layoutDirection, .rightToLeft)
            let featuresRenderer = ImageRenderer(content: features)
            featuresRenderer.scale = 2
            let featuresData = try #require(featuresRenderer.uiImage?.pngData())
            try featuresData.write(to: URL(fileURLWithPath: directory).appendingPathComponent("features-\(name).png"))

            let start = StartPageView(pageCount: 4, currentPage: 3, isActive: false, startsComplete: true, onBegin: {})
                .frame(width: size.width, height: size.height)
                .environment(\.locale, Locale(identifier: "ar"))
                .environment(\.layoutDirection, .rightToLeft)
            let startRenderer = ImageRenderer(content: start)
            startRenderer.scale = 2
            let startData = try #require(startRenderer.uiImage?.pngData())
            try startData.write(to: URL(fileURLWithPath: directory).appendingPathComponent("start-\(name).png"))
        }
    }
}
