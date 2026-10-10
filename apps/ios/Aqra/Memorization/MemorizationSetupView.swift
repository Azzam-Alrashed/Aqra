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
    @Environment(AccountStore.self) private var account: AccountStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction

    @State private var section = SetupSection.juz
    /// An unmarking that would erase revision history, waiting for the student to confirm it.
    @State private var pendingRemoval: Removal?
    /// What the last unmarking removed, kept for a moment so it can be undone.
    @State private var undo: Undo?
    @State private var restoring = false
    @AppStorage("memorization.hasDeclared") private var hasDeclared = false

    /// «لديّ حساب في اقرأ»: offered in setup, before anything is declared, to someone not signed in yet.
    private var offersRestore: Bool {
        !isSheet && AccountStore.isAvailable && memorization.count == 0 && account?.profile?.isAnonymous != false
    }
    /// The stairs' climb as shown; it follows the memorized count with a spring, starting from the bottom.
    @State private var shownClimb = 0.0
    @State private var climbAnimation: Animation?

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
                            if offersRestore { restoreCard }
                            controls(scale: scale)
                            list(columns: scale > 1 ? 5 : 4, scale: scale)
                        }
                    }
                    .padding(.horizontal, 20 * scale)
                } else {
                    VStack(spacing: 14 * scale) {
                        hero(scale: scale)
                            .padding(.top, 12 * scale)
                        if offersRestore {
                            restoreCard
                                .frame(maxWidth: 560)
                                .transition(.scale(scale: 0.95).combined(with: .opacity))
                        }
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
            .overlay(alignment: .bottom) { undoChip }
            .overlay { confirmation }
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
        .animation(.snappy, value: offersRestore)
        .sheet(isPresented: $restoring) {
            RestoreAccountSheet {
                restoring = false
                // What they memorized, the daily amount and the plan came back with the account: setup is over.
                withAnimation { hasDeclared = true }
            }
        }
    }

    private var restoreCard: some View {
        Button { restoring = true } label: {
            AqraCard(padding: 0, radius: 22) {
                AqraRow(icon: "🔑", tint: Palette.sky, title: Text("I have an Aqra account"),
                        detail: Text("Restore what you memorized and carry on"))
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Hero

    private var quranShare: Double { memorization.quranShare(in: store) }

    /// How many of the ten steps are climbed: three juz' make a step.
    private var targetClimb: Double {
        quranShare * Double(GlossyStairs.stepCount)
    }

    /// The animation is the stairs' own: in a `withAnimation`, the rest of the screen's first layout would be
    /// animated with it.
    private func climb(to value: Double, entrance: Bool) {
        climbAnimation = reduceMotion ? nil : entrance ? .spring(duration: 1.4, bounce: 0.1).delay(0.25) : .spring(duration: 0.9, bounce: 0.15)
        shownClimb = value
    }

    private func hero(scale: CGFloat) -> some View {
        VStack(spacing: 4 * scale) {
            VStack(spacing: 0) {
                Text("What have you memorized").foregroundStyle(Palette.ink)
                Text("of the Quran?").foregroundStyle(Palette.brand)
            }
            .aqraFont(size: 28 * scale, weight: .heavy)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            summary
                .aqraFont(size: 15 * scale, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText(value: Double(memorization.count)))
                .animation(.snappy, value: memorization.count)
            stage(scale: scale)
        }
        .accessibilityElement(children: .combine)
    }

    /// «٥٦٤ آية · جزء واحد», or how to start when nothing is chosen yet.
    private var summary: Text {
        let count = memorization.count
        guard count > 0 else { return Text("Choose what you've memorized to start climbing") }
        let fullJuz = (1...30).filter { juz in
            store.juzAyahs[juz].map { memorization.memorizedCount(in: $0) == $0.count } ?? false
        }.count
        let ayat = Text("\(count) ayat")
        return fullJuz > 0 ? ayat + Text(verbatim: Separator.facts) + Text("\(fullJuz) juz'") : ayat
    }

    /// The home's stage, smaller: the stairs in their glowing rings, climbing as juz' and surahs are chosen,
    /// with the share of the Quran floating beside them.
    private func stage(scale: CGFloat) -> some View {
        let mirror: CGFloat = direction == .rightToLeft ? 1 : -1
        let share = quranShare
        return ZStack {
            GlossyStairs(climb: shownClimb)
                .animation(climbAnimation, value: shownClimb)
                .environment(\.layoutDirection, direction)
                .scaleEffect((offersRestore ? 0.52 : 0.66) * scale)
                .offset(x: 6 * mirror * scale)
            if memorization.count > 0 {
                AqraChip(icon: "🪜", tint: Palette.lavender) {
                    HStack(spacing: 4) {
                        Text(verbatim: share.formatted(.percent.precision(.fractionLength(0...1))))
                            .contentTransition(.numericText(value: share))
                        Text("of the Quran")
                    }
                }
                .environment(\.layoutDirection, direction)
                .rotationEffect(.degrees(-4 * mirror))
                .offset(x: 100 * mirror * scale, y: -52 * scale)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
                .animation(.snappy, value: share)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: memorization.count > 0)
        .frame(height: (offersRestore ? 128 : 168) * scale)
        .frame(maxWidth: .infinity)
        // Behind the stage, so the glow spreads past its edges without widening the screen.
        .background {
            AqraGlowRings(open: true, breath: 0)
                .scaleEffect(0.62 * scale)
        }
    }

    // MARK: - Controls

    private func controls(scale: CGFloat) -> some View {
        let isAll = memorization.count == MushafStore.ayahCount
        return HStack(spacing: 10) {
            AqraSegmented(selection: $section, options: [(.juz, "Juz'"), (.surahs, "Surahs")], scale: scale)
            Spacer(minLength: 0)
            Button {
                toggle(0...(MushafStore.ayahCount - 1), memorize: !isAll, what: .wholeQuran)
            } label: {
                HStack(spacing: 6) {
                    StarShape(points: 8, innerRatio: 0.42, cornerRadius: 0.05)
                        .fill(LinearGradient(colors: [Color(light: 0xF8D371, dark: 0xF8D371), Color(light: 0xEFB54A, dark: 0xEFB54A)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 16 * scale, height: 16 * scale)
                    Text("The whole Quran")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
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
            toggle(range, memorize: fraction < 1, what: .juz(juz))
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
            toggle(range, memorize: memorized < range.count, what: .surah(store.surahNames[surah] ?? ""))
        } label: {
            HStack(spacing: 14) {
                Text(surah.formatted())
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 38, height: 38)
                    .background(face.top, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: store.surahNames[surah] ?? "")
                        .aqraFont(size: 18, weight: .bold)
                        .foregroundStyle(Palette.ink)
                    Text("\(range.count) ayat")
                        .aqraFont(size: 13, weight: .medium)
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

    // MARK: - Unmarking safely

    /// Marks a juz', a surah or the whole Quran, or unmarks it. Unmarking ayat that carry revision history (strength,
    /// stumbles, a teacher's mark) asks first; any unmarking can be undone for a few seconds.
    private func toggle(_ range: ClosedRange<Int>, memorize: Bool, what: Removal.What) {
        guard !memorize else {
            withAnimation(.easeInOut(duration: 0.2)) { undo = nil }
            memorization.mark(range, memorized: true)
            return
        }
        let records = range.compactMap { memorization.memory(ofAyah: $0) }
        let withHistory = records.filter { $0.lastReviewed != nil || $0.lapses > 0 || $0.verified || $0.learnedAt != nil }
        if withHistory.isEmpty {
            remove(range, what: what)
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                pendingRemoval = Removal(range: range, what: what, count: records.count,
                                         verified: records.filter(\.verified).count)
            }
        }
    }

    private func remove(_ range: ClosedRange<Int>, what: Removal.What) {
        let removed = memorization.mark(range, memorized: false)
        guard !removed.isEmpty else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            undo = Undo(records: removed, what: what)
        }
    }

    /// «تُزيل الجزء ٢ من حفظك؟»: what goes with the ayat, «إبقاء» as the main choice.
    @ViewBuilder private var confirmation: some View {
        if let removal = pendingRemoval {
            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { pendingRemoval = nil } }
                    .accessibilityHidden(true)
                AqraCard(padding: 20, radius: 28) {
                    VStack(spacing: 14) {
                        IconTile(icon: "🗂️", tint: Palette.rose, size: 52)
                        removal.title
                            .aqraFont(size: 20, weight: .heavy)
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        removal.detail
                            .aqraFont(size: 14, weight: .semibold)
                            .foregroundStyle(Palette.inkSoft)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Button {
                                let range = removal.range, what = removal.what
                                withAnimation(.easeOut(duration: 0.2)) { pendingRemoval = nil }
                                remove(range, what: what)
                            } label: {
                                Text("Remove")
                                    .aqraFont(size: 15, weight: .bold)
                                    .foregroundStyle(Color(light: 0x9A3E26, dark: 0x9A3E26))
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(Palette.rose, in: Capsule())
                            }
                            .buttonStyle(PressableStyle())
                            Button("Keep") {
                                withAnimation(.easeOut(duration: 0.2)) { pendingRemoval = nil }
                            }
                            .buttonStyle(BrandButtonStyle(height: 46, fontSize: 15))
                        }
                    }
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 26)
                .accessibilityAddTraits(.isModal)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
            .transition(.opacity)
        }
    }

    /// «أُزيل الجزء ٢» with «تراجع», for a few seconds after an unmarking.
    @ViewBuilder private var undoChip: some View {
        if let undo {
            HStack(spacing: 12) {
                undo.what.removedText
                    .aqraFont(size: 14, weight: .bold)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button {
                    memorization.restore(undo.records)
                    withAnimation(.easeOut(duration: 0.2)) { self.undo = nil }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .aqraFont(size: 14, weight: .heavy)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Palette.brand, in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.leading, 18)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(.white, in: Capsule())
            .shadow(color: Palette.shadow.opacity(0.14), radius: 14, y: 8)
            .frame(maxWidth: 360)
            .padding(.horizontal, 30)
            .padding(.bottom, 110)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: undo.id) {
                let id = undo.id
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled, self.undo?.id == id else { return }
                withAnimation(.easeOut(duration: 0.25)) { self.undo = nil }
            }
        }
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
                    .aqraFont(size: 15 * min(scale, 1.15), weight: .semibold)
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

/// An unmarking of ayat with history, waiting for the student's answer.
private struct Removal {
    enum What {
        case juz(Int)
        case surah(String)
        case wholeQuran

        var removedText: Text {
            switch self {
            case .juz(let juz): Text("Juz' \(juz) removed")
            case .surah(let name): Text("\(name) removed")
            case .wholeQuran: Text("The whole Quran removed")
            }
        }
    }

    var range: ClosedRange<Int>
    var what: What
    /// The memorized ayat it would remove, and how many of them a teacher verified.
    var count: Int
    var verified: Int

    var title: Text {
        switch what {
        case .juz(let juz): Text("Remove juz' \(juz) from what you've memorized?")
        case .surah(let name): Text("Remove \(name) from what you've memorized?")
        case .wholeQuran: Text("Remove the whole Quran from what you've memorized?")
        }
    }

    var detail: Text {
        var text = Text("\(count) ayat, with their revision history and strength.")
        if verified > 0 {
            text = text + Text(verbatim: " ") + Text("A sheikh verified \(verified) of them.")
        }
        return text + Text(verbatim: " ") + Text("You can undo it for a few seconds.")
    }
}

/// What an unmarking removed, to put back with «تراجع».
private struct Undo {
    let id = UUID()
    var records: [Int: AyahMemory]
    var what: Removal.What
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
