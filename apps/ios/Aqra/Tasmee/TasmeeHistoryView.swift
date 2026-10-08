import SwiftUI

/// Every tasmee' others heard from the student: teachers and friends, newest first.
struct TasmeeHistoryView: View {
    var store: MushafStore

    @Environment(TasmeeStore.self) private var tasmee

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Every tasmee'")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                let verified = tasmee.history.filter { $0.kind == .sheikh }
                HStack(spacing: 10) {
                    stat(icon: "🎓", tint: Palette.mint, value: verified.count.formatted(), label: Text("With a teacher"))
                    stat(icon: "🤝", tint: Palette.peach, value: (tasmee.history.count - verified.count).formatted(),
                         label: Text("With a friend"))
                    stat(icon: "📖", tint: Palette.sky, value: Set(tasmee.history.flatMap(\.pages)).count.formatted(),
                         label: Text("Pages heard"))
                }
                AqraCard(padding: 0, radius: 24) {
                    VStack(spacing: 0) {
                        ForEach(Array(tasmee.history.enumerated()), id: \.element.id) { index, record in
                            if index > 0 { AqraRowDivider() }
                            TasmeeRecordRow(record: record, store: store)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Palette.surface.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
    }

    private func stat(icon: String, tint: Color, value: String, label: Text) -> some View {
        AqraCard(padding: 12, radius: 20) {
            VStack(alignment: .leading, spacing: 8) {
                IconTile(icon: icon, tint: tint, size: 32)
                Text(verbatim: value)
                    .font(.system(size: 20, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                label
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One tasmee' in a list: who heard it, when, how much and how it went. Tapping it opens the details.
struct TasmeeRecordRow: View {
    var record: TasmeeRecord
    var store: MushafStore
    /// Whether to name the listener (not in the teacher's own file on a student).
    var showsListener = true
    @State private var showingDetails = false

    var body: some View {
        Button {
            showingDetails = true
        } label: {
            AqraRow(icon: record.kind == .peer ? "🤝" : "🎓", tint: record.kind == .peer ? Palette.peach : Palette.mint,
                    title: title, detail: detail) {
                if let passed = record.passesTest {
                    Text(passed ? "Passed" : "Not yet")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(passed ? Color(light: 0x1F7A4D, dark: 0x1F7A4D) : Color(light: 0x9A3E26, dark: 0x9A3E26))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(passed ? Palette.mint : Palette.rose, in: Capsule())
                } else {
                    AqraChevron()
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetails) {
            TasmeeRecordDetails(record: record, store: store, showsListener: showsListener)
        }
    }

    private var title: Text {
        if let test = record.test {
            return Text("Stage \(test.stage) test")
        }
        if showsListener {
            return record.teacherName.isEmpty ? Text("A friend") : Text(verbatim: record.teacherName)
        }
        return Text(verbatim: record.at.formatted(date: .abbreviated, time: .omitted))
    }

    private var detail: Text {
        let counts = TasmeeFormat.counts(pages: Set(record.pages).count, stumbles: record.stumbles.count)
        guard showsListener || record.test != nil else { return counts }
        return Text(verbatim: record.at.formatted(.relative(presentation: .named))) + Text(verbatim: " · ") + counts
    }
}

/// A tasmee' in full: the pages heard, and each stumble with its surah, ayah and kind.
struct TasmeeRecordDetails: View {
    var record: TasmeeRecord
    var store: MushafStore
    var showsListener = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        if let test = record.test {
                            Text("Stage \(test.stage) test")
                        } else if record.kind == .peer {
                            Text("Tasmee' with a friend")
                        } else {
                            Text("Tasmee' with a teacher")
                        }
                    }
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                    Group {
                        if showsListener && !record.teacherName.isEmpty {
                            Text(verbatim: record.teacherName + " · " + TasmeeFormat.when(record.at))
                        } else {
                            Text(verbatim: TasmeeFormat.when(record.at))
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                }
                .padding(.top, 20)

                if let test = record.test, let passed = record.passesTest {
                    AqraCard(padding: 14, radius: 24) {
                        HStack(spacing: 12) {
                            IconTile(icon: passed ? "🏅" : "🌱", tint: passed ? Palette.butter : Palette.mint, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(passed ? "The test was passed" : "Not passed yet")
                                    .font(.system(size: 16, weight: .heavy))
                                    .foregroundStyle(Palette.ink)
                                Text("\(record.stumbles.count) mistakes, \(test.allowedMistakesPerPage) allowed per page heard")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Palette.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                AqraSectionTitle(title: "Pages heard")
                AqraCard(padding: 14, radius: 24) {
                    Text(verbatim: pagesLine)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !record.stumbles.isEmpty {
                    AqraSectionTitle(title: "Stumbles").padding(.top, 6)
                    AqraCard(padding: 0, radius: 24) {
                        VStack(spacing: 0) {
                            ForEach(Array(record.stumbles.enumerated()), id: \.element) { index, ayah in
                                if index > 0 { AqraRowDivider() }
                                let reference = store.reference(ofAyah: ayah)
                                AqraRow(icon: "🎯", tint: Palette.rose,
                                        title: Text(verbatim: "\(store.surahNames[reference.surah] ?? "") \(arabic(reference.ayah))"),
                                        detail: Text(record.mistakeType(of: ayah).title)) { EmptyView() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .environment(\.colorScheme, .light)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// «البقرة: ٢–٣ · آل عمران: ٥٠»: the pages heard, grouped by the surah each starts in.
    private var pagesLine: String {
        let pages = Set(record.pages).sorted()
        var groups: [(surah: Int, pages: [Int])] = []
        for page in pages {
            let surah = store.page(page).surah
            if groups.last?.surah == surah, groups.last?.pages.last == page - 1 {
                groups[groups.count - 1].pages.append(page)
            } else {
                groups.append((surah, [page]))
            }
        }
        return groups.map { group in
            let range = group.pages.count > 1 ? "\(arabic(group.pages.first!))–\(arabic(group.pages.last!))" : arabic(group.pages[0])
            return "\(store.surahNames[group.surah] ?? ""): \(range)"
        }.joined(separator: " · ")
    }

    private func arabic(_ number: Int) -> String {
        number.formatted(.number.locale(Locale(identifier: "ar@numbers=arab")))
    }
}

private typealias Palette = OnboardingPalette
