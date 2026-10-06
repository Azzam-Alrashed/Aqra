import SwiftUI

/// The Mushaf's index: every surah and juz', each opening on its first page.
struct MushafIndexView: View {
    var store: MushafStore
    var currentPage: Int
    var onSelect: (Int) -> Void

    private enum Section: Hashable { case surahs, juz }
    @State private var section = Section.surahs

    var body: some View {
        NavigationStack {
            List {
                switch section {
                case .surahs:
                    ForEach(1...114, id: \.self) { surah in
                        let page = store.surahStartPages[surah] ?? 1
                        row(number: surah, title: store.surahNames[surah] ?? "", page: page)
                    }
                case .juz:
                    ForEach(1...30, id: \.self) { juz in
                        let page = store.juzStartPages[juz] ?? 1
                        row(number: juz, title: "الجزء \(arabic(juz))", page: page,
                            subtitle: store.surahNames[store.page(page).surah])
                    }
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .top) {
                Picker("Index", selection: $section) {
                    Text("Surahs").tag(Section.surahs)
                    Text("Juz'").tag(Section.juz)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .navigationTitle("Index")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(MushafStyle.marker)
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.medium, .large])
    }

    private func row(number: Int, title: String, page: Int, subtitle: String? = nil) -> some View {
        Button {
            onSelect(page)
        } label: {
            HStack(spacing: 14) {
                Text(verbatim: arabic(number))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(MushafStyle.marker)
                    .frame(width: 34, height: 34)
                    .background(MushafStyle.markerFill, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(MushafStyle.ink)
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(MushafStyle.chrome)
                    }
                }
                Spacer()
                Text(verbatim: arabic(page))
                    .font(.system(size: 14, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(MushafStyle.chrome)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(page == currentPage ? MushafStyle.markerFill.opacity(0.5) : Color.clear)
    }

    private func arabic(_ number: Int) -> String {
        number.formatted(.number.locale(Locale(identifier: "ar@numbers=arab")))
    }
}
