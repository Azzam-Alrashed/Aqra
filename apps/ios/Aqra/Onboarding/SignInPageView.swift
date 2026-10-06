import AuthenticationServices
import SwiftUI
import UIKit

/// Onboarding page 4, the last: a gold star with rising sparkles, then optional sign-in.
struct SignInPageView: View {
    var pageCount: Int
    var currentPage: Int
    /// The entrance plays the first time the page becomes the visible one.
    var isActive: Bool
    var onAppleSignIn: (ASAuthorization) -> Void
    var onGoogleSignIn: () -> Void
    var onContinueWithoutAccount: () -> Void
    /// Shows the finished scene without the entrance (snapshots and previews).
    var startsComplete = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var glowIn = false
    @State private var starIn = false
    @State private var copyIn = false
    @State private var actionsIn = false
    @State private var played = false

    init(
        pageCount: Int, currentPage: Int, isActive: Bool, startsComplete: Bool = false,
        onAppleSignIn: @escaping (ASAuthorization) -> Void,
        onGoogleSignIn: @escaping () -> Void,
        onContinueWithoutAccount: @escaping () -> Void
    ) {
        self.pageCount = pageCount
        self.currentPage = currentPage
        self.isActive = isActive
        self.startsComplete = startsComplete
        self.onAppleSignIn = onAppleSignIn
        self.onGoogleSignIn = onGoogleSignIn
        self.onContinueWithoutAccount = onContinueWithoutAccount
        if startsComplete {
            _glowIn = State(initialValue: true)
            _starIn = State(initialValue: true)
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
                    first: "Save your progress,",
                    second: "and begin your journey.",
                    detail: "Sign in to keep your revision and stations, and to book tasmee' with teachers.",
                    scale: scale, visible: copyIn
                )
            },
            buttons: { metrics in signInButtons(metrics) }
        )
        .onChange(of: isActive, initial: true) {
            guard isActive, !played else { return }
            played = true
            Task { await playEntrance() }
        }
    }

    // MARK: - Stage

    private var stage: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(light: 0xFFF1D6, dark: 0xFFF1D6), Palette.lavender, Palette.rose.opacity(0.4), Palette.surface.opacity(0)],
                        center: .center, startRadius: 10, endRadius: 210
                    ))
                    .frame(width: 420, height: 420)
                    .scaleEffect(glowIn ? 1 + sin(time * 0.9) * 0.03 : 0.3)
                    .opacity(glowIn ? 1 : 0)

                ForEach([150.0, 240.0, 330.0], id: \.self) { size in
                    Circle()
                        .strokeBorder(.white, lineWidth: 1.5)
                        .frame(width: size, height: size)
                        .scaleEffect(glowIn ? 1 + sin(time * 0.9 + size) * 0.015 : 0.2)
                        .opacity(glowIn ? 0.9 : 0)
                }

                RisingSparkles(time: time)
                    .opacity(starIn ? 1 : 0)

                StarShape(points: 8, innerRatio: 0.38, cornerRadius: 0.04)
                    .fill(LinearGradient(colors: [Color(light: 0xF8D371, dark: 0xF8D371), Color(light: 0xEFB54A, dark: 0xEFB54A)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 150, height: 150)
                    .shadow(color: Color(light: 0xF6CB66, dark: 0xF6CB66).opacity(0.6), radius: 36 + 10 * sin(time * 2))
                    .scaleEffect(starIn ? 1 + 0.03 * sin(time * 2) : 0.3)
                    .rotationEffect(.degrees(starIn ? 0 : -140))
                    .offset(y: starIn ? 0 : 90)
                    .opacity(starIn ? 1 : 0)
            }
            .frame(width: 420, height: 440)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Buttons

    @ViewBuilder private func signInButtons(_ metrics: OnboardingButtonMetrics) -> some View {
        VStack(spacing: metrics.compact ? 8 : 12) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                if case .success(let authorization) = result { onAppleSignIn(authorization) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: metrics.height)
            .clipShape(Capsule())

            // TODO: use Google's official button and logo once the GoogleSignIn SDK is added.
            Button(action: onGoogleSignIn) {
                Text("Continue with Google")
                    .font(.system(size: metrics.fontSize - 1, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: metrics.height)
                    .background(.white, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.ink.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button("Continue without an account", action: onContinueWithoutAccount)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.brand)
                .padding(.top, metrics.compact ? 0 : 2)
        }
    }

    // MARK: - Choreography

    private func playEntrance() async {
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.4)) { glowIn = true; starIn = true; copyIn = true; actionsIn = true }
            return
        }
        let light = UIImpactFeedbackGenerator(style: .light)
        light.prepare()
        do {
            try await pause(120)
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { glowIn = true }
            try await pause(250)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.55)) { starIn = true }
            light.impactOccurred(intensity: 0.8)
            try await pause(450)
            copyIn = true
            try await pause(350)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { actionsIn = true }
        } catch {}
    }

    private func pause(_ milliseconds: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}

/// Small gold sparkles drifting upward around the star, fading in and out.
private struct RisingSparkles: View {
    var time: TimeInterval

    private static let sparkles: [(x: CGFloat, speed: Double, phase: Double, size: CGFloat)] = [
        (-150, 0.10, 0.0, 14), (-95, 0.14, 0.45, 10), (-40, 0.08, 0.2, 12), (35, 0.12, 0.7, 10),
        (90, 0.09, 0.35, 14), (145, 0.13, 0.9, 11), (-120, 0.11, 0.6, 9), (120, 0.1, 0.15, 9),
    ]

    var body: some View {
        ZStack {
            ForEach(Self.sparkles.indices, id: \.self) { index in
                let sparkle = Self.sparkles[index]
                let progress = (time * sparkle.speed + sparkle.phase).truncatingRemainder(dividingBy: 1)
                StarShape(points: 4, innerRatio: 0.38, cornerRadius: 0.1)
                    .fill(Color(light: 0xEFC47C, dark: 0xEFC47C))
                    .frame(width: sparkle.size, height: sparkle.size)
                    .offset(x: sparkle.x, y: 170 - progress * 360)
                    .opacity(sin(progress * .pi))
            }
        }
    }
}

private typealias Palette = OnboardingPalette

#Preview {
    SignInPageView(pageCount: 4, currentPage: 3, isActive: true, onAppleSignIn: { _ in }, onGoogleSignIn: {}, onContinueWithoutAccount: {})
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}
