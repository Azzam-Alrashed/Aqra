import SwiftUI

/// التسميع: for a teacher, their profile, sessions and students; for everyone, the next tasmee' booked, reciting to
/// or hearing a friend, the vetted teachers to book with, what others heard, and the way to apply to teach.
struct TasmeeView: View {
    var store: MushafStore

    @Environment(TasmeeStore.self) private var tasmee
    @Environment(AccountStore.self) private var account
    @Environment(WalletStore.self) private var wallet
    @Environment(AppRouter.self) private var router
    @State private var creatingSession = false
    @State private var editingProfile = false
    @State private var cancelling: Booking?
    @State private var problem: AccountStore.Problem?
    @State private var reciting = false
    @State private var hearing: HearingFriend?
    @State private var startingCompetition = false
    @State private var showingEarnings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tasmee'")
                        .aqraFont(size: 30, weight: .heavy)
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 16)
                        .accessibilityAddTraits(.isHeader)

                    if !AccountStore.isAvailable {
                        unavailable
                    } else {
                        if tasmee.isTeacher {
                            teacherSections
                        }
                        if let booking = tasmee.nextBooking {
                            AqraSectionTitle(title: "Your next tasmee'").padding(.top, 10)
                            bookingCard(booking)
                        }
                        AqraSectionTitle(title: "With a friend").padding(.top, 10)
                        friendCard
                        AqraSectionTitle(title: "Teachers").padding(.top, 10)
                        teachersCard
                        if !tasmee.history.isEmpty {
                            historySection
                        }
                        if !tasmee.isTeacher {
                            applyCard.padding(.top, 10)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .animation(.snappy, value: tasmee.bookings)
                .animation(.snappy, value: tasmee.mySessions)
                .animation(.snappy, value: tasmee.history)
            }
            .scrollIndicators(.hidden)
            .background(Palette.surface.ignoresSafeArea())
            .fadesUnderStatusBar()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Teacher.self) { TeacherView(teacher: $0, store: store) }
            .navigationDestination(for: TasmeeSession.self) { SessionView(session: $0, store: store) }
            .navigationDestination(for: StudentFile.self) { StudentFileView(student: $0, store: store) }
            .navigationDestination(for: TasmeeRoute.self) { route in
                switch route {
                case .history: TasmeeHistoryView(store: store)
                case .apply: TeacherApplicationView()
                }
            }
            .refreshable { await tasmee.loadTeachers() }
        }
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .task { await tasmee.loadTeachers() }
        .sheet(isPresented: $creatingSession) { SessionEditor(session: nil) }
        .sheet(isPresented: $editingProfile) { TeacherProfileEditor() }
        .sheet(isPresented: $reciting) { PeerRequestView() }
        .sheet(isPresented: $startingCompetition) { NewCompetitionView(kinds: [.teacher]) }
        .sheet(isPresented: $showingEarnings) { EarningsView() }
        .fullScreenCover(item: $hearing) { hearing in
            HearFriendView(store: store, initialCode: hearing.code)
        }
        // A friend's code opened from a link or the camera.
        .onChange(of: router.peerCode, initial: true) {
            guard let code = router.peerCode else { return }
            router.peerCode = nil
            hearing = HearingFriend(code: code)
        }
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
                    .aqraFont(size: 14, weight: .medium)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - A teacher's side

    @ViewBuilder
    private var teacherSections: some View {
        if let profile = tasmee.teacherProfile {
            AqraCard(padding: 0, radius: 24) {
                Button {
                    editingProfile = true
                } label: {
                    AqraRow(icon: "🎓", tint: Palette.mint, title: Text(verbatim: profile.name),
                            detail: TasmeeFormat.about(profile).map { Text(verbatim: $0) } ?? Text("Add your city and a line about you")) {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Palette.brand)
                            .frame(width: 30, height: 30)
                            .background(Palette.lavender, in: Circle())
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }

        Button {
            showingEarnings = true
        } label: {
            AqraCard(padding: 0, radius: 24) {
                AqraRow(icon: "🏦", tint: Palette.butter, title: Text("Your earnings"),
                        detail: Text("\(CreditsFormat.credits(wallet.due)) credits due to you"))
            }
        }
        .buttonStyle(AqraPressStyle())

        AqraSectionTitle(title: "My sessions").padding(.top, 10)
        AqraCard(padding: 0, radius: 24) {
            VStack(spacing: 0) {
                ForEach(tasmee.mySessions) { session in
                    NavigationLink(value: session) {
                        // The count first: a place name in the other script would otherwise reorder the line.
                        AqraRow(icon: session.kind == .video ? "🎥" : "📅", tint: Palette.sky,
                                title: Text(verbatim: TasmeeFormat.when(session.startsAt)),
                                detail: Text("\(session.booked) of \(session.seats) seats") + Text(verbatim: Separator.facts) + TasmeeFormat.place(session))
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

        if !tasmee.myStudents.isEmpty {
            AqraSectionTitle(title: "My students").padding(.top, 10)
            AqraCard(padding: 0, radius: 24) {
                VStack(spacing: 0) {
                    ForEach(Array(tasmee.myStudents.prefix(8).enumerated()), id: \.element.id) { index, student in
                        if index > 0 { AqraRowDivider() }
                        NavigationLink(value: student) {
                            AqraRow(icon: "🧑‍🎓", tint: Palette.butter, title: Text(verbatim: student.name),
                                    detail: Text("Last heard \(student.lastHeardAt.formatted(.relative(presentation: .named)))"))
                        }
                        .buttonStyle(.plain)
                    }
                    AqraRowDivider()
                    Button {
                        startingCompetition = true
                    } label: {
                        AqraRow(icon: "🏆", tint: Palette.mint, title: Text("A competition for my students"),
                                detail: Text("Scored from the pages you hear clean"))
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
                    IconTile(icon: booking.kind == .video ? "🎥" : "🎓", tint: cancelled ? Palette.rose : Palette.mint, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: booking.teacherName)
                            .aqraFont(size: 17, weight: .heavy)
                            .foregroundStyle(Palette.ink)
                        Text(verbatim: TasmeeFormat.when(live?.startsAt ?? booking.startsAt))
                            .aqraFont(size: 13, weight: .bold)
                            .foregroundStyle(cancelled ? Palette.inkSoft : Palette.brand)
                            .strikethrough(cancelled)
                        TasmeeFormat.place(live.map { Booking($0) } ?? booking)
                            .aqraFont(size: 12, weight: .semibold)
                            .foregroundStyle(Palette.inkSoft)
                        if cancelled {
                            Text("The teacher cancelled this session.")
                                .aqraFont(size: 12, weight: .semibold)
                                .foregroundStyle(Color(light: 0x9A3E26, dark: 0x9A3E26))
                        }
                    }
                    Spacer(minLength: 4)
                    Button(cancelled ? "Remove" : "Cancel booking") { cancelling = booking }
                        .aqraFont(size: 13, weight: .bold)
                        .foregroundStyle(Palette.brand)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .frame(minHeight: 28)
                        .background(Palette.lavender, in: Capsule())
                        .buttonStyle(.plain)
                }
                if booking.kind == .video, let live, !cancelled {
                    JoinCallButton(session: live)
                }
                if let problem {
                    ProblemLine(problem: problem)
                }
            }
        }
    }

    // MARK: - With a friend

    private var friendCard: some View {
        AqraCard(padding: 0, radius: 24) {
            VStack(spacing: 0) {
                Button {
                    reciting = true
                } label: {
                    AqraRow(icon: "🗣️", tint: Palette.peach, title: Text("Recite to a friend"),
                            detail: Text("They mark your stumbles on their phone"))
                }
                .buttonStyle(.plain)
                AqraRowDivider()
                Button {
                    hearing = HearingFriend(code: nil)
                } label: {
                    AqraRow(icon: "👂", tint: Palette.sky, title: Text("Hear a friend"),
                            detail: Text("With the code your friend shows you"))
                }
                .buttonStyle(.plain)
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
                    .aqraFont(size: 14, weight: .medium)
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

    // MARK: - What others heard

    private var historySection: some View {
        Group {
            AqraSectionTitle(title: "What others heard").padding(.top, 10)
            AqraCard(padding: 0, radius: 24) {
                VStack(spacing: 0) {
                    ForEach(Array(tasmee.history.prefix(3).enumerated()), id: \.element.id) { index, record in
                        if index > 0 { AqraRowDivider() }
                        TasmeeRecordRow(record: record, store: store)
                    }
                    AqraRowDivider()
                    NavigationLink(value: TasmeeRoute.history) {
                        AqraRow(icon: "🗂️", tint: Palette.lavender, title: Text("Every tasmee'"))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Teaching

    private var applyCard: some View {
        NavigationLink(value: TasmeeRoute.apply) {
            AqraCard(padding: 0, radius: 24) {
                AqraRow(icon: "📜", tint: Palette.butter, title: Text("Teach on Aqra"), detail: applicationLine)
            }
        }
        .buttonStyle(AqraPressStyle())
    }

    private var applicationLine: Text {
        switch tasmee.application?.status {
        case nil: Text("Hold an ijazah? Apply to hear students")
        case .submitted: Text("Your application is waiting for review")
        case .interview: Text("We'll be in touch for your interview")
        case .approved: Text("Approved")
        case .rejected: Text("Your application wasn't accepted")
        }
    }
}

/// Places in the tasmee' tab's navigation that aren't values of their own.
enum TasmeeRoute: Hashable {
    case history, apply
}

/// The friend being heard, from a code typed in, scanned, or opened from a link.
struct HearingFriend: Identifiable {
    var code: String?
    var id: String { code ?? "" }
}

/// How dates, places and teachers are written across the tasmee' screens.
enum TasmeeFormat {
    /// «الأربعاء ٨ أكتوبر، ٨:٠٠ م»
    static func when(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())
    }

    /// The teacher's city and line, or nil when they wrote neither.
    static func about(_ teacher: Teacher) -> String? {
        let parts = [teacher.city, teacher.line].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: Separator.facts)
    }

    /// Where a session is held: its place, or the video call.
    static func place(_ session: TasmeeSession) -> Text {
        session.kind == .video ? Text("Video call") : Text(verbatim: session.place)
    }

    static func place(_ booking: Booking) -> Text {
        booking.kind == .video ? Text("Video call") : Text(verbatim: booking.place)
    }

    /// «صفحتان · تعثّر واحد»: each count with its own plural.
    static func counts(pages: Int, stumbles: Int) -> Text {
        Text("\(pages) pages") + Text(verbatim: Separator.facts) + Text("\(stumbles) stumbles")
    }
}

private typealias Palette = OnboardingPalette
