import SwiftUI

/// «كم تراجع يوميًا؟»: the pages to revise each day, with the length of a full revision cycle shown as it changes.
/// Shown right after «ماذا تحفظ؟», and later from today's plan to change it.
struct DailyAmountView: View {
    var memorizedPages: Int
    /// Changing an amount already set (from today's plan), rather than setting it the first time.
    var isEditor = false
    /// In setup, back to the step before; nil hides «رجوع».
    var onBack: (() -> Void)?
    var onDone: (Int) -> Void

    @State private var amount: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    init(memorizedPages: Int, initial: Int, isEditor: Bool = false, onBack: (() -> Void)? = nil,
         onDone: @escaping (Int) -> Void) {
        self.memorizedPages = memorizedPages
        self.isEditor = isEditor
        self.onBack = onBack
        self.onDone = onDone
        _amount = State(initialValue: min(max(initial, 1), 40))
    }

    /// The days a full pass through everything memorized takes at a daily amount.
    static func cycleDays(memorizedPages: Int, amount: Int) -> Int {
        max(Int((Double(memorizedPages) / Double(max(amount, 1))).rounded(.up)), 1)
    }

    var body: some View {
        let suggested = ReviewPolicy.suggestedDailyPages(memorizedPages: memorizedPages)
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            stage(suggested: suggested)
            VStack(spacing: 0) {
                Text("How much will you").foregroundStyle(Palette.ink)
                Text("revise each day?").foregroundStyle(Palette.brand)
            }
            .aqraFont(size: 31, weight: .heavy)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, 8)
            Spacer(minLength: 0)
            BrandButton(isEditor ? "Save" : "Begin", metrics: OnboardingButtonMetrics(height: 56, fontSize: 18, compact: false)) {
                onDone(amount)
                if isEditor { dismiss() }
            }
            .frame(maxWidth: 520)
            .padding(.top, 24)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if let onBack {
                AqraBackButton(action: onBack)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
        }
        .fontDesign(.rounded)
        .background(Palette.surface.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .sensoryFeedback(.selection, trigger: amount)
    }

    /// «صفحات يوميًا» under the large number: the app's «%lld pages a day», which already agrees with the number in
    /// each language («صفحتان», «صفحات», «صفحة»), with the number itself taken out.
    private var unit: String {
        String(localized: "\(amount) pages a day", locale: locale)
            .replacingOccurrences(of: amount.formatted(.number.locale(locale)), with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// The amount in the glowing rings, − and + on either side, and chips for the cycle and the suggestion.
    private func stage(suggested: Int) -> some View {
        ZStack {
            HStack(spacing: 0) {
                stepButton("minus", enabled: amount > 1) { amount -= 1 }
                VStack(spacing: 0) {
                    Text(amount.formatted())
                        .font(.system(size: 76, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Palette.brand)
                        .contentTransition(.numericText(value: Double(amount)))
                    Text(verbatim: unit)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
                .frame(width: 170)
                stepButton("plus", enabled: amount < 40) { amount += 1 }
            }
            .animation(.snappy, value: amount)

            AqraChip(icon: "🗓️", tint: Palette.peach) {
                Text("A full revision every \(Self.cycleDays(memorizedPages: memorizedPages, amount: amount)) days")
                    .contentTransition(.numericText())
            }
            .animation(.snappy, value: amount)
            .rotationEffect(.degrees(-3))
            .offset(y: 132)

            if amount != suggested {
                Button {
                    amount = suggested
                } label: {
                    AqraChip(icon: "✨", tint: Palette.butter) { Text("Suggested: \(suggested)") }
                }
                .buttonStyle(AqraPressStyle())
                .rotationEffect(.degrees(4))
                .offset(y: -128)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: amount != suggested)
        .frame(height: 340)
        .frame(maxWidth: .infinity)
        // Behind the stage, so the glow spreads past its edges without widening the screen.
        .background {
            AqraGlowRings(open: true, breath: 0)
                .scaleEffect(1.02)
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
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

private typealias Palette = OnboardingPalette
