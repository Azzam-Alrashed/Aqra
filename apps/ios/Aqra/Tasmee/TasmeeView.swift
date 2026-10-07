import SwiftUI

/// التسميع: for a teacher, their sessions and the students in each; for everyone, the next tasmee' booked and
/// the vetted teachers to book with.
struct TasmeeView: View {
    var store: MushafStore

    @Environment(TasmeeStore.self) private var tasmee
    @Environment(AccountStore.self) private var account
    @State private var creatingSession = false
    @State private var cancelling: Booking?
    @State private var problem: AccountStore.Problem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tasmee'")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 16)
                        .accessibilityAddTraits(.isHeader)

                    if !AccountStore.isAvailable {
                        unavailable
                    } else {
                        if tasmee.isTeacher {
                            mySessions
                        }
                        if let booking = tasmee.nextBooking {
                            AqraSectionTitle(title: "Your next tasmee'").padding(.top, 10)
                            bookingCard(booking)
                        }
                        AqraSectionTitle(title: "Teachers").padding(.top, 10)
                        teachersCard
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .animation(.snappy, value: tasmee.bookings)
                .animation(.snappy, value: tasmee.mySessions)
            }
            .scrollIndicators(.hidden)
            .reservesTabBarSpace()
            .background(Palette.surface.ignoresSafeArea())
            .fadesUnderStatusBar()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Teacher.self) { TeacherView(teacher: $0, store: store) }
            .navigationDestination(for: TasmeeSession.self) { SessionView(session: $0, store: store) }
            .refreshable { await tasmee.loadTeachers() }
        }
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .task { await tasmee.loadTeachers() }
        .sheet(isPresented: $creatingSession) { NewSessionView() }
        .alert("Cancel your booking?", isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
               presenting: cancelling) { booking in
            Button("Cancel booking", role: .destructive) {
                Task {
                    do {
                        try await tasmee.cancelBooking(booking)
                        problem = nil
                    } catch {
                        problem = AccountStore.problem(for: error)
                    }
                }
            }
            Button("Keep it", role: .cancel) {}
        } message: { _ in
            Text("Your seat goes back to the session.")
        }
    }

    private var unavailable: some View {
        AqraCard(padding: 14, radius: 24) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(icon: "🎓", tint: Palette.mint, size: 40)
                Text("Accounts aren't set up in this build, so teachers and tasmee' are off.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - A teacher's sessions

    private var mySessions: some View {
        Group {
            AqraSectionTitle(title: "My sessions").padding(.top, 10)
            AqraCard(padding: 0, radius: 24) {
                VStack(spacing: 0) {
                    ForEach(tasmee.mySessions) { session in
                        NavigationLink(value: session) {
                            // The count first: a place name in the other script would otherwise reorder the line.
                            AqraRow(icon: "📅", tint: Palette.sky, title: Text(verbatim: TasmeeFormat.when(session.startsAt)),
                                    detail: Text("\(session.booked) of \(session.seats) seats") + Text(verbatim: " · ") + Text(verbatim: session.place))
                        }
                        .buttonStyle(.plain)
                        AqraRowDivider()
                    }
                    Button {
                        creatingSession = true
                    } label: {
                        AqraRow(icon: "➕", tint: Palette.butter, title: Text("New session")) { EmptyView() }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - The student's booking

    private func bookingCard(_ booking: Booking) -> some View {
        let live = tasmee.session(of: booking)
        let cancelled = live?.status == .cancelled
        return AqraCard(padding: 14, radius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    IconTile(icon: "🎓", tint: cancelled ? Palette.rose : Palette.mint, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: booking.teacherName)
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(Palette.ink)
                        Text(verbatim: TasmeeFormat.when(live?.startsAt ?? booking.startsAt))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(cancelled ? Palette.inkSoft : Palette.brand)
                            .strikethrough(cancelled)
                        Text(verbatim: live?.place ?? booking.place)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                        if cancelled {
                            Text("The teacher cancelled this session.")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(light: 0x9A3E26, dark: 0x9A3E26))
                        }
                    }
                    Spacer(minLength: 4)
                    Button(cancelled ? "Remove" : "Cancel booking") { cancelling = booking }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.brand)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Palette.lavender, in: Capsule())
                        .buttonStyle(.plain)
                }
                if let problem {
                    ProblemLine(problem: problem)
                }
            }
        }
    }

    // MARK: - Teachers

    private var teachersCard: some View {
        Group {
            if tasmee.teachers.isEmpty {
                AqraCard(padding: 14, radius: 24) {
                    HStack(spacing: 12) {
                        if tasmee.isLoadingTeachers {
                            ProgressView().tint(Palette.brand)
                            Text("Loading teachers…")
                        } else {
                            IconTile(icon: "🕌", tint: Palette.lavender, size: 40)
                            Text("No teachers have joined yet.")
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                AqraCard(padding: 0, radius: 24) {
                    VStack(spacing: 0) {
                        ForEach(Array(tasmee.teachers.enumerated()), id: \.element.id) { index, teacher in
                            if index > 0 { AqraRowDivider() }
                            NavigationLink(value: teacher) {
                                AqraRow(icon: "🎓", tint: Palette.mint, title: Text(verbatim: teacher.name),
                                        detail: TasmeeFormat.about(teacher).map { Text(verbatim: $0) })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let problem = tasmee.problem {
                ProblemLine(problem: problem).padding(.horizontal, 6)
            }
        }
    }
}

/// How dates and teachers are written across the tasmee' screens.
enum TasmeeFormat {
    /// «الأربعاء ٨ أكتوبر، ٨:٠٠ م»
    static func when(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())
    }

    /// The teacher's city and line, or nil when they wrote neither.
    static func about(_ teacher: Teacher) -> String? {
        let parts = [teacher.city, teacher.line].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

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

    private var signedIn: Bool { account.profile?.isAnonymous == false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AqraCard(padding: 14, radius: 24) {
                    HStack(alignment: .top, spacing: 12) {
                        IconTile(icon: "🎓", tint: Palette.mint, size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: teacher.name)
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundStyle(Palette.ink)
                            if !teacher.city.isEmpty {
                                Text(verbatim: teacher.city)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Palette.brand)
                            }
                            if !teacher.line.isEmpty {
                                Text(verbatim: teacher.line)
                                    .font(.system(size: 12, weight: .semibold))
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
                                .font(.system(size: 16, weight: .heavy))
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
        .reservesTabBarSpace()
        .background(Palette.surface.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .task { await load() }
        .refreshable { await load() }
    }

    private func note(_ text: Text) -> some View {
        text
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Palette.inkSoft)
            .padding(.horizontal, 6)
    }

    private func sessionRow(_ session: TasmeeSession) -> some View {
        let booked = tasmee.hasBooked(session)
        let seats = booked ? Text("Booked") : Text("Seats left: \(session.seatsLeft)")
        return AqraRow(icon: "📅", tint: Palette.sky, title: Text(verbatim: TasmeeFormat.when(session.startsAt)),
                       detail: seats + Text(verbatim: " · ") + Text(verbatim: session.place)) {
            if working == session.id {
                ProgressView().tint(Palette.brand)
            } else if booked {
                Button("Cancel") {
                    Task { await change(session) { try await tasmee.cancelBooking(Booking(session)) } }
                }
                .buttonStyle(ChipButtonStyle(filled: false))
            } else if !signedIn {
                EmptyView()
            } else if session.isFull {
                Text("Full")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.inkSoft)
            } else {
                Button("Book") {
                    Task { await change(session) { try await tasmee.book(session, name: studentName, memorizedPages: memorizedPages, juzSummary: juzSummary) } }
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
            sessions = try await tasmee.upcomingSessions(of: teacher.id)
        } catch {
            sessions = sessions ?? []
            problem = AccountStore.problem(for: error)
        }
    }

    // What the teacher sees of the student: their name and what they've memorized.

    private var studentName: String {
        account.profile?.name ?? account.profile?.email ?? String(localized: "A student")
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

/// A small capsule button at the end of a row: purple when filled, lavender otherwise.
struct ChipButtonStyle: ButtonStyle {
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .lineLimit(1)
            .foregroundStyle(filled ? .white : OnboardingPalette.brand)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(filled ? OnboardingPalette.brand : OnboardingPalette.lavender, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

// MARK: - A new session

/// A teacher schedules an in-person session: when, where, and how many seats.
struct NewSessionView: View {
    @Environment(TasmeeStore.self) private var tasmee
    @Environment(\.dismiss) private var dismiss
    @State private var startsAt = NewSessionView.suggestedStart
    @State private var place = ""
    @State private var seats = 5

    /// Tomorrow, on the hour.
    private static var suggestedStart: Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return Calendar.current.date(bySetting: .minute, value: 0, of: tomorrow) ?? tomorrow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New session")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Palette.ink)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            AqraCard(padding: 0, radius: 24) {
                VStack(spacing: 0) {
                    row(Text("When")) {
                        DatePicker("When", selection: $startsAt, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                    AqraRowDivider().padding(.leading, -50)
                    row(Text("Place")) {
                        TextField("Place", text: $place)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 15, weight: .medium))
                    }
                    AqraRowDivider().padding(.leading, -50)
                    row(Text("Seats")) {
                        HStack(spacing: 10) {
                            stepButton("minus", enabled: seats > 1) { seats -= 1 }
                            Text(seats.formatted())
                                .font(.system(size: 17, weight: .heavy).monospacedDigit())
                                .foregroundStyle(Palette.ink)
                                .frame(minWidth: 28)
                                .contentTransition(.numericText())
                            stepButton("plus", enabled: seats < 30) { seats += 1 }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            BrandButton("Create", metrics: OnboardingButtonMetrics(height: 56, fontSize: 18, compact: false)) {
                tasmee.createSession(startsAt: startsAt, place: place.trimmingCharacters(in: .whitespacesAndNewlines), seats: seats)
                dismiss()
            }
            .disabled(place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
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
        .animation(.snappy, value: seats)
    }

    private func row<Control: View>(_ label: Text, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            label
                .font(.system(size: 15, weight: .bold))
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
    @State private var confirmingCancel = false

    /// The session as it is now; the one navigated to is only a snapshot.
    private var live: TasmeeSession { tasmee.mySessions.first { $0.id == session.id } ?? session }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AqraCard(padding: 14, radius: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            IconTile(icon: "📅", tint: Palette.sky, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: TasmeeFormat.when(live.startsAt))
                                    .font(.system(size: 19, weight: .heavy))
                                    .foregroundStyle(Palette.ink)
                                Text(verbatim: live.place)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.inkSoft)
                                Text("\(seats.count) of \(live.seats) seats")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Palette.brand)
                            }
                            Spacer(minLength: 0)
                        }
                        Button("Cancel session") { confirmingCancel = true }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(light: 0xB3261E, dark: 0xB3261E))
                            .buttonStyle(.plain)
                    }
                }

                AqraSectionTitle(title: "Students").padding(.top, 10)
                if seats.isEmpty {
                    Text("No one has booked a seat yet.")
                        .font(.system(size: 14, weight: .medium))
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
                        .font(.system(size: 12, weight: .medium))
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
        .reservesTabBarSpace()
        .background(Palette.surface.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .task {
            for await seats in tasmee.seats(of: session.id) {
                self.seats = seats
            }
        }
        .fullScreenCover(item: $marking) { seat in
            TasmeeMarkingView(store: store, session: live, seat: seat)
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

    /// «٤٠ صفحة · الأجزاء 29, 30»
    private func detail(of seat: Seat) -> Text {
        let pages = Text("\(seat.memorizedPages) pages")
        guard let juz = seat.juzSummary else { return pages }
        return pages + Text(verbatim: " · ") + Text("Juz' \(juz)")
    }
}

private typealias Palette = OnboardingPalette
