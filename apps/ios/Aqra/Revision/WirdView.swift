import SwiftUI

/// Today's wird, opened full screen over the home: its pages revised one after another, each veiled and revealed
/// ayah by ayah, and back home when the wird is done. The Mushaf keeps the page the student was reading.
struct WirdView: View {
    var store: MushafStore
    /// The page to revise first; the rest of today's wird follows it.
    var startPage: Int
    /// A page revised outside the app, with stumbles to record: shown whole, recorded as revised outside, alone.
    var outside = false

    @Environment(MemorizationStore.self) private var memorization
    @Environment(RevisionStore.self) private var revision
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mushaf.tajweed") private var tajweed = true
    @AppStorage("mushaf.topics") private var topicColors = true
    /// Whether the student revises aloud, Aqra following by ear; kept for the next revision.
    @AppStorage("recitation.listens") private var listens = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: RevisionSession?
    @State private var listener: RecitationListener?
    @State private var settingUpListening = false

    var body: some View {
        GeometryReader { geometry in
            let facingPages = geometry.size.width > geometry.size.height && geometry.size.width >= 900
            // The bars stay for the whole revision, so the page sits between them rather than under them:
            // every ayah stays in sight as it's revealed.
            VStack(spacing: 6) {
                if let session {
                    MushafTopBar(page: store.page(session.page), store: store) {
                        EmptyView()
                    } trailing: {
                        FloatingCapsule { MushafColorsMenu() }
                    }
                    // A revision holds its page still: no turning until it's done.
                    Group {
                        if facingPages {
                            MushafSpreadView(spread: (session.page + 1) / 2, store: store)
                        } else {
                            MushafPageView(page: store.page(session.page), store: store)
                        }
                    }
                    .environment(\.mushafTajweed, tajweed)
                    .environment(\.mushafTopics, topicColors)
                    .environment(session)
                    .id(session.page)
                    .transition(.opacity)
                    .frame(maxHeight: .infinity)
                    revisionBar(session)
                }
            }
        }
        .background(MushafStyle.paper.ignoresSafeArea())
        .followsSystemColorScheme()
        // A revision under way is never closed by a stray swipe.
        .interactiveDismissDisabled()
        .onAppear {
            if session == nil { start(startPage) }
        }
        .onDisappear { listener?.pause() }
        // The microphone stops in the background; listening waits to be resumed.
        .onChange(of: scenePhase) { if scenePhase != .active { listener?.pause() } }
        .sheet(isPresented: $settingUpListening) {
            ListenSetupSheet {
                if let session { startListening(session) }
            }
        }
    }

    private func start(_ page: Int) {
        let ayahs = store.page(page).ayahs.filter { memorization.isMemorized($0) }
        let session = RevisionSession(page: page, ayahs: ayahs)
        if outside { session.revealAll() }
        self.session = session
        if let listener {
            listener.follow(session)
            if listener.phase == .paused { listener.resume() }
        } else if listens, !outside, RecitationModel.isInstalled {
            startListening(session)
        }
    }

    /// «سمّع بصوتك»: listens right away once the model is on the device; the first time, explains and downloads it.
    private func beginListening(_ session: RevisionSession) {
        if RecitationModel.isInstalled {
            startListening(session)
        } else {
            settingUpListening = true
        }
    }

    private func startListening(_ session: RevisionSession) {
        let listener = RecitationListener(session: session, store: store)
        self.listener = listener
        listens = true
        Task { await listener.start() }
    }

    /// Back to revealing by hand, for this revision and the next.
    private func stopListening() {
        listener?.pause()
        listener = nil
        listens = false
    }

    /// Whether a page of today's wird is left after this one.
    private func hasNextPage(after session: RevisionSession) -> Bool {
        revision.plan?.items.contains { !$0.done && $0.page != session.page } ?? false
    }

    /// Ends a page's revision. Recorded, it moves straight on to the next page of today's wird, and back home
    /// when the wird is done; left, it goes back home without recording the page.
    private func finish(_ session: RevisionSession, record: Bool) {
        guard record else {
            dismiss()
            return
        }
        revision.record(page: session.page, ayahs: session.ayahs, stumbles: session.stumbles,
                        source: outside ? .outside : .app, memorization: memorization)
        if !outside, let next = revision.plan?.items.first(where: { !$0.done }) {
            withAnimation(.easeInOut(duration: 0.25)) { start(next.page) }
        } else {
            dismiss()
        }
    }

    @ViewBuilder private func revisionBar(_ session: RevisionSession) -> some View {
        if let listener, !outside {
            FloatingPanel {
                if session.isComplete {
                    ListeningSummary(session: session, store: store, hasNextPage: hasNextPage(after: session)) {
                        withAnimation(.easeInOut(duration: 0.25)) { start(session.page) }
                    } onNext: {
                        finish(session, record: true)
                    }
                } else {
                    ListeningPanel(listener: listener, session: session) {
                        withAnimation(.snappy) { stopListening() }
                    } onDone: {
                        finish(session, record: true)
                    }
                }
            }
            .animation(.snappy, value: session.isComplete)
            .sensoryFeedback(.selection, trigger: session.revealed)
            .sensoryFeedback(.impact(weight: .light), trigger: session.stumbles.count)
            .sensoryFeedback(.success, trigger: session.isComplete) { _, done in done }
            .environment(\.layoutDirection, .rightToLeft)
        } else {
            manualBar(session)
        }
    }

    private func manualBar(_ session: RevisionSession) -> some View {
        FloatingPanel {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Button {
                        finish(session, record: false)
                    } label: {
                        Label("Leave revision", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(MushafStyle.barAccent)
                            .frame(width: 38, height: 38)
                            .background(MushafStyle.barAccentFill, in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Page \(session.page)")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(MushafStyle.ink)
                        Group {
                            if session.stumbles.isEmpty {
                                Text("\(min(session.revealed, session.ayahs.count)) of \(session.ayahs.count)")
                            } else {
                                Text("\(min(session.revealed, session.ayahs.count)) of \(session.ayahs.count)") + Text(verbatim: Separator.facts)
                                    + Text("\(session.stumbles.count) stumbles").foregroundStyle(Color(light: 0x9A3E26, dark: 0xF6C9B8))
                            }
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(MushafStyle.chrome)
                        .contentTransition(.numericText())
                    }
                    Spacer()
                    MushafModeChip(mode: .revising)
                }
                Group {
                    if outside {
                        Text("Tap the ayat you stumbled on when you revised this page")
                    } else if session.isComplete {
                        Text("Tap an ayah to mark or clear a stumble, then Done")
                    } else {
                        Text("Recite the next ayah from memory, then reveal it")
                    }
                }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(MushafStyle.chrome)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if !outside && !session.isComplete {
                    Button("Next ayah") { withAnimation(.easeOut(duration: 0.2)) { session.revealNext() } }
                        .buttonStyle(MarkingButtonStyle(prominent: true))
                }
                HStack(spacing: 10) {
                    if !outside && !session.isComplete {
                        Button("I stumbled here") { withAnimation(.easeOut(duration: 0.2)) { session.stumbleOnNext() } }
                            .buttonStyle(StumbleButtonStyle())
                        Button("Show page") { withAnimation(.easeOut(duration: 0.2)) { session.revealAll() } }
                            .buttonStyle(MarkingButtonStyle())
                    }
                    Button("Done") { finish(session, record: true) }
                        .buttonStyle(MarkingButtonStyle(prominent: outside || session.isComplete))
                }
                let canListen = !outside && !session.isComplete && RecitationModel.shared.isAvailable
                if canListen {
                    Button { withAnimation(.snappy) { beginListening(session) } } label: {
                        Label("Recite aloud instead", systemImage: "mic.fill")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(MushafStyle.barAccent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .animation(.snappy, value: session.stumbles.count)
        .animation(.snappy, value: session.isComplete)
        .sensoryFeedback(.selection, trigger: session.revealed)
        .sensoryFeedback(.impact(weight: .light), trigger: session.stumbles.count)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// «تعثّرتُ هنا»: the stumble color, a soft red that says what it does.
private struct StumbleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .foregroundStyle(Color(light: 0x9A3E26, dark: 0xF6C9B8))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(MushafStyle.stumble.opacity(configuration.isPressed ? 0.8 : 0.55), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
