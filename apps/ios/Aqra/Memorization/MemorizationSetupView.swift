import SwiftUI

/// «ماذا تحفظ من القرآن؟»: right after onboarding (and later from the Mushaf's marking mode), the student picks
/// the juz' and surahs they've memorized. The منازل stairs above climb as they choose; pages and single ayat
/// are marked in the Mushaf itself.
struct MemorizationSetupView: View {
    var store: MushafStore
    /// Shown over the Mushaf from marking mode, rather than as the step after onboarding.
    var isSheet = false
    /// Called when the student is done; true when they chose to mark pages and ayat in the Mushaf next.
    var onFinish: (_ markInMushaf: Bool) -> Void

    @Environment(MemorizationStore.self) private var memorization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var section = SetupSection.juz
    /// The stairs' climb as shown; it follows the memorized count with a spring, starting from the bottom.
    @State private var shownClimb = 0.0

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let landscape = size.width > size.height * 1.1
            // iPad-sized space in either orientation.
            let scale: CGFloat = min(size.width, size.height) >= 600 ? 1.35 : 1

            Group {
                if landscape {
                    HStack(spacing: 24 * scale) {
                        VStack(spacing: 16 * scale) {
                            Spacer(minLength: 0)
                            hero(scale: scale * 0.9)
                            Spacer(minLength: 0)
                            footer(scale: scale)
                        }
                        .frame(width: min(size.width * 0.42, 460 * scale))
                        VStack(spacing: 14) {
                            controls(scale: scale)
                            list(columns: scale > 1 ? 5 : 4, scale: scale)
                        }
                    }
                    .padding(.horizontal, 20 * scale)
                } else {
                    VStack(spacing: 14 * scale) {
                        hero(scale: scale)
                            .padding(.top, 12 * scale)
                        controls(scale: scale)
                            .frame(maxWidth: 760)
                        // On iPad all thirty juz' fit without scrolling.
                        list(columns: scale > 1 ? 6 : 3, scale: scale > 1 ? 1.1 : 1)
                            .frame(maxWidth: 760)
                        footer(scale: scale)
                            .frame(maxWidth: 560)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .background(Palette.surface.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        // A soft tick for each choice, and a fuller one when the whole Quran is chosen.
        .sensoryFeedback(.selection, trigger: memorization.count)
        .sensoryFeedback(.success, trigger: memorization.count == MushafStore.ayahCount) { _, isAll in isAll }
        .onAppear { climb(to: targetClimb, entrance: true) }
        .onChange(of: memorization.count) { climb(to: targetClimb, entrance: false) }
    }

    // MARK: - Hero

    private var quranShare: Double { memorization.quranShare(in: store) }

    /// How many of the ten steps are climbed: three juz' make a step.
    private var targetClimb: Double {
        quranShare * Double(ManazilStairs.stepCount)
    }

    private func climb(to value: Double, entrance: Bool) {
        guard !reduceMotion else {
            shownClimb = value
            return
        }
        withAnimation(entrance ? .spring(duration: 1.4, bounce: 0.1).delay(0.25) : .spring(duration: 0.9, bounce: 0.15)) {
            shownClimb = value
        }
    }

    private func hero(scale: CGFloat) -> some View {
        VStack(spacing: 12 * scale) {
            VStack(spacing: 0) {
                Text("What have you memorized").foregroundStyle(Palette.ink)
                Text("of the Quran?").foregroundStyle(Palette.brand)
            }
            .font(.system(size: 28 * scale, weight: .heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)

            ManazilStairs(climb: shownClimb)
                .frame(maxWidth: 420 * scale)
                .frame(height: 118 * scale)

            numbers(scale: scale)
                .frame(minHeight: 64 * scale)
        }
        .accessibilityElement(children: .combine)
    }

    private func numbers(scale: CGFloat) -> some View {
        let count = memorization.count
        let share = quranShare.formatted(.percent.precision(.fractionLength(0...1)))
        let fullJuz = (1...30).filter { juz in
            store.juzAyahs[juz].map { memorization.memorizedCount(in: $0) == $0.count } ?? false
        }.count
        return VStack(spacing: 4 * scale) {
            if count == 0 {
                Text("Choose what you've memorized to start climbing")
                    .font(.system(size: 16 * scale, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                    Text(verbatim: share)
                        .font(.system(size: 40 * scale, weight: .heavy))
                        .foregroundStyle(Palette.brand)
                        .contentTransition(.numericText(value: Double(count)))
                    Text("of the Quran")
                        .font(.system(size: 17 * scale, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
                HStack(spacing: 6) {
                    Text("\(count) ayat")
                    if fullJuz > 0 {
                        Text(verbatim: "·")
                        Text("\(fullJuz) juz'")
                    }
                }
                .font(.system(size: 14 * scale, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
                .contentTransition(.numericText(value: Double(count)))
            }
        }
        .animation(.snappy, value: count)
    }

    // MARK: - Controls

    private func controls(scale: CGFloat) -> some View {
        let isAll = memorization.count == MushafStore.ayahCount
        return HStack(spacing: 10) {
            SectionSwitch(selection: $section, scale: scale)
            Spacer(minLength: 0)
            Button {
                memorization.mark(0..<MushafStore.ayahCount, memorized: !isAll)
            } label: {
                HStack(spacing: 6) {
                    StarShape(points: 8, innerRatio: 0.42, cornerRadius: 0.05)
                        .fill(LinearGradient(colors: [Color(light: 0xF8D371, dark: 0xF8D371), Color(light: 0xEFB54A, dark: 0xEFB54A)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 16 * scale, height: 16 * scale)
                    Text("The whole Quran")
                }
                .font(.system(size: 14 * scale, weight: .bold))
                .foregroundStyle(isAll ? Color(light: 0x8A5A12, dark: 0x8A5A12) : Palette.brand)
                .padding(.horizontal, 14 * scale)
                .frame(height: 46 * scale)
                .background(isAll ? Palette.butter : .white, in: Capsule())
                .overlay(Capsule().strokeBorder(isAll ? Color(light: 0xEFC46A, dark: 0xEFC46A) : Palette.lavender, lineWidth: 1.5))
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: - Lists

    @ViewBuilder
    private func list(columns: Int, scale: CGFloat) -> some View {
        ScrollView {
            Group {
                switch section {
                case .juz: juzGrid(columns: columns, scale: scale)
                case .surahs: surahList
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        // The list fades out under the controls and above the footer rather than ending at a hard line.
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                                     .init(color: .black, location: 0.95), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }

    private func juzGrid(columns: Int, scale: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12 * scale), count: columns), spacing: 12 * scale) {
            ForEach(1...30, id: \.self) { juz in
                if let range = store.juzAyahs[juz] {
                    juzTile(juz, range: range, scale: scale)
                }
            }
        }
    }

    /// A juz' tile, in its band's color on the stairs, fills from the bottom up as its ayat are memorized.
    private func juzTile(_ juz: Int, range: ClosedRange<Int>, scale: CGFloat) -> some View {
        let fraction = Double(memorization.memorizedCount(in: range)) / Double(range.count)
        let face = ManazilStairs.face(forJuz: juz)
        return Button {
            memorization.mark(range, memorized: fraction < 1)
        } label: {
            ZStack {
                GeometryReader { geometry in
                    LinearGradient(colors: [face.top.opacity(0.75), face.top], startPoint: .top, endPoint: .bottom)
                        .frame(height: geometry.size.height * fraction)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                Text(juz.formatted())
                    .font(.system(size: 30 * scale, weight: .heavy))
                    .foregroundStyle(fraction > 0 ? Palette.ink : Palette.brand)
                if fraction == 1 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(face.bottom, in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 72 * scale)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(fraction > 0 ? .white.opacity(0.7) : face.top.opacity(0.9), lineWidth: 1.5)
            )
            .shadow(color: (fraction > 0 ? face.bottom : Palette.shadow).opacity(fraction > 0 ? 0.25 : 0.05), radius: 10, y: 5)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: fraction)
            // A small pop as a juz' is completed or cleared.
            .keyframeAnimator(initialValue: 1.0, trigger: fraction == 1) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.06, duration: 0.12)
                SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text("Juz' \(juz)"))
        .accessibilityValue(Text(fraction.formatted(.percent.precision(.fractionLength(0)))))
    }

    private var surahList: some View {
        LazyVStack(spacing: 10) {
            ForEach(1...114, id: \.self) { surah in
                if let range = store.surahAyahs[surah] {
                    surahRow(surah, range: range)
                }
            }
        }
    }

    private func surahRow(_ surah: Int, range: ClosedRange<Int>) -> some View {
        let memorized = memorization.memorizedCount(in: range)
        // The surah takes the band color of the juz' it begins in.
        let juz = (1...30).first { store.juzAyahs[$0]?.contains(range.lowerBound) == true } ?? 1
        let face = ManazilStairs.face(forJuz: juz)
        return Button {
            memorization.mark(range, memorized: memorized < range.count)
        } label: {
            HStack(spacing: 14) {
                Text(surah.formatted())
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 38, height: 38)
                    .background(face.top, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: store.surahNames[surah] ?? "")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text("\(range.count) ayat")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer()
                Image(systemName: memorized == range.count ? "checkmark.circle.fill"
                      : memorized > 0 ? "circle.lefthalf.filled" : "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(memorized > 0 ? face.bottom : Palette.lavender)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(memorized == range.count ? face.top.opacity(0.35) : .white,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Palette.shadow.opacity(0.05), radius: 8, y: 4)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: memorized)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Footer

    private func footer(scale: CGFloat) -> some View {
        // With nothing chosen, the student is starting from zero; once something is chosen, they continue.
        let title: LocalizedStringKey = isSheet ? "Done" : memorization.count == 0 ? "I'm just starting" : "Continue"
        return VStack(spacing: 12) {
            BrandButton(title, metrics: OnboardingButtonMetrics(height: 56 * min(scale, 1.15), fontSize: 18 * min(scale, 1.15), compact: false)) {
                onFinish(false)
            }
            .animation(.snappy, value: memorization.count == 0)
            if !isSheet {
                Button("Mark pages and ayat in the Mushaf") { onFinish(true) }
                    .font(.system(size: 15 * min(scale, 1.15), weight: .semibold))
                    .foregroundStyle(Palette.brand)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
}

/// Which list the setup screen shows.
private enum SetupSection: Hashable {
    case juz, surahs
}

/// «الأجزاء / السور»: a white capsule with a brand-colored thumb that slides to the chosen side.
private struct SectionSwitch: View {
    @Binding var selection: SetupSection
    var scale: CGFloat = 1
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            item(.juz, title: "Juz'")
            item(.surahs, title: "Surahs")
        }
        .padding(4)
        .background(.white, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.lavender, lineWidth: 1.5))
    }

    private func item(_ value: SetupSection, title: LocalizedStringKey) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { selection = value }
        } label: {
            Text(title)
                .font(.system(size: 15 * scale, weight: .bold))
                .foregroundStyle(selection == value ? .white : Palette.inkSoft)
                .padding(.horizontal, 18 * scale)
                .frame(height: 38 * scale)
                .background {
                    if selection == value {
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.brand, Palette.brandDeep], startPoint: .top, endPoint: .bottom))
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Tiles, rows and chips shrink a little under the finger.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private typealias Palette = OnboardingPalette
