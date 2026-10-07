import SwiftUI

/// What a listener marked: the pages heard, the ayat stumbled on with their types, and, for a teacher, whether it
/// was a stage test.
struct TasmeeResult: Hashable {
    var pages: [Int]
    var stumbles: [Int]
    var mistakes: [Mistake]
    var test: TasmeeRecord.StageTest?
}

/// Someone hearing a student — a teacher in a session, or a friend with the student's code: the Mushaf on the
/// listener's phone, turned page by page as the student recites. A tap marks an ayah the student stumbled on;
/// pressing and holding one says what kind of mistake it was; each page heard is marked as such; «سجّل التسميع»
/// hands it all to `onRecord`, which writes it into the student's account, where their own app applies it. The
/// listener's own memorization colors are kept off the page: this is the student's page.
struct TasmeeMarkingView<Overlay: View>: View {
    var store: MushafStore
    var studentName: String
    /// Teachers can record a tasmee' as a stage test; friends can't.
    var allowsStageTest = false
    var onRecord: (TasmeeResult) -> Void
    /// Shown over the page's top corner: the student's video in a video session.
    @ViewBuilder var overlay: Overlay

    @Environment(\.dismiss) private var dismiss
    @AppStorage("mushaf.tajweed") private var tajweed = true
    @State private var page: Int
    /// One revision per page visited, fully revealed, so a tap toggles a stumble.
    @State private var pages: [Int: RevisionSession] = [:]
    @State private var heard: Set<Int> = []
    /// The type of each stumble the listener classified; the rest are memorization errors.
    @State private var types: [Int: MistakeType] = [:]
    @State private var classifying: Int?
    @State private var showingIndex = false
    @State private var confirmingLeave = false
    @State private var stageTest: TasmeeRecord.StageTest?

    init(store: MushafStore, studentName: String, startPage: Int, allowsStageTest: Bool = false,
         onRecord: @escaping (TasmeeResult) -> Void, @ViewBuilder overlay: () -> Overlay = { EmptyView() }) {
        self.store = store
        self.studentName = studentName
        self.allowsStageTest = allowsStageTest
        self.onRecord = onRecord
        self.overlay = overlay()
        _page = State(initialValue: min(max(startPage, 1), MushafStore.pageCount))
    }

    var body: some View {
        VStack(spacing: 6) {
            MushafTopBar(page: store.page(page), store: store) {
                FloatingCapsule {
                    HStack(spacing: 0) {
                        Button {
                            leave()
                        } label: {
                            MushafBarIcon("Close", systemImage: "xmark")
                        }
                        Button {
                            showingIndex = true
                        } label: {
                            MushafBarIcon("Index", systemImage: "list.bullet")
                        }
                    }
                }
            } trailing: {
                FloatingCapsule { MushafColorsMenu() }
            }
            pager
                .frame(maxHeight: .infinity)
                .overlay(alignment: .topLeading) { overlay.padding(10) }
            markingBar
        }
        .background(MushafStyle.paper.ignoresSafeArea())
        .interactiveDismissDisabled()
        .onChange(of: page, initial: true) { prepare(page) }
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.impact(weight: .light), trigger: stumbles.count)
        .sheet(isPresented: $showingIndex) {
            MushafIndexView(store: store, currentPage: page) { chosen in
                page = chosen
                showingIndex = false
            }
        }
        .confirmationDialog("What kind of mistake?", isPresented: Binding(get: { classifying != nil }, set: { if !$0 { classifying = nil } }),
                            titleVisibility: .visible, presenting: classifying) { ayah in
            ForEach(MistakeType.allCases, id: \.self) { type in
                Button(type.title) { classify(ayah, as: type) }
            }
            if stumbles.contains(ayah) {
                Button("Not a mistake", role: .destructive) { unmark(ayah) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Leave without recording?", isPresented: $confirmingLeave) {
            Button("Leave", role: .destructive) { dismiss() }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("What you marked will be lost.")
        }
    }

    private var pager: some View {
        TabView(selection: $page) {
            ForEach(1...MushafStore.pageCount, id: \.self) { number in
                MushafPageView(page: store.page(number), store: store)
                    .environment(pages[number])
                    .tag(number)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Page 1 sits on the right; the next page comes in from the left, as in a printed Mushaf.
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.mushafTajweed, tajweed)
        .environment(\.mushafTopics, false)
        .environment(\.mushafAyahLongPress, { ayah in classifying = ayah })
    }

    /// Every page visited gets a revision covering all its ayat, revealed, so taps mark stumbles.
    private func prepare(_ page: Int) {
        guard pages[page] == nil else { return }
        let revision = RevisionSession(page: page, ayahs: Array(store.page(page).ayahs))
        revision.revealAll()
        pages[page] = revision
    }

    private func classify(_ ayah: Int, as type: MistakeType) {
        guard let session = pages.values.first(where: { $0.covers(ayah) }) else { return }
        session.markStumble(ayah)
        types[ayah] = type
    }

    private func unmark(_ ayah: Int) {
        for session in pages.values where session.covers(ayah) { session.clearStumble(ayah) }
        types[ayah] = nil
    }

    // MARK: - What's been marked

    /// The ayat stumbled on, over every page.
    private var stumbles: Set<Int> {
        pages.values.reduce(into: Set<Int>()) { $0.formUnion($1.stumbles) }
    }

    /// The pages heard: marked as such, or with a stumble on them.
    private var recorded: Set<Int> {
        heard.union(pages.filter { !$0.value.stumbles.isEmpty }.keys)
    }

    private var markingBar: some View {
        let onThisPage = pages[page]?.stumbles.count ?? 0
        let pageHeard = recorded.contains(page)
        return FloatingPanel {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: studentName)
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(MushafStyle.ink)
                            .lineLimit(1)
                        TasmeeFormat.counts(pages: recorded.count, stumbles: stumbles.count)
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(MushafStyle.chrome)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    if onThisPage > 0 {
                        Text("\(onThisPage) stumbles")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(light: 0x9A3E26, dark: 0xF6C9B8))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(MushafStyle.stumble.opacity(0.6), in: Capsule())
                            .transition(.scale.combined(with: .opacity))
                    }
                    if allowsStageTest {
                        stageTestMenu
                    }
                }
                Text("Tap an ayah the student stumbled on, press and hold it to say what kind, and mark each page you heard.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(MushafStyle.chrome)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 10) {
                    Button {
                        if heard.contains(page) { heard.remove(page) } else { heard.insert(page) }
                    } label: {
                        Label(pageHeard ? "Heard" : "Mark as heard", systemImage: pageHeard ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(MarkingButtonStyle())
                    .disabled(pageHeard && onThisPage > 0)
                    Button("Record tasmee'") { finish() }
                        .buttonStyle(MarkingButtonStyle(prominent: true))
                        .disabled(recorded.isEmpty)
                }
            }
        }
        .animation(.snappy, value: onThisPage)
        .animation(.snappy, value: pageHeard)
        .animation(.snappy, value: stageTest)
        .environment(\.layoutDirection, .rightToLeft)
    }

    /// A teacher can count this tasmee' as the test of a stage, with the mistakes allowed per page heard.
    private var stageTestMenu: some View {
        Menu {
            Picker("Stage test", selection: Binding(get: { stageTest?.stage ?? 0 }, set: { stage in
                stageTest = stage == 0 ? nil : TasmeeRecord.StageTest(
                    stage: stage, allowedMistakesPerPage: stageTest?.allowedMistakesPerPage ?? StagePolicy.standard.allowedMistakesPerPage)
            })) {
                Text("Not a test").tag(0)
                ForEach(1...Curriculum.stageCount, id: \.self) { stage in
                    Text("Stage \(stage)").tag(stage)
                }
            }
            if let test = stageTest {
                Picker("Mistakes allowed per page", selection: Binding(get: { test.allowedMistakesPerPage }, set: {
                    stageTest?.allowedMistakesPerPage = $0
                })) {
                    ForEach(0...3, id: \.self) { Text("\($0) mistakes per page").tag($0) }
                }
            }
        } label: {
            Group {
                if let test = stageTest {
                    Text("Stage \(test.stage) test")
                } else {
                    Text("Stage test")
                }
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(stageTest == nil ? MushafStyle.barAccent : .white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(stageTest == nil ? MushafStyle.barAccentFill : OnboardingPalette.brand, in: Capsule())
        }
    }

    private func leave() {
        if recorded.isEmpty {
            dismiss()
        } else {
            confirmingLeave = true
        }
    }

    /// Hands the tasmee' over to be recorded (queued if offline) and closes.
    private func finish() {
        let stumbles = stumbles.sorted()
        let mistakes = stumbles.map { Mistake(ayah: $0, type: types[$0] ?? .memorization) }
        onRecord(TasmeeResult(pages: recorded.sorted(), stumbles: stumbles, mistakes: mistakes, test: stageTest))
        dismiss()
    }
}

extension MistakeType {
    var title: LocalizedStringKey {
        switch self {
        case .memorization: "Memorization error"
        case .forgetting: "Forgot"
        case .prompting: "Needed prompting"
        case .hesitation: "Hesitated"
        case .lahn: "Clear error (لحن جلي)"
        case .tajweed: "Tajweed"
        }
    }
}
