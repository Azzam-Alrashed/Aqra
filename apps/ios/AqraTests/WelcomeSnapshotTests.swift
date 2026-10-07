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

    /// The منازل stairs of the «ماذا تحفظ؟» screen: none climbed, a quarter, and all ten with the star lit.
    @Test func renderManazilStairs() throws {
        guard let directory = ProcessInfo.processInfo.environment["AQRA_SNAPSHOT_OUT"] else { return }
        for climb in [0.0, 2.5, 10] {
            let view = ManazilStairs(climb: climb)
                .frame(width: 360, height: 130)
                .padding(20)
                .background(OnboardingPalette.surface)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let data = try #require(renderer.uiImage?.pngData())
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("stairs-\(climb).png"))
        }
    }

    /// Revising al-Baqarah 1–5 on page 2: two ayat revealed, the second marked as stumbled, the rest veiled;
    /// and the daily-amount step.
    @Test func renderRevision() throws {
        guard let directory = ProcessInfo.processInfo.environment["AQRA_SNAPSHOT_OUT"] else { return }
        let store = try MushafStore()
        let memorization = MemorizationStore(fileURL: nil)
        memorization.mark(7...11, memorized: true)
        let session = RevisionSession(page: 2, ayahs: Array(7...11))
        session.revealNext()
        session.revealNext()
        session.tap(8)
        let renders: [(String, AnyView, CGSize)] = [
            ("revision-iphone-2", AnyView(MushafPageView(page: store.page(2), store: store).environment(memorization).environment(session)), CGSize(width: 402, height: 874)),
            ("revision-iphone-2-dark", AnyView(MushafPageView(page: store.page(2), store: store).environment(memorization).environment(session).environment(\.colorScheme, .dark)), CGSize(width: 402, height: 874)),
            ("daily-amount-iphone", AnyView(DailyAmountView(memorizedPages: 23, initial: 2) { _ in }.environment(\.locale, Locale(identifier: "ar")).environment(\.layoutDirection, .rightToLeft)), CGSize(width: 402, height: 874)),
        ]
        for (name, view, size) in renders {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
            renderer.scale = 2
            let data = try #require(renderer.uiImage?.pngData())
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }

    /// Renders Mushaf pages on iPhone (with and without tajweed and topic colors, light and dark), and full-screen iPad landscape spreads.
    @Test func renderMushafLayouts() throws {
        guard let directory = ProcessInfo.processInfo.environment["AQRA_SNAPSHOT_OUT"] else { return }
        let store = try MushafStore()
        let renders: [(String, AnyView, CGSize)] = [
            ("mushaf-iphone", AnyView(MushafPageView(page: store.page(385), store: store)), CGSize(width: 402, height: 874)),
            ("mushaf-ipad-spread", AnyView(MushafSpreadView(spread: 193, store: store)), CGSize(width: 1376, height: 1032)),
            ("mushaf-iphone-dark", AnyView(MushafPageView(page: store.page(385), store: store).environment(\.colorScheme, .dark)), CGSize(width: 402, height: 874)),
            ("mushaf-iphone-45", AnyView(MushafPageView(page: store.page(45), store: store)), CGSize(width: 402, height: 874)),
            ("mushaf-iphone-475", AnyView(MushafPageView(page: store.page(475), store: store)), CGSize(width: 402, height: 874)),
            ("mushaf-iphone-2", AnyView(MushafPageView(page: store.page(2), store: store)), CGSize(width: 402, height: 874)),
            ("mushaf-iphone-91", AnyView(MushafPageView(page: store.page(91), store: store)), CGSize(width: 402, height: 874)),
            ("mushaf-ipad-spread-533", AnyView(MushafSpreadView(spread: 267, store: store)), CGSize(width: 1376, height: 1032)),
            ("mushaf-ipad-spread-591", AnyView(MushafSpreadView(spread: 296, store: store)), CGSize(width: 1376, height: 1032)),
            ("mushaf-iphone-no-topics", AnyView(MushafPageView(page: store.page(385), store: store).environment(\.mushafTopics, false)), CGSize(width: 402, height: 874)),
            ("mushaf-iphone-plain", AnyView(MushafPageView(page: store.page(385), store: store).environment(\.mushafTajweed, false)), CGSize(width: 402, height: 874)),
            ("mushaf-iphone-plain-dark", AnyView(MushafPageView(page: store.page(385), store: store).environment(\.mushafTajweed, false).environment(\.colorScheme, .dark)), CGSize(width: 402, height: 874)),
        ]
        // Memorized ayat take their topic color, faint while newly memorized: al-Baqarah 1–3, and al-A'la 1–10.
        let memorization = MemorizationStore(fileURL: nil)
        memorization.mark(7...9, memorized: true)
        if let alAla = store.surahAyahs[87] { memorization.mark(alAla.lowerBound..<(alAla.lowerBound + 10), memorized: true) }
        let memorized: [(String, AnyView, CGSize)] = [
            ("memorized-iphone-2", AnyView(MushafPageView(page: store.page(2), store: store).environment(memorization)), CGSize(width: 402, height: 874)),
            ("memorized-iphone-2-dark", AnyView(MushafPageView(page: store.page(2), store: store).environment(memorization).environment(\.colorScheme, .dark)), CGSize(width: 402, height: 874)),
            ("memorized-ipad-spread-591", AnyView(MushafSpreadView(spread: 296, store: store).environment(memorization)), CGSize(width: 1376, height: 1032)),
        ]
        for (name, view, size) in renders + memorized {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
            renderer.scale = 2
            let data = try #require(renderer.uiImage?.pngData())
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }
}
