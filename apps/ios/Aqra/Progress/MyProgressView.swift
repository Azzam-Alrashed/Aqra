import SwiftUI

/// تقدّمي: the share of the Quran memorized, the revision streak, a few numbers, and every juz' at a glance —
/// how much of it is memorized and how strong.
struct MyProgressView: View {
    var store: MushafStore

    @Environment(MemorizationStore.self) private var memorization
    @Environment(RevisionStore.self) private var revision
    @Environment(PlanStore.self) private var plan
    @State private var editingPlan = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headline
                sharesCard
                streakCard
                HStack(spacing: 10) {
                    stat(icon: "📖", tint: Palette.sky, value: memorization.count.formatted(), label: Text("Ayat memorized"))
                    stat(icon: "🔁", tint: Palette.mint, value: pagesThisWeek.formatted(), label: Text("Pages revised this week"))
                    stat(icon: "🌱", tint: Palette.butter,
                         value: memorization.averageStrength().map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                         label: Text("Memorization strength"))
                }
                AqraSectionTitle(title: "Strength by juz'")
                    .padding(.top, 10)
                juzGrid
                Text("The fuller a juz', the more of it you've memorized; the deeper its color, the stronger.")
                    .aqraFont(size: 12, weight: .medium)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                AqraSectionTitle(title: "Your plan").padding(.top, 10)
                planCard

                AqraSectionTitle(title: "The stages").padding(.top, 10)
                StagesSection(store: store)

                RewardsSection()

                TogetherSection(store: store)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Palette.surface.ignoresSafeArea())
        .fadesUnderStatusBar()
        .fontDesign(.rounded)
        .environment(\.colorScheme, .light)
        .sheet(isPresented: $editingPlan) { PlanEditorView(store: store) { _ in } }
    }

    // MARK: - Memorized, mastered, verified

    /// Kept apart: how much is memorized, how much of it is mastered, and how much a teacher heard clean — each
    /// counting every juz' equally, so mastered and verified never read more than memorized.
    private var sharesCard: some View {
        let mastered = memorization.quranShare(in: store) { memorization.masteredCount(in: $0) }
        let verified = memorization.quranShare(in: store) { memorization.verifiedCount(in: $0) }
        return AqraCard(padding: 14, radius: 24) {
            HStack(spacing: 0) {
                share(memorization.quranShare(in: store), label: Text("Memorized"), color: Palette.brand.opacity(0.45))
                share(mastered, label: Text("Mastered"), color: Palette.brand)
                share(verified, label: Text("Verified"), color: Color(light: 0x2E9B63, dark: 0x2E9B63))
            }
        }
    }

    private func share(_ value: Double, label: Text, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Palette.lavender, lineWidth: 7)
                Circle().trim(from: 0, to: min(max(value, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(verbatim: value.formatted(.percent.precision(.fractionLength(value > 0 && value < 0.01 ? 1 : 0))))
                    .font(.system(size: 14, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 64, height: 64)
            label
                .aqraFont(size: 12, weight: .bold)
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - The plan

    private var planCard: some View {
        Button {
            editingPlan = true
        } label: {
            AqraCard(padding: 0, radius: 24) {
                if let current = plan.plan {
                    AqraRow(icon: current.paused ? "⏸️" : "✍️", tint: Palette.butter,
                            title: PlanFormat.amount(current.dailyLines) + Text(verbatim: Separator.facts) + Text("\(current.studyDays.count) days a week"),
                            detail: planDetail)
                } else {
                    AqraRow(icon: "✍️", tint: Palette.butter, title: Text("Memorize new portions"),
                            detail: Text("A daily amount, and the date you'd complete the Quran"))
                }
            }
        }
        .buttonStyle(AqraPressStyle())
    }

    private var planDetail: Text {
        let week = Int(plan.lines(inLast: 7).rounded())
        if let date = plan.completionDate(memorization: memorization, store: store) {
            return Text("\(week) lines this week") + Text(verbatim: Separator.facts) + Text("Completion: \(PlanFormat.month(date))")
        }
        return Text("\(week) lines this week")
    }

    private var headline: some View {
        let share = memorization.quranShare(in: store)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Your progress")
                .foregroundStyle(Palette.ink)
            HStack(spacing: 8) {
                Text(verbatim: share.formatted(.percent.precision(.fractionLength(0...1))))
                Text("of the Quran")
            }
            .foregroundStyle(Palette.brand)
        }
        .aqraFont(size: 30, weight: .heavy)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Streak

    private var streakCard: some View {
        let streak = revision.streak()
        let days = revision.recentDays()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return AqraCard(padding: 14, radius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    IconTile(icon: "🔥", tint: Palette.peach, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(streak) days")
                            .aqraFont(size: 19, weight: .heavy)
                            .foregroundStyle(Palette.ink)
                        Text("Revision streak")
                            .aqraFont(size: 12, weight: .semibold)
                            .foregroundStyle(Palette.inkSoft)
                    }
                    Spacer()
                }
                // The last seven days, oldest first in the reading direction, ending today.
                HStack(spacing: 0) {
                    ForEach(days.indices, id: \.self) { index in
                        let revised = days[index]
                        let day = calendar.date(byAdding: .day, value: index - (days.count - 1), to: today) ?? today
                        VStack(spacing: 5) {
                            Circle()
                                .fill(revised ? Palette.brand : Palette.lavender)
                                .frame(width: 26, height: 26)
                                .overlay {
                                    Image(systemName: "checkmark")
                                        .aqraFont(size: 11, weight: .black)
                                        .foregroundStyle(.white)
                                        .opacity(revised ? 1 : 0)
                                }
                                .overlay {
                                    if index == days.count - 1 {
                                        Circle().strokeBorder(Palette.brand.opacity(0.35), lineWidth: 2).padding(-4)
                                    }
                                }
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .aqraFont(size: 11, weight: .bold)
                                .foregroundStyle(index == days.count - 1 ? Palette.brand : Palette.inkSoft)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(day.formatted(.dateTime.weekday(.wide))))
                        .accessibilityValue(revised ? Text("Revised") : Text("Not revised"))
                    }
                }
            }
        }
    }

    private var pagesThisWeek: Int {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return revision.history.filter { $0.date >= start }.count
    }

    private func stat(icon: String, tint: Color, value: String, label: Text) -> some View {
        AqraCard(padding: 12, radius: 20) {
            VStack(alignment: .leading, spacing: 8) {
                IconTile(icon: icon, tint: tint, size: 32)
                Text(verbatim: value)
                    .aqraFont(size: 20, weight: .heavy, monospacedDigit: true)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                label
                    .aqraFont(size: 11, weight: .semibold)
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(2, reservesSpace: true)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Juz' by juz'

    private var juzGrid: some View {
        AqraCard(padding: 12, radius: 24) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(1...30, id: \.self) { juz in
                    juzTile(juz)
                }
            }
        }
    }

    /// A juz' fills from the bottom with its band's color as far as it's memorized, deeper as its memorization is stronger.
    private func juzTile(_ juz: Int) -> some View {
        let range = store.juzAyahs[juz] ?? 0...0
        let memorized = memorization.memorizedCount(in: range)
        let share = range.isEmpty ? 0 : Double(memorized) / Double(range.count)
        let strength = memorized == 0 ? 0 : range.compactMap { memorization.strength(ofAyah: $0) }.reduce(0, +) / Double(memorized)
        let face = ManazilStairs.face(forJuz: juz)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ZStack(alignment: .bottom) {
            shape.fill(.white)
            GeometryReader { geometry in
                shape
                    .fill(LinearGradient(colors: [face.top, face.bottom], startPoint: .top, endPoint: .bottom))
                    .opacity(0.35 + 0.65 * strength)
                    .mask(alignment: .bottom) { Rectangle().frame(height: geometry.size.height * share) }
            }
            Text(juz.formatted())
                .font(.system(size: 17, weight: .heavy).monospacedDigit())
                .foregroundStyle(share > 0 ? Palette.ink : Palette.inkSoft.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 56)
        .overlay(shape.strokeBorder(share > 0 ? .white.opacity(0.8) : Palette.lavender, lineWidth: 1.2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Juz' \(juz)"))
        .accessibilityValue(Text(verbatim: [share, strength].map { $0.formatted(.percent.precision(.fractionLength(0))) }.formatted(.list(type: .and, width: .narrow))))
    }
}

private typealias Palette = OnboardingPalette
