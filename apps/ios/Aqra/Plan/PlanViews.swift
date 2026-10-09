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
        }.joined(separator: Separator.arabic)
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
