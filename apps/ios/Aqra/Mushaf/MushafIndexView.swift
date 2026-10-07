import SwiftUI

/// The Mushaf's index: every surah and juz', each opening on its first page.
struct MushafIndexView: View {
    var store: MushafStore
    var currentPage: Int
    var onSelect: (Int) -> Void

    private enum Section: Hashable { case surahs, juz }
    @State private var section = Section.surahs

    var body: some View {
        let currentSurah = store.surah(containing: currentPage)
        let currentJuz = store.juz(containing: currentPage)
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text("Index")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                AqraSegmented(selection: $section, options: [(.surahs, "Surahs"), (.juz, "Juz'")])
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        switch section {
                        case .surahs:
                            ForEach(1...114, id: \.self) { surah in
                                let page = store.surahStartPages[surah] ?? 1
                                row(number: surah, title: store.surahNames[surah] ?? "", page: page,
                                    subtitle: store.surahAyahs[surah].map { Text("\($0.count) ayat") }, isCurrent: surah == currentSurah)
                                    .id(surah)
                            }
                        case .juz:
                            ForEach(1...30, id: \.self) { juz in
                                let page = store.juzStartPages[juz] ?? 1
                                row(number: juz, title: "الجزء \(arabic(juz))", page: page,
                                    subtitle: Text(verbatim: store.surahNames[store.page(page).surah] ?? ""), isCurrent: juz == currentJuz)
                                    .id(juz)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                // Open on the surah (or juz') being read.
                .onAppear { proxy.scrollTo(currentSurah, anchor: .center) }
                .onChange(of: section) {
                    proxy.scrollTo(section == .surahs ? currentSurah : currentJuz, anchor: .center)
                }
            }
        }
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.colorScheme, .light)
        .presentationDetents([.medium, .large])
    }

    /// A surah or juz': its number in a tile of its juz's color, its name, and the page it starts on.
    private func row(number: Int, title: String, page: Int, subtitle: Text?, isCurrent: Bool) -> some View {
        let face = ManazilStairs.face(forJuz: store.page(page).juz)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button {
            onSelect(page)
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: arabic(number))
                    .font(.system(size: 15, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(face.top, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    subtitle?
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 8)
                Text(verbatim: arabic(page))
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.brand)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(isCurrent ? .white : Palette.lavender, in: Capsule())
            }
            .padding(10)
            .background(isCurrent ? Palette.lavender : .white, in: shape)
            .overlay(shape.strokeBorder(isCurrent ? Palette.brand.opacity(0.3) : .clear, lineWidth: 1.5))
            .shadow(color: Palette.shadow.opacity(0.06), radius: 8, y: 4)
            .contentShape(shape)
        }
        .buttonStyle(AqraPressStyle())
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func arabic(_ number: Int) -> String {
        number.formatted(.number.locale(Locale(identifier: "ar@numbers=arab")))
    }
}

private typealias Palette = OnboardingPalette
