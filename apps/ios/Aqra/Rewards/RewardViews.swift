import SwiftUI
import UIKit

extension Achievement {
    var title: LocalizedStringKey {
        switch self {
        case .firstRevision: "First revision"
        case .firstWird: "A whole day's wird"
        case .firstPortion: "First new portion"
        case .firstJuz: "A whole juz'"
        case .firstVerified: "Heard clean by a teacher"
        case .firstPeer: "Recited to a friend"
        case .streak7: "7 days in a row"
        case .streak30: "30 days in a row"
        case .streak100: "100 days in a row"
        case .firstStage: "First stage passed"
        case .fiveStages: "Five stages passed"
        case .wholeQuran: "The whole Quran"
        }
    }
}

extension Challenge.Kind {
    func title(_ target: Int) -> Text {
        switch self {
        case .wirdDays: Text("Complete the wird on \(target) days")
        case .pagesRevised: Text("Revise \(target) pages")
        case .linesMemorized: Text("Memorize \(target) lines")
        case .dailyRevision: Text("Revise every day for a week")
        }
    }

    var icon: String {
        switch self {
        case .wirdDays: "✅"
        case .pagesRevised: "📄"
        case .linesMemorized: "✍️"
        case .dailyRevision: "🔥"
        }
    }
}

// MARK: - Celebrating

/// The moment something is earned: a small toast of points, or a fuller card for an achievement, a stage or a
/// challenge, with a gentle chime and a haptic. Shown over the app, never over the Mushaf's own reading.
struct CelebrationOverlay: View {
    @Environment(RewardStore.self) private var rewards
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The celebration on screen. One earned under the wird, the Mushaf or a sheet waits until they close, rather
    /// than chiming unseen behind them.
    @State private var shown: UUID?

    var body: some View {
        VStack {
            if let celebration = rewards.celebration, shown == celebration.id {
                content(celebration)
                    .id(celebration.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .scale(scale: 0.8)).combined(with: .opacity))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { rewards.finishCelebration() }
                    }
            }
            Spacer()
        }
        .padding(.top, 8)
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: shown)
        .sensoryFeedback(.success, trigger: shown) { _, id in id != nil }
        .allowsHitTesting(shown != nil)
        .task(id: rewards.celebration?.id) {
            guard let celebration = rewards.celebration else {
                shown = nil
                return
            }
            while UIApplication.shared.topViewController !== UIApplication.shared.activeWindow?.rootViewController {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { return }
            }
            shown = celebration.id
            Chime.play(big: celebration.isBig)
            try? await Task.sleep(for: .seconds(celebration.isBig ? 2.6 : 1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { rewards.finishCelebration() }
        }
    }

    @ViewBuilder
    private func content(_ celebration: Celebration) -> some View {
        switch celebration.kind {
        case .points(let points):
            AqraChip(icon: "⭐️", tint: Palette.butter) {
                Text("+\(points) points")
                    .monospacedDigit()
            }
            .scaleEffect(1.15)
            .accessibilityAddTraits(.updatesFrequently)
        case .achievement(let achievement):
            card(icon: achievement.icon, tint: Palette.butter, title: Text(achievement.title), detail: Text("A new achievement"))
        case .stage(let stage):
            card(icon: "🏅", tint: Palette.lavender, title: Text("Stage \(stage) passed"), detail: Text("May Allah bless you"))
        case .challenge(let kind, let target):
            card(icon: kind.icon, tint: Palette.mint, title: kind.title(target), detail: Text("Challenge met"))
        }
    }

    private func card(icon: String, tint: Color, title: Text, detail: Text) -> some View {
        HStack(spacing: 12) {
            IconTile(icon: icon, tint: tint, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                detail
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.brand)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: 420)
        .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Palette.shadow.opacity(0.2), radius: 24, y: 12)
        .padding(.horizontal, 22)
        .fontDesign(.rounded)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - On the progress screen

/// Points, achievements and the week's challenges.
struct RewardsSection: View {
    @Environment(RewardStore.self) private var rewards
    @Environment(RevisionStore.self) private var revision
    @Environment(PlanStore.self) private var plan
    @State private var choosingChallenge = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AqraSectionTitle(title: "Rewards").padding(.top, 10)
            AqraCard(padding: 14, radius: 24) {
                HStack(spacing: 12) {
                    IconTile(icon: "⭐️", tint: Palette.butter, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(rewards.points) points")
                            .font(.system(size: 19, weight: .heavy).monospacedDigit())
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText())
                        Text("\(rewards.points(since: weekStart)) this week")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    Spacer()
                    Text("Just for you")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.brand)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Palette.lavender, in: Capsule())
                }
            }

            AqraCard(padding: 12, radius: 24) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                    ForEach(Achievement.allCases, id: \.self) { achievement in
                        let earned = rewards.achievements[achievement] != nil
                        VStack(spacing: 5) {
                            Text(verbatim: achievement.icon)
                                .font(.system(size: 24))
                                .frame(width: 48, height: 48)
                                .background(earned ? Palette.butter : Palette.lavender.opacity(0.6), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .grayscale(earned ? 0 : 1)
                                .opacity(earned ? 1 : 0.45)
                            Text(achievement.title)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(earned ? Palette.ink : Palette.inkSoft)
                                .multilineTextAlignment(.center)
                                .lineLimit(2, reservesSpace: true)
                                .minimumScaleFactor(0.8)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(earned ? Text("Earned") : Text("Not yet"))
                    }
                }
            }

            HStack {
                AqraSectionTitle(title: "This week's challenges")
                Button {
                    choosingChallenge = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Palette.brand)
                        .frame(width: 30, height: 30)
                        .background(Palette.lavender, in: Circle())
                }
                .accessibilityLabel(Text("New challenge"))
            }
            .padding(.top, 6)
            let active = rewards.activeChallenges()
            if active.isEmpty {
                Button {
                    choosingChallenge = true
                } label: {
                    AqraCard(padding: 0, radius: 24) {
                        AqraRow(icon: "🎯", tint: Palette.peach, title: Text("Set yourself a challenge"),
                                detail: Text("A goal for the week, between you and yourself"))
                    }
                }
                .buttonStyle(AqraPressStyle())
            } else {
                AqraCard(padding: 0, radius: 24) {
                    VStack(spacing: 0) {
                        ForEach(Array(active.enumerated()), id: \.element.id) { index, challenge in
                            if index > 0 { AqraRowDivider() }
                            challengeRow(challenge)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $choosingChallenge) { ChallengePicker() }
    }

    private var weekStart: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    }

    private func challengeRow(_ challenge: Challenge) -> some View {
        let progress = rewards.progress(of: challenge, revision: revision, plan: plan)
        let done = challenge.completedAt != nil
        return HStack(spacing: 12) {
            IconTile(icon: done ? "🏆" : challenge.kind.icon, tint: done ? Palette.butter : Palette.peach, size: 38)
            VStack(alignment: .leading, spacing: 6) {
                challenge.kind.title(challenge.target)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                ProgressView(value: Double(min(progress, challenge.target)), total: Double(max(challenge.target, 1)))
                    .tint(done ? Color(light: 0x2E9B63, dark: 0x2E9B63) : Palette.brand)
                (done ? Text("Done") : Text("\(min(progress, challenge.target)) of \(challenge.target) · until \(challenge.end.formatted(.dateTime.weekday(.wide)))"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
            }
            if !done {
                Button {
                    withAnimation(.snappy) { rewards.remove(challenge) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 26, height: 26)
                        .background(Palette.lavender, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove the challenge"))
            }
        }
        .padding(14)
    }
}

/// Choosing a challenge for the coming week.
struct ChallengePicker: View {
    @Environment(RewardStore.self) private var rewards
    @Environment(PlanStore.self) private var plan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("A challenge").foregroundStyle(Palette.ink)
                Text("for this week").foregroundStyle(Palette.brand)
            }
            .font(.system(size: 26, weight: .heavy))
            .padding(.top, 20)
            Text("Between you and yourself: nobody else sees it.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
            ScrollView {
                AqraCard(padding: 0, radius: 24) {
                    VStack(spacing: 0) {
                        let options = Challenge.options.filter { $0.kind != .linesMemorized || plan.plan != nil }
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            if index > 0 { AqraRowDivider() }
                            Button {
                                rewards.start(option.kind, target: option.target)
                                dismiss()
                            } label: {
                                AqraRow(icon: option.kind.icon, tint: Palette.peach, title: option.kind.title(option.target)) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(Palette.brand)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .environment(\.colorScheme, .light)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private typealias Palette = OnboardingPalette
