import SwiftUI

/// «وِرد اليوم»: today's pages to revise, opened from the pill on the Mushaf. Each page starts a revision in the
/// Mushaf, or can be checked off as revised elsewhere (in prayer, or to a friend).
struct TodayView: View {
    var store: MushafStore
    /// Opens a page in the Mushaf to revise it.
    var onStart: (Int) -> Void

    @Environment(MemorizationStore.self) private var memorization
    @Environment(RevisionStore.self) private var revision

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if let plan = revision.plan {
                        VStack(spacing: 12) {
                            ForEach(plan.items) { item in
                                card(item)
                            }
                        }
                        if !plan.isComplete {
                            Text("Revised a page outside the app? Press and hold it.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.inkSoft)
                                .multilineTextAlignment(.center)
                        }
                    }
                    amountRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        let plan = revision.plan
        let done = plan?.doneCount ?? 0, total = plan?.items.count ?? 0
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's revision")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer()
            ZStack {
                Circle().stroke(Palette.lavender, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: total == 0 ? 0 : Double(done) / Double(total))
                    .stroke(LinearGradient(colors: [Palette.brand, Palette.brandDeep], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if plan?.isComplete == true {
                    StarShape(points: 8, innerRatio: 0.42, cornerRadius: 0.05)
                        .fill(LinearGradient(colors: [Color(light: 0xF8D371, dark: 0xF8D371), Color(light: 0xEFB54A, dark: 0xEFB54A)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 28, height: 28)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("\(done) of \(total)")
                        .font(.system(size: 14, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Palette.brand)
                        .contentTransition(.numericText())
                }
            }
            .frame(width: 68, height: 68)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: done)
        }
        .padding(.top, 14)
    }

    // MARK: - Pages

    private func card(_ item: PlanItem) -> some View {
        let page = store.page(item.page)
        let face = ManazilStairs.face(forJuz: page.juz)
        return HStack(spacing: 14) {
            Text(item.page.formatted())
                .font(.system(size: 17, weight: .heavy).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .frame(width: 52, height: 52)
                .background(face.top, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: store.surahNames[page.surah] ?? "")
                    .font(.system(size: 18, weight: .bold))
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
            if item.done {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(face.bottom, in: Circle())
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button("Start") { onStart(item.page) }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(LinearGradient(colors: [Palette.brand, Palette.brandDeep], startPoint: .top, endPoint: .bottom),
                                in: Capsule())
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Palette.shadow.opacity(0.06), radius: 10, y: 5)
        .opacity(item.done ? 0.7 : 1)
        .contextMenu {
            if !item.done {
                Button {
                    recordOutside(item.page)
                } label: {
                    Label("Revised outside the app", systemImage: "checkmark.circle")
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: item.done)
    }

    private func recordOutside(_ page: Int) {
        let ayahs = store.page(page).ayahs.filter { memorization.isMemorized($0) }
        revision.record(page: page, ayahs: ayahs, stumbles: [], source: .outside, memorization: memorization)
    }

    // MARK: - Daily amount

    private var amountRow: some View {
        let memorizedPages = RevisionStore.memorizedPages(in: store, memorization: memorization).count
        let amount = revision.effectiveDailyPages(memorizedPages: memorizedPages)
        return NavigationLink {
            DailyAmountView(memorizedPages: memorizedPages, initial: amount, isEditor: true) { revision.setDailyPages($0) }
                .toolbar(.visible, for: .navigationBar)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(amount) pages a day")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text("A full revision every \(DailyAmountView.cycleDays(memorizedPages: memorizedPages, amount: amount)) days")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.inkSoft)
            }
            .padding(14)
            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.lavender, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

private typealias Palette = OnboardingPalette
