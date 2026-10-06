import SwiftUI
import UIKit

/// Onboarding page 1: the Aqra logo coming alive, and the hadith «اقرَأ وارقَ» beneath.
struct AqraWelcomeView: View {
    var pageCount = 3
    var onBegin: () -> Void
    var onHaveAccount: () -> Void
    /// Shows the finished scene without the entrance (snapshots and previews).
    var startsComplete = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    @State private var archReveal: CGFloat = 0
    @State private var bookReveal: CGFloat = 0
    @State private var doorReveal: CGFloat = 0
    @State private var starReveal: CGFloat = 0
    @State private var headlineIn = false
    @State private var emphasisLit = false
    @State private var actionsIn = false

    init(pageCount: Int = 3, startsComplete: Bool = false, onBegin: @escaping () -> Void, onHaveAccount: @escaping () -> Void) {
        self.pageCount = pageCount
        self.startsComplete = startsComplete
        self.onBegin = onBegin
        self.onHaveAccount = onHaveAccount
        if startsComplete {
            _archReveal = State(initialValue: 1)
            _bookReveal = State(initialValue: 1)
            _doorReveal = State(initialValue: 1)
            _starReveal = State(initialValue: 1)
            _headlineIn = State(initialValue: true)
            _emphasisLit = State(initialValue: true)
            _actionsIn = State(initialValue: true)
        }
    }

    var body: some View {
        OnboardingPageLayout(
            pageCount: pageCount, currentPage: 0, buttonTitle: "Begin", onButton: onBegin,
            onHaveAccount: onHaveAccount, actionsVisible: actionsIn,
            stage: { stage },
            copy: { scale in hadith(scale: scale) }
        )
        .task { await playEntrance() }
    }

    // MARK: - Stage

    private var stage: some View {
        TimelineView(.animation) { timeline in
            AqraArchLogo(
                withBackground: false,
                archReveal: archReveal, bookReveal: bookReveal, doorReveal: doorReveal, starReveal: starReveal,
                time: timeline.date.timeIntervalSinceReferenceDate
            )
            .scaleEffect(Self.logoScale)
            .frame(width: 1024 * Self.logoScale, height: 1024 * Self.logoScale)
        }
    }

    /// The 1024-point logo canvas scaled onto the ~420×440pt stage.
    private static let logoScale: CGFloat = 0.42

    // MARK: - Hadith

    /// The hadith, quoted verbatim, with «اقرَأ وارقَ» lighting up in the brand color.
    private func hadith(scale: CGFloat) -> some View {
        VStack(spacing: 8 * scale) {
            VStack(spacing: 2) {
                Text(verbatim: SacredText.reciteAndAscendNarrator)
                    .font(AqraFont.hadith(size: 16 * scale))
                    .foregroundStyle(Palette.inkSoft)
                Text(verbatim: "قال رسول الله ﷺ:")
                    .font(AqraFont.hadith(size: 19 * scale, bold: true))
                    .foregroundStyle(Palette.ink)
            }
            .fontDesign(nil)
            .environment(\.layoutDirection, .rightToLeft)

            ZStack {
                hadithText(emphasis: Palette.ink, scale: scale)
                hadithText(emphasis: Palette.brand, scale: scale)
                    .opacity(emphasisLit ? 1 : 0)
            }
            // The rounded design set on the screen must not replace Amiri.
            .fontDesign(nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(SacredText.reciteAndAscendNarrator)، قال رسول الله ﷺ: \(SacredText.reciteAndAscend)"))

            Text("Reported by Ahmad")
                .font(.system(size: max(12, 13 * scale), weight: .semibold))
                .foregroundStyle(Palette.inkSoft)

            if locale.language.languageCode != .arabic {
                Text(verbatim: SacredText.reciteAndAscendTranslation)
                    .font(.system(size: max(12, 13 * scale), weight: .medium, design: .serif))
                    .foregroundStyle(Palette.ink.opacity(0.8))
                    .padding(.top, 2)
                Text("Translation: Jami' at-Tirmidhi 2914, Darussalam")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .multilineTextAlignment(.center)
        .opacity(headlineIn ? 1 : 0)
        .offset(y: headlineIn ? 0 : 14)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: headlineIn)
    }

    private func hadithText(emphasis: Color, scale: CGFloat) -> some View {
        let text = SacredText.reciteAndAscend
        let phrase = SacredText.reciteAndAscendEmphasis
        let range = text.range(of: phrase)!
        return (
            Text(verbatim: String(text[..<range.lowerBound]))
            + Text(verbatim: phrase)
                .font(AqraFont.hadith(size: 25 * scale, bold: true))
                .foregroundStyle(emphasis)
            + Text(verbatim: String(text[range.upperBound...]))
        )
        .font(AqraFont.hadith(size: 22 * scale))
        .foregroundStyle(Palette.ink)
        .lineSpacing(4 * scale)
        .environment(\.layoutDirection, .rightToLeft)
    }

    // MARK: - Choreography

    private func playEntrance() async {
        guard !startsComplete else { return }
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.4)) {
                archReveal = 1; bookReveal = 1; doorReveal = 1; starReveal = 1
                headlineIn = true; emphasisLit = true; actionsIn = true
            }
            return
        }
        let soft = UIImpactFeedbackGenerator(style: .soft)
        let light = UIImpactFeedbackGenerator(style: .light)
        soft.prepare(); light.prepare()
        do {
            try await pause(200)
            withAnimation(.spring(response: 0.8, dampingFraction: 0.78)) { archReveal = 1 }
            soft.impactOccurred(intensity: 0.5)
            try await pause(320)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { bookReveal = 1 }
            soft.impactOccurred(intensity: 0.5)
            try await pause(380)
            withAnimation(.easeInOut(duration: 0.7)) { doorReveal = 1 }
            try await pause(420)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.5)) { starReveal = 1 }
            light.impactOccurred(intensity: 0.8)
            try await pause(300)
            headlineIn = true
            try await pause(450)
            withAnimation(.easeInOut(duration: 0.45)) { emphasisLit = true }
            light.impactOccurred(intensity: 0.5)
            try await pause(300)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { actionsIn = true }
        } catch {}
    }

    private func pause(_ milliseconds: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}

private typealias Palette = OnboardingPalette

#Preview {
    AqraWelcomeView(onBegin: {}, onHaveAccount: {})
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}
