import SwiftUI

/// «كم تحفظ يوميًا؟»: the personal plan, one question to a page in the onboarding's own style — how much a day, on
/// which days, where to begin — then the completion date they lead to, with the منازل stairs climbing to it.
/// The last step of setup, and later a sheet to change, pause or stop the plan.
struct PlanEditorView: View {
    var store: MushafStore
    /// The last step of setup, where it can be left for later, rather than a sheet changing the plan.
    var isSetup = false
    /// Called with the plan chosen, or nil when it's left for later or stopped.
    var onDone: (MemorizationPlan?) -> Void

    @Environment(PlanStore.self) private var planStore
    @Environment(MemorizationStore.self) private var memorization
    @Environment(\.dismiss) private var dismiss

    @State private var draft = MemorizationPlan(dailyLines: PlanPolicy.standard.defaultAmount,
                                                studyDays: PlanPolicy.standard.defaultStudyDays, order: .fromEnd)
    @State private var page = 0
    @State private var prepared = false
    @State private var confirmingStop = false
    private let pageCount = 4

    var body: some View {
        // The plan being changed: its completion date is shown beside the new one, and it can be paused or stopped.
        let current = isSetup ? nil : planStore.plan
        ZStack(alignment: .topTrailing) {
            Palette.surface.ignoresSafeArea()
            TabView(selection: $page) {
                PlanAmountPage(lines: $draft.dailyLines, pageCount: pageCount) { next() }
                    .tag(0)
                PlanDaysPage(days: $draft.studyDays, pageCount: pageCount) { next() }
                    .tag(1)
                PlanOrderPage(order: $draft.order, pageCount: pageCount) { next() }
                    .tag(2)
                PlanFinishPage(plan: draft, previous: current, store: store, pageCount: pageCount, isActive: page == 3,
                               title: current == nil ? "Start my plan" : "Save") {
                    var plan = draft
                    plan.paused = false
                    finish(plan)
                } extra: {
                    if let current { manage(current) }
                }
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)

            if isSetup {
                Button("Not now") { finish(nil) }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            } else {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 36, height: 36)
                        .background(.white, in: Circle())
                        .shadow(color: Palette.shadow.opacity(0.10), radius: 8, y: 4)
                }
                .buttonStyle(AqraPressStyle())
                .accessibilityLabel(Text("Close"))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .sensoryFeedback(.selection, trigger: draft)
        .onAppear(perform: prepare)
        .alert("Stop your plan?", isPresented: $confirmingStop) {
            Button("Stop", role: .destructive) { finish(nil) }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("What you've memorized stays, and its revision goes on. You can start a plan again anytime.")
        }
    }

    /// «إيقاف مؤقت» and «إيقاف الخطة», under «حفظ» when changing a plan.
    private func manage(_ plan: MemorizationPlan) -> some View {
        HStack(spacing: 24) {
            Button(plan.paused ? "Resume" : "Pause") {
                var changed = plan
                changed.paused.toggle()
                finish(changed)
            }
            Button("Stop the plan") { confirmingStop = true }
                .foregroundStyle(Color(light: 0xB3261E, dark: 0xB3261E))
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Palette.brand)
    }

    private func next() {
        withAnimation { page = min(page + 1, pageCount - 1) }
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        if !isSetup, let plan = planStore.plan {
            draft = plan
        } else {
            draft.order = PlanStore.suggestedOrder(memorization: memorization, store: store)
        }
    }

    private func finish(_ plan: MemorizationPlan?) {
        // In setup, «ليس الآن» leaves no plan; outside it, only «إيقاف الخطة» removes one.
        if plan != nil || !isSetup { planStore.setPlan(plan) }
        onDone(plan)
        if !isSetup { dismiss() }
    }
}

// MARK: - 1. How much a day

/// An open Mushaf whose lines light up, right page first, as far as the daily amount reaches, with − and + beneath.
private struct PlanAmountPage: View {
    @Binding var lines: Int
    var pageCount: Int
    var onContinue: () -> Void

    private let options = PlanPolicy.standard.amountOptions

    var body: some View {
        OnboardingPageLayout(
            pageCount: pageCount, currentPage: 0, actionsVisible: true,
            stage: { stage },
            copy: { scale in
                OnboardingHeadline(
                    first: "How much will you memorize",
                    second: "each day?",
                    detail: "A little every day, and the review engine keeps it.",
                    scale: scale, visible: true
                )
            },
            buttons: { metrics in BrandButton("Continue", metrics: metrics, action: onContinue) }
        )
    }

    private var index: Int { options.firstIndex(of: lines) ?? 0 }

    private var stage: some View {
        ZStack {
            AqraGlowRings(open: true, breath: 0)
                .offset(y: -40)
            VStack(spacing: 26) {
                OpenMushaf(lit: Double(lines))
                    .animation(.spring(response: 0.7, dampingFraction: 0.85), value: lines)
                    .overlay(alignment: .topLeading) {
                        AqraChip(icon: "📖", tint: Palette.lavender) { Text("\(lines) lines") }
                            .contentTransition(.numericText(value: Double(lines)))
                            .animation(.snappy, value: lines)
                            .rotationEffect(.degrees(-5))
                            .offset(x: -26, y: -22)
                    }
                HStack(spacing: 0) {
                    StepButton(symbol: "minus", enabled: index > 0) { lines = options[index - 1] }
                    PlanFormat.amount(lines)
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(Palette.brand)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText(value: Double(lines)))
                        .animation(.snappy, value: lines)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity)
                    StepButton(symbol: "plus", enabled: index < options.count - 1) { lines = options[index + 1] }
                }
                .frame(width: 380)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Daily amount"))
                .accessibilityValue(PlanFormat.amount(lines))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment where index < options.count - 1: lines = options[index + 1]
                    case .decrement where index > 0: lines = options[index - 1]
                    default: break
                    }
                }
            }
        }
        .frame(width: 420, height: 440)
    }
}

/// Two facing pages of the fifteen-line Mushaf. `lit` lines glow from the top of the right-hand page, each
/// lighting from right to left as Arabic is read, then on into the left-hand page.
private struct OpenMushaf: View, Animatable {
    var lit: Double

    nonisolated var animatableData: Double {
        get { lit }
        set { lit = newValue }
    }

    private static let lines = 15
    private static let pageSize = CGSize(width: 150, height: 214)

    var body: some View {
        HStack(spacing: 4) {
            // The Mushaf opens right to left: the first page is on the right.
            page(first: Self.lines, outerEdge: .leading)
            page(first: 0, outerEdge: .trailing)
        }
        .environment(\.layoutDirection, .leftToRight)
        .shadow(color: Palette.shadow.opacity(0.14), radius: 20, y: 12)
        .shadow(color: Palette.shadow.opacity(0.06), radius: 2, y: 1)
        .accessibilityHidden(true)
    }

    private func page(first: Int, outerEdge: HorizontalEdge) -> some View {
        let outer: CGFloat = 20, inner: CGFloat = 5
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: outerEdge == .leading ? outer : inner, bottomLeadingRadius: outerEdge == .leading ? outer : inner,
            bottomTrailingRadius: outerEdge == .trailing ? outer : inner, topTrailingRadius: outerEdge == .trailing ? outer : inner,
            style: .continuous)
        return VStack(spacing: 0) {
            ForEach(0..<Self.lines, id: \.self) { line in
                let fill = min(max(lit - Double(first + line), 0), 1)
                Capsule()
                    .fill(Palette.lavender.opacity(0.7))
                    .overlay {
                        GeometryReader { geometry in
                            Capsule()
                                .fill(LinearGradient(colors: [Palette.brand.opacity(0.75), Palette.brand], startPoint: .leading, endPoint: .trailing))
                                .frame(width: fill > 0 ? max(geometry.size.width * fill, geometry.size.height) : 0)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .frame(height: 5)
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height)
        .background(.white, in: shape)
        .overlay(shape.strokeBorder(Palette.lavender, lineWidth: 1))
    }
}

/// A white round − or + that repeats while held, as on «كم تراجع كل يوم؟».
private struct StepButton: View {
    var symbol: String
    var enabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(enabled ? Palette.brand : Palette.inkSoft.opacity(0.4))
                .frame(width: 58, height: 58)
                .background(.white, in: Circle())
                .shadow(color: Palette.shadow.opacity(0.12), radius: 12, y: 6)
                .shadow(color: Palette.shadow.opacity(0.05), radius: 2, y: 1)
        }
        .buttonStyle(AqraPressStyle())
        .disabled(!enabled)
        .buttonRepeatBehavior(.enabled)
    }
}

// MARK: - 2. Which days

/// The seven days set around the glowing rings in the week's reading order, the count of study days at the center.
private struct PlanDaysPage: View {
    @Binding var days: Set<Int>
    var pageCount: Int
    var onContinue: () -> Void

    @Environment(\.layoutDirection) private var direction

    var body: some View {
        OnboardingPageLayout(
            pageCount: pageCount, currentPage: 1, actionsVisible: true,
            stage: { stage },
            copy: { scale in
                OnboardingHeadline(
                    first: "Which days",
                    second: "will you memorize?",
                    detail: "Revision goes on every day.",
                    scale: scale, visible: true
                )
            },
            buttons: { metrics in BrandButton("Continue", metrics: metrics, action: onContinue) }
        )
    }

    private var stage: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let names = calendar.standaloneWeekdaySymbols
        // The week from its first day in this locale, around the ring in the reading direction from the top.
        let week = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        let turn: Double = direction == .rightToLeft ? -1 : 1
        let radius: CGFloat = 138
        return ZStack {
            AqraGlowRings(open: true, breath: 0)
                .scaleEffect(1.04)
            VStack(spacing: 0) {
                Text(days.count.formatted())
                    .font(.system(size: 64, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Palette.brand)
                    .contentTransition(.numericText(value: Double(days.count)))
                    .animation(.snappy, value: days.count)
                Text("a week")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(days.count) days a week"))
            ForEach(Array(week.enumerated()), id: \.element) { position, weekday in
                let angle = (-90 + turn * Double(position) * 360 / 7) * .pi / 180
                let on = days.contains(weekday)
                Button {
                    if on, days.count > 1 { days.remove(weekday) } else { days.insert(weekday) }
                } label: {
                    Text(verbatim: symbols[weekday - 1])
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(on ? .white : Palette.inkSoft)
                        .frame(width: 60, height: 60)
                        .background {
                            if on {
                                Circle().fill(LinearGradient(colors: [Palette.brand, Palette.brandDeep], startPoint: .top, endPoint: .bottom))
                            } else {
                                Circle().fill(.white)
                            }
                        }
                        .overlay(Circle().strokeBorder(on ? .white.opacity(0.25) : Palette.lavender, lineWidth: 1.5))
                        .shadow(color: Palette.shadow.opacity(on ? 0.3 : 0.08), radius: on ? 10 : 6, y: on ? 6 : 3)
                        .scaleEffect(on ? 1 : 0.88)
                        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: on)
                }
                .buttonStyle(AqraPressStyle())
                .offset(x: radius * cos(angle), y: radius * sin(angle))
                .accessibilityLabel(Text(verbatim: names[weekday - 1]))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(width: 420, height: 440)
    }
}

// MARK: - 3. Where to begin

/// Two Mushaf covers in their juz' colors; the one chosen stands forward.
private struct PlanOrderPage: View {
    @Binding var order: MemorizationPlan.Order
    var pageCount: Int
    var onContinue: () -> Void

    var body: some View {
        OnboardingPageLayout(
            pageCount: pageCount, currentPage: 2, actionsVisible: true,
            stage: { stage },
            copy: { scale in
                OnboardingHeadline(
                    first: Text("Where will you"),
                    second: Text("begin?"),
                    detail: order == .fromEnd
                        ? Text("From an-Nas back toward al-Baqarah, each surah from its first ayah.")
                        : Text("From the beginning of the Mushaf, in its order."),
                    scale: scale, visible: true
                )
            },
            buttons: { metrics in BrandButton("Continue", metrics: metrics, action: onContinue) }
        )
    }

    private var stage: some View {
        ZStack {
            AqraGlowRings(open: true, breath: 0)
            HStack(spacing: -14) {
                cover(.fromEnd, title: "جزء عمّ", label: "From juz' ʿAmma", juz: 30, tilt: -7)
                cover(.fromStart, title: "البقرة", label: "From al-Baqarah", juz: 1, tilt: 7)
            }
        }
        .frame(width: 420, height: 440)
    }

    private func cover(_ option: MemorizationPlan.Order, title: String, label: LocalizedStringKey, juz: Int, tilt: Double) -> some View {
        let selected = order == option
        let face = ManazilStairs.face(forJuz: juz)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return Button {
            order = option
        } label: {
            VStack(spacing: 16) {
                ZStack {
                    shape.fill(LinearGradient(colors: [face.top, face.bottom], startPoint: .top, endPoint: .bottom))
                    shape
                        .fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .center))
                        .padding(3)
                    shape
                        .strokeBorder(.white.opacity(0.75), lineWidth: 1.5)
                        .padding(10)
                    VStack(spacing: 10) {
                        AqraStar()
                            .frame(width: 26, height: 26)
                        Text(verbatim: title)
                            .font(AqraFont.hadith(size: 34, bold: true))
                            .foregroundStyle(Palette.ink)
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                }
                .frame(width: 158, height: 214)
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Palette.brand, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                            .offset(x: 10, y: -10)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
                .shadow(color: face.bottom.opacity(selected ? 0.5 : 0.2), radius: selected ? 22 : 10, y: selected ? 14 : 6)
                Text(label)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(selected ? .white : Palette.brand)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(selected ? Palette.brand : .white, in: Capsule())
            }
            .scaleEffect(selected ? 1.04 : 0.88)
            .rotationEffect(.degrees(selected ? tilt * 0.3 : tilt))
            .opacity(selected ? 1 : 0.8)
        }
        .buttonStyle(AqraPressStyle())
        .zIndex(selected ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.68), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - 4. The finish

/// The completion date the choices lead to, with the منازل stairs climbing from what's memorized to the star — and,
/// when a plan is being changed, the date it led to before.
private struct PlanFinishPage<Extra: View>: View {
    var plan: MemorizationPlan
    var previous: MemorizationPlan?
    var store: MushafStore
    var pageCount: Int
    var isActive: Bool
    var title: LocalizedStringKey
    var onSave: () -> Void
    /// Beneath the button: pausing or stopping a plan being changed.
    @ViewBuilder var extra: Extra

    @Environment(MemorizationStore.self) private var memorization
    @Environment(\.layoutDirection) private var direction
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var climb = 0.0
    @State private var reached = false

    var body: some View {
        let remaining = PlanStore.remainingLines(memorization: memorization, store: store)
        let date = PlanStore.estimate(plan, remainingLines: remaining, pace: nil, from: .now)
        let before = previous.flatMap { PlanStore.estimate($0, remainingLines: remaining, pace: nil, from: .now) }
        OnboardingPageLayout(
            pageCount: pageCount, currentPage: 3, actionsVisible: true,
            stage: { stage(before: moved(from: before, to: date) ? before : nil) },
            copy: { scale in
                if let date {
                    OnboardingHeadline(
                        first: Text("You'll finish, God willing,"),
                        second: Text("in \(month(date))"),
                        detail: summary,
                        scale: scale, visible: true
                    )
                    .contentTransition(.numericText())
                } else {
                    OnboardingHeadline(first: "You've memorized", second: "the whole Quran", detail: "", scale: scale, visible: true)
                }
            },
            buttons: { metrics in
                VStack(spacing: 14) {
                    BrandButton(title, metrics: metrics, action: onSave)
                    extra
                }
            }
        )
        .sensoryFeedback(.success, trigger: reached) { _, done in done }
        .onChange(of: isActive, initial: true) {
            guard isActive else { return }
            let from = memorization.quranShare(in: store) * Double(GlossyStairs.stepCount)
            climb = from
            reached = false
            guard !reduceMotion else {
                climb = Double(GlossyStairs.stepCount)
                return
            }
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation(.spring(duration: 1.6, bounce: 0.1)) { climb = Double(GlossyStairs.stepCount) }
                try? await Task.sleep(for: .milliseconds(1300))
                reached = true
            }
        }
    }

    /// «ذي الحجة ١٤٤٩»: the Hijri month and year — to follow «في», which puts ذو in the genitive, unless `genitive`
    /// is false.
    private func month(_ date: Date, genitive: Bool = true) -> String {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.locale = locale
        let name = calendar.monthSymbols[calendar.component(.month, from: date) - 1]
        let year = calendar.component(.year, from: date).formatted(.number.grouping(.never).locale(locale))
        let inflected = genitive && locale.language.languageCode == .arabic && name.hasPrefix("ذو ") ? "ذي " + name.dropFirst(3) : name
        return "\(inflected) \(year)"
    }

    /// «نصف وجه · ٦ أيام في الأسبوع»
    private var summary: Text {
        PlanFormat.amount(plan.dailyLines) + Text(verbatim: Separator.facts) + Text("\(plan.studyDays.count) days a week")
    }

    /// Whether a change moves the completion to another month.
    private func moved(from before: Date?, to date: Date?) -> Bool {
        guard let before, let date else { return false }
        return month(before) != month(date)
    }

    /// The stairs, and «قبل التعديل: ذو الحجة ١٤٥٠» below them when the change moves the date.
    private func stage(before: Date?) -> some View {
        let mirror: CGFloat = direction == .rightToLeft ? -1 : 1
        return ZStack {
            AqraGlowRings(open: true, breath: 0, glow: [Palette.butter, Palette.peach.opacity(0.5)])
                .scaleEffect(1.1)
            GlossyStairs(climb: climb)
                .environment(\.layoutDirection, direction)
                .scaleEffect(1.15)
            if let before {
                AqraChip(icon: "🗓️", tint: Palette.lavender) { Text("Before: \(month(before, genitive: false))") }
                    .rotationEffect(.degrees(-4 * mirror))
                    // Beneath the stairs, away from their low end; the offset follows the reading direction itself.
                    .offset(x: 70, y: 150)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: before)
        .frame(width: 420, height: 440)
    }
}

private typealias Palette = OnboardingPalette
