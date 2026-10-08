import SwiftUI

/// Memorizing today's portion: its pages, with the portion standing out and the rest faded back. The student reads
/// and repeats it, hides ayat to recite them from memory, then «حفظته» starts its life in the revision engine — or
/// «حفظت جزءًا منه» and a tap on the last ayah memorized records just that part.
struct MemorizeView: View {
    var store: MushafStore
    var portion: [Int]

    @Environment(PlanStore.self) private var plan
    @Environment(MemorizationStore.self) private var memorization
    @Environment(RevisionStore.self) private var revision
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mushaf.tajweed") private var tajweed = true
    @State private var focus: MemorizeFocus
    @State private var page: Int
    @State private var repetitions = 0

    init(store: MushafStore, portion: [Int]) {
        self.store = store
        self.portion = portion
        _focus = State(initialValue: MemorizeFocus(portion: portion))
        _page = State(initialValue: portion.first.map { store.page(ofAyah: $0) } ?? 1)
    }

    /// The portion's pages, in Mushaf order.
    private var pages: [Int] {
        var pages = Set<Int>()
        for ayah in portion {
            let first = store.page(ofAyah: ayah)
            pages.insert(first)
            if first < MushafStore.pageCount, store.page(first + 1).ayahs.lowerBound == ayah { pages.insert(first + 1) }
        }
        return pages.sorted()
    }

    var body: some View {
        VStack(spacing: 6) {
            MushafTopBar(page: store.page(page), store: store) {
                FloatingCapsule {
                    Button {
                        dismiss()
                    } label: {
                        MushafBarIcon("Close", systemImage: "xmark")
                    }
                }
            } trailing: {
                FloatingCapsule { MushafColorsMenu() }
            }
            TabView(selection: $page) {
                ForEach(pages, id: \.self) { number in
                    MushafPageView(page: store.page(number), store: store)
                        .tag(number)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.mushafTajweed, tajweed)
            .environment(\.mushafTopics, false)
            .environment(\.mushafFocus, focus)
            .frame(maxHeight: .infinity)
            bar
        }
        .background(MushafStyle.paper.ignoresSafeArea())
        .followsSystemColorScheme()
        .interactiveDismissDisabled()
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.impact(weight: .light), trigger: repetitions)
        .sensoryFeedback(.selection, trigger: focus.hidden)
    }

    private var bar: some View {
        FloatingPanel {
            VStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text(verbatim: PlanFormat.portion(portion, store: store))
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(MushafStyle.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Group {
                        if focus.choosingEnd {
                            Text("Tap the last ayah you memorized")
                        } else {
                            Text("Read it and repeat it, then tap an ayah to hide it and recite it from memory")
                        }
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(MushafStyle.chrome)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                if focus.choosingEnd {
                    HStack(spacing: 10) {
                        Button("Cancel") { withAnimation(.snappy) { focus.choosingEnd = false } }
                            .buttonStyle(MarkingButtonStyle())
                        Button("Save this part") { record(focus.memorizedPart) }
                            .buttonStyle(MarkingButtonStyle(prominent: true))
                            .disabled(focus.memorizedPart.isEmpty)
                    }
                } else {
                    HStack(spacing: 10) {
                        Button {
                            repetitions += 1
                        } label: {
                            Label {
                                Text(verbatim: repetitions.formatted())
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                            } icon: {
                                Image(systemName: "repeat")
                            }
                        }
                        .buttonStyle(MarkingButtonStyle())
                        .accessibilityLabel(Text("Repetitions: \(repetitions)"))
                        .contextMenu { Button("Start counting again") { repetitions = 0 } }
                        Button(focus.hidden.count == focus.ayahs.count ? "Show all" : "Hide all") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                if focus.hidden.count == focus.ayahs.count { focus.showAll() } else { focus.hideAll() }
                            }
                        }
                        .buttonStyle(MarkingButtonStyle())
                    }
                    HStack(spacing: 10) {
                        Button("Only part of it") { withAnimation(.snappy) { focus.choosingEnd = true } }
                            .buttonStyle(MarkingButtonStyle())
                        Button("I memorized it") { record(portion) }
                            .buttonStyle(MarkingButtonStyle(prominent: true))
                    }
                }
            }
        }
        .animation(.snappy, value: focus.choosingEnd)
        .animation(.snappy, value: repetitions)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func record(_ memorized: [Int]) {
        plan.record(planned: portion, memorized: memorized, store: store, memorization: memorization, revision: revision)
        dismiss()
    }
}
