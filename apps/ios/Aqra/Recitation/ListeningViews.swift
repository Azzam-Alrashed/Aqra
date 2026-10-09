import SwiftUI

/// The revision panel while Aqra listens: what it's doing, how far the page is, the stumbles so far, and pausing.
struct ListeningPanel: View {
    var listener: RecitationListener
    var session: RevisionSession
    /// Stops listening and goes back to revealing by hand.
    var onStop: () -> Void
    var onDone: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Button(action: onStop) {
                    ListeningMic(level: listener.phase == .listening ? listener.level : 0,
                                 active: listener.phase == .listening)
                }
                .buttonStyle(AqraPressStyle())
                .accessibilityLabel(Text("Stop listening"))
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(MushafStyle.ink)
                    Text("Page \(session.page) · \(min(session.revealed, session.ayahs.count)) of \(session.ayahs.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(MushafStyle.chrome)
                        .contentTransition(.numericText())
                }
                Spacer()
                if !session.stumbles.isEmpty {
                    StumbleCount(count: session.stumbles.count)
                }
            }
            if case .failed(let failure) = listener.phase {
                Group {
                    switch failure {
                    case .microphone: Text("Aqra can't use the microphone. Allow it in Settings.")
                    case .model: Text("Listening couldn't start. Try again.")
                    }
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(MushafStyle.chrome)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            } else {
                LevelMeter(level: listener.phase == .listening ? listener.level : 0)
                Text("Tap an ayah to mark a stumble or take it back")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(MushafStyle.chrome)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 10) {
                switch listener.phase {
                case .listening, .preparing:
                    Button { listener.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                        .buttonStyle(MarkingButtonStyle())
                        .disabled(listener.phase == .preparing)
                case .paused:
                    Button { listener.resume() } label: { Label("Resume", systemImage: "mic.fill") }
                        .buttonStyle(MarkingButtonStyle())
                case .failed(.microphone):
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(MarkingButtonStyle())
                case .failed(.model):
                    Button("Try again") { Task { await listener.start() } }
                        .buttonStyle(MarkingButtonStyle())
                }
                Button("Done", action: onDone)
                    .buttonStyle(MarkingButtonStyle(prominent: true))
            }
        }
        .animation(.snappy, value: session.stumbles.count)
        .animation(.snappy, value: listener.phase)
    }

    @ViewBuilder private var title: some View {
        switch listener.phase {
        case .preparing: Text("Getting ready to listen…")
        case .listening: Text("Listening…")
        case .paused: Text("Paused")
        case .failed: Text("Not listening")
        }
    }
}

/// The page done, heard to its end: how it went, ayah by ayah, then on to the next page or once more.
struct ListeningSummary: View {
    var session: RevisionSession
    var store: MushafStore
    /// Whether another page of today's wird follows.
    var hasNextPage: Bool
    var onAgain: () -> Void
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 3) {
                Text("You finished page \(session.page)")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(MushafStyle.ink)
                Group {
                    if session.stumbles.isEmpty {
                        Text("Every ayah without a stumble")
                    } else {
                        Text("\(session.stumbles.count) stumbles")
                    }
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(MushafStyle.chrome)
            }
            if !session.stumbles.isEmpty {
                FlowChips(items: session.ayahs.filter(session.stumbles.contains)) { ayah in
                    chip(for: ayah)
                }
            }
            HStack(spacing: 10) {
                Button("Recite the page again", action: onAgain)
                    .buttonStyle(MarkingButtonStyle())
                Button(action: onNext) {
                    if hasNextPage {
                        Label("Next page", systemImage: "chevron.backward").labelStyle(TrailingIconLabel())
                    } else {
                        Text("Finish")
                    }
                }
                .buttonStyle(MarkingButtonStyle(prominent: true))
            }
            if hasNextPage {
                Text("The revision is recorded, and listening carries on to the next page")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(MushafStyle.chrome)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// «الآية ٤ · خطأ في الحفظ»
    private func chip(for ayah: Int) -> some View {
        let number = store.reference(ofAyah: ayah).ayah
        let kinds = MistakeType.allCases.filter { session.stumbleKinds[ayah]?.contains($0) ?? false }
        let prompted = kinds == [.prompting]
        var label = Text("Ayah \(number)")
        for kind in kinds { label = label + Text(verbatim: Separator.facts) + Text(kind.title) }
        return label
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(prompted ? Color(light: 0x7A5A12, dark: 0xF3DE98) : Color(light: 0x9A3E26, dark: 0xF6C9B8))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background((prompted ? MushafStyle.prompt : MushafStyle.stumble).opacity(0.7), in: Capsule())
    }
}

/// «نزّل وابدأ»: what listening does, the one-time download, and the promise that the voice stays on the device.
struct ListenSetupSheet: View {
    /// Called once the model is installed.
    var onReady: () -> Void

    @Environment(\.dismiss) private var dismiss
    private var model: RecitationModel { .shared }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "mic.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(OnboardingPalette.brand)
                .frame(width: 72, height: 72)
                .background(OnboardingPalette.lavender, in: Circle())
                .padding(.top, 28)
            Text("Recite aloud")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(OnboardingPalette.ink)
                .padding(.top, 14)
            Text("Recite from memory, and Aqra follows along")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(OnboardingPalette.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 12) {
                point("eye", "The ayat are revealed as you recite")
                point("flag", "What you stumble on is marked, and you can correct it")
                point("lightbulb", "After a long pause, the next word is shown")
                point("lock", "Your voice stays on your device and isn't kept")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 22)
            Spacer(minLength: 18)
            download
            Button("Not now") { dismiss() }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(OnboardingPalette.inkSoft)
                .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .fontDesign(.rounded)
        .environment(\.colorScheme, .light)
        .background(Color.white.ignoresSafeArea())
        .presentationDetents([.large])
        .onChange(of: model.state, initial: true) {
            if model.state == .ready {
                onReady()
                dismiss()
            }
        }
    }

    private func point(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(OnboardingPalette.brand)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(OnboardingPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var download: some View {
        let size = RecitationModel.downloadSize.formatted(.byteCount(style: .file))
        VStack(spacing: 8) {
            switch model.state {
            case .downloading(let fraction):
                ProgressView(value: fraction)
                    .tint(OnboardingPalette.brand)
                Text("Downloading… \(fraction.formatted(.percent.precision(.fractionLength(0))))")
            case .installing:
                ProgressView()
                Text("Preparing…")
            case .failed:
                Text("The download didn't finish. Try again.")
            case .absent, .ready:
                Text("A one-time download · \(size)")
            }
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(OnboardingPalette.inkSoft)
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(light: 0xF6F1E7, dark: 0xF6F1E7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 14)
        BrandButton(model.state == .failed ? "Try again" : "Download and begin",
                    metrics: OnboardingButtonMetrics(height: 56, fontSize: 18, compact: false)) {
            Task { await model.download() }
        }
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
    }

    private var isBusy: Bool {
        switch model.state {
        case .downloading, .installing: true
        default: false
        }
    }
}

/// The microphone in a purple circle, its ring swelling with the voice.
private struct ListeningMic: View {
    var level: Double
    var active: Bool

    var body: some View {
        Image(systemName: active ? "mic.fill" : "mic.slash.fill")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Circle().fill(active ? OnboardingPalette.brand : MushafStyle.chrome))
            .background(Circle().fill(MushafStyle.barAccentFill).padding(-4 - 6 * level))
            .animation(.easeOut(duration: 0.12), value: level)
            .frame(width: 52, height: 52)
    }
}

/// Eight bars that rise with the voice, the middle ones most.
private struct LevelMeter: View {
    var level: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<9) { index in
                let weight = 1 - abs(Double(index) - 4) / 5
                Capsule()
                    .fill(OnboardingPalette.brand.opacity(0.35 + 0.65 * weight))
                    .frame(width: 3.5, height: 4 + 18 * level * weight)
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }
}

/// «٢ تعثّر» in a coral capsule.
struct StumbleCount: View {
    var count: Int

    var body: some View {
        Text("\(count) stumbles")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color(light: 0x9A3E26, dark: 0xF6C9B8))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(MushafStyle.stumble.opacity(0.6), in: Capsule())
            .transition(.scale.combined(with: .opacity))
    }
}

/// A label with its icon after the title, as «الصفحة التالية ←» reads.
private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

/// Chips laid in rows, centered, wrapping as they need.
private struct FlowChips<Item: Hashable, Chip: View>: View {
    var items: [Item]
    @ViewBuilder var chip: (Item) -> Chip

    var body: some View {
        WordFlow(spacing: 6, lineSpacing: 6) {
            ForEach(items, id: \.self) { chip($0) }
        }
    }
}
