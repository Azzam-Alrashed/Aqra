import SwiftUI
import UIKit

/// The app's tabs. The Mushaf isn't one: it opens full screen from the home, over everything.
enum AppTab: Hashable, CaseIterable {
    case home, tasmee, progress, account

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .tasmee: "Tasmee'"
        case .progress: "Progress"
        case .account: "Account"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .tasmee: "person.2.wave.2.fill"
        case .progress: "chart.bar.fill"
        case .account: "person.crop.circle.fill"
        }
    }

    var label: Label<Text, Image> { Label(title, systemImage: symbol) }
}

/// The app after setup: the home, tasmee', progress and account tabs, under the system tab bar.
struct AppTabView: View {
    var store: MushafStore
    var startsMarking = false

    @Environment(MemorizationStore.self) private var memorization
    @Environment(RevisionStore.self) private var revision
    @Environment(PlanStore.self) private var plan
    @Environment(RewardStore.self) private var rewards
    @Environment(TasmeeStore.self) private var tasmee
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("reminder.on") private var reminderOn = false
    @AppStorage("reminder.minutes") private var reminderMinutes = 5 * 60 + 30

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            HomeView(store: store, startsMarking: startsMarking, tab: $router.tab)
                .tabItem { AppTab.home.label }
                .tag(AppTab.home)
            TasmeeView(store: store)
                .tabItem { AppTab.tasmee.label }
                .tag(AppTab.tasmee)
            MyProgressView(store: store)
                .tabItem { AppTab.progress.label }
                .tag(AppTab.progress)
            AccountView()
                .tabItem { AppTab.account.label }
                .tag(AppTab.account)
        }
        .tint(OnboardingPalette.brand)
        .minimizesTabBarOnScroll()
        .overlay { CelebrationOverlay() }
        .environment(\.colorScheme, .light)
        // Today's plan is made (or kept) whenever the app comes back and whenever what's memorized changes.
        .task { refreshPlan() }
        .onChange(of: memorization.count) { refreshPlan() }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                refreshPlan()
                rewards.checkChallenges(revision: revision, plan: plan)
            }
        }
        // A reminder an hour before each booked session.
        .onChange(of: tasmee.upcomingBookings, initial: true) { SessionReminders.schedule(tasmee.upcomingBookings) }
        // The daily reminder mentions the new portion on the plan's study days.
        .onChange(of: plan.plan) {
            guard reminderOn else { return }
            DailyReminder.schedule(minutes: reminderMinutes, studyDays: plan.plan.flatMap { $0.paused ? nil : $0.studyDays })
        }
    }

    private func refreshPlan() {
        revision.refreshPlan(memorizedPages: RevisionStore.memorizedPages(in: store, memorization: memorization))
    }
}

/// The home: the منازل stairs on a glowing stage, today's wird and one button to start it, then the Mushaf where
/// the student left it, today's pages, and what they've memorized. The Mushaf and the wird open full screen over it.
struct HomeView: View {
    var store: MushafStore
    /// Opens straight into the Mushaf's marking mode (after the student chose to mark pages and ayat).
    var startsMarking = false
    /// The app's tab, so a card can lead to another tab.
    @Binding var tab: AppTab

    /// What the home has open over it.
    enum Destination: Hashable, Identifiable {
        case mushaf(marking: Bool)
        /// Today's wird, from one of its pages; started from the home's button, or from that page's tile.
        case wird(page: Int, fromButton: Bool)
        /// A page of today's wird revised outside the app, with the ayat stumbled on.
        case outside(page: Int)
        /// Today's new portion, to memorize.
        case memorize(portion: [Int])

        var id: Self { self }

        /// The view on the home it grows from and shrinks back into.
        var sourceID: String {
            switch self {
            case .mushaf: "mushaf"
            case .wird(_, true): "start"
            case .wird(let page, false), .outside(let page): "page-\(page)"
            case .memorize: "portion"
            }
        }
    }

    @Environment(MemorizationStore.self) private var memorization
    @Environment(RevisionStore.self) private var revision
    @Environment(PlanStore.self) private var plan
    @Environment(AssessmentStore.self) private var assessments
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction
    @AppStorage("mushaf.lastPage") private var lastPage = 1
    @Environment(AccountStore.self) private var account
    @Environment(TasmeeStore.self) private var tasmee
    /// The app's launch: the entrance waits until the splash has stepped back.
    @Environment(LaunchState.self) private var launch: LaunchState?
    @State private var destination: Destination?
    @AppStorage(SetupAfterMarking.key) private var afterMarking = SetupAfterMarking.none
    /// «لاحقًا» on the invitation to sign in hides it until this date.
    @AppStorage("home.saveProgressSnoozedUntil") private var saveProgressSnoozedUntil = 0.0
    /// The newest tasmee' whose card was closed, so it isn't shown again.
    @AppStorage("home.seenTasmee") private var seenTasmee = ""
    @State private var editingMemorization = false
    @State private var editingAmount = false
    @State private var editingPlan = false
    @State private var openedStage: StageRoute?
    /// Bumped when a suggestion is taken or dismissed, so the list is worked out again.
    @State private var suggestionsVersion = 0
    @State private var openedMarking = false
    /// The entrance plays once: the stage opens, the stairs climb, the chips pop out and the rest rises.
    @State private var entered = false
    @State private var chipsOut = false
    @State private var shownClimb = 0.0
    @State private var climbAnimation: Animation?
    /// Pauses the stage's ambient motion while the home isn't on screen.
    @State private var isVisible = false
    /// On a short screen (an iPhone SE, or any iPhone in landscape) the stage is drawn smaller, so today's wird and
    /// its button are on the first screen.
    @State private var isShortScreen = false
    private var stageScale: CGFloat { isShortScreen ? 0.76 : 1 }
    @Namespace private var zoom

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                stage
                Group {
                    headline
                        .padding(.top, 4)
                    action
                        .padding(.top, 24)
                    VStack(spacing: 14) {
                        if showsPortion {
                            PortionCard(store: store) { portion in
                                destination = .memorize(portion: portion)
                            } onEditPlan: {
                                editingPlan = true
                            }
                            .zoomTransitionSource(id: "portion", in: zoom)
                        }
                        if memorization.count > 0 || plan.plan != nil {
                            StageCard(store: store, stage: currentStage) { openedStage = StageRoute(stage: currentStage) }
                        }
                        if !suggestions.isEmpty {
                            suggestionCard(suggestions)
                                .transition(.scale(scale: 0.95).combined(with: .opacity))
                        }
                        if let record = newTasmee {
                            heardCard(record)
                                .transition(.scale(scale: 0.95).combined(with: .opacity))
                        }
                        if let booking = tasmee.nextBooking {
                            tasmeeCard(booking)
                                .transition(.scale(scale: 0.95).combined(with: .opacity))
                        }
                        mushafCard
                        if let plan = revision.plan, !plan.items.isEmpty {
                            pagesCard(plan)
                        }
                        if showsSaveProgress {
                            saveProgressCard
                                .transition(.scale(scale: 0.95).combined(with: .opacity))
                        }
                        memorizationCard
                    }
                    .padding(.top, 22)
                }
                .opacity(entered ? 1 : 0)
                .offset(y: entered ? 0 : 16)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background {
            GeometryReader { geometry in
                Color.clear.onChange(of: geometry.size, initial: true) {
                    isShortScreen = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom < 700
                }
            }
        }
        .background(Palette.surface.ignoresSafeArea())
        .fadesUnderStatusBar()
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .onAppear {
            isVisible = true
            // After choosing to mark in the Mushaf, the app opens straight on it, with the home underneath.
            if startsMarking && !openedMarking {
                openedMarking = true
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { destination = .mushaf(marking: true) }
            }
        }
        .onDisappear { isVisible = false }
        .task(id: launch?.isRevealed ?? true) {
            guard launch?.isRevealed ?? true, !entered else { return }
            // A beat after the first layout, so the entrance animates only what it means to.
            try? await Task.sleep(for: .milliseconds(80))
            await playEntrance()
        }
        .onChange(of: memorization.count) {
            guard entered else { return }
            climbAnimation = reduceMotion ? nil : .spring(duration: 0.9, bounce: 0.15)
            shownClimb = climbTarget
        }
        .sensoryFeedback(.success, trigger: revision.plan?.isComplete == true) { _, isComplete in isComplete }
        .sheet(isPresented: $editingMemorization) {
            MemorizationSetupView(store: store, isSheet: true) { _ in editingMemorization = false }
        }
        .sheet(isPresented: $editingAmount) {
            DailyAmountView(memorizedPages: memorizedPageCount, initial: dailyPages, isEditor: true) { revision.setDailyPages($0) }
        }
        .sheet(isPresented: $editingPlan) {
            PlanEditorView(store: store) { _ in }
        }
        .sheet(item: $openedStage) { route in
            NavigationStack { StageDetailView(store: store, stage: route.stage) }
        }
        .fullScreenCover(item: $destination, onDismiss: {
            // The setup's marking is over once the Mushaf closes: the daily amount and the plan follow.
            if afterMarking == .marking { afterMarking = .next(memorization: memorization) }
        }) { destination in
            Group {
                switch destination {
                case .mushaf(let marking):
                    MushafView(store: store, startsMarking: marking)
                case .wird(let page, _):
                    WirdView(store: store, startPage: page)
                case .outside(let page):
                    WirdView(store: store, startPage: page, outside: true)
                case .memorize(let portion):
                    MemorizeView(store: store, portion: portion)
                }
            }
            .zoomTransition(sourceID: destination.sourceID, in: zoom)
        }
    }

    // MARK: - Header

    private var header: some View {
        var hijri = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        hijri.calendar = Calendar(identifier: .islamicUmmAlQura)
        let streak = revision.streak()
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Peace be upon you")
                    .aqraFont(size: 20, weight: .heavy)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(Date.now.formatted(hijri))
                    .aqraFont(size: 13, weight: .semibold)
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 0)
            if streak > 0 {
                AqraChip(icon: "🔥", tint: Palette.peach) { Text("\(streak) days") }
                    .accessibilityLabel(Text("Revision streak: \(streak) days"))
            }
            if AccountStore.isAvailable {
                InboxButton()
            }
        }
        .padding(.top, 8)
    }

    // MARK: - The stage

    private var climbTarget: Double {
        memorization.quranShare(in: store) * Double(GlossyStairs.stepCount)
    }

    /// The glowing rings, the stairs and the floating chips, laid out as one picture.
    private var stage: some View {
        // Positions are a fixed composition, mirrored for left-to-right languages; chips keep the screen's direction.
        let mirror: CGFloat = direction == .rightToLeft ? 1 : -1
        // Worked out once here, not on every frame of the chips' drift.
        let share = memorization.quranShare(in: store)
        let strength = memorization.averageStrength()
        return ZStack {
            GlossyStairs(climb: shownClimb)
                .animation(climbAnimation, value: shownClimb)
                .environment(\.layoutDirection, direction)
                .offset(x: 8 * mirror, y: 6)
            if memorization.count > 0 {
                TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !isVisible || reduceMotion)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    // Each chip rests against its side of the stage, whatever its width in the app's language,
                    // and flies out to it from the middle.
                    ZStack {
                        floating(0, from: CGPoint(x: 92 * mirror, y: -118), tilt: -5 * mirror, time: time) { shareChip(share) }
                            .frame(maxWidth: .infinity, alignment: mirror > 0 ? .trailing : .leading)
                        if let strength {
                            floating(1, from: CGPoint(x: -96 * mirror, y: 128), tilt: 4 * mirror, time: time) { strengthChip(strength) }
                                .frame(maxWidth: .infinity, alignment: mirror > 0 ? .leading : .trailing)
                        }
                    }
                    .padding(.horizontal, 2)
                    // The chips' layer spans the stage, so nothing they drift to is cut off.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .drawingGroup()
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: 360)
        .frame(maxWidth: .infinity)
        // Behind the stage, so the glow spreads past its edges without widening the page.
        .background {
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !isVisible || reduceMotion)) { timeline in
                AqraGlowRings(open: entered, breath: sin(timeline.date.timeIntervalSinceReferenceDate * 0.9))
                    .scaleEffect(1.05)
                    // Drawn on the GPU, so the breathing doesn't redraw the gradients on the CPU every frame.
                    .drawingGroup()
            }
        }
        // The whole composition, glow and chips included, shrinks together on a short screen.
        .scaleEffect(stageScale)
        .frame(height: 360 * stageScale)
    }

    /// A chip at its resting place, after flying out from `start`'s distance back toward the stage's middle.
    private func floating<Content: View>(_ index: Int, from start: CGPoint, tilt: Double, time: TimeInterval,
                                         @ViewBuilder content: () -> Content) -> some View {
        let drift = chipsOut && !reduceMotion ? sin(time * (0.8 + Double(index) * 0.2) + Double(index) * 1.3) * 5 : 0
        return content()
            .environment(\.layoutDirection, direction)
            .scaleEffect(chipsOut ? 1 : 0.3)
            .rotationEffect(.degrees(chipsOut ? tilt : 0))
            .opacity(chipsOut ? 1 : 0)
            .offset(x: chipsOut ? 0 : -start.x, y: (chipsOut ? start.y : 0) + drift)
    }

    private func shareChip(_ share: Double) -> some View {
        AqraChip(icon: "🪜", tint: Palette.lavender) {
            HStack(spacing: 4) {
                Text(verbatim: share.formatted(.percent.precision(.fractionLength(0...1))))
                    .contentTransition(.numericText(value: share))
                Text("of the Quran")
            }
        }
    }

    private func strengthChip(_ strength: Double) -> some View {
        AqraChip(icon: "🌱", tint: Palette.mint) {
            HStack(spacing: 4) {
                Text("Memorization strength")
                Text(verbatim: strength.formatted(.percent.precision(.fractionLength(0))))
            }
        }
    }

    private func playEntrance() async {
        guard !reduceMotion else {
            entered = true
            chipsOut = true
            shownClimb = climbTarget
            return
        }
        let light = UIImpactFeedbackGenerator(style: .light)
        light.prepare()
        withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { entered = true }
        climbAnimation = .spring(duration: 1.3, bounce: 0.1)
        shownClimb = climbTarget
        try? await Task.sleep(for: .milliseconds(420))
        guard memorization.count > 0 else { return }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.66)) { chipsOut = true }
        light.impactOccurred(intensity: 0.5)
    }

    // MARK: - Today's wird

    /// What's left of today's wird: the pages not yet revised, the first of them leading.
    private var remaining: [PlanItem] {
        revision.plan?.items.filter { !$0.done } ?? []
    }

    private var memorizedPageCount: Int {
        RevisionStore.memorizedPages(in: store, memorization: memorization).count
    }

    private var dailyPages: Int {
        revision.effectiveDailyPages(memorizedPages: memorizedPageCount)
    }

    private var cycleLine: Text {
        Text("A full revision every \(DailyAmountView.cycleDays(memorizedPages: memorizedPageCount, amount: dailyPages)) days")
    }

    private var headline: some View {
        let plan = revision.plan
        return VStack(spacing: 10) {
            VStack(spacing: 2) {
                if memorization.count == 0, self.plan.plan != nil {
                    Text("Begin your journey").foregroundStyle(Palette.ink)
                    Text("with today's portion").foregroundStyle(Palette.brand)
                } else if memorization.count == 0 || plan == nil || plan?.items.isEmpty == true {
                    Text("What have you memorized").foregroundStyle(Palette.ink)
                    Text("of the Quran?").foregroundStyle(Palette.brand)
                } else if let next = remaining.first {
                    Text("Your revision today").foregroundStyle(Palette.ink)
                    Text("\(remaining.count) pages from \(store.surahNames[store.page(next.page).surah] ?? "")")
                        .foregroundStyle(Palette.brand)
                } else {
                    Text("Today's revision is done").foregroundStyle(Palette.ink)
                    Text("May Allah bless you").foregroundStyle(Palette.brand)
                }
            }
            .aqraFont(size: 31, weight: .heavy)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Group {
                if memorization.count == 0, self.plan.plan != nil {
                    Text("Every ayah you memorize is a step up")
                } else if memorization.count == 0 {
                    Text("Choose what you've memorized to start climbing")
                } else {
                    cycleLine
                }
            }
            .aqraFont(size: 16, weight: .medium)
            .foregroundStyle(Palette.inkSoft)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var action: some View {
        let metrics = OnboardingButtonMetrics(height: 56, fontSize: 18, compact: false)
        if memorization.count == 0, plan.plan != nil {
            EmptyView()
        } else if memorization.count == 0 {
            BrandButton("Choose what you've memorized", metrics: metrics) { editingMemorization = true }
        } else if let next = remaining.first, let plan = revision.plan {
            BrandButton(plan.doneCount == 0 ? "Start today's revision" : "Continue today's revision", metrics: metrics) {
                destination = .wird(page: next.page, fromButton: true)
            }
            .zoomTransitionSource(id: Destination.wird(page: next.page, fromButton: true).sourceID, in: zoom)
        }
    }

    // MARK: - Cards

    /// The Mushaf, open on the page last read: its miniature grows into the full page.
    private var mushafCard: some View {
        let page = store.page(lastPage)
        return Button {
            destination = .mushaf(marking: false)
        } label: {
            AqraCard(padding: 12, radius: 24) {
                HStack(spacing: 12) {
                    MushafThumbnail(page: page, store: store)
                        .frame(width: 40, height: 63)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MushafStyle.chrome.opacity(0.25), lineWidth: 1))
                        .zoomTransitionSource(id: Destination.mushaf(marking: false).sourceID, in: zoom)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Continue reading")
                            .aqraFont(size: 12, weight: .semibold)
                            .foregroundStyle(Palette.inkSoft)
                        (Text(verbatim: (store.surahNames[page.surah] ?? "") + Separator.facts) + Text("Page \(page.number)"))
                        .aqraFont(size: 16, weight: .heavy)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    IconTile(icon: "📖", tint: Palette.sky, size: 40)
                }
            }
        }
        .buttonStyle(AqraPressStyle())
    }

    private func pagesCard(_ plan: DayPlan) -> some View {
        AqraCard(padding: 14, radius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    IconTile(icon: "📄", tint: Palette.sky, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Today's pages")
                            .aqraFont(size: 19, weight: .heavy)
                            .foregroundStyle(Palette.ink)
                        if !plan.isComplete {
                            Text("Revised a page outside the app? Press and hold it.")
                                .aqraFont(size: 11, weight: .semibold)
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    Text("\(plan.doneCount) of \(plan.items.count)")
                        .aqraFont(size: 13, weight: .bold, monospacedDigit: true)
                        .foregroundStyle(Palette.brand)
                        .contentTransition(.numericText())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .frame(minHeight: 28)
                        .background(Palette.lavender, in: Capsule())
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(plan.items) { item in
                        pageTile(item)
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: plan.doneCount)
        }
    }

    /// A page of today's wird, in its juz's band color: tap to revise it, press and hold if it was revised elsewhere.
    private func pageTile(_ item: PlanItem) -> some View {
        let page = store.page(item.page)
        let face = ManazilStairs.face(forJuz: page.juz)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            destination = .wird(page: item.page, fromButton: false)
        } label: {
            VStack(spacing: 2) {
                Text(item.page.formatted())
                    .aqraFont(size: 18, weight: .heavy, monospacedDigit: true)
                    .foregroundStyle(item.done ? Palette.inkSoft : Palette.ink)
                Group {
                    if item.kind == .followUp {
                        Text("Follow-up").foregroundStyle(Color(light: 0x9A3E26, dark: 0x9A3E26))
                    } else {
                        Text(verbatim: store.surahNames[page.surah] ?? "").foregroundStyle(Palette.inkSoft)
                    }
                }
                .aqraFont(size: 11, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .frame(minHeight: 62)
            .background(
                item.done
                    ? AnyShapeStyle(face.top.opacity(0.14))
                    : AnyShapeStyle(LinearGradient(colors: [face.top.opacity(0.6), face.top.opacity(0.28)], startPoint: .top, endPoint: .bottom)),
                in: shape
            )
            .overlay(shape.strokeBorder(.white.opacity(0.8), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if item.done {
                    Image(systemName: "checkmark.circle.fill")
                        .aqraFont(size: 16, weight: .bold)
                        .foregroundStyle(.white, face.bottom)
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(AqraPressStyle())
        .zoomTransitionSource(id: Destination.wird(page: item.page, fromButton: false).sourceID, in: zoom)
        .contextMenu {
            if !item.done {
                Button {
                    let ayahs = page.ayahs.filter { memorization.isMemorized($0) }
                    revision.record(page: item.page, ayahs: ayahs, stumbles: [], source: .outside, memorization: memorization)
                } label: {
                    Label("Revised outside the app", systemImage: "checkmark.circle")
                }
                Button {
                    destination = .outside(page: item.page)
                } label: {
                    Label("Revised outside the app, with stumbles…", systemImage: "exclamationmark.circle")
                }
            }
        }
        .accessibilityValue(item.done ? Text("Revised") : Text(verbatim: ""))
    }

    // MARK: - Tasmee'

    /// The next tasmee' booked, with a teacher: when and where, or that the teacher cancelled it.
    private func tasmeeCard(_ booking: Booking) -> some View {
        let live = tasmee.session(of: booking)
        let cancelled = live?.status == .cancelled
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { tab = .tasmee }
        } label: {
            AqraCard(padding: 12, radius: 24) {
                HStack(spacing: 12) {
                    IconTile(icon: "🎓", tint: cancelled ? Palette.rose : Palette.mint, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cancelled ? "Tasmee' cancelled" : "Your next tasmee'")
                            .aqraFont(size: 12, weight: .semibold)
                            .foregroundStyle(Palette.inkSoft)
                        Text(verbatim: booking.teacherName)
                            .aqraFont(size: 16, weight: .heavy)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        (Text(verbatim: TasmeeFormat.when(live?.startsAt ?? booking.startsAt) + Separator.facts)
                            + TasmeeFormat.place(live.map { Booking($0) } ?? booking))
                            .aqraFont(size: 12, weight: .bold)
                            .foregroundStyle(cancelled ? Palette.inkSoft : Palette.brand)
                            .strikethrough(cancelled)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    AqraChevron()
                }
            }
        }
        .buttonStyle(AqraPressStyle())
        .accessibilityElement(children: .combine)
    }

    /// Today's portion, or the invitation to a plan — not for a student who has memorized the whole Quran.
    private var showsPortion: Bool {
        plan.plan != nil || memorization.count < MushafStore.ayahCount
    }

    /// The stage the student is in.
    private var currentStage: Int {
        AssessmentStore.currentStage(nextAyah: plan.nextAyah(memorization: memorization, store: store),
                                     memorization: memorization, store: store, passes: assessments.passes)
    }

    /// Pages that keep slipping, suggested for extra follow-up.
    private var suggestions: [Int] {
        _ = suggestionsVersion
        return RotationAdvisor.suggestions(store: store, memorization: memorization, revision: revision)
    }

    private func suggestionCard(_ pages: [Int]) -> some View {
        AqraCard(padding: 14, radius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    IconTile(icon: "🌿", tint: Palette.mint, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("These pages keep slipping")
                            .aqraFont(size: 16, weight: .heavy)
                            .foregroundStyle(Palette.ink)
                        Text("Pages \(pages.map { $0.formatted() }.formatted(.list(type: .and, width: .narrow))): bring them back tomorrow to make them firm?")
                            .aqraFont(size: 12, weight: .semibold)
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    Button("Not now") {
                        RotationAdvisor.dismiss(pages)
                        withAnimation(.snappy) { suggestionsVersion += 1 }
                    }
                    .buttonStyle(ChipButtonStyle(filled: false))
                    Button("Add to follow-up") {
                        RotationAdvisor.accept(pages, revision: revision)
                        withAnimation(.snappy) { suggestionsVersion += 1 }
                    }
                    .buttonStyle(ChipButtonStyle(filled: true))
                }
            }
        }
    }

    /// A tasmee' applied in the last two days that the student hasn't closed yet.
    private var newTasmee: TasmeeRecord? {
        guard let record = tasmee.history.first(where: { $0.appliedAt != nil }), record.id != seenTasmee,
              record.at > Date.now.addingTimeInterval(-2 * 86_400) else { return nil }
        return record
    }

    /// What a teacher or a friend heard, now applied to the student's progress.
    private func heardCard(_ record: TasmeeRecord) -> some View {
        let pages = Set(record.pages).count
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { tab = .tasmee }
        } label: {
            AqraCard(padding: 12, radius: 24) {
                HStack(spacing: 12) {
                    IconTile(icon: record.kind == .peer ? "🤝" : "🎓", tint: record.kind == .peer ? Palette.peach : Palette.mint, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Group {
                            if record.kind == .peer {
                                Text("Your friend heard \(pages) pages")
                            } else {
                                Text("Your teacher heard \(pages) pages")
                            }
                        }
                        .aqraFont(size: 16, weight: .heavy)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        Group {
                            if record.kind == .sheikh && record.stumbles.isEmpty {
                                Text("No stumbles: the ayat heard are verified")
                            } else {
                                Text("\(record.stumbles.count) stumbles · added to your revision")
                            }
                        }
                        .aqraFont(size: 12, weight: .semibold)
                        .foregroundStyle(Palette.brand)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    Button {
                        withAnimation(.snappy) { seenTasmee = record.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Palette.brand)
                            .frame(width: 28, height: 28)
                            .background(Palette.lavender, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Close"))
                }
            }
        }
        .buttonStyle(AqraPressStyle())
    }

    // MARK: - Saving progress

    /// The invitation to sign in: only for an anonymous student, and only once they've revised at least once, so
    /// it comes after something worth keeping.
    private var showsSaveProgress: Bool {
        AccountStore.isAvailable && account.profile?.isAnonymous == true && !revision.revisedDays.isEmpty
            && Date.now.timeIntervalSince1970 > saveProgressSnoozedUntil
    }

    private var saveProgressCard: some View {
        AqraCard(padding: 14, radius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    IconTile(icon: "🪪", tint: Palette.butter, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Save your progress")
                            .aqraFont(size: 17, weight: .heavy)
                            .foregroundStyle(Palette.ink)
                        Text("Your progress is only on this device until you sign in.")
                            .aqraFont(size: 12, weight: .semibold)
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button("Later") {
                        withAnimation(.snappy) { saveProgressSnoozedUntil = Date.now.addingTimeInterval(7 * 86_400).timeIntervalSince1970 }
                    }
                    .aqraFont(size: 13, weight: .bold)
                    .foregroundStyle(Palette.brand)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .frame(minHeight: 28)
                    .background(Palette.lavender, in: Capsule())
                    .buttonStyle(.plain)
                }
                SignInButtons()
                if let problem = account.problem {
                    ProblemLine(problem: problem)
                }
            }
        }
    }

    /// What's memorized and how much is revised each day, each opening its editor.
    private var memorizationCard: some View {
        AqraCard(padding: 0, radius: 24) {
            VStack(spacing: 0) {
                Button {
                    editingMemorization = true
                } label: {
                    AqraRow(icon: "✏️", tint: Palette.butter,
                            title: memorization.count == 0 ? Text("Choose what you've memorized") : Text("Edit what you've memorized"),
                            detail: memorization.count == 0 ? nil : memorizedSummary)
                }
                .buttonStyle(.plain)
                if memorization.count > 0 {
                    AqraRowDivider()
                    Button {
                        editingAmount = true
                    } label: {
                        AqraRow(icon: "🗓️", tint: Palette.peach, title: Text("\(dailyPages) pages a day"), detail: cycleLine)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// «٥٦٤ آية · جزء واحد»: the ayat memorized, and the whole juz' among them.
    private var memorizedSummary: Text {
        let fullJuz = (1...30).filter { juz in
            store.juzAyahs[juz].map { memorization.memorizedCount(in: $0) == $0.count } ?? false
        }.count
        let ayat = Text("\(memorization.count) ayat")
        return fullJuz > 0 ? ayat + Text(verbatim: Separator.facts) + Text("\(fullJuz) juz'") : ayat
    }
}

/// A miniature of a Mushaf page: the real page, drawn at a phone's size and scaled down.
struct MushafThumbnail: View {
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

private extension View {
    /// The tab bar shrinks to the selected tab while a page scrolls down, and comes back on scrolling up (iOS 26 and later).
    @ViewBuilder
    func minimizesTabBarOnScroll() -> some View {
        if #available(iOS 26, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
