import SwiftUI

/// «كم تراجع يوميًا؟»: the pages to revise each day, with the length of a full revision cycle shown as it changes.
/// Shown right after «ماذا تحفظ؟», and later from today's plan to change it.
struct DailyAmountView: View {
    var memorizedPages: Int
    /// Changing an amount already set (from today's plan), rather than setting it the first time.
    var isEditor = false
    var onDone: (Int) -> Void

    @State private var amount: Int
    @Environment(\.dismiss) private var dismiss

    init(memorizedPages: Int, initial: Int, isEditor: Bool = false, onDone: @escaping (Int) -> Void) {
        self.memorizedPages = memorizedPages
        self.isEditor = isEditor
        self.onDone = onDone
        _amount = State(initialValue: min(max(initial, 1), 40))
    }

    /// The days a full pass through everything memorized takes at a daily amount.
    static func cycleDays(memorizedPages: Int, amount: Int) -> Int {
        max(Int((Double(memorizedPages) / Double(max(amount, 1))).rounded(.up)), 1)
    }

    var body: some View {
        let suggested = ReviewPolicy.suggestedDailyPages(memorizedPages: memorizedPages)
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                Text("How much will you").foregroundStyle(Palette.ink)
                Text("revise each day?").foregroundStyle(Palette.brand)
            }
            .font(.system(size: 30, weight: .heavy))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            HStack(spacing: 26) {
                stepButton("minus", enabled: amount > 1) { amount -= 1 }
                VStack(spacing: 2) {
                    Text(amount.formatted())
                        .font(.system(size: 76, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Palette.brand)
                        .contentTransition(.numericText(value: Double(amount)))
                    // A unit label under the large number, read the same whatever the number.
                    Text("pages a day")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
                .frame(minWidth: 130)
                stepButton("plus", enabled: amount < 40) { amount += 1 }
            }
            .animation(.snappy, value: amount)

            VStack(spacing: 8) {
                Text("A full revision every \(Self.cycleDays(memorizedPages: memorizedPages, amount: amount)) days")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: amount)
                if amount != suggested {
                    Button {
                        amount = suggested
                    } label: {
                        Text("Suggested: \(suggested)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.brand)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Palette.lavender, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .frame(minHeight: 70, alignment: .top)

            Spacer(minLength: 0)
            BrandButton(isEditor ? "Save" : "Begin", metrics: OnboardingButtonMetrics(height: 56, fontSize: 18, compact: false)) {
                onDone(amount)
                if isEditor { dismiss() }
            }
            .frame(maxWidth: 520)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fontDesign(.rounded)
        .background(Palette.surface.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .sensoryFeedback(.selection, trigger: amount)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(enabled ? Palette.brand : Palette.inkSoft.opacity(0.4))
                .frame(width: 60, height: 60)
                .background(.white, in: Circle())
                .overlay(Circle().strokeBorder(Palette.lavender, lineWidth: 1.5))
                .shadow(color: Palette.shadow.opacity(0.06), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .buttonRepeatBehavior(.enabled)
    }
}

private typealias Palette = OnboardingPalette
