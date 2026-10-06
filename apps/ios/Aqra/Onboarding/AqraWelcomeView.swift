import SwiftUI
import UIKit

/// Welcome screen: the Aqra logo coming alive at the center, layered cards bursting
/// around it, and the hadith «اقرَأ وارقَ» beneath.
struct AqraWelcomeView: View {
    var pageCount = 4
    var onBegin: () -> Void
    var onHaveAccount: () -> Void
    /// Shows the finished scene without the entrance (snapshots and previews).
    var startsComplete = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var archReveal: CGFloat = 0
    @State private var bookReveal: CGFloat = 0
    @State private var doorReveal: CGFloat = 0
    @State private var starReveal: CGFloat = 0
    @State private var cardsOut = 0
    @State private var streakDays = 0
    @State private var manzilProgress: CGFloat = 0
    @State private var headlineIn = false
    @State private var emphasisLit = false
    @State private var actionsIn = false

    init(pageCount: Int = 4, startsComplete: Bool = false, onBegin: @escaping () -> Void, onHaveAccount: @escaping () -> Void) {
        self.pageCount = pageCount
        self.startsComplete = startsComplete
        self.onBegin = onBegin
        self.onHaveAccount = onHaveAccount
        if startsComplete {
            _archReveal = State(initialValue: 1)
            _bookReveal = State(initialValue: 1)
            _doorReveal = State(initialValue: 1)
            _starReveal = State(initialValue: 1)
            _cardsOut = State(initialValue: 5)
            _streakDays = State(initialValue: 5)
            _manzilProgress = State(initialValue: 0.68)
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
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                AqraArchLogo(
                    withBackground: false,
                    archReveal: archReveal, bookReveal: bookReveal, doorReveal: doorReveal, starReveal: starReveal,
                    time: time
                )
                .scaleEffect(Self.logoScale)
                .frame(width: 1024 * Self.logoScale, height: 1024 * Self.logoScale)

                floating(0, depth: .back, at: CGPoint(x: -122, y: -172), tilt: -8, time: time) {
                    Chip(icon: "⭐️", tint: Palette.butter, text: "+٥٠ نقطة")
                }
                floating(1, depth: .front, at: CGPoint(x: 104, y: -150), tilt: 4, time: time) {
                    StreakCard(days: streakDays)
                }
                floating(2, depth: .front, at: CGPoint(x: -122, y: 52), tilt: -3, time: time) {
                    ManzilCard(progress: manzilProgress)
                }
                floating(3, depth: .mid, at: CGPoint(x: 118, y: 120), tilt: 5, time: time) {
                    SessionCard()
                }
                floating(4, depth: .back, at: CGPoint(x: -96, y: 182), tilt: 3, time: time) {
                    Chip(icon: "✅", tint: Palette.mint, text: "أتممت الجزء ٣٠")
                }
            }
            // Positions follow the logo's fixed orientation, so cards never cover its steps.
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    /// The 1024-point logo canvas scaled onto the ~420×440pt stage.
    private static let logoScale: CGFloat = 0.3

    private enum Depth {
        case back, mid, front

        var scale: CGFloat { switch self { case .back: 0.86; case .mid: 0.94; case .front: 1 } }
        var drift: Double { switch self { case .back: 3; case .mid: 5; case .front: 7 } }
        var layer: Double { switch self { case .back: 0; case .mid: 1; case .front: 2 } }
    }

    private func floating<Content: View>(
        _ index: Int, depth: Depth, at target: CGPoint, tilt: Double, time: TimeInterval,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let out = index < cardsOut
        let drift = out ? sin(time * (0.8 + Double(index) * 0.17) + Double(index) * 1.3) * depth.drift : 0
        return content()
            .environment(\.layoutDirection, layoutDirection)
            .scaleEffect(out ? depth.scale : 0.3)
            .rotationEffect(.degrees(out ? tilt : 0))
            .opacity(out ? 1 : 0)
            .offset(x: out ? target.x : 0, y: (out ? target.y : 0) + drift)
            .zIndex(depth.layer)
            .animation(.spring(response: 0.62, dampingFraction: 0.66), value: out)
    }

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
                cardsOut = 5; streakDays = 5; manzilProgress = 0.68; headlineIn = true; emphasisLit = true; actionsIn = true
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
            try await pause(220)
            for card in 1...5 {
                cardsOut = card
                try await pause(85)
            }
            withAnimation(.easeOut(duration: 0.9)) { manzilProgress = 0.68 }
            for day in 1...5 {
                withAnimation(.snappy) { streakDays = day }
                try await pause(70)
            }
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

// MARK: - Cards

/// Every icon sits in the same tinted rounded square.
private struct IconTile: View {
    var icon: String
    var tint: Color
    var size: CGFloat = 34

    var body: some View {
        Text(icon)
            .font(.system(size: size * 0.52))
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Palette.shadow.opacity(0.10), radius: 18, y: 10)
            .shadow(color: Palette.shadow.opacity(0.06), radius: 2, y: 1)
    }
}

private struct StreakCard: View {
    var days: Int

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    IconTile(icon: "🔥", tint: Palette.peach)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "\(days.formatted(.number.locale(Locale(identifier: "ar@numbers=arab")))) أيام")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText())
                        Text(verbatim: "سلسلة المراجعة")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                HStack(spacing: 5) {
                    ForEach(0..<7, id: \.self) { day in
                        Circle()
                            .fill(day < days ? Palette.brand : Palette.lavender)
                            .frame(width: 16, height: 16)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .black))
                                    .foregroundStyle(.white)
                                    .opacity(day < days ? 1 : 0)
                            }
                    }
                }
            }
        }
    }
}

private struct ManzilCard: View {
    var progress: CGFloat

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    IconTile(icon: "🪜", tint: Palette.lavender)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "المنزلة ١٢")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(Palette.ink)
                        Text(verbatim: "٣٤ آية إلى التالية")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                Capsule()
                    .fill(Palette.lavender)
                    .frame(width: 132, height: 7)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.brand, Color(light: 0xB36AD8, dark: 0xB36AD8)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 132 * progress, height: 7)
                    }
            }
        }
    }
}

private struct SessionCard: View {
    var body: some View {
        Card {
            HStack(spacing: 10) {
                IconTile(icon: "🎙️", tint: Palette.sky)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "تسميع مع شيخ")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    Text(verbatim: "غدًا · ٨:٠٠ م")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            .padding(.trailing, 4)
        }
    }
}

private struct Chip: View {
    var icon: String
    var tint: Color
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            IconTile(icon: icon, tint: tint, size: 26)
            Text(verbatim: text)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.ink)
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(.white, in: Capsule())
        .shadow(color: Palette.shadow.opacity(0.10), radius: 12, y: 6)
    }
}

#Preview {
    AqraWelcomeView(onBegin: {}, onHaveAccount: {})
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}
