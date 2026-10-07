import SwiftUI

/// Today's wird, opened full screen over the home: its pages revised one after another, each veiled and revealed
/// ayah by ayah, and back home when the wird is done. The Mushaf keeps the page the student was reading.
struct WirdView: View {
    var store: MushafStore
    /// The page to revise first; the rest of today's wird follows it.
    var startPage: Int

    @Environment(MemorizationStore.self) private var memorization
    @Environment(RevisionStore.self) private var revision
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mushaf.tajweed") private var tajweed = true
    @AppStorage("mushaf.topics") private var topicColors = true
    @State private var session: RevisionSession?

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
        // A revision under way is never closed by a stray swipe.
        .interactiveDismissDisabled()
        .onAppear {
            if session == nil { start(startPage) }
        }
    }

    private func start(_ page: Int) {
        let ayahs = store.page(page).ayahs.filter { memorization.isMemorized($0) }
        session = RevisionSession(page: page, ayahs: ayahs)
    }

    /// Ends a page's revision. Recorded, it moves straight on to the next page of today's wird, and back home
    /// when the wird is done; left, it goes back home without recording the page.
    private func finish(_ session: RevisionSession, record: Bool) {
        guard record else {
            dismiss()
            return
        }
        revision.record(page: session.page, ayahs: session.ayahs, stumbles: session.stumbles,
                        source: .app, memorization: memorization)
        if let next = revision.plan?.items.first(where: { !$0.done }) {
            withAnimation(.easeInOut(duration: 0.25)) { start(next.page) }
        } else {
            dismiss()
        }
    }

    private func revisionBar(_ session: RevisionSession) -> some View {
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
                        Text("\(min(session.revealed, session.ayahs.count)) of \(session.ayahs.count)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(MushafStyle.chrome)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    if !session.stumbles.isEmpty {
                        Text("\(session.stumbles.count) stumbles")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(light: 0x9A3E26, dark: 0xF6C9B8))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(MushafStyle.stumble.opacity(0.6), in: Capsule())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text("Tap to reveal the next ayah, and tap a revealed ayah if you stumbled on it")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(MushafStyle.chrome)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 10) {
                    Button("Next ayah") { withAnimation(.easeOut(duration: 0.2)) { session.revealNext() } }
                        .buttonStyle(MarkingButtonStyle())
                        .disabled(session.isComplete)
                    Button("Show page") { withAnimation(.easeOut(duration: 0.2)) { session.revealAll() } }
                        .buttonStyle(MarkingButtonStyle())
                        .disabled(session.isComplete)
                    Button("Done") { finish(session, record: true) }
                        .buttonStyle(MarkingButtonStyle(prominent: true))
                }
            }
        }
        .animation(.snappy, value: session.stumbles.count)
        .sensoryFeedback(.selection, trigger: session.revealed)
        .sensoryFeedback(.impact(weight: .light), trigger: session.stumbles.count)
        .environment(\.layoutDirection, .rightToLeft)
    }
}
