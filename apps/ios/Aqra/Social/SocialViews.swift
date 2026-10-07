import SwiftUI

extension Competition.Metric {
    var title: LocalizedStringKey {
        switch self {
        case .pagesRevised: "Pages revised"
        case .daysRevised: "Days revised"
        case .ayatMemorized: "Ayat memorized"
        case .parts: "Parts finished"
        case .cleanPages: "Pages heard clean"
        }
    }
}

extension Competition.Kind {
    var icon: String {
        switch self {
        case .friends: "🏁"
        case .khatmah: "📚"
        case .teacher: "🎓"
        }
    }
}

// MARK: - On the progress screen

/// «مع الآخرين»: friends, and the competitions the student is in — constructive, private to their members.
struct TogetherSection: View {
    var store: MushafStore

    @Environment(AccountStore.self) private var account
    @Environment(SocialStore.self) private var social
    @Environment(AppRouter.self) private var router
    @State private var showingFriends = false
    @State private var creating = false
    @State private var opened: Competition?
    @State private var accepting: FriendCode?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AqraSectionTitle(title: "Together").padding(.top, 10)
            if !AccountStore.isAvailable {
                EmptyView()
            } else if account.profile?.isAnonymous != false {
                AqraCard(padding: 14, radius: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            IconTile(icon: "🤝", tint: Palette.peach, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Compete with friends")
                                    .font(.system(size: 16, weight: .heavy))
                                    .foregroundStyle(Palette.ink)
                                Text("Sign in to add friends, race them, and finish a khatmah together.")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Palette.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        SignInButtons()
                    }
                }
            } else {
                AqraCard(padding: 0, radius: 24) {
                    VStack(spacing: 0) {
                        Button {
                            showingFriends = true
                        } label: {
                            AqraRow(icon: "🤝", tint: Palette.peach, title: Text("Friends"),
                                    detail: social.friends.isEmpty ? Text("Invite a friend with a code") : Text("\(social.friends.count) friends"))
                        }
                        .buttonStyle(.plain)
                        ForEach(social.competitions) { competition in
                            AqraRowDivider()
                            Button {
                                opened = competition
                            } label: {
                                AqraRow(icon: competition.kind.icon, tint: competition.isRunning() ? Palette.mint : Palette.lavender,
                                        title: Text(verbatim: competition.title),
                                        detail: competition.isRunning()
                                            ? Text("Until \(competition.endsAt.formatted(date: .abbreviated, time: .omitted))")
                                            : Text("Ended"))
                            }
                            .buttonStyle(.plain)
                        }
                        AqraRowDivider()
                        Button {
                            creating = true
                        } label: {
                            AqraRow(icon: "➕", tint: Palette.butter, title: Text("New competition")) { EmptyView() }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let problem = social.problem {
                    ProblemLine(problem: problem).padding(.horizontal, 6)
                }
            }
        }
        .sheet(isPresented: $showingFriends) { FriendsView() }
        .sheet(isPresented: $creating) { NewCompetitionView(kinds: [.friends, .khatmah]) }
        .sheet(item: $opened) { competition in CompetitionView(competition: competition) }
        .sheet(item: $accepting) { code in AcceptFriendView(code: code.id) }
        // A friend's invitation opened from a link.
        .onChange(of: router.friendCode, initial: true) {
            guard let code = router.friendCode else { return }
            router.friendCode = nil
            accepting = FriendCode(id: code)
        }
    }
}

struct FriendCode: Identifiable {
    var id: String
}

// MARK: - Friends

/// The student's friends: an invitation to share, a friend's code to enter, and the friends themselves.
struct FriendsView: View {
    @Environment(SocialStore.self) private var social
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var invite: FriendInvite?
    @State private var making = false
    @State private var code = ""
    @State private var accepting: FriendCode?
    @State private var removing: (uid: String, name: String)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Friends").foregroundStyle(Palette.ink)
                    Text("to compete with").foregroundStyle(Palette.brand)
                }
                .font(.system(size: 28, weight: .heavy))
                .padding(.top, 22)

                AqraCard(padding: 14, radius: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            IconTile(icon: "💌", tint: Palette.rose, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Invite a friend")
                                    .font(.system(size: 16, weight: .heavy))
                                    .foregroundStyle(Palette.ink)
                                Text("Share your code; it's valid for a week.")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Palette.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                        if let invite {
                            HStack(spacing: 12) {
                                if let qr = QRCode.image(for: invite.link.absoluteString) {
                                    Image(uiImage: qr)
                                        .interpolation(.none)
                                        .resizable()
                                        .frame(width: 84, height: 84)
                                        .accessibilityHidden(true)
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(verbatim: invite.id.map(String.init).joined(separator: " "))
                                        .font(.system(size: 24, weight: .heavy, design: .monospaced))
                                        .foregroundStyle(Palette.brand)
                                        .environment(\.layoutDirection, .leftToRight)
                                    ShareLink(item: invite.link,
                                              message: Text("Be my friend on Aqra: open this link, or enter the code \(invite.id).")) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    .buttonStyle(ChipButtonStyle(filled: true))
                                }
                            }
                        } else {
                            Button {
                                Task { await makeInvite() }
                            } label: {
                                Label("Make my code", systemImage: "qrcode")
                            }
                            .buttonStyle(ChipButtonStyle(filled: true))
                            .disabled(making)
                        }
                    }
                }

                AqraCard(padding: 14, radius: 24) {
                    HStack(spacing: 10) {
                        TextField(text: $code, prompt: Text("A friend's code")) { Text("Code") }
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onChange(of: code) {
                                let normalized = String(PeerRequest.normalize(code).prefix(PeerRequest.codeLength))
                                if normalized != code { code = normalized }
                            }
                        Button("Add") { accepting = FriendCode(id: code) }
                            .buttonStyle(ChipButtonStyle(filled: true))
                            .disabled(!PeerRequest.isWellFormed(code))
                    }
                }

                if !social.friends.isEmpty {
                    AqraSectionTitle(title: "Your friends").padding(.top, 6)
                    AqraCard(padding: 0, radius: 24) {
                        VStack(spacing: 0) {
                            ForEach(Array(social.friends.enumerated()), id: \.element.uid) { index, friend in
                                if index > 0 { AqraRowDivider() }
                                AqraRow(icon: "🙂", tint: Palette.sky, title: Text(verbatim: friend.name.isEmpty ? "—" : friend.name)) {
                                    Button {
                                        removing = friend
                                    } label: {
                                        Image(systemName: "person.fill.xmark")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(Palette.inkSoft)
                                            .frame(width: 30, height: 30)
                                            .background(Palette.lavender, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text("Remove"))
                                }
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
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .presentationDragIndicator(.visible)
        .sheet(item: $accepting) { code in AcceptFriendView(code: code.id) }
        .alert("Remove this friend?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) {
                if let removing { social.remove(friendUid: removing.uid) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func makeInvite() async {
        making = true
        defer { making = false }
        invite = try? await social.createInvite(name: account.publicName ?? "")
    }
}

/// «أضف صديقًا»: an invitation found by its code, and accepting it.
struct AcceptFriendView: View {
    var code: String

    @Environment(SocialStore.self) private var social
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var invite: FriendInvite?
    @State private var loading = true
    @State private var done = false
    @State private var problem: AccountStore.Problem?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            if loading {
                ProgressView().tint(Palette.brand)
            } else if let invite, invite.ownerUid != account.profile?.uid {
                Text(verbatim: done ? "✅" : "🤝").font(.system(size: 64))
                (done ? Text("You're friends with \(invite.ownerName)") : Text("Be friends with \(invite.ownerName)?"))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Text("Friends see each other's names in the competitions they share, and nothing else.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                if let problem { ProblemLine(problem: problem) }
            } else {
                Text(verbatim: "🔎").font(.system(size: 56))
                Text("This code isn't valid, or it has expired.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            if let invite, !done, invite.ownerUid != account.profile?.uid {
                BrandButton("Become friends", metrics: OnboardingButtonMetrics(height: 54, fontSize: 17, compact: false)) {
                    Task { await accept(invite) }
                }
            } else {
                BrandButton("Done", metrics: OnboardingButtonMetrics(height: 54, fontSize: 17, compact: false)) { dismiss() }
            }
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .environment(\.colorScheme, .light)
        .presentationDetents([.medium])
        .sensoryFeedback(.success, trigger: done) { _, done in done }
        .task {
            invite = try? await social.invite(code: code)
            loading = false
        }
    }

    private func accept(_ invite: FriendInvite) async {
        do {
            try await social.accept(invite, name: account.publicName ?? "")
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { done = true }
        } catch {
            problem = AccountStore.problem(for: error)
        }
    }
}

// MARK: - A competition

/// A competition: the standings of a race (the student among them), or a khatmah's thirty parts.
struct CompetitionView: View {
    var competition: Competition

    @Environment(SocialStore.self) private var social
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var members: [CompetitionMember] = []
    @State private var parts: [KhatmahPart] = []
    @State private var confirmingLeave = false

    private var live: Competition { social.competitions.first { $0.id == competition.id } ?? competition }
    private var uid: String? { account.profile?.uid }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: live.title)
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: 6) {
                        Text(live.metric.title)
                        Text(verbatim: "·")
                        if live.isRunning() {
                            Text("Until \(live.endsAt.formatted(date: .abbreviated, time: .omitted))")
                        } else {
                            Text("Ended")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.brand)
                    if live.kind == .teacher {
                        Text("Scored from the pages \(live.ownerName) hears clean in tasmee'.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                .padding(.top, 22)

                if live.kind == .khatmah {
                    khatmah
                } else {
                    standings
                }

                HStack(spacing: 16) {
                    if live.ownerUid == uid, live.isRunning() {
                        Button("End it now") { social.end(live) }
                    }
                    if live.ownerUid != uid {
                        Button("Leave") { confirmingLeave = true }
                            .foregroundStyle(Color(light: 0xB3261E, dark: 0xB3261E))
                    }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.brand)
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .environment(\.colorScheme, .light)
        .presentationDragIndicator(.visible)
        .task {
            if competition.kind == .khatmah {
                for await parts in social.parts(of: competition) { self.parts = parts }
            } else {
                for await members in social.members(of: competition) { self.members = members }
            }
        }
        .alert("Leave this competition?", isPresented: $confirmingLeave) {
            Button("Leave", role: .destructive) {
                social.leave(live)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var standings: some View {
        AqraCard(padding: 0, radius: 24) {
            VStack(spacing: 0) {
                let ranked = CompetitionMember.ranked(members.filter { live.memberUids.contains($0.id) })
                if ranked.isEmpty {
                    Text("No scores yet: they appear as members revise.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(ranked.enumerated()), id: \.element.member.id) { index, entry in
                    if index > 0 { AqraRowDivider() }
                    HStack(spacing: 12) {
                        Text(verbatim: entry.rank <= 3 ? ["🥇", "🥈", "🥉"][entry.rank - 1] : entry.rank.formatted())
                            .font(.system(size: entry.rank <= 3 ? 22 : 16, weight: .heavy))
                            .frame(width: 38)
                        Text(verbatim: entry.member.name.isEmpty ? "—" : entry.member.name)
                            .font(.system(size: 16, weight: entry.member.id == uid ? .heavy : .semibold))
                            .foregroundStyle(entry.member.id == uid ? Palette.brand : Palette.ink)
                        Spacer()
                        Text(verbatim: entry.member.score.formatted())
                            .font(.system(size: 17, weight: .heavy).monospacedDigit())
                            .foregroundStyle(Palette.ink)
                    }
                    .padding(14)
                    .background(entry.member.id == uid ? Palette.lavender.opacity(0.5) : .clear)
                }
            }
        }
    }

    private var khatmah: some View {
        let done = parts.filter(\.done).count
        return VStack(alignment: .leading, spacing: 12) {
            AqraCard(padding: 14, radius: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(done) of 30 parts finished")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    ProgressView(value: Double(done), total: 30).tint(Palette.brand)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(parts) { part in
                    partTile(part)
                }
            }
            Text("Tap a free part to take it, and tap yours when you've read it.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
        }
    }

    private func partTile(_ part: KhatmahPart) -> some View {
        let mine = part.claimedBy == uid
        let face = ManazilStairs.face(forJuz: part.id)
        return Button {
            guard let uid else { return }
            if part.claimedBy == nil {
                social.claim(part, in: live, name: account.publicName ?? "")
            } else if part.claimedBy == uid {
                social.setDone(!part.done, part, in: live)
            }
        } label: {
            VStack(spacing: 2) {
                Text(verbatim: part.id.formatted())
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                Text(verbatim: part.done ? "✓" : String(part.claimedName.prefix(6)))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(mine ? Palette.brand : Palette.inkSoft)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(part.done ? face.top : part.claimedBy == nil ? .white : face.top.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(mine ? Palette.brand : Palette.lavender, lineWidth: mine ? 2 : 1))
        }
        .buttonStyle(AqraPressStyle())
        .contextMenu {
            if mine && !part.done {
                Button("Give it back") { social.release(part, in: live) }
            }
        }
        .accessibilityLabel(Text("Juz' \(part.id)"))
    }
}

// MARK: - A new competition

/// Starting a competition: a race among friends, a group khatmah, or — for a teacher — a competition among their
/// students, scored from the pages the teacher hears clean.
struct NewCompetitionView: View {
    /// The kinds offered: friends and khatmah for everyone; teacher for a teacher's own students.
    var kinds: [Competition.Kind]

    @Environment(SocialStore.self) private var social
    @Environment(TasmeeStore.self) private var tasmee
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var kind = Competition.Kind.friends
    @State private var title = ""
    @State private var metric = Competition.Metric.pagesRevised
    @State private var days = 7
    @State private var chosen: Set<String> = []
    @State private var working = false
    @State private var problem: AccountStore.Problem?

    /// Who can be added: friends, or the teacher's students.
    private var people: [(uid: String, name: String)] {
        kind == .teacher ? tasmee.myStudents.map { ($0.id, $0.name) } : social.friends
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("New competition")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 22)
                if kinds.count > 1 {
                    AqraSegmented(selection: $kind, options: [(.friends, "A race"), (.khatmah, "A khatmah together")])
                }
                AqraCard(padding: 0, radius: 24) {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Text("Name")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            TextField(text: $title, prompt: Text("Ramadan's revision")) { Text("Name") }
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 15, weight: .medium))
                        }
                        .padding(14)
                        if kind == .friends {
                            AqraRowDivider().padding(.leading, -50)
                            HStack {
                                Text("Counting")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Picker("Counting", selection: $metric) {
                                    ForEach([Competition.Metric.pagesRevised, .daysRevised, .ayatMemorized], id: \.self) { metric in
                                        Text(metric.title).tag(metric)
                                    }
                                }
                                .labelsHidden()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                        }
                        AqraRowDivider().padding(.leading, -50)
                        HStack {
                            Text("For")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Picker("For", selection: $days) {
                                Text("A week").tag(7)
                                Text("Two weeks").tag(14)
                                Text("A month").tag(30)
                            }
                            .labelsHidden()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                }

                AqraSectionTitle(title: kind == .teacher ? "Your students" : "Friends to invite").padding(.top, 6)
                if people.isEmpty {
                    Text(kind == .teacher ? "Students appear here once you've heard them." : "Add friends first, with a code.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.horizontal, 6)
                } else {
                    AqraCard(padding: 0, radius: 24) {
                        VStack(spacing: 0) {
                            ForEach(Array(people.enumerated()), id: \.element.uid) { index, person in
                                if index > 0 { AqraRowDivider() }
                                Button {
                                    if chosen.contains(person.uid) { chosen.remove(person.uid) } else { chosen.insert(person.uid) }
                                } label: {
                                    AqraRow(icon: kind == .teacher ? "🧑‍🎓" : "🙂", tint: Palette.sky, title: Text(verbatim: person.name)) {
                                        Image(systemName: chosen.contains(person.uid) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 22))
                                            .foregroundStyle(chosen.contains(person.uid) ? Palette.brand : Palette.lavender)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let problem { ProblemLine(problem: problem) }
                BrandButton("Start", metrics: OnboardingButtonMetrics(height: 54, fontSize: 17, compact: false)) {
                    Task { await start() }
                }
                .disabled(trimmedTitle.isEmpty || chosen.isEmpty || working)
                .opacity(trimmedTitle.isEmpty || chosen.isEmpty ? 0.5 : 1)
                .padding(.top, 8)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .presentationDragIndicator(.visible)
        .onAppear { kind = kinds.first ?? .friends }
        .animation(.snappy, value: kind)
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func start() async {
        working = true
        defer { working = false }
        let metric: Competition.Metric = kind == .khatmah ? .parts : kind == .teacher ? .cleanPages : self.metric
        let name = kind == .teacher ? (tasmee.teacherProfile?.name ?? "") : (account.publicName ?? "")
        do {
            try await social.start(kind: kind, title: String(trimmedTitle.prefix(60)), metric: metric, days: days, ownerName: name,
                                   members: Array(chosen))
            if let me = account.publicName { social.reportScores(name: me) }
            dismiss()
        } catch {
            problem = AccountStore.problem(for: error)
        }
    }
}

private typealias Palette = OnboardingPalette
