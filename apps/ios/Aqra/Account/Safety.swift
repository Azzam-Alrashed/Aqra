@preconcurrency import FirebaseFirestore
import Foundation
import Observation
import SwiftUI

// MARK: - Reporting and blocking

/// Someone shown to the student by name, in a place they can be reported from: a teacher's profile, a call, a friend,
/// a competition's standings, a teacher's student.
struct PersonRef: Identifiable, Hashable {
    var uid: String
    var name: String
    var context: PersonReport.Context
    /// The session, competition or friendship the report is about, for the team to look at.
    var contextId: String?

    var id: String { uid }
    /// The name as shown, never empty.
    var shownName: String { name.isEmpty ? "—" : name }
}

/// A report to Aqra's team about someone's name, words or conduct (docs/SRS.md SAF-01; App Review guideline 1.2).
/// The person reported isn't told, and the student never sees reports again: the team reads them with
/// `npm run admin -- reports`.
struct PersonReport: Equatable {
    enum Context: String, CaseIterable, Sendable { case teacher, student, call, friend, competition }

    enum Reason: String, CaseIterable, Identifiable, Sendable {
        case inappropriate, abuse, spam, other
        var id: Self { self }

        var icon: String {
            switch self {
            case .inappropriate: "🚫"
            case .abuse: "😠"
            case .spam: "📢"
            case .other: "💬"
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .inappropriate: "Inappropriate name, words or picture"
            case .abuse: "Abuse or harassment"
            case .spam: "Spam or a scam"
            case .other: "Something else"
            }
        }
    }

    /// What Firestore keeps of a note: the rules take at most a thousand characters.
    static let noteLimit = 1000

    var person: PersonRef
    var reason: Reason
    var note: String

    /// The document as the rules take it, dated by the server.
    func document(reporter: String) -> [String: Any] {
        var document: [String: Any] = [
            "reporter": reporter, "subject": person.uid, "subjectName": String(person.name.prefix(100)),
            "context": person.context.rawValue, "reason": reason.rawValue, "createdAt": FieldValue.serverTimestamp(),
        ]
        if let contextId = person.contextId { document["contextId"] = String(contextId.prefix(128)) }
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { document["note"] = String(note.prefix(Self.noteLimit)) }
        return document
    }
}

/// The people this student blocked, kept on the device (docs/SRS.md SAF-02): a blocked teacher's sessions leave the
/// list, a blocked friend stops being a friend, and a blocked name in a competition's standings is hidden. Reports
/// go to the team through the account.
@MainActor @Observable
final class SafetyStore {
    struct Blocked: Codable, Hashable, Identifiable {
        var uid: String
        var name: String
        var id: String { uid }
    }

    private(set) var blocked: [Blocked] = []

    @ObservationIgnored private let defaults: UserDefaults
    static let key = "safety.blocked"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode([Blocked].self, from: data) {
            blocked = saved
        }
    }

    func isBlocked(_ uid: String) -> Bool { blocked.contains { $0.uid == uid } }

    func block(_ person: PersonRef) {
        guard !isBlocked(person.uid) else { return }
        blocked.append(Blocked(uid: person.uid, name: person.name))
        save()
    }

    func unblock(_ uid: String) {
        blocked.removeAll { $0.uid == uid }
        save()
    }

    /// Sends a report to the team; offline, it says so rather than waits.
    func send(_ report: PersonReport, from reporter: String) async throws {
        try await withServerTimeout {
            _ = try await Firestore.firestore().collection("reports").addDocument(data: report.document(reporter: reporter))
        }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(blocked), forKey: Self.key)
    }
}

// MARK: - The menu beside a name

/// The menu items for someone: report them, and block or unblock them where blocking hides something.
struct PersonActions: View {
    var person: PersonRef
    @Binding var reporting: PersonRef?
    @Binding var blocking: PersonRef?
    var canBlock = true

    @Environment(SafetyStore.self) private var safety

    var body: some View {
        Button {
            reporting = person
        } label: {
            Label("Report", systemImage: "flag")
        }
        if !canBlock {
            EmptyView()
        } else if safety.isBlocked(person.uid) {
            Button {
                safety.unblock(person.uid)
            } label: {
                Label("Unblock", systemImage: "hand.raised.slash")
            }
        } else {
            Button(role: .destructive) {
                blocking = person
            } label: {
                Label("Block", systemImage: "hand.raised")
            }
        }
    }
}

/// «…» beside a name, opening its menu: drawn small, tapped at 44 points.
struct PersonMenuLabel: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Palette.inkSoft)
            .frame(width: 30, height: 30)
            .background(Palette.lavender, in: Circle())
            .tapTarget(drawn: CGSize(width: 30, height: 30))
            .accessibilityLabel(Text("More"))
    }
}

extension View {
    /// The report sheet and the block confirmation for the people on this screen. `onBlock` runs after blocking,
    /// for what the screen does then (ending a friendship, leaving a teacher's page).
    func reportsAndBlocks(_ reporting: Binding<PersonRef?>, _ blocking: Binding<PersonRef?>,
                          onBlock: @escaping (PersonRef) -> Void = { _ in }) -> some View {
        modifier(ReportsAndBlocks(reporting: reporting, blocking: blocking, onBlock: onBlock))
    }
}

private struct ReportsAndBlocks: ViewModifier {
    @Binding var reporting: PersonRef?
    @Binding var blocking: PersonRef?
    var onBlock: (PersonRef) -> Void

    @Environment(SafetyStore.self) private var safety

    func body(content: Content) -> some View {
        content
            .sheet(item: $reporting) { person in
                ReportSheet(person: person, onBlock: onBlock)
            }
            .alert(Text("Block \(blocking?.shownName ?? "")?"), isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }),
                   presenting: blocking) { person in
                Button("Block", role: .destructive) {
                    safety.block(person)
                    onBlock(person)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("You won't see their sessions, their name or their scores. You can unblock them in Account.")
            }
    }
}

// MARK: - The report sheet

/// «الإبلاغ»: why, a word more if the student wants, and whether to block the person too; then a thank-you.
struct ReportSheet: View {
    var person: PersonRef
    var onBlock: (PersonRef) -> Void = { _ in }

    @Environment(SafetyStore.self) private var safety
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var reason: PersonReport.Reason?
    @State private var note = ""
    @State private var alsoBlock = false
    @State private var sending = false
    @State private var sent = false
    @State private var problem: AccountStore.Problem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if sent {
                    thanks
                } else {
                    form
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: sent)
            .animation(.snappy, value: reason)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .preferredColorScheme(.light)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(sending)
        .sensoryFeedback(.success, trigger: sent) { _, sent in sent }
        // What the screen does once someone is blocked (closing a teacher's page) waits for the thank-you to close.
        .onDisappear { if sent && alsoBlock { onBlock(person) } }
    }

    @ViewBuilder private var form: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Report \(person.shownName)")
                .aqraFont(size: 26, weight: .heavy)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Aqra's team reads every report. \(person.shownName) isn't told who sent it.")
                .aqraFont(size: 13, weight: .semibold)
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }

        AqraSectionTitle(title: "What happened?").padding(.top, 6)
        AqraCard(padding: 0, radius: 24) {
            VStack(spacing: 0) {
                ForEach(Array(PersonReport.Reason.allCases.enumerated()), id: \.element) { index, choice in
                    if index > 0 { AqraRowDivider() }
                    Button {
                        reason = choice
                    } label: {
                        AqraRow(icon: choice.icon, tint: Palette.lavender, title: Text(choice.title)) {
                            Image(systemName: reason == choice ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(reason == choice ? Palette.brand : Palette.lavender)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(reason == choice ? .isSelected : [])
                }
            }
        }

        AqraCard(padding: 14, radius: 24) {
            TextField(text: $note, prompt: Text("Anything that helps the team (optional)"), axis: .vertical) {
                Text("Details")
            }
            .aqraFont(size: 15, weight: .medium)
            .lineLimit(3...6)
            .onChange(of: note) {
                if note.count > PersonReport.noteLimit { note = String(note.prefix(PersonReport.noteLimit)) }
            }
        }

        if !safety.isBlocked(person.uid) {
            AqraCard(padding: 0, radius: 24) {
                AqraRow(icon: "✋", tint: Palette.rose, title: Text("Block \(person.shownName) too"),
                        detail: Text("You won't see their sessions, their name or their scores.")) {
                    Toggle(isOn: $alsoBlock) { Text("Block \(person.shownName) too") }
                        .labelsHidden()
                        .tint(Palette.brand)
                }
            }
        }

        if let problem {
            ProblemLine(problem: problem).padding(.horizontal, 6)
        }

        Button {
            Task { await send() }
        } label: {
            Group {
                if sending {
                    ProgressView().tint(.white)
                } else {
                    Text("Send report")
                }
            }
        }
        .buttonStyle(BrandButtonStyle())
        .disabled(reason == nil || sending)
        .opacity(reason == nil ? 0.5 : 1)
        .padding(.top, 6)
    }

    @ViewBuilder private var thanks: some View {
        VStack(spacing: 12) {
            Text(verbatim: "🤍").font(.system(size: 52))
            Text("Thank you")
                .aqraFont(size: 26, weight: .heavy)
                .foregroundStyle(Palette.ink)
            Text("The team will look into it.")
                .aqraFont(size: 14, weight: .semibold)
                .foregroundStyle(Palette.inkSoft)
            if alsoBlock {
                Text("\(person.shownName) is blocked. You can unblock them in Account.")
                    .aqraFont(size: 13, weight: .semibold)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
        Button("Done") { dismiss() }
            .buttonStyle(BrandButtonStyle())
            .padding(.top, 18)
    }

    private func send() async {
        guard let reason, let reporter = account.profile?.uid else {
            problem = .failed
            return
        }
        sending = true
        problem = nil
        defer { sending = false }
        do {
            try await safety.send(PersonReport(person: person, reason: reason, note: note), from: reporter)
            if alsoBlock { safety.block(person) }
            sent = true
        } catch {
            problem = AccountStore.problem(for: error)
        }
    }
}

// MARK: - The people blocked

/// «المحظورون» in Account: everyone blocked on this device, each with «إلغاء الحظر».
struct BlockedPeopleView: View {
    @Environment(SafetyStore.self) private var safety

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Blocked")
                    .aqraFont(size: 28, weight: .heavy)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 22)
                    .accessibilityAddTraits(.isHeader)
                Text("You don't see their sessions, their names or their scores.")
                    .aqraFont(size: 13, weight: .semibold)
                    .foregroundStyle(Palette.inkSoft)
                if safety.blocked.isEmpty {
                    AqraCard(padding: 14, radius: 24) {
                        Text("No one is blocked.")
                            .aqraFont(size: 14, weight: .medium)
                            .foregroundStyle(Palette.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    AqraCard(padding: 0, radius: 24) {
                        VStack(spacing: 0) {
                            ForEach(Array(safety.blocked.enumerated()), id: \.element.id) { index, person in
                                if index > 0 { AqraRowDivider() }
                                AqraRow(icon: "✋", tint: Palette.rose, title: Text(verbatim: person.name.isEmpty ? "—" : person.name)) {
                                    Button("Unblock") {
                                        withAnimation(.snappy) { safety.unblock(person.uid) }
                                    }
                                    .buttonStyle(ChipButtonStyle(filled: false))
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
        .preferredColorScheme(.light)
        .presentationDragIndicator(.visible)
    }
}

private typealias Palette = OnboardingPalette
