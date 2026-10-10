import GoogleSignIn
import SwiftUI

/// The Mushaf, opened full screen from the home on the last page read, and turned like a book (right to left).
/// On a wide iPad it shows two facing pages, odd on the right, as in the printed Madinah Mushaf.
struct MushafView: View {
    var store: MushafStore
    /// Opens straight into marking mode (after the student chose to mark pages and ayat).
    var startsMarking = false

    @Environment(MemorizationStore.self) private var memorization
    @Environment(ReadingStore.self) private var reading
    @Environment(\.dismiss) private var dismiss
    /// The app's own direction, for the bars' lines of text inside their Mushaf-ordered (right-to-left) layout.
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage("mushaf.lastPage") private var lastPage = 1
    @AppStorage("mushaf.tajweed") private var tajweed = true
    @AppStorage("mushaf.topics") private var topicColors = true
    @State private var toolbarVisible = false
    @State private var showingIndex = false
    /// The page shown while the slider is being dragged; committed to `lastPage` on release.
    @State private var sliderPage: Double?
    /// Set when the toolbar itself moves the page, so the toolbar stays open.
    @State private var movedByToolbar = false
    /// Marking mode, while the student marks the ayat they've memorized.
    @State private var marking: MarkingSession?
    @State private var showingSetup = false
    /// What the ribbon button just did, shown for a moment above the bottom bar.
    @State private var ribbonNotice: RibbonNotice?

    var body: some View {
        GeometryReader { geometry in
            let facingPages = geometry.size.width > geometry.size.height && geometry.size.width >= 900
            ZStack {
                Group {
                    if facingPages {
                        spreadPager
                    } else {
                        pagePager
                    }
                }
                .environment(\.mushafTajweed, tajweed)
                .environment(\.mushafTopics, topicColors)
                .environment(marking)
                .onTapGesture {
                    // In marking mode, taps belong to the page and the toolbar stays.
                    guard marking == nil else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { toolbarVisible.toggle() }
                }

                VStack(spacing: 0) {
                    if toolbarVisible {
                        topBar.transition(.opacity)
                    }
                    Spacer()
                    if toolbarVisible, marking == nil, let ribbonNotice {
                        ribbonPanel(ribbonNotice)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if toolbarVisible {
                        Group {
                            if let marking {
                                markingBar(marking, pages: facingPages ? spreadPages : [lastPage])
                            } else {
                                bottomBar
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
        .background(MushafStyle.paper.ignoresSafeArea())
        .followsSystemColorScheme()
        .statusBarHidden(!toolbarVisible)
        // Swiping down closes the Mushaf, but not while marking, where a stray swipe would lose the place.
        .interactiveDismissDisabled(marking != nil)
        .animation(.easeInOut(duration: 0.2), value: toolbarVisible)
        // Swiping to another page hides the toolbar; jumps made from the toolbar keep it open.
        .onChange(of: lastPage) {
            if movedByToolbar {
                movedByToolbar = false
            } else if toolbarVisible && marking == nil {
                withAnimation(.easeInOut(duration: 0.2)) { toolbarVisible = false }
            }
        }
        .onAppear {
            if startsMarking && marking == nil { startMarking() }
        }
        // A light tick as each page turns, and a firmer one on entering a new juz'.
        .sensoryFeedback(.selection, trigger: lastPage)
        .sensoryFeedback(.impact(weight: .medium), trigger: store.page(lastPage).juz)
        // A soft tap as ayat are marked or unmarked.
        .sensoryFeedback(.impact(weight: .light), trigger: memorization.count) { _, _ in marking != nil }
        .sheet(isPresented: $showingSetup) {
            MemorizationSetupView(store: store, isSheet: true) { _ in showingSetup = false }
                .environment(memorization)
        }
        .sheet(isPresented: $showingIndex) {
            MushafIndexView(store: store, currentPage: lastPage) { page in
                movedByToolbar = page != lastPage
                lastPage = page
                showingIndex = false
            }
        }
    }

    // MARK: - Pagers

    private var pagePager: some View {
        TabView(selection: $lastPage) {
            ForEach(1...MushafStore.pageCount, id: \.self) { number in
                MushafPageView(page: store.page(number), store: store)
                    .overlay(alignment: .top) {
                        if reading.bookmark?.page == number { MushafRibbon(page: number) }
                    }
                    .tag(number)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Page 1 sits on the right; the next page comes in from the left, as in a printed Mushaf.
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var spreadPager: some View {
        // Only a turn to another spread moves the page, so the left (even) page survives rotation.
        let spread = Binding<Int>(
            get: { (lastPage + 1) / 2 },
            set: { if $0 != (lastPage + 1) / 2 { lastPage = $0 * 2 - 1 } }
        )
        return TabView(selection: spread) {
            ForEach(1...(MushafStore.pageCount / 2), id: \.self) { number in
                MushafSpreadView(spread: number, store: store, bookmark: reading.bookmark?.page)
                    .tag(number)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, .rightToLeft)
    }

    // MARK: - Marking

    /// The pages of the spread on screen, odd on the right.
    private var spreadPages: [Int] {
        let first = ((lastPage + 1) / 2) * 2 - 1
        return [first, first + 1]
    }

    private func startMarking() {
        withAnimation(.easeInOut(duration: 0.2)) {
            marking = MarkingSession(memorization: memorization)
            toolbarVisible = true
        }
    }

    private func markingBar(_ marking: MarkingSession, pages: [Int]) -> some View {
        let ayahs = store.page(pages.first ?? lastPage).ayahs.lowerBound...store.page(pages.last ?? lastPage).ayahs.upperBound
        return FloatingPanel {
            VStack(spacing: 14) {
                VStack(spacing: 3) {
                    MushafModeChip(mode: .marking)
                        .padding(.bottom, 4)
                    // While a range waits for its first or last ayah, the bar says so.
                    Group {
                        if marking.choosingRangeStart {
                            Text("Tap the first ayah of the range")
                        } else if marking.rangeStart != nil {
                            Text("Now tap the last ayah of the range")
                        } else {
                            Text("Tap the ayat you've memorized")
                        }
                    }
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(MushafStyle.ink)
                    if marking.unmarked.isEmpty {
                        (Text("\(memorization.count) ayat memorized")
                            + (marking.choosingRangeStart || marking.rangeStart != nil ? Text(verbatim: "")
                               : Text(verbatim: Separator.facts) + Text("or mark from one ayah to another with «Select a range»")))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(MushafStyle.chrome)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    } else {
                        // An unmarked ayah loses its record; for a moment it can be brought back as it was.
                        HStack(spacing: 10) {
                            Text("Unmarked \(marking.unmarked.count) ayat")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(MushafStyle.chrome)
                                .lineLimit(1)
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { marking.undo() }
                            } label: {
                                Label("Undo", systemImage: "arrow.uturn.backward")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(MushafStyle.barAccent)
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 26)
                                    .background(MushafStyle.barAccentFill, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .environment(\.layoutDirection, layoutDirection)
                        .transition(.opacity)
                        .task(id: marking.unmarkedVersion) {
                            let version = marking.unmarkedVersion
                            try? await Task.sleep(for: .seconds(6))
                            guard !Task.isCancelled else { return }
                            withAnimation(.easeInOut(duration: 0.2)) { marking.expireUndo(version: version) }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: marking.rangeStart)
                .animation(.easeInOut(duration: 0.2), value: marking.choosingRangeStart)
                .animation(.easeInOut(duration: 0.2), value: marking.unmarked.isEmpty)
                HStack(spacing: 10) {
                    let choosing = marking.choosingRangeStart || marking.rangeStart != nil
                    Button(choosing ? "Cancel the range" : "Select a range") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if choosing { marking.cancelRange() } else { marking.chooseRange() }
                        }
                    }
                    .buttonStyle(MarkingButtonStyle())
                    Button(pages.count > 1 ? "Both pages" : "Whole page") { marking.toggle(ayahs) }
                        .buttonStyle(MarkingButtonStyle())
                }
                HStack(spacing: 10) {
                    Button("Juz' & surahs") { showingSetup = true }
                        .buttonStyle(MarkingButtonStyle())
                    Button("Done") {
                        memorization.saveNow()
                        // Marking as part of setup, Done closes the Mushaf: the daily amount and the plan follow.
                        if startsMarking {
                            dismiss()
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) { self.marking = nil }
                        }
                    }
                    .buttonStyle(MarkingButtonStyle(prominent: true))
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    // MARK: - Toolbar

    private var topBar: some View {
        MushafTopBar(page: store.page(lastPage), store: store) {
            FloatingCapsule {
                HStack(spacing: 0) {
                    Button {
                        if marking != nil { memorization.saveNow() }
                        dismiss()
                    } label: {
                        MushafBarIcon("Home", systemImage: "house.fill")
                    }
                    Button {
                        showingIndex = true
                    } label: {
                        MushafBarIcon("Index", systemImage: "list.bullet")
                    }
                }
            }
        } trailing: {
            FloatingCapsule {
                HStack(spacing: 0) {
                    Button {
                        if marking == nil { startMarking() } else { marking = nil }
                    } label: {
                        MushafBarIcon("My memorization", systemImage: marking == nil ? "checkmark.seal" : "checkmark.seal.fill")
                    }
                    MushafColorsMenu()
                }
            }
        }
    }

    private var bottomBar: some View {
        // Dragging only moves the number; the Mushaf turns once, to the page you let go on.
        let position = Binding<Double>(
            get: { sliderPage ?? Double(lastPage) },
            set: { sliderPage = $0 }
        )
        return FloatingCapsule {
            HStack(spacing: 12) {
                Text(verbatim: arabic(Int(position.wrappedValue.rounded())))
                    .font(.system(size: 16, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(MushafStyle.barAccent)
                    .frame(minWidth: 40)
                    .padding(.vertical, 6)
                    .background(MushafStyle.barAccentFill, in: Capsule())
                Slider(value: position, in: 1...Double(MushafStore.pageCount), step: 1) { editing in
                    guard !editing, let target = sliderPage else { return }
                    let page = Int(target.rounded())
                    movedByToolbar = page != lastPage
                    lastPage = page
                    sliderPage = nil
                }
                .tint(MushafStyle.barAccent)
                ribbonButton
            }
            .padding(.leading, 4)
            .padding(.trailing, 4)
        }
        .frame(maxWidth: 620)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        // Page 1 at the right end of the slider, matching the direction pages turn.
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func arabic(_ number: Int) -> String {
        number.formatted(.number.locale(Locale(identifier: "ar@numbers=arab")))
    }

    // MARK: - The ribbon

    /// «الفاصل هنا»: places the ribbon on the page shown (the right page of a spread), or takes it away from it.
    private var ribbonButton: some View {
        let here = reading.bookmark?.page == lastPage
        return Button {
            if here {
                reading.remove()
                show(.removed)
            } else {
                reading.place(on: lastPage)
                show(.placed(page: lastPage))
            }
        } label: {
            MushafBarIcon(here ? "Remove the bookmark" : "Bookmark here", systemImage: here ? "bookmark.fill" : "bookmark")
        }
        .sensoryFeedback(.success, trigger: reading.bookmark?.page)
    }

    private func show(_ notice: RibbonNotice) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { ribbonNotice = notice }
    }

    private func ribbonPanel(_ notice: RibbonNotice) -> some View {
        FloatingPanel {
            HStack(spacing: 12) {
                IconTile(icon: "🔖", tint: OnboardingPalette.rose, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    switch notice {
                    case .placed(let page):
                        Text("Bookmark placed at \(store.surahNames[store.page(page).surah] ?? ""), page \(page)")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(MushafStyle.ink)
                        Text("Home opens on it, and browsing or marking never moves it.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(MushafStyle.chrome)
                    case .removed:
                        Text("Bookmark removed")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(MushafStyle.ink)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .environment(\.layoutDirection, layoutDirection)
        }
        .accessibilityElement(children: .combine)
        .task(id: notice) {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, ribbonNotice == notice else { return }
            withAnimation(.easeOut(duration: 0.25)) { ribbonNotice = nil }
        }
    }
}

/// What the ribbon button just did.
private enum RibbonNotice: Hashable {
    case placed(page: Int)
    case removed
}

/// The ribbon (فاصل) hanging from the top of the page it marks, with the page's number. It lies in the page's header
/// band, beside the juz' label, and ends above the first line, so it never covers a word of the page.
struct MushafRibbon: View {
    var page: Int

    var body: some View {
        GeometryReader { geometry in
            ribbon(depth: PageMetrics(size: geometry.size).topInset + PageMetrics.chrome)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your bookmark"))
    }

    private func ribbon(depth: CGFloat) -> some View {
        HStack {
            ZStack(alignment: .bottom) {
                RibbonShape()
                    .fill(LinearGradient(colors: [OnboardingPalette.brand, OnboardingPalette.brandDeep], startPoint: .top, endPoint: .bottom))
                    .frame(width: 30, height: depth)
                    .shadow(color: OnboardingPalette.shadow.opacity(0.25), radius: 6, y: 3)
                Text(verbatim: page.formatted(.number.locale(Locale(identifier: "ar@numbers=arab"))))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .frame(width: 26)
                    .padding(.bottom, 16)
            }
            // Clear of the header's juz' label, and between the top bar's title and its buttons.
            .padding(.leading, 112)
            Spacer(minLength: 0)
        }
    }
}


/// A ribbon's tail: the bottom edge cut in a notch.
private struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 12))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Two facing pages: the odd page on the right and the even page on the left, as in the printed Mushaf.
struct MushafSpreadView: View {
    var spread: Int
    var store: MushafStore
    /// The page the reader's ribbon is on, drawn on whichever of the two it is.
    var bookmark: Int? = nil

    var body: some View {
        HStack(spacing: 0) {
            MushafPageView(page: store.page(spread * 2 - 1), store: store)
                .overlay(alignment: .top) { if bookmark == spread * 2 - 1 { MushafRibbon(page: spread * 2 - 1) } }
            Rectangle().fill(MushafStyle.chrome.opacity(0.18)).frame(width: 1)
            MushafPageView(page: store.page(spread * 2), store: store)
                .overlay(alignment: .top) { if bookmark == spread * 2 { MushafRibbon(page: spread * 2) } }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// Loads the Mushaf once, then shows it — or explains what's missing.
/// Where a student who chose to mark what they've memorized in the Mushaf is in setup: marking, then the daily
/// amount (when they've marked anything), then the plan, as the other path goes. Kept across launches.
enum SetupAfterMarking: String {
    case none, marking, dailyAmount, plan

    static let key = "setup.afterMarking"

    /// The step after the marking.
    @MainActor static func next(memorization: MemorizationStore) -> Self {
        memorization.count > 0 ? .dailyAmount : .plan
    }
}

struct MushafRootView: View {
    @State private var store: Result<MushafStore, Error>?
    @State private var memorization: MemorizationStore
    @State private var revision: RevisionStore
    @State private var plan: PlanStore
    @State private var rewards: RewardStore
    @State private var assessments: AssessmentStore
    @State private var reading: ReadingStore
    /// The account the progress is backed up to.
    @State private var account: AccountStore
    @State private var router = AppRouter()
    @Environment(LaunchState.self) private var launch
    /// Whether the student has said what they've memorized (or that they're just starting).
    @AppStorage("memorization.hasDeclared") private var hasDeclared = false
    @State private var startsMarking = false
    /// After choosing what they've memorized, the student chooses how much to revise each day, then their plan.
    @State private var setupStep = SetupStep.memorized
    /// When they chose to mark it in the Mushaf instead, the same two steps follow the marking.
    @AppStorage(SetupAfterMarking.key) private var afterMarking = SetupAfterMarking.none
    @Environment(\.scenePhase) private var scenePhase

    private enum SetupStep { case memorized, dailyAmount, plan }

    init() {
        let memorization = MemorizationStore()
        let revision = RevisionStore()
        let plan = PlanStore()
        let rewards = RewardStore()
        let assessments = AssessmentStore()
        let reading = ReadingStore()
        _memorization = State(initialValue: memorization)
        _revision = State(initialValue: revision)
        _plan = State(initialValue: plan)
        _rewards = State(initialValue: rewards)
        _assessments = State(initialValue: assessments)
        _reading = State(initialValue: reading)
        let journey = Journey(plan: plan, rewards: rewards, assessments: assessments, reading: reading)
        _account = State(initialValue: AccountStore(sync: CloudSync(memorization: memorization, revision: revision, journey: journey),
                                                    tasmee: TasmeeStore(memorization: memorization, revision: revision),
                                                    social: SocialStore(memorization: memorization, revision: revision)))
    }

    var body: some View {
        // The first screen is built beneath the splash once the Mushaf has loaded (see LaunchSplash).
        ZStack {
            Color.clear
            if launch.showsScreen {
                screen
            }
        }
        .environment(memorization)
        .environment(revision)
        .environment(plan)
        .environment(rewards)
        .environment(assessments)
        .environment(reading)
        .environment(account)
        .environment(account.sync)
        .environment(account.tasmee)
        .environment(account.social)
        .environment(account.wallet)
        .environment(account.inbox)
        .environment(router)
        // After signing out, setup starts from «ماذا تحفظ؟» again.
        .onChange(of: hasDeclared) {
            if !hasDeclared {
                setupStep = .memorized
                afterMarking = .none
            }
        }
        // Once the setup's marking is over, the home that comes back doesn't open the Mushaf on its own again.
        .onChange(of: afterMarking) { if afterMarking != .marking { startsMarking = false } }
        .onOpenURL { url in
            if !router.open(url) { _ = GIDSignIn.sharedInstance.handle(url) }
        }
        .task { account.start() }
        // Back in the foreground: what another device wrote to the account meanwhile is merged in.
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await account.sync.syncIfChanged() } }
        }
        .task {
            guard store == nil else { return }
            // Decoding the Quran data takes a moment; keep it off the main thread so the app stays responsive.
            store = await Task.detached(priority: .userInitiated) { Result { try MushafStore() } }.value
            launch.isReady = true
            guard case .success(let mushaf) = store else { return }
            connect(mushaf)
            // A setup marking cut short (the app was closed during it) goes on to its next steps.
            if afterMarking == .marking { afterMarking = .next(memorization: memorization) }
            // A tasmee' waiting in the account can be applied once the Mushaf says which ayat each page holds.
            account.tasmee.mushaf = mushaf
        }
    }

    @ViewBuilder private var screen: some View {
        switch store {
        case .success(let store) where !hasDeclared && setupStep == .plan,
             .success(let store) where afterMarking == .plan:
            PlanEditorView(store: store, isSetup: true, onBack: backFromPlan) { _ in
                withAnimation {
                    hasDeclared = true
                    afterMarking = .none
                }
            }
            .transition(.move(edge: .leading).combined(with: .opacity))
        case .success(let store) where !hasDeclared && setupStep == .dailyAmount,
             .success(let store) where afterMarking == .dailyAmount:
            let pages = RevisionStore.memorizedPages(in: store, memorization: memorization).count
            DailyAmountView(memorizedPages: pages, initial: revision.effectiveDailyPages(memorizedPages: pages),
                            onBack: backToMemorized) { amount in
                revision.setDailyPages(amount)
                withAnimation {
                    setupStep = .plan
                    if afterMarking == .dailyAmount { afterMarking = .plan }
                }
            }
            .transition(.move(edge: .leading).combined(with: .opacity))
        case .success(let store) where !hasDeclared:
            MemorizationSetupView(store: store) { markInMushaf in
                startsMarking = markInMushaf
                if markInMushaf {
                    afterMarking = .marking
                    withAnimation { hasDeclared = true }
                } else {
                    // With something memorized, its daily revision first; starting from zero, straight to the plan.
                    withAnimation { setupStep = memorization.count > 0 ? .dailyAmount : .plan }
                }
            }
        case .success(let store):
            AppTabView(store: store, startsMarking: startsMarking)
        case .failure(let error):
            ContentUnavailableView("The Mushaf couldn't be loaded", systemImage: "book.closed", description: Text(verbatim: "\(error)"))
        case nil:
            // Only after onboarding: the Mushaf is still loading, for a moment, before the setup.
            OnboardingPalette.surface.ignoresSafeArea()
        }
    }

    /// «رجوع» on «كم تراجع كل يوم؟»: back to «ماذا تحفظ؟», or to the marking in the Mushaf when that came before.
    private func backToMemorized() {
        withAnimation {
            if afterMarking != .none {
                startsMarking = true
                afterMarking = .marking
            } else {
                setupStep = .memorized
            }
        }
    }

    /// «رجوع» on the plan's first page: back to the daily revision, or, with nothing memorized, to the step before it.
    private func backFromPlan() {
        guard memorization.count == 0 else {
            withAnimation {
                if afterMarking == .plan { afterMarking = .dailyAmount } else { setupStep = .dailyAmount }
            }
            return
        }
        backToMemorized()
    }

    /// How the stores answer one another: each revision, portion, teacher's test and stage passed earns its
    /// rewards, and may pass a stage or meet a challenge.
    private func connect(_ mushaf: MushafStore) {
        let (memorization, revision, plan, rewards, assessments) = (memorization, revision, plan, rewards, assessments)
        let account = account
        revision.onRecord = { record in
            rewards.revised(record, revision: revision)
            rewards.checkChallenges(revision: revision, plan: plan)
            assessments.checkPasses(store: mushaf, memorization: memorization)
            if let name = account.publicName { account.social.reportScores(name: name) }
        }
        plan.onPortion = { portion in
            rewards.memorized(portion, memorization: memorization, store: mushaf)
            rewards.checkChallenges(revision: revision, plan: plan)
            if let name = account.publicName { account.social.reportScores(name: name) }
        }
        assessments.onPass = { stage in
            rewards.passedStage(stage, totalPassed: assessments.passes.count)
        }
        account.tasmee.onApplied = { record in
            assessments.record(record)
            assessments.checkPasses(store: mushaf, memorization: memorization)
        }
    }
}

/// The Mushaf's top bar: the surah, juz' and page in the middle, with buttons on either side.
struct MushafTopBar<Leading: View, Trailing: View>: View {
    var page: MushafPage
    var store: MushafStore
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 8)
            trailing
        }
        // The title stays centered, whatever the buttons on either side.
        .overlay {
            FloatingCapsule {
                VStack(spacing: 1) {
                    Text(verbatim: store.surahNames[page.surah] ?? "")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(MushafStyle.ink)
                    Text(verbatim: "الجزء \(arabic(page.juz))" + Separator.arabic + "الصفحة \(arabic(page.number))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(MushafStyle.chrome)
                }
                .lineLimit(1)
                .padding(.horizontal, 14)
            }
        }
        .tint(MushafStyle.barAccent)
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func arabic(_ number: Int) -> String {
        number.formatted(.number.locale(Locale(identifier: "ar@numbers=arab")))
    }
}

/// What a tap on the page does now, said in the panel of each mode: revising, marking or memorizing.
struct MushafModeChip: View {
    enum Mode {
        case revising, marking, memorizing
    }

    var mode: Mode

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: icon)
                .font(.system(size: 13))
            Group {
                switch mode {
                case .revising: Text("Revising")
                case .marking: Text("Marking what you've memorized")
                case .memorizing: Text("Memorizing")
                }
            }
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(MushafStyle.barAccent)
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 26)
        .background(MushafStyle.barAccentFill, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch mode {
        case .revising: "🧠"
        case .marking: "✅"
        case .memorizing: "✍️"
        }
    }
}

/// A button's icon in the Mushaf's top bar.
struct MushafBarIcon: View {
    var title: LocalizedStringKey
    var systemImage: String

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(MushafStyle.barAccent)
            .frame(width: 42, height: 42)
            .contentShape(Rectangle())
    }
}

/// The tajweed and topic color switches, kept for the whole app.
struct MushafColorsMenu: View {
    @AppStorage("mushaf.tajweed") private var tajweed = true
    @AppStorage("mushaf.topics") private var topicColors = true

    var body: some View {
        Menu {
            Toggle("Tajweed colors", isOn: $tajweed)
            Toggle("Topic colors", isOn: $topicColors)
        } label: {
            MushafBarIcon("Colors", systemImage: "paintpalette")
        }
    }
}

/// The marking and revision bars' buttons, in the app's colors: lavender capsules, the main one the purple of
/// the app's buttons.
struct MarkingButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        MarkingButton(configuration: configuration, prominent: prominent)
    }

    private struct MarkingButton: View {
        var configuration: Configuration
        var prominent: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(prominent ? .white : MushafStyle.barAccent)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background {
                    if prominent {
                        Capsule().fill(LinearGradient(colors: [OnboardingPalette.brand, OnboardingPalette.brandDeep], startPoint: .top, endPoint: .bottom))
                    } else {
                        Capsule().fill(MushafStyle.barAccentFill)
                    }
                }
                .shadow(color: prominent ? OnboardingPalette.brand.opacity(0.3) : .clear, radius: 10, y: 5)
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }
}
