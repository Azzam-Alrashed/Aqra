import SwiftUI

/// Where the app is: which tab is showing, and a page the home asked the Mushaf to open (and revise).
@MainActor @Observable
final class AppNavigator {
    enum Tab: Hashable { case home, mushaf }

    /// A request for the Mushaf: open a page, and start revising it when `revise` is set.
    struct Request: Equatable {
        var page: Int
        var revise: Bool
        var id = UUID()
    }

    var tab = Tab.home
    var request: Request?

    func open(page: Int, revise: Bool) {
        request = Request(page: page, revise: revise)
        tab = .mushaf
    }
}

/// The app after setup: the home, where the journey and today's wird are, and the Mushaf, for reading and revising.
struct AppTabView: View {
    var store: MushafStore
    var startsMarking = false

    @Environment(MemorizationStore.self) private var memorization
    @Environment(RevisionStore.self) private var revision
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigator = AppNavigator()

    var body: some View {
        TabView(selection: $navigator.tab) {
            HomeView(store: store)
                .tag(AppNavigator.Tab.home)
                .tabItem { Label("Home", systemImage: "house") }
            MushafView(store: store, startsMarking: startsMarking)
                .tag(AppNavigator.Tab.mushaf)
                .tabItem { Label("Mushaf", systemImage: "book") }
        }
        .tint(OnboardingPalette.brand)
        .environment(navigator)
        .onAppear { if startsMarking { navigator.tab = .mushaf } }
        // Today's plan is made (or kept) whenever the app comes back and whenever what's memorized changes.
        .task { refreshPlan() }
        .onChange(of: memorization.count) { refreshPlan() }
        .onChange(of: scenePhase) { if scenePhase == .active { refreshPlan() } }
    }

    private func refreshPlan() {
        revision.refreshPlan(memorizedPages: RevisionStore.memorizedPages(in: store, memorization: memorization))
    }
}

/// The home: where the student is on the journey (the منازل stairs), and what they have today (the wird).
struct HomeView: View {
    var store: MushafStore

    @Environment(MemorizationStore.self) private var memorization
    @Environment(RevisionStore.self) private var revision
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownClimb = 0.0
    @State private var editingMemorization = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    greeting
                    journey
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
            .toolbar(.hidden, for: .navigationBar)
        }
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .onAppear { climb(entrance: true) }
        .onChange(of: memorization.count) { climb(entrance: false) }
        .sheet(isPresented: $editingMemorization) {
            MemorizationSetupView(store: store, isSheet: true) { _ in editingMemorization = false }
        }
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

    private func climb(entrance: Bool) {
        let target = memorization.quranShare(in: store) * Double(ManazilStairs.stepCount)
        guard !reduceMotion else {
            shownClimb = target
            return
        }
        withAnimation(entrance ? .spring(duration: 1.4, bounce: 0.1).delay(0.2) : .spring(duration: 0.9, bounce: 0.15)) {
            shownClimb = target
        }
    }

    private var journey: some View {
        let share = memorization.quranShare(in: store)
        let strength = memorization.averageStrength()
        return VStack(spacing: 16) {
            ManazilStairs(climb: shownClimb)
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
                            navigator.open(page: next.page, revise: true)
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
            navigator.open(page: item.page, revise: !item.done)
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

private typealias Palette = OnboardingPalette
