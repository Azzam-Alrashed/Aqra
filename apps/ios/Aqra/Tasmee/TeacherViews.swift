import SwiftUI

// MARK: - A teacher, with sessions to book

/// A teacher's profile and the sessions they hold; a signed-in student books a seat here.
struct TeacherView: View {
    var teacher: Teacher
    var store: MushafStore

    @Environment(TasmeeStore.self) private var tasmee
    @Environment(AccountStore.self) private var account
    @Environment(MemorizationStore.self) private var memorization
    /// Nil while loading.
    @State private var sessions: [TasmeeSession]?
    /// The session being booked or given back.
    @State private var working: String?
    @State private var problem: AccountStore.Problem?
    @State private var bidding: TasmeeSession?
    /// This student's bids, by session: a student holds a free seat or a bid, not both.
    @State private var myBids: [String: Bid] = [:]
    @State private var choosingFreeSeat: TasmeeSession?

    private var signedIn: Bool { account.profile?.isAnonymous == false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AqraCard(padding: 14, radius: 24) {
                    HStack(alignment: .top, spacing: 12) {
                        IconTile(icon: "🎓", tint: Palette.mint, size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: teacher.name)
                                .aqraFont(size: 22, weight: .heavy)
                                .foregroundStyle(Palette.ink)
                            if !teacher.city.isEmpty {
                                Text(verbatim: teacher.city)
                                    .aqraFont(size: 13, weight: .bold)
                                    .foregroundStyle(Palette.brand)
                            }
                            if !teacher.line.isEmpty {
                                Text(verbatim: teacher.line)
                                    .aqraFont(size: 12, weight: .semibold)
                                    .foregroundStyle(Palette.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }

                AqraSectionTitle(title: "Upcoming sessions").padding(.top, 10)
                if let sessions {
                    if sessions.isEmpty {
                        note(Text("No sessions scheduled yet."))
                    } else {
                        AqraCard(padding: 0, radius: 24) {
                            VStack(spacing: 0) {
                                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                                    if index > 0 { AqraRowDivider() }
                                    sessionRow(session)
                                    // Once the student has a seat, the auction is no longer theirs to join.
                                    if let auction = session.auction, !tasmee.hasBooked(session),
                                       auction.isOpen() || activeBid(in: session) != nil {
                                        auctionStrip(session, auction)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ProgressView().tint(Palette.brand).frame(maxWidth: .infinity)
                }

                if !signedIn && AccountStore.isAvailable {
                    AqraCard(padding: 14, radius: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sign in to book a seat")
                                .aqraFont(size: 16, weight: .heavy)
                                .foregroundStyle(Palette.ink)
                            SignInButtons()
                            if let problem = account.problem {
                                ProblemLine(problem: problem)
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                if let problem {
                    ProblemLine(problem: problem).padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: tasmee.bookings)
        }
        .scrollIndicators(.hidden)
        .background(Palette.surface.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $bidding, onDismiss: { Task { await load() } }) { session in BidSheet(session: session, store: store) }
        .alert("Book a free seat instead?", isPresented: Binding(get: { choosingFreeSeat != nil }, set: { if !$0 { choosingFreeSeat = nil } }),
               presenting: choosingFreeSeat) { session in
            Button("Book the free seat") {
                Task {
                    await change(session) {
                        try await tasmee.takeFreeSeat(instead: session, name: studentName, memorizedPages: memorizedPages,
                                                      juzSummary: juzSummary)
                    }
                }
            }
            Button("Keep my bid", role: .cancel) {}
        } message: { session in
            Text("Your bid of \(activeBid(in: session)?.amount ?? 0) credits is let go, and its credits come back to you.")
        }
    }

    /// The student's bid in a session, while it holds a seat.
    private func activeBid(in session: TasmeeSession) -> Bid? {
        myBids[session.id].flatMap { $0.status == .active ? $0 : nil }
    }

    /// A session's seats by auction: what a bid takes now, and «زايد»; with the student's bid, where it stands, and
    /// the free seat to take instead.
    private func auctionStrip(_ session: TasmeeSession, _ auction: TasmeeSession.Auction) -> some View {
        let bid = activeBid(in: session)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(verbatim: "🔨")
                    .aqraFont(size: 16)
                    .frame(width: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(auction.seats) seats by auction")
                        .aqraFont(size: 13, weight: .heavy)
                        .foregroundStyle(Palette.ink)
                    Group {
                        if let bid {
                            Text("Your bid of \(bid.amount) holds a seat")
                        } else if auction.nextAtLeast == 0 {
                            Text("Free while seats remain")
                        } else {
                            Text("Next bid from \(auction.nextAtLeast) credits")
                        }
                    }
                    .aqraFont(size: 11, weight: .semibold)
                    .foregroundStyle(bid == nil ? Palette.inkSoft : Palette.brand)
                }
                Spacer()
                if signedIn && auction.isOpen() {
                    Button(bid == nil ? "Bid" : "Raise") { bidding = session }
                        .buttonStyle(ChipButtonStyle(filled: false))
                }
            }
            if signedIn, bid != nil, !session.isFull, working != session.id {
                Button("Book a free seat instead") { choosingFreeSeat = session }
                    .buttonStyle(ChipButtonStyle(filled: false))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func note(_ text: Text) -> some View {
        text
            .aqraFont(size: 14, weight: .medium)
            .foregroundStyle(Palette.inkSoft)
            .padding(.horizontal, 6)
    }

    private func sessionRow(_ session: TasmeeSession) -> some View {
        let booked = tasmee.hasBooked(session)
        let seats = booked ? Text("Booked") : Text("Seats left: \(session.seatsLeft)")
        return AqraRow(icon: session.kind == .video ? "🎥" : "📅", tint: Palette.sky,
                       title: Text(verbatim: TasmeeFormat.when(session.startsAt)),
                       detail: seats + Text(verbatim: Separator.facts) + TasmeeFormat.place(session)) {
            if working == session.id {
                ProgressView().tint(Palette.brand)
            } else if booked {
                Button("Cancel") {
                    Task { await change(session) { try await tasmee.cancelBooking(Booking(session)) } }
                }
                .buttonStyle(ChipButtonStyle(filled: false))
            } else if !signedIn || activeBid(in: session) != nil {
                // A bidder takes the free seat instead from the auction's strip.
                EmptyView()
            } else if session.isFull {
                Text("Full")
                    .aqraFont(size: 13, weight: .bold)
                    .foregroundStyle(Palette.inkSoft)
            } else {
                Button("Book") {
                    Task {
                        await change(session) {
                            try await tasmee.book(session, name: studentName, memorizedPages: memorizedPages, juzSummary: juzSummary)
                        }
                    }
                }
                .buttonStyle(ChipButtonStyle(filled: true))
            }
        }
    }

    private func change(_ session: TasmeeSession, _ action: () async throws -> Void) async {
        working = session.id
        problem = nil
        defer { working = nil }
        do {
            try await action()
            await load()
        } catch {
            problem = AccountStore.problem(for: error)
        }
    }

    private func load() async {
        do {
            let sessions = try await tasmee.upcomingSessions(of: teacher.id)
            myBids = await tasmee.myBids(in: sessions)
            self.sessions = sessions
        } catch {
            sessions = sessions ?? []
            problem = AccountStore.problem(for: error)
        }
    }

    // What the teacher sees of the student: their name and what they've memorized.

    private var studentName: String {
        account.publicName ?? String(localized: "A student")
    }

    private var memorizedPages: Int {
        RevisionStore.memorizedPages(in: store, memorization: memorization).count
    }

    /// The juz' memorized in full, as numbers: «29, 30».
    private var juzSummary: String? {
        let full = (1...30).filter { juz in
            store.juzAyahs[juz].map { memorization.memorizedCount(in: $0) == $0.count } ?? false
        }
        return full.isEmpty ? nil : full.map(String.init).joined(separator: ", ")
    }
}

/// A small capsule button at the end of a row: purple when filled, lavender otherwise; faded when disabled.
struct ChipButtonStyle: ButtonStyle {
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration, filled: filled)
    }

    private struct Chip: View {
        var configuration: Configuration
        var filled: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .aqraFont(size: 13, weight: .bold)
                .lineLimit(1)
                .foregroundStyle(filled ? .white : OnboardingPalette.brand)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .frame(minHeight: 30)
                .background(filled ? OnboardingPalette.brand : OnboardingPalette.lavender, in: Capsule())
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
        }
    }
}

// MARK: - A session, new or edited

/// A teacher schedules a session, or changes one: when, in person (where) or by video, and how many seats.
struct SessionEditor: View {
    /// The session being changed, or nil for a new one.
    var session: TasmeeSession?

    @Environment(TasmeeStore.self) private var tasmee
    @Environment(\.dismiss) private var dismiss
    @State private var startsAt: Date
    @State private var kind: TasmeeSession.Kind
    @State private var place: String
    @State private var seats: Int
    @State private var auctionSeats = 0
    @State private var minBid = 0

    init(session: TasmeeSession?) {
        self.session = session
        _startsAt = State(initialValue: session?.startsAt ?? Self.suggestedStart)
        _kind = State(initialValue: session?.kind ?? .inPerson)
        _place = State(initialValue: session?.place ?? "")
        _seats = State(initialValue: session?.seats ?? 5)
    }

    /// Tomorrow, on the hour.
    private static var suggestedStart: Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return Calendar.current.date(bySetting: .minute, value: 0, of: tomorrow) ?? tomorrow
    }

    private var trimmedPlace: String { place.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// When bidding would close for the start chosen; nil when it's too soon for auctioned seats.
    private var biddingClosesAt: Date? { TasmeeStore.biddingClosesAt(startsAt: startsAt) }
    /// A session's seats can't go below the students who already booked.
    private var minimumSeats: Int { max(session?.booked ?? 0, 1) }
    private var isValid: Bool { kind == .video || !trimmedPlace.isEmpty }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Text(session == nil ? "New session" : "Edit session")
                .aqraFont(size: 26, weight: .heavy)
                .foregroundStyle(Palette.ink)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            if session == nil {
                AqraSegmented(selection: $kind, options: [(.inPerson, "In person"), (.video, "Video")])
            }
            AqraCard(padding: 0, radius: 24) {
                VStack(spacing: 0) {
                    row(Text("When")) {
                        DatePicker("When", selection: $startsAt, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                    if kind == .inPerson {
                        AqraRowDivider().padding(.leading, -50)
                        row(Text("Place")) {
                            TextField("Place", text: $place)
                                .multilineTextAlignment(.trailing)
                                .aqraFont(size: 15, weight: .medium)
                        }
                    }
                    AqraRowDivider().padding(.leading, -50)
                    row(Text("Seats")) {
                        HStack(spacing: 10) {
                            stepButton("minus", enabled: seats > minimumSeats) { seats -= 1 }
                            Text(seats.formatted())
                                .aqraFont(size: 17, weight: .heavy, monospacedDigit: true)
                                .foregroundStyle(Palette.ink)
                                .frame(minWidth: 28)
                                .contentTransition(.numericText())
                            stepButton("plus", enabled: seats < 30) { seats += 1 }
                        }
                    }
                }
            }
            if session == nil {
                AqraCard(padding: 0, radius: 24) {
                    VStack(spacing: 0) {
                        row(Text("Seats by auction")) {
                            HStack(spacing: 10) {
                                stepButton("minus", enabled: auctionSeats > 0) { auctionSeats -= 1 }
                                Text(auctionSeats.formatted())
                                    .aqraFont(size: 17, weight: .heavy, monospacedDigit: true)
                                    .foregroundStyle(Palette.ink)
                                    .frame(minWidth: 28)
                                    .contentTransition(.numericText())
                                stepButton("plus", enabled: auctionSeats < 20 && biddingClosesAt != nil) { auctionSeats += 1 }
                            }
                        }
                        if auctionSeats > 0 {
                            AqraRowDivider().padding(.leading, -50)
                            row(Text("Lowest bid")) {
                                HStack(spacing: 10) {
                                    stepButton("minus", enabled: minBid > 0) { minBid -= 1 }
                                    Text(minBid.formatted())
                                        .aqraFont(size: 17, weight: .heavy, monospacedDigit: true)
                                        .foregroundStyle(Palette.ink)
                                        .frame(minWidth: 28)
                                        .contentTransition(.numericText())
                                    stepButton("plus", enabled: minBid < 100) { minBid += 1 }
                                }
                            }
                        }
                    }
                }
                Group {
                    if let closesAt = biddingClosesAt {
                        if auctionSeats > 0 {
                            if startsAt.timeIntervalSince(closesAt) >= TasmeeStore.biddingClosesBefore {
                                Text("Beside the free seats, these go to the highest bids, in credits. Bidding closes three hours before the session; you earn most of each winning bid.")
                            } else {
                                Text("Beside the free seats, these go to the highest bids, in credits. The session is soon, so bidding closes 30 minutes before it; you earn most of each winning bid.")
                            }
                        }
                    } else {
                        Text("A session less than an hour away offers free seats only: there's no time to bid.")
                    }
                }
                .aqraFont(size: 12, weight: .medium)
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
            }
            if kind == .video {
                Text("Students who book join the call from the session's page, from 15 minutes before it starts.")
                    .aqraFont(size: 12, weight: .medium)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
            Spacer(minLength: 0)
            BrandButton(session == nil ? "Create" : "Save", metrics: OnboardingButtonMetrics(height: 56, fontSize: 18, compact: false)) {
                save()
                dismiss()
            }
            .disabled(!isValid)
            .opacity(isValid ? 1 : 0.5)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .animation(.snappy, value: seats)
        .animation(.snappy, value: kind)
        .animation(.snappy, value: auctionSeats)
        // A start moved too close for bidding takes the auctioned seats away.
        .onChange(of: startsAt) {
            if biddingClosesAt == nil { auctionSeats = 0 }
        }
    }

    private func save() {
        if var session {
            session.startsAt = startsAt
            session.place = kind == .video ? "" : trimmedPlace
            session.seats = max(seats, minimumSeats)
            tasmee.updateSession(session)
        } else {
            tasmee.createSession(startsAt: startsAt, kind: kind, place: trimmedPlace, seats: seats, auctionSeats: auctionSeats,
                                 minBid: minBid)
        }
    }

    private func row<Control: View>(_ label: Text, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            label
                .aqraFont(size: 15, weight: .bold)
                .foregroundStyle(Palette.ink)
            Spacer()
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(enabled ? Palette.brand : Palette.inkSoft.opacity(0.4))
                .frame(width: 34, height: 34)
                .background(Palette.lavender, in: Circle())
        }
        .buttonStyle(AqraPressStyle())
        .disabled(!enabled)
        .buttonRepeatBehavior(.enabled)
    }
}

// MARK: - A teacher's session

/// One of the teacher's sessions: when and where, and the students who booked, each opening the marking screen.
struct SessionView: View {
    var session: TasmeeSession
    var store: MushafStore

    @Environment(TasmeeStore.self) private var tasmee
    @Environment(\.dismiss) private var dismiss
    @State private var seats: [Seat] = []
    @State private var marking: Seat?
    @State private var editing = false
    @State private var confirmingCancel = false
    @State private var calling = false
    @State private var bids: [Bid] = []

    /// The session as it is now; the one navigated to is only a snapshot.
    private var live: TasmeeSession { tasmee.mySessions.first { $0.id == session.id } ?? session }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AqraCard(padding: 14, radius: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            IconTile(icon: live.kind == .video ? "🎥" : "📅", tint: Palette.sky, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: TasmeeFormat.when(live.startsAt))
                                    .aqraFont(size: 19, weight: .heavy)
                                    .foregroundStyle(Palette.ink)
                                TasmeeFormat.place(live)
                                    .aqraFont(size: 13, weight: .semibold)
                                    .foregroundStyle(Palette.inkSoft)
                                Text("\(live.booked) of \(live.seats) seats")
                                    .aqraFont(size: 13, weight: .bold)
                                    .foregroundStyle(Palette.brand)
                                if let auction = live.auction {
                                    Text("\(auction.seats) seats by auction · \(auction.state == .settled ? auction.won : auction.bids) bids")
                                        .aqraFont(size: 12, weight: .semibold)
                                        .foregroundStyle(Palette.inkSoft)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        if live.kind == .video {
                            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                                let open = CallModel.isOpen(live, at: timeline.date)
                                Button {
                                    calling = true
                                } label: {
                                    Label(open ? "Start the call" : "The call opens 15 minutes before", systemImage: "video.fill")
                                        .aqraFont(size: 15, weight: .bold)
                                        .foregroundStyle(open ? .white : Palette.inkSoft)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(open ? Palette.brand : Palette.lavender, in: Capsule())
                                }
                                .buttonStyle(AqraPressStyle())
                                .disabled(!open)
                            }
                        }
                        HStack(spacing: 16) {
                            Button("Edit") { editing = true }
                                .aqraFont(size: 13, weight: .bold)
                                .foregroundStyle(Palette.brand)
                                .buttonStyle(.plain)
                            Button("Cancel session") { confirmingCancel = true }
                                .aqraFont(size: 13, weight: .bold)
                                .foregroundStyle(Color(light: 0xB3261E, dark: 0xB3261E))
                                .buttonStyle(.plain)
                        }
                    }
                }

                if live.auction != nil, !bids.isEmpty {
                    AqraSectionTitle(title: "Bids").padding(.top, 10)
                    AqraCard(padding: 0, radius: 24) {
                        VStack(spacing: 0) {
                            ForEach(Array(bids.enumerated()), id: \.element.id) { index, bid in
                                if index > 0 { AqraRowDivider() }
                                AqraRow(icon: bid.status == .won ? "🎉" : bid.status == .active ? "🔨" : "↩️", tint: Palette.butter,
                                        title: Text(verbatim: bid.name), detail: bidStatus(bid)) {
                                    Text("\(bid.amount) credits")
                                        .aqraFont(size: 14, weight: .heavy, monospacedDigit: true)
                                        .foregroundStyle(bid.status == .active || bid.status == .won ? Palette.brand : Palette.inkSoft)
                                }
                            }
                        }
                    }
                }

                AqraSectionTitle(title: "Students").padding(.top, 10)
                if seats.isEmpty {
                    Text("No one has booked a seat yet.")
                        .aqraFont(size: 14, weight: .medium)
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.horizontal, 6)
                } else {
                    AqraCard(padding: 0, radius: 24) {
                        VStack(spacing: 0) {
                            ForEach(Array(seats.enumerated()), id: \.element.id) { index, seat in
                                if index > 0 { AqraRowDivider() }
                                Button {
                                    marking = seat
                                } label: {
                                    AqraRow(icon: "🧑‍🎓", tint: Palette.butter, title: Text(verbatim: seat.name), detail: detail(of: seat))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Text("Tap a student to hear them: mark the ayat they stumble on, and the pages you heard.")
                        .aqraFont(size: 12, weight: .medium)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: seats)
        }
        .scrollIndicators(.hidden)
        .background(Palette.surface.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .task {
            for await seats in tasmee.seats(of: session.id) {
                self.seats = seats
            }
        }
        .task {
            guard session.auction != nil else { return }
            for await bids in tasmee.bids(of: session.id) { self.bids = bids }
        }
        .sheet(isPresented: $editing) { SessionEditor(session: live) }
        .fullScreenCover(isPresented: $calling) {
            TeacherCallView(session: live, store: store, seats: seats)
        }
        .fullScreenCover(item: $marking) { seat in
            TasmeeMarkingView(store: store, studentName: seat.name, startPage: startPage(for: seat), allowsStageTest: true) { result in
                tasmee.recordTasmee(for: seat, in: live, pages: result.pages, stumbles: result.stumbles,
                                    mistakes: result.mistakes, test: result.test)
            }
        }
        .alert("Cancel this session?", isPresented: $confirmingCancel) {
            Button("Cancel session", role: .destructive) {
                tasmee.cancelSession(live)
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The students who booked will see it cancelled.")
        }
    }

    private func bidStatus(_ bid: Bid) -> Text {
        switch bid.status {
        case .active: Text("Holding a seat")
        case .outbid: Text("Outbid")
        case .won: Text("Won a seat")
        case .released: Text("Released")
        }
    }

    /// Where the student's memorization begins, if they said: the first page of their first whole juz'.
    private func startPage(for seat: Seat) -> Int {
        let firstJuz = seat.juzSummary?.split(separator: ",").first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return firstJuz.flatMap { store.juzStartPages[$0] } ?? 1
    }

    /// «٤٠ صفحة · الأجزاء ٢٩، ٣٠»: the student's app writes the juz' as plain numbers, «29, 30»; they're shown in the
    /// teacher's language.
    private func detail(of seat: Seat) -> Text {
        let pages = Text("\(seat.memorizedPages) pages")
        guard let summary = seat.juzSummary else { return pages }
        let numbers = summary.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let juz = numbers.isEmpty ? summary : numbers.map { $0.formatted() }.formatted(.list(type: .and, width: .narrow))
        return pages + Text(verbatim: Separator.facts) + Text("Juz' \(juz)")
    }
}

// MARK: - The teacher's profile

/// The teacher's name, city and line, as students see them.
struct TeacherProfileEditor: View {
    @Environment(TasmeeStore.self) private var tasmee
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var city = ""
    @State private var line = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your teacher profile")
                .aqraFont(size: 26, weight: .heavy)
                .foregroundStyle(Palette.ink)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            AqraCard(padding: 0, radius: 24) {
                VStack(spacing: 0) {
                    field(Text("Name"), text: $name)
                    AqraRowDivider().padding(.leading, -50)
                    field(Text("City"), text: $city)
                    AqraRowDivider().padding(.leading, -50)
                    field(Text("About you"), text: $line, prompt: Text("Ijazah, riwayah, halaqah"))
                }
            }
            Spacer(minLength: 0)
            BrandButton("Save", metrics: OnboardingButtonMetrics(height: 56, fontSize: 18, compact: false)) {
                tasmee.updateTeacherProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                            city: city.trimmingCharacters(in: .whitespacesAndNewlines),
                                            line: line.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            name = tasmee.teacherProfile?.name ?? ""
            city = tasmee.teacherProfile?.city ?? ""
            line = tasmee.teacherProfile?.line ?? ""
        }
    }

    private func field(_ label: Text, text: Binding<String>, prompt: Text? = nil) -> some View {
        HStack(spacing: 12) {
            label
                .aqraFont(size: 15, weight: .bold)
                .foregroundStyle(Palette.ink)
            TextField(text: text, prompt: prompt) { label }
                .multilineTextAlignment(.trailing)
                .aqraFont(size: 15, weight: .medium)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

// MARK: - A student's file

/// A teacher's file on one student: what the teacher heard from them, and the teacher's own notes.
struct StudentFileView: View {
    var student: StudentFile
    var store: MushafStore

    @Environment(TasmeeStore.self) private var tasmee
    @State private var records: [TasmeeRecord] = []
    @State private var notes = ""
    @FocusState private var editingNotes: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: student.name)
                        .aqraFont(size: 28, weight: .heavy)
                        .foregroundStyle(Palette.ink)
                    Text("Last heard \(student.lastHeardAt.formatted(.relative(presentation: .named)))")
                        .aqraFont(size: 13, weight: .semibold)
                        .foregroundStyle(Palette.inkSoft)
                }
                .padding(.top, 8)

                if !records.isEmpty {
                    let pages = Set(records.flatMap(\.pages)).count
                    let stumbles = records.reduce(0) { $0 + $1.stumbles.count }
                    HStack(spacing: 10) {
                        stat(icon: "📖", tint: Palette.sky, value: pages.formatted(), label: Text("Pages heard"))
                        stat(icon: "🎯", tint: Palette.rose, value: stumbles.formatted(), label: Text("Stumbles"))
                        stat(icon: "🗓️", tint: Palette.mint, value: records.count.formatted(), label: Text("Tasmee'"))
                    }
                }

                AqraSectionTitle(title: "Notes").padding(.top, 10)
                AqraCard(padding: 14, radius: 24) {
                    TextField("What to work on next time", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                        .aqraFont(size: 15, weight: .medium)
                        .focused($editingNotes)
                }

                AqraSectionTitle(title: "What you heard").padding(.top, 10)
                if records.isEmpty {
                    Text("Nothing recorded yet.")
                        .aqraFont(size: 14, weight: .medium)
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.horizontal, 6)
                } else {
                    AqraCard(padding: 0, radius: 24) {
                        VStack(spacing: 0) {
                            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                if index > 0 { AqraRowDivider() }
                                TasmeeRecordRow(record: record, store: store, showsListener: false)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.surface.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .onAppear { notes = savedNotes }
        .onChange(of: editingNotes) { if !editingNotes { saveNotes() } }
        .onDisappear { saveNotes() }
        .task {
            for await records in tasmee.records(of: student.id) {
                self.records = records
            }
        }
    }

    private var savedNotes: String {
        tasmee.myStudents.first { $0.id == student.id }?.notes ?? student.notes
    }

    private func saveNotes() {
        guard notes != savedNotes else { return }
        tasmee.saveNotes(notes, for: student.id)
    }

    private func stat(icon: String, tint: Color, value: String, label: Text) -> some View {
        AqraCard(padding: 12, radius: 20) {
            VStack(alignment: .leading, spacing: 8) {
                IconTile(icon: icon, tint: tint, size: 32)
                Text(verbatim: value)
                    .aqraFont(size: 20, weight: .heavy, monospacedDigit: true)
                    .foregroundStyle(Palette.ink)
                label
                    .aqraFont(size: 11, weight: .semibold)
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private typealias Palette = OnboardingPalette
