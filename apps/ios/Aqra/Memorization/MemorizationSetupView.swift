import SwiftUI

/// «ماذا تحفظ من القرآن؟»: right after onboarding (and later from the Mushaf's marking mode), the student picks
/// the juz' and surahs they've memorized. Pages and single ayat are marked in the Mushaf itself.
struct MemorizationSetupView: View {
    var store: MushafStore
    /// Shown over the Mushaf from marking mode, rather than as the step after onboarding.
    var isSheet = false
    /// Called when the student is done; true when they chose to mark pages and ayat in the Mushaf next.
    var onFinish: (_ markInMushaf: Bool) -> Void

    @Environment(MemorizationStore.self) private var memorization

    private enum Section: Hashable { case juz, surahs }
    @State private var section = Section.juz

    /// The colored Mushaf's pastels, in the same order as the topic colors.
    private static let pastels = [Palette.mint, Palette.sky, Palette.rose, Palette.lavender, Palette.butter, Palette.peach]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                OnboardingHeadline(
                    first: "What have you memorized",
                    second: "of the Quran?",
                    detail: "Choose the juz' and surahs you know. You can mark pages and ayat in the Mushaf anytime.",
                    scale: 1, visible: true
                )
                shortcuts
                Picker("Memorized by", selection: $section) {
                    Text("Juz'").tag(Section.juz)
                    Text("Surahs").tag(Section.surahs)
                }
                .pickerStyle(.segmented)
                switch section {
                case .juz: juzGrid
                case .surahs: surahList
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 12)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .background(Palette.surface.ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }

    // MARK: - Shortcuts

    private var shortcuts: some View {
        HStack(spacing: 10) {
            Button {
                memorization.mark(0..<MushafStore.ayahCount, memorized: true)
            } label: {
                Label("The whole Quran", systemImage: "book.fill")
            }
            .buttonStyle(ShortcutButtonStyle(selected: memorization.count == MushafStore.ayahCount))
            if !isSheet {
                Button {
                    memorization.mark(0..<MushafStore.ayahCount, memorized: false)
                    onFinish(false)
                } label: {
                    Label("I'm just starting", systemImage: "sparkles")
                }
                .buttonStyle(ShortcutButtonStyle(selected: false))
            }
        }
    }

    // MARK: - Juz'

    private var juzGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
            ForEach(1...30, id: \.self) { juz in
                if let range = store.juzAyahs[juz] {
                    juzTile(juz, range: range)
                }
            }
        }
    }

    /// A juz' tile fills with its pastel from the bottom up as its ayat are memorized, like a step being climbed.
    private func juzTile(_ juz: Int, range: ClosedRange<Int>) -> some View {
        let fraction = Double(memorization.memorizedCount(in: range)) / Double(range.count)
        let color = Self.pastels[(juz - 1) % Self.pastels.count]
        let firstSurah = store.juzStartPages[juz].map { store.surahNames[store.page($0).surah] ?? "" } ?? ""
        return Button {
            memorization.mark(range, memorized: fraction < 1)
        } label: {
            ZStack {
                GeometryReader { geometry in
                    color
                        .frame(height: geometry.size.height * fraction)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                VStack(spacing: 2) {
                    Text(juz.formatted())
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(fraction > 0 ? Palette.ink : Palette.brand)
                    Text(verbatim: firstSurah)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 6)
                if fraction == 1 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Palette.brand)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                }
            }
            .frame(height: 86)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(fraction > 0 ? .clear : Palette.lavender, lineWidth: 1.5)
            )
            .shadow(color: Palette.shadow.opacity(fraction > 0 ? 0.12 : 0.05), radius: 10, y: 5)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: fraction)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text("Juz' \(juz)"))
        .accessibilityValue(Text(fraction.formatted(.percent.precision(.fractionLength(0)))))
    }

    // MARK: - Surahs

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
        let color = Self.pastels[(surah - 1) % Self.pastels.count]
        return Button {
            memorization.mark(range, memorized: memorized < range.count)
        } label: {
            HStack(spacing: 14) {
                Text(surah.formatted())
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 38, height: 38)
                    .background(color, in: Circle())
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
                    .foregroundStyle(memorized > 0 ? Palette.brand : Palette.lavender)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Palette.shadow.opacity(0.05), radius: 8, y: 4)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            Group {
                if memorization.count == 0 {
                    Text("Nothing chosen yet")
                } else {
                    let share = (Double(memorization.count) / Double(MushafStore.ayahCount))
                        .formatted(.percent.precision(.fractionLength(0...1)))
                    HStack(spacing: 6) {
                        Text("\(memorization.count) ayat memorized")
                        Text(verbatim: "·")
                        Text("\(share) of the Quran")
                    }
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.inkSoft)
            .contentTransition(.numericText())
            .animation(.snappy, value: memorization.count)

            BrandButton(isSheet ? "Done" : "Continue", metrics: OnboardingButtonMetrics(height: 56, fontSize: 18, compact: false)) {
                onFinish(false)
            }
            if !isSheet {
                Button("Mark pages and ayat in the Mushaf") { onFinish(true) }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.brand)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Palette.surface.ignoresSafeArea())
        // The list fades out just above the footer instead of ending at a hard line.
        .overlay(alignment: .top) {
            LinearGradient(colors: [Palette.surface.opacity(0), Palette.surface], startPoint: .top, endPoint: .bottom)
                .frame(height: 28)
                .offset(y: -28)
                .allowsHitTesting(false)
        }
    }
}

/// A shortcut: a white capsule, filled with the brand color once it's in effect.
private struct ShortcutButtonStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(selected ? .white : Palette.brand)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(selected ? Palette.brand : .white, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.lavender, lineWidth: selected ? 0 : 1.5))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Tiles and rows shrink a little under the finger.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private typealias Palette = OnboardingPalette
