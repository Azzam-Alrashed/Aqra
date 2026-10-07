import SwiftUI
import UIKit

/// Onboarding page 3: what Aqra offers, as cards that burst out of a soft glow and keep floating.
struct FeaturesPageView: View {
    var pageCount: Int
    var currentPage: Int
    /// The entrance plays the first time the page becomes the visible one.
    var isActive: Bool
    var onContinue: () -> Void
    /// Shows the finished scene without the entrance (snapshots and previews).
    var startsComplete = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var glowIn = false
    @State private var cardsOut = 0
    @State private var streakDays = 0
    @State private var manzilProgress: CGFloat = 0
    @State private var copyIn = false
    @State private var actionsIn = false
    @State private var played = false

    init(pageCount: Int, currentPage: Int, isActive: Bool, startsComplete: Bool = false, onContinue: @escaping () -> Void) {
        self.pageCount = pageCount
        self.currentPage = currentPage
        self.isActive = isActive
        self.startsComplete = startsComplete
        self.onContinue = onContinue
        if startsComplete {
            _glowIn = State(initialValue: true)
            _cardsOut = State(initialValue: 5)
            _streakDays = State(initialValue: 5)
            _manzilProgress = State(initialValue: 0.68)
            _copyIn = State(initialValue: true)
            _actionsIn = State(initialValue: true)
            _played = State(initialValue: true)
        }
    }

    var body: some View {
        OnboardingPageLayout(
            pageCount: pageCount, currentPage: currentPage, actionsVisible: actionsIn,
            stage: { stage },
            copy: { scale in
                OnboardingHeadline(
                    first: "Everything that helps your memorization,",
                    second: "in one place.",
                    detail: "Daily revision, tasmee' with qualified teachers, and rewards that motivate you.",
                    scale: scale, visible: copyIn
                )
            },
            buttons: { metrics in BrandButton("Continue", metrics: metrics, action: onContinue) }
        )
        .onChange(of: isActive, initial: true) {
            guard isActive, !played else { return }
            played = true
            Task { await playEntrance() }
        }
    }

    // MARK: - Stage

    private var stage: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Palette.lavender, Palette.rose.opacity(0.45), Palette.surface.opacity(0)], center: .center, startRadius: 10, endRadius: 200))
                    .frame(width: 400, height: 400)
                    .scaleEffect(glowIn ? 1 + sin(time * 0.9) * 0.03 : 0.3)
                    .opacity(glowIn ? 1 : 0)

                floating(0, depth: .back, at: CGPoint(x: -112, y: -168), tilt: -8, time: time) {
                    AqraChip(icon: "⭐️", tint: Palette.butter) { Text(verbatim: "+٥٠ نقطة") }
                }
                floating(1, depth: .front, at: CGPoint(x: 58, y: -104), tilt: 4, time: time) {
                    StreakCard(days: streakDays)
                }
                floating(2, depth: .front, at: CGPoint(x: -66, y: 24), tilt: -3, time: time) {
                    ManzilCard(progress: manzilProgress)
                }
                floating(3, depth: .mid, at: CGPoint(x: 76, y: 138), tilt: 5, time: time) {
                    SessionCard()
                }
                floating(4, depth: .back, at: CGPoint(x: -98, y: 180), tilt: 3, time: time) {
                    AqraChip(icon: "✅", tint: Palette.mint) { Text(verbatim: "أتممت الجزء ٣٠") }
                }
            }
            // Positions are a fixed composition; each card's contents keep the screen's direction.
            .environment(\.layoutDirection, .leftToRight)
        }
    }

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

    // MARK: - Choreography

    private func playEntrance() async {
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.4)) {
                glowIn = true; cardsOut = 5; streakDays = 5; manzilProgress = 0.68; copyIn = true; actionsIn = true
            }
            return
        }
        let light = UIImpactFeedbackGenerator(style: .light)
        light.prepare()
        do {
            try await pause(120)
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { glowIn = true }
            try await pause(200)
            for card in 1...5 {
                cardsOut = card
                light.impactOccurred(intensity: 0.4)
                try await pause(110)
            }
            withAnimation(.easeOut(duration: 0.9)) { manzilProgress = 0.68 }
            for day in 1...5 {
                withAnimation(.snappy) { streakDays = day }
                try await pause(80)
            }
            copyIn = true
            try await pause(350)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { actionsIn = true }
        } catch {}
    }

    private func pause(_ milliseconds: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}

private typealias Palette = OnboardingPalette

// MARK: - Cards

private struct StreakCard: View {
    var days: Int

    var body: some View {
        AqraCard {
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
        AqraCard {
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
        AqraCard {
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

#Preview {
    FeaturesPageView(pageCount: 3, currentPage: 2, isActive: true, onContinue: {})
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}
