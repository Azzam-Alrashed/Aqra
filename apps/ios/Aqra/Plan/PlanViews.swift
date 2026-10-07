import SwiftUI

/// How the plan is written across the app.
enum PlanFormat {
    /// «نصف وجه»: a daily amount in the Mushaf's own measure.
    static func amount(_ lines: Int) -> Text {
        switch lines {
        case 4: Text("¼ page")
        case 8: Text("½ page")
        case 11: Text("¾ page")
        case 15: Text("1 page")
        case 19: Text("1¼ pages")
        case 23: Text("1½ pages")
        default: Text("\(lines) lines")
        }
    }

    /// «الناس ١–٦ · الفلق ١–٥»: a portion's ayat, by surah, in the order they're memorized.
    static func portion(_ ayahs: [Int], store: MushafStore) -> String {
        var groups: [(surah: Int, first: Int, last: Int)] = []
        for ayah in ayahs {
            let reference = store.reference(ofAyah: ayah)
            if let last = groups.last, last.surah == reference.surah, last.last == reference.ayah - 1 {
                groups[groups.count - 1].last = reference.ayah
            } else {
                groups.append((reference.surah, reference.ayah, reference.ayah))
            }
        }
        return groups.map { group in
            let name = store.surahNames[group.surah] ?? ""
            let range = group.first == group.last ? arabic(group.first) : "\(arabic(group.first))–\(arabic(group.last))"
            return "\(name) \(range)"
        }.joined(separator: " · ")
    }

    /// «رجب ١٤٤٩»: a far date, by the Hijri month.
    static func month(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.month(.wide).year()
        style.calendar = Calendar(identifier: .islamicUmmAlQura)
        return date.formatted(style)
    }

    static func arabic(_ number: Int) -> String {
        number.formatted(.number.locale(Locale(identifier: "ar@numbers=arab")))
    }
}

// MARK: - Setting the plan

/// «كم تحفظ يوميًا؟»: the personal plan — how much new memorization a day, on which days, in which order — with the
/// completion date it leads to. Shown at the end of setup, and later to change the plan.
struct PlanEditorView: View {
    var store: MushafStore
    /// The last step of setup, where it can be left for later, rather than a sheet changing the plan.
    var isSetup = false
    var onDone: (MemorizationPlan?) -> Void

    @Environment(PlanStore.self) private var planStore
    @Environment(MemorizationStore.self) private var memorization
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MemorizationPlan(dailyLines: PlanPolicy.standard.defaultAmount,
                                                studyDays: PlanPolicy.standard.defaultStudyDays, order: .fromEnd)
    @State private var prepared = false
    @State private var confirmingStop = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 0) {
                    Text("How much will you memorize").foregroundStyle(Palette.ink)
                    Text("each day?").foregroundStyle(Palette.brand)
                }
                .font(.system(size: 30, weight: .heavy))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, isSetup ? 28 : 24)
                Text("A little every day, and the review engine keeps it.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)

                amountCard
                daysCard
                orderCard
                estimate
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) { buttons }
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .sensoryFeedback(.selection, trigger: draft)
        .animation(.snappy, value: draft)
        .onAppear(perform: prepare)
        .alert("Stop your plan?", isPresented: $confirmingStop) {
            Button("Stop", role: .destructive) { finish(nil) }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("What you've memorized stays, and its revision goes on. You can start a plan again anytime.")
        }
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        if let plan = planStore.plan {
            draft = plan
        } else {
            draft.order = PlanStore.suggestedOrder(memorization: memorization, store: store)
        }
    }

    // MARK: - The choices

    private var amountCard: some View {
        AqraCard(padding: 14, radius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                label(icon: "✍️", tint: Palette.butter, title: Text("Daily amount"))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(PlanPolicy.standard.amountOptions, id: \.self) { lines in
                        let selected = draft.dailyLines == lines
                        Button {
                            draft.dailyLines = lines
                        } label: {
                            PlanFormat.amount(lines)
                                .font(.system(size: 15, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(selected ? .white : Palette.brand)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(selected ? AnyShapeStyle(LinearGradient(colors: [Palette.brand, Palette.brandDeep], startPoint: .top, endPoint: .bottom))
                                                     : AnyShapeStyle(Palette.lavender), in: Capsule())
                        }
                        .buttonStyle(AqraPressStyle())
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var daysCard: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let names = calendar.standaloneWeekdaySymbols
        // The week from its first day in this locale, Saturday or Sunday or Monday.
        let days = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        return AqraCard(padding: 14, radius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    label(icon: "🗓️", tint: Palette.peach, title: Text("Study days"))
                    Spacer()
                    Text("\(draft.studyDays.count) days a week")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.brand)
                }
                HStack(spacing: 6) {
                    ForEach(days, id: \.self) { weekday in
                        let on = draft.studyDays.contains(weekday)
                        Button {
                            if on, draft.studyDays.count > 1 { draft.studyDays.remove(weekday) } else { draft.studyDays.insert(weekday) }
                        } label: {
                            Text(verbatim: symbols[weekday - 1])
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(on ? .white : Palette.inkSoft)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(on ? Palette.brand : Palette.lavender, in: Circle())
                        }
                        .buttonStyle(AqraPressStyle())
                        .accessibilityLabel(Text(verbatim: names[weekday - 1]))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var orderCard: some View {
        AqraCard(padding: 14, radius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                label(icon: "🧭", tint: Palette.sky, title: Text("Where to go next"))
                AqraSegmented(selection: $draft.order, options: [(.fromEnd, "From juz' ʿAmma"), (.fromStart, "From al-Baqarah")])
                Text(draft.order == .fromEnd
                     ? "From an-Nas back toward al-Baqarah, each surah from its first ayah."
                     : "From the beginning of the Mushaf, in its order.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var estimate: some View {
        let remaining = PlanStore.remainingLines(memorization: memorization, store: store)
        let date = PlanStore.estimate(draft, remainingLines: remaining, pace: nil, from: .now)
        return Group {
            if let date {
                AqraChip(icon: "🏁", tint: Palette.mint) {
                    Text("Your expected completion, God willing: \(PlanFormat.month(date))")
                }
            } else {
                AqraChip(icon: "⭐️", tint: Palette.butter) { Text("You've memorized the whole Quran") }
            }
        }
        .contentTransition(.numericText())
        .padding(.top, 4)
    }

    private func label(icon: String, tint: Color, title: Text) -> some View {
        HStack(spacing: 10) {
            IconTile(icon: icon, tint: tint, size: 32)
            title
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Palette.ink)
        }
    }

    // MARK: - Buttons

    private var buttons: some View {
        VStack(spacing: 10) {
            BrandButton(isSetup || planStore.plan == nil ? "Start my plan" : "Save",
                        metrics: OnboardingButtonMetrics(height: 56, fontSize: 18, compact: false)) {
                var plan = draft
                plan.paused = false
                finish(plan)
            }
            if isSetup {
                Button("Not now") { finish(nil) }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.brand)
            } else if let plan = planStore.plan {
                HStack(spacing: 20) {
                    Button(plan.paused ? "Resume" : "Pause") {
                        var changed = plan
                        changed.paused.toggle()
                        planStore.setPlan(changed)
                        onDone(changed)
                        dismiss()
                    }
                    Button("Stop the plan") { confirmingStop = true }
                        .foregroundStyle(Color(light: 0xB3261E, dark: 0xB3261E))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.brand)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(Palette.surface.opacity(0.95))
    }

    private func finish(_ plan: MemorizationPlan?) {
        // In setup, «ليس الآن» leaves no plan; outside it, only «إيقاف الخطة» removes one.
        if plan != nil || !isSetup { planStore.setPlan(plan) }
        onDone(plan)
        if !isSetup { dismiss() }
    }
}

// MARK: - Today's portion on the home

/// Today's new memorization on the home: the portion and «احفظ», done for today, or a day of rest — with the date
/// the plan leads to. Without a plan, an invitation to make one.
struct PortionCard: View {
    var store: MushafStore
    var onMemorize: ([Int]) -> Void
    var onEditPlan: () -> Void

    @Environment(PlanStore.self) private var plan
    @Environment(MemorizationStore.self) private var memorization

    var body: some View {
        AqraCard(padding: 14, radius: 24) {
            if plan.plan == nil {
                invitation
            } else if let today = plan.today(memorization: memorization, store: store) {
                content(today)
            } else {
                paused
            }
        }
    }

    private var invitation: some View {
        Button(action: onEditPlan) {
            HStack(spacing: 12) {
                IconTile(icon: "✍️", tint: Palette.butter, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memorize new portions")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    Text("A daily amount, and the date you'd complete the Quran")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                AqraChevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var paused: some View {
        Button(action: onEditPlan) {
            HStack(spacing: 12) {
                IconTile(icon: "⏸️", tint: Palette.lavender, size: 40)
                Text("Your memorization plan is paused")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 4)
                AqraChevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func content(_ today: TodayPortion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(icon: icon(today), tint: tint(today), size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    title(today)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                    detail(today)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                Button(action: onEditPlan) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Palette.brand)
                        .frame(width: 30, height: 30)
                        .background(Palette.lavender, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Your plan"))
            }
            if case .due(let portion) = today {
                Button {
                    onMemorize(portion)
                } label: {
                    Label("Memorize", systemImage: "book.pages")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(LinearGradient(colors: [Palette.brand, Palette.brandDeep], startPoint: .top, endPoint: .bottom), in: Capsule())
                }
                .buttonStyle(AqraPressStyle())
            }
            if let date = plan.completionDate(memorization: memorization, store: store) {
                Text("Your expected completion, God willing: \(PlanFormat.month(date))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.brand)
            }
        }
    }

    private func icon(_ today: TodayPortion) -> String {
        switch today {
        case .due: "✍️"
        case .done: "✅"
        case .restDay: "🌙"
        case .complete: "⭐️"
        }
    }

    private func tint(_ today: TodayPortion) -> Color {
        switch today {
        case .due: Palette.butter
        case .done: Palette.mint
        case .restDay: Palette.lavender
        case .complete: Palette.butter
        }
    }

    private func title(_ today: TodayPortion) -> Text {
        switch today {
        case .due: Text("Today's new portion")
        case .done: Text("Memorized today")
        case .restDay: Text("A rest day from new memorization")
        case .complete: Text("Every ayah is memorized")
        }
    }

    private func detail(_ today: TodayPortion) -> Text {
        switch today {
        case .due(let portion): Text(verbatim: PlanFormat.portion(portion, store: store))
        case .done(let portion): Text(verbatim: PlanFormat.portion(portion.memorized, store: store))
        case .restDay(let next): Text("Next portion \(next.formatted(.dateTime.weekday(.wide)))")
        case .complete: Text("May Allah bless you")
        }
    }
}

private typealias Palette = OnboardingPalette
