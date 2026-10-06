import SwiftUI

/// The main screen: the Mushaf, opening on the last page read and turned like a book (right to left).
/// On a wide iPad it shows two facing pages, odd on the right, as in the printed Madinah Mushaf.
struct MushafView: View {
    var store: MushafStore

    @AppStorage("mushaf.lastPage") private var lastPage = 1
    @AppStorage("mushaf.tajweed") private var tajweed = true
    @AppStorage("mushaf.topics") private var topicColors = true
    @State private var toolbarVisible = false
    @State private var showingIndex = false
    /// The page shown while the slider is being dragged; committed to `lastPage` on release.
    @State private var sliderPage: Double?
    /// Set when the toolbar itself moves the page, so the toolbar stays open.
    @State private var movedByToolbar = false

    var body: some View {
        GeometryReader { geometry in
            let facingPages = geometry.size.width > geometry.size.height && geometry.size.width >= 900
            ZStack {
                Group {
                    if facingPages { spreadPager } else { pagePager }
                }
                .environment(\.mushafTajweed, tajweed)
                .environment(\.mushafTopics, topicColors)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { toolbarVisible.toggle() }
                }

                if toolbarVisible {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                        bottomBar
                    }
                    .transition(.opacity)
                }
            }
        }
        .background(MushafStyle.paper.ignoresSafeArea())
        .statusBarHidden(!toolbarVisible)
        // Swiping to another page hides the toolbar; jumps made from the toolbar keep it open.
        .onChange(of: lastPage) {
            if movedByToolbar {
                movedByToolbar = false
            } else if toolbarVisible {
                withAnimation(.easeInOut(duration: 0.2)) { toolbarVisible = false }
            }
        }
        // A light tick as each page turns, and a firmer one on entering a new juz'.
        .sensoryFeedback(.selection, trigger: lastPage)
        .sensoryFeedback(.impact(weight: .medium), trigger: store.page(lastPage).juz)
        .sheet(isPresented: $showingIndex) {
            MushafIndexView(store: store, currentPage: lastPage) { page in
                movedByToolbar = page != lastPage
                lastPage = page
                showingIndex = false
            }
        }
    }

    // MARK: - Pagers

    private var pagePager: some View {
        TabView(selection: $lastPage) {
            ForEach(1...MushafStore.pageCount, id: \.self) { number in
                MushafPageView(page: store.page(number), store: store)
                    .tag(number)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Page 1 sits on the right; the next page comes in from the left, as in a printed Mushaf.
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var spreadPager: some View {
        // Only a turn to another spread moves the page, so the left (even) page survives rotation.
        let spread = Binding<Int>(
            get: { (lastPage + 1) / 2 },
            set: { if $0 != (lastPage + 1) / 2 { lastPage = $0 * 2 - 1 } }
        )
        return TabView(selection: spread) {
            ForEach(1...(MushafStore.pageCount / 2), id: \.self) { number in
                MushafSpreadView(spread: number, store: store)
                    .tag(number)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, .rightToLeft)
    }

    // MARK: - Toolbar

    private var topBar: some View {
        let page = store.page(lastPage)
        return HStack {
            Button {
                showingIndex = true
            } label: {
                Label("Index", systemImage: "list.bullet")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(verbatim: store.surahNames[page.surah] ?? "")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(verbatim: "الجزء \(arabic(page.juz)) · الصفحة \(arabic(page.number))")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(MushafStyle.chrome)
            }
            Spacer()
            Menu {
                Toggle("Tajweed colors", isOn: $tajweed)
                Toggle("Topic colors", isOn: $topicColors)
            } label: {
                Label("Colors", systemImage: "paintpalette")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(MushafStyle.ink)
        .tint(MushafStyle.marker)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var bottomBar: some View {
        // Dragging only moves the number; the Mushaf turns once, to the page you let go on.
        let position = Binding<Double>(
            get: { sliderPage ?? Double(lastPage) },
            set: { sliderPage = $0 }
        )
        return HStack(spacing: 14) {
            Text(verbatim: arabic(Int(position.wrappedValue.rounded())))
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .frame(minWidth: 36)
            Slider(value: position, in: 1...Double(MushafStore.pageCount), step: 1) { editing in
                guard !editing, let target = sliderPage else { return }
                let page = Int(target.rounded())
                movedByToolbar = page != lastPage
                lastPage = page
                sliderPage = nil
            }
            .tint(MushafStyle.marker)
        }
        .foregroundStyle(MushafStyle.ink)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        // Page 1 at the right end of the slider, matching the direction pages turn.
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func arabic(_ number: Int) -> String {
        number.formatted(.number.locale(Locale(identifier: "ar@numbers=arab")))
    }
}

/// Two facing pages: the odd page on the right and the even page on the left, as in the printed Mushaf.
struct MushafSpreadView: View {
    var spread: Int
    var store: MushafStore

    var body: some View {
        HStack(spacing: 0) {
            MushafPageView(page: store.page(spread * 2 - 1), store: store)
            Rectangle().fill(MushafStyle.chrome.opacity(0.18)).frame(width: 1)
            MushafPageView(page: store.page(spread * 2), store: store)
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// Loads the Mushaf once, then shows it — or explains what's missing.
struct MushafRootView: View {
    @State private var store: Result<MushafStore, Error>?

    var body: some View {
        Group {
            switch store {
            case .success(let store):
                MushafView(store: store)
            case .failure(let error):
                ContentUnavailableView("The Mushaf couldn't be loaded", systemImage: "book.closed", description: Text(verbatim: "\(error)"))
            case nil:
                ZStack {
                    MushafStyle.paper.ignoresSafeArea()
                    ProgressView().tint(MushafStyle.chrome)
                }
            }
        }
        .task {
            guard store == nil else { return }
            // Decoding the Quran data takes a moment; keep it off the main thread so the app stays responsive.
            store = await Task.detached(priority: .userInitiated) { Result { try MushafStore() } }.value
        }
    }
}
