import SwiftUI

/// The main screen: the Mushaf, opening on the last page read and turned like a book (right to left).
struct MushafView: View {
    var store: MushafStore

    @AppStorage("mushaf.lastPage") private var lastPage = 1

    var body: some View {
        TabView(selection: $lastPage) {
            ForEach(1...MushafStore.pageCount, id: \.self) { number in
                MushafPageView(page: store.page(number), store: store)
                    .tag(number)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Page 1 sits on the right; the next page comes in from the left, as in a printed Mushaf.
        .environment(\.layoutDirection, .rightToLeft)
        .background(MushafStyle.paper.ignoresSafeArea())
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
                MushafStyle.paper.ignoresSafeArea()
            }
        }
        .task {
            guard store == nil else { return }
            store = Result { try MushafStore() }
        }
    }
}
