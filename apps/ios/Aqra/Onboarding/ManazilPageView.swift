import SwiftUI
import UIKit

/// Onboarding page 2: the منازل stairs build step by step inside glowing rings,
/// the gold star lands on top, and the promise rises beneath.
struct ManazilPageView: View {
    var pageCount: Int
    var currentPage: Int
    /// The entrance plays the first time the page becomes the visible one.
    var isActive: Bool
    var onContinue: () -> Void
    /// Shows the finished scene without the entrance (snapshots and previews).
    var startsComplete = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var ringsOpen = false
    @State private var builtSteps = 0
    @State private var starLit = false
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
            _ringsOpen = State(initialValue: true)
            _builtSteps = State(initialValue: AqraLogoMark.stepCount)
            _starLit = State(initialValue: true)
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
                    first: "Strengthen your memorization,",
                    second: "and rise, ayah by ayah.",
                    detail: "Revise every day, and climb your stations in Aqra.",
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
                AqraGlowRings(open: ringsOpen, breath: sin(time * 0.9))
                    .scaleEffect(1.15)
                AqraLogoMark(built: builtSteps, starLit: starLit, twinkle: sin(time * 2.2))
                    .scaleEffect(1.45)
                    .offset(x: 8, y: 6)
            }
            .frame(width: 420, height: 440)
        }
    }

    // MARK: - Choreography

    private func playEntrance() async {
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.4)) {
                ringsOpen = true; builtSteps = AqraLogoMark.stepCount; starLit = true; copyIn = true; actionsIn = true
            }
            return
        }
        let soft = UIImpactFeedbackGenerator(style: .soft)
        let light = UIImpactFeedbackGenerator(style: .light)
        soft.prepare(); light.prepare()
        do {
            try await pause(150)
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { ringsOpen = true }
            try await pause(150)
            for step in 1...AqraLogoMark.stepCount {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { builtSteps = step }
                try await pause(120)
                soft.impactOccurred(intensity: 0.5)
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.45)) { starLit = true }
            light.impactOccurred(intensity: 0.8)
            try await pause(350)
            copyIn = true
            try await pause(350)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { actionsIn = true }
        } catch {}
    }

    private func pause(_ milliseconds: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}

#Preview {
    ManazilPageView(pageCount: 2, currentPage: 1, isActive: true, onContinue: {})
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}
