import SwiftUI

/// The home, the app's root: where the student is on the journey (the منازل stairs), the Mushaf where they left
/// it, and what they have today (the wird). The Mushaf and the wird open full screen over it and close back to it.
struct HomeView: View {
    var store: MushafStore
    /// Opens straight into the Mushaf's marking mode (after the student chose to mark pages and ayat).
    var startsMarking = false

    /// What the home has open over it.
    enum Destination: Hashable, Identifiable {
        case mushaf(marking: Bool)
        /// Today's wird, from one of its pages.
        case wird(page: Int)

        var id: Self { self }

        /// The view on the home it grows from and shrinks back into.
        var sourceID: String {
            switch self {
            case .mushaf: "mushaf"
            case .wird(let page): "page-\(page)"
            }
        }
    }

    @Environment(MemorizationStore.self) private var memorization
    @Environment(RevisionStore.self) private var revision
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mushaf.lastPage") private var lastPage = 1
    @State private var shownClimb = 0.0
    @State private var climbAnimation: Animation?
    @State private var editingMemorization = false
    @State private var destination: Destination?
    @State private var openedMarking = false
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    greeting
                    journey
                    mushaf
                    wird
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Palette.surface.ignoresSafeArea())
            // What scrolls up fades away under the status bar instead of running into it.
            .overlay(alignment: .top) {
                GeometryReader { geometry in
                    LinearGradient(colors: [Palette.surface, Palette.surface.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: geometry.safeAreaInsets.top + 14)
                        .offset(y: -geometry.safeAreaInsets.top)
                }
                .allowsHitTesting(false)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .onAppear {
            climb(entrance: true)
            // After choosing to mark in the Mushaf, the app opens straight on it, with the home underneath.
            if startsMarking && !openedMarking {
                openedMarking = true
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { destination = .mushaf(marking: true) }
            }
        }
        .onChange(of: memorization.count) { climb(entrance: false) }
        // Today's plan is made (or kept) whenever the app comes back and whenever what's memorized changes.
        .task { refreshPlan() }
        .onChange(of: memorization.count) { refreshPlan() }
        .onChange(of: scenePhase) { if scenePhase == .active { refreshPlan() } }
        .sensoryFeedback(.success, trigger: revision.plan?.isComplete == true) { _, isComplete in isComplete }
        .sheet(isPresented: $editingMemorization) {
            MemorizationSetupView(store: store, isSheet: true) { _ in editingMemorization = false }
        }
        .fullScreenCover(item: $destination) { destination in
            Group {
                switch destination {
                case .mushaf(let marking):
                    MushafView(store: store, startsMarking: marking)
                case .wird(let page):
                    WirdView(store: store, startPage: page)
                }
            }
            .zoomTransition(sourceID: destination.sourceID, in: zoom)
        }
    }

    private func refreshPlan() {
        revision.refreshPlan(memorizedPages: RevisionStore.memorizedPages(in: store, memorization: memorization))
    }

    // MARK: - Greeting

    private var greeting: some View {
        var hijri = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).year()
        hijri.calendar = Calendar(identifier: .islamicUmmAlQura)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Peace be upon you")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Palette.ink)
            Text(Date.now.formatted(hijri))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The journey

    /// Moves the stairs to what's memorized. The animation is the stairs' own: in a `withAnimation`, the rest of
    /// the home's first layout would be animated with it, its text sliding in glyph by glyph.
    private func climb(entrance: Bool) {
        climbAnimation = reduceMotion ? nil : entrance ? .spring(duration: 1.4, bounce: 0.1).delay(0.2) : .spring(duration: 0.9, bounce: 0.15)
        shownClimb = memorization.quranShare(in: store) * Double(ManazilStairs.stepCount)
    }

    private var journey: some View {
        let share = memorization.quranShare(in: store)
        let strength = memorization.averageStrength()
        return VStack(spacing: 16) {
            ManazilStairs(climb: shownClimb)
                .animation(climbAnimation, value: shownClimb)
                .frame(height: 130)
            if memorization.count == 0 {
                Text("Choose what you've memorized to start climbing")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: share.formatted(.percent.precision(.fractionLength(0...1))))
                            .font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(Palette.brand)
                            .contentTransition(.numericText(value: share))
                        Text("of the Quran")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Palette.ink)
                    }
                    Spacer()
                    if let strength {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: strength.formatted(.percent.precision(.fractionLength(0))))
                                .font(.system(size: 20, weight: .heavy))
                                .foregroundStyle(Palette.ink)
                            Text("Memorization strength")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.inkSoft)
                        }
                    }
                }
            }
            Button {
                editingMemorization = true
            } label: {
                Label(memorization.count == 0 ? "Choose what you've memorized" : "Edit what you've memorized",
                      systemImage: "square.and.pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.brand)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(Palette.lavender, in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: memorization.count == 0 ? .center : .leading)
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Palette.shadow.opacity(0.06), radius: 14, y: 6)
    }

    // MARK: - The Mushaf

    /// The Mushaf, open on the page last read: its miniature grows into the full page.
    private var mushaf: some View {
        let page = store.page(lastPage)
        return Button {
            destination = .mushaf(marking: false)
        } label: {
            HStack(spacing: 14) {
                MushafThumbnail(page: page, store: store)
                    .frame(width: 58, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(MushafStyle.chrome.opacity(0.25), lineWidth: 1))
                    .shadow(color: Palette.shadow.opacity(0.12), radius: 6, y: 3)
                    .zoomTransitionSource(id: Destination.mushaf(marking: false).sourceID, in: zoom)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mushaf")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                    Text(verbatim: store.surahNames[page.surah] ?? "")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: 6) {
                        Text("Juz' \(page.juz)")
                        Text(verbatim: "·")
                        Text("Page \(page.number)")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Palette.brand)
                    .frame(width: 34, height: 34)
                    .background(Palette.lavender, in: Circle())
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Palette.shadow.opacity(0.06), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Today's wird

    @ViewBuilder
    private var wird: some View {
        if let plan = revision.plan, !plan.items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                wirdHeader(plan)
                VStack(spacing: 10) {
                    ForEach(plan.items) { item in
                        card(item)
                    }
                }
                if !plan.isComplete {
                    BrandButton(plan.doneCount == 0 ? "Start today's revision" : "Continue today's revision",
                                metrics: OnboardingButtonMetrics(height: 54, fontSize: 17, compact: false)) {
                        if let next = plan.items.first(where: { !$0.done }) {
                            destination = .wird(page: next.page)
                        }
                    }
                    Text("Revised a page outside the app? Press and hold it.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                }
                amountRow
            }
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Palette.shadow.opacity(0.06), radius: 14, y: 6)
        }
    }

    private func wirdHeader(_ plan: DayPlan) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(plan.isComplete ? "Today's revision is done" : "Today's revision")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                Text("\(plan.doneCount) of \(plan.items.count)")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.inkSoft)
                    .contentTransition(.numericText())
            }
            Spacer()
            ZStack {
                Circle().stroke(Palette.lavender, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: Double(plan.doneCount) / Double(plan.items.count))
                    .stroke(LinearGradient(colors: [Palette.brand, Palette.brandDeep], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if plan.isComplete {
                    StarShape(points: 8, innerRatio: 0.42, cornerRadius: 0.05)
                        .fill(LinearGradient(colors: [Color(light: 0xF8D371, dark: 0xF8D371), Color(light: 0xEFB54A, dark: 0xEFB54A)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 22, height: 22)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 52, height: 52)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: plan.doneCount)
    }

    private func card(_ item: PlanItem) -> some View {
        let page = store.page(item.page)
        let face = ManazilStairs.face(forJuz: page.juz)
        return Button {
            destination = .wird(page: item.page)
        } label: {
            HStack(spacing: 12) {
                Text(item.page.formatted())
                    .font(.system(size: 16, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .frame(width: 48, height: 48)
                    .background(face.top, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: store.surahNames[page.surah] ?? "")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: 6) {
                        Text("Juz' \(page.juz)")
                        Text(item.kind == .followUp ? "Follow-up" : "Rotation")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(item.kind == .followUp ? Color(light: 0x9A3E26, dark: 0x9A3E26) : Palette.brand)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(item.kind == .followUp ? Color(light: 0xFCE3DA, dark: 0xFCE3DA) : Palette.lavender, in: Capsule())
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 8)
                Image(systemName: item.done ? "checkmark" : "chevron.forward")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(item.done ? .white : Palette.inkSoft)
                    .frame(width: 34, height: 34)
                    .background(item.done ? face.bottom : Palette.surface, in: Circle())
            }
            .padding(10)
            .background(item.done ? Palette.surface : .white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.lavender, lineWidth: item.done ? 0 : 1.2))
            .zoomTransitionSource(id: Destination.wird(page: item.page).sourceID, in: zoom)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !item.done {
                Button {
                    let ayahs = store.page(item.page).ayahs.filter { memorization.isMemorized($0) }
                    revision.record(page: item.page, ayahs: ayahs, stumbles: [], source: .outside, memorization: memorization)
                } label: {
                    Label("Revised outside the app", systemImage: "checkmark.circle")
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: item.done)
    }

    private var amountRow: some View {
        let memorizedPages = RevisionStore.memorizedPages(in: store, memorization: memorization).count
        let amount = revision.effectiveDailyPages(memorizedPages: memorizedPages)
        return NavigationLink {
            DailyAmountView(memorizedPages: memorizedPages, initial: amount, isEditor: true) { revision.setDailyPages($0) }
                .toolbar(.visible, for: .navigationBar)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(amount) pages a day")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text("A full revision every \(DailyAmountView.cycleDays(memorizedPages: memorizedPages, amount: amount)) days")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.inkSoft)
            }
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
    }
}

/// A miniature of a Mushaf page: the real page, drawn at a phone's size and scaled down.
private struct MushafThumbnail: View {
    var page: MushafPage
    var store: MushafStore
    private static let drawnSize = CGSize(width: 380, height: 600)

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / Self.drawnSize.width, geometry.size.height / Self.drawnSize.height)
            MushafPageView(page: page, store: store)
                .frame(width: Self.drawnSize.width, height: Self.drawnSize.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .background(MushafStyle.paper)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Opens a full-screen view by growing it out of the view it was opened from (iOS 18 and later).
    @ViewBuilder
    func zoomTransition(sourceID: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }

    /// Marks the view a zoom transition grows from and shrinks back into.
    @ViewBuilder
    func zoomTransitionSource(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}

private typealias Palette = OnboardingPalette
