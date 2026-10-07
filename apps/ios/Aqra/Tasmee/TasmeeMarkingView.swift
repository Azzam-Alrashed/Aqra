import SwiftUI

/// A teacher hearing a student: the Mushaf on the teacher's phone, turned page by page as the student recites.
/// A tap marks an ayah the student stumbled on; each page heard is marked as such; «تم» records it all into the
/// student's account, where their own app applies it. The teacher's own memorization colors are kept off the
/// page: this is the student's page.
struct TasmeeMarkingView: View {
    var store: MushafStore
    var session: TasmeeSession
    var seat: Seat

    @Environment(TasmeeStore.self) private var tasmee
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mushaf.tajweed") private var tajweed = true
    @State private var page: Int
    /// One revision per page visited, fully revealed, so a tap toggles a stumble.
    @State private var pages: [Int: RevisionSession] = [:]
    @State private var heard: Set<Int> = []
    @State private var showingIndex = false
    @State private var confirmingLeave = false

    init(store: MushafStore, session: TasmeeSession, seat: Seat) {
        self.store = store
        self.session = session
        self.seat = seat
        // Open where the student's memorization begins, if they said: the first page of their first whole juz'.
        let firstJuz = seat.juzSummary?.split(separator: ",").first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        _page = State(initialValue: firstJuz.flatMap { store.juzStartPages[$0] } ?? 1)
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
    }

    /// Every page visited gets a revision covering all its ayat, revealed, so taps mark stumbles.
    private func prepare(_ page: Int) {
        guard pages[page] == nil else { return }
        let revision = RevisionSession(page: page, ayahs: Array(store.page(page).ayahs))
        revision.revealAll()
        pages[page] = revision
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
                        Text(verbatim: seat.name)
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(MushafStyle.ink)
                            .lineLimit(1)
                        Text("\(recorded.count) pages · \(stumbles.count) stumbles")
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
                }
                Text("Tap an ayah the student stumbled on, and mark each page you heard.")
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
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func leave() {
        if recorded.isEmpty {
            dismiss()
        } else {
            confirmingLeave = true
        }
    }

    /// Records the tasmee' into the student's account (queued if offline) and closes.
    private func finish() {
        tasmee.recordTasmee(for: seat.id, in: session, pages: recorded.sorted(), stumbles: stumbles.sorted())
        dismiss()
    }
}
