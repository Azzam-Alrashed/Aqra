import SwiftUI
import UIKit

/// The app's tabs. The Mushaf isn't one: it opens full screen from the home, over everything.
enum AppTab: Hashable, CaseIterable {
    case home, progress, account

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .progress: "Progress"
        case .account: "Account"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .progress: "chart.bar.fill"
        case .account: "person.crop.circle.fill"
        }
    }
}

/// The app after setup: the home, progress and account tabs, under the app's own floating tab bar.
struct AppTabView: View {
    var store: MushafStore
    var startsMarking = false

    @Environment(MemorizationStore.self) private var memorization
    @Environment(RevisionStore.self) private var revision
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = AppTab.home

    var body: some View {
        TabView(selection: $tab) {
            HomeView(store: store, startsMarking: startsMarking)
                .reservesTabBarSpace()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.home)
            MyProgressView(store: store)
                .reservesTabBarSpace()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.progress)
            // Its pages reserve the tab bar's space inside its navigation stack.
            AccountView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.account)
        }
        .overlay(alignment: .bottom) {
            AqraTabBar(selection: $tab)
                .padding(.bottom, AqraTabBar.bottomPadding)
        }
        .environment(\.colorScheme, .light)
        // Today's plan is made (or kept) whenever the app comes back and whenever what's memorized changes.
        .task { refreshPlan() }
        .onChange(of: memorization.count) { refreshPlan() }
        .onChange(of: scenePhase) { if scenePhase == .active { refreshPlan() } }
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

    /// What the home has open over it.
    enum Destination: Hashable, Identifiable {
        case mushaf(marking: Bool)
        /// Today's wird, from one of its pages; started from the home's button, or from that page's tile.
        case wird(page: Int, fromButton: Bool)

        var id: Self { self }

        /// The view on the home it grows from and shrinks back into.
        var sourceID: String {
            switch self {
            case .mushaf: "mushaf"
            case .wird(_, true): "start"
            case .wird(let page, false): "page-\(page)"
            }
        }
    }

    @Environment(MemorizationStore.self) private var memorization
    @Environment(RevisionStore.self) private var revision
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction
    @AppStorage("mushaf.lastPage") private var lastPage = 1
    @State private var destination: Destination?
    @State private var editingMemorization = false
    @State private var editingAmount = false
    @State private var openedMarking = false
    /// The entrance plays once: the stage opens, the stairs climb, the chips pop out and the rest rises.
    @State private var entered = false
    @State private var chipsOut = false
    @State private var shownClimb = 0.0
    @State private var climbAnimation: Animation?
    /// Pauses the stage's ambient motion while the home isn't on screen.
    @State private var isVisible = false
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
                        mushafCard
                        if let plan = revision.plan, !plan.items.isEmpty {
                            pagesCard(plan)
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
        .task {
            guard !entered else { return }
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
        .fullScreenCover(item: $destination) { destination in
            Group {
                switch destination {
                case .mushaf(let marking):
                    MushafView(store: store, startsMarking: marking)
                case .wird(let page, _):
                    WirdView(store: store, startPage: page)
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
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                Text(Date.now.formatted(hijri))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 0)
            if streak > 0 {
                AqraChip(icon: "🔥", tint: Palette.peach) { Text("\(streak) days") }
                    .accessibilityLabel(Text("Revision streak: \(streak) days"))
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
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !isVisible || reduceMotion)) { timeline in
                AqraGlowRings(open: entered, breath: sin(timeline.date.timeIntervalSinceReferenceDate * 0.9))
                    .scaleEffect(1.05)
                    // Drawn on the GPU, so the breathing doesn't redraw the gradients on the CPU every frame.
                    .drawingGroup()
            }
            GlossyStairs(climb: shownClimb)
                .animation(climbAnimation, value: shownClimb)
                .environment(\.layoutDirection, direction)
                .offset(x: 8 * mirror, y: 6)
            if memorization.count > 0 {
                TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !isVisible || reduceMotion)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        floating(0, at: CGPoint(x: 92 * mirror, y: -118), tilt: -5 * mirror, time: time) { shareChip(share) }
                        if let strength {
                            floating(1, at: CGPoint(x: -96 * mirror, y: 128), tilt: 4 * mirror, time: time) { strengthChip(strength) }
                        }
                    }
                    // The chips' layer spans the stage, so nothing they drift to is cut off.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .drawingGroup()
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: 360)
        .frame(maxWidth: .infinity)
    }

    private func floating<Content: View>(_ index: Int, at target: CGPoint, tilt: Double, time: TimeInterval,
                                         @ViewBuilder content: () -> Content) -> some View {
        let drift = chipsOut && !reduceMotion ? sin(time * (0.8 + Double(index) * 0.2) + Double(index) * 1.3) * 5 : 0
        return content()
            .environment(\.layoutDirection, direction)
            .scaleEffect(chipsOut ? 1 : 0.3)
            .rotationEffect(.degrees(chipsOut ? tilt : 0))
            .opacity(chipsOut ? 1 : 0)
            .offset(x: chipsOut ? target.x : 0, y: (chipsOut ? target.y : 0) + drift)
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
                if memorization.count == 0 || plan == nil || plan?.items.isEmpty == true {
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
            .font(.system(size: 31, weight: .heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Group {
                if memorization.count == 0 {
                    Text("Choose what you've memorized to start climbing")
                } else {
                    cycleLine
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Palette.inkSoft)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var action: some View {
        let metrics = OnboardingButtonMetrics(height: 56, fontSize: 18, compact: false)
        if memorization.count == 0 {
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
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                        HStack(spacing: 5) {
                            Text(verbatim: store.surahNames[page.surah] ?? "")
                            Text(verbatim: "·")
                            Text("Page \(page.number)")
                        }
                        .font(.system(size: 16, weight: .heavy))
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
                            .font(.system(size: 19, weight: .heavy))
                            .foregroundStyle(Palette.ink)
                        if !plan.isComplete {
                            Text("Revised a page outside the app? Press and hold it.")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    Text("\(plan.doneCount) of \(plan.items.count)")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(Palette.brand)
                        .contentTransition(.numericText())
                        .padding(.horizontal, 10)
                        .frame(height: 28)
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
                    .font(.system(size: 18, weight: .heavy).monospacedDigit())
                    .foregroundStyle(item.done ? Palette.inkSoft : Palette.ink)
                Group {
                    if item.kind == .followUp {
                        Text("Follow-up").foregroundStyle(Color(light: 0x9A3E26, dark: 0x9A3E26))
                    } else {
                        Text(verbatim: store.surahNames[page.surah] ?? "").foregroundStyle(Palette.inkSoft)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
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
                        .font(.system(size: 16, weight: .bold))
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
            }
        }
        .accessibilityValue(item.done ? Text("Revised") : Text(verbatim: ""))
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
        return fullJuz > 0 ? ayat + Text(verbatim: " · ") + Text("\(fullJuz) juz'") : ayat
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
