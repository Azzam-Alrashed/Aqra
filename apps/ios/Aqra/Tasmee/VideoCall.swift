@preconcurrency import FirebaseFunctions
import LiveKit
import SwiftUI

/// A video session's live call: one LiveKit room per session, joined with a token only the server issues — to the
/// session's teacher, or a student holding a seat in it, within the call's window (backend/functions/src/video.ts).
@MainActor @Observable
final class CallModel {
    enum Phase: Equatable {
        case idle
        case joining
        case joined
        /// Couldn't join: not yet open, closed, no seat, or no connection.
        case failed(CallProblem)
    }

    let sessionId: String
    let room = Room()
    private(set) var phase = Phase.idle
    private(set) var isTeacher = false
    /// The teacher's uid, to put their video first for students.
    private(set) var teacherId: String?
    private(set) var microphoneOn = true
    private(set) var cameraOn = true

    init(sessionId: String) {
        self.sessionId = sessionId
    }

    /// When a session's call can be joined: from a quarter of an hour before it starts until three hours after.
    static func isOpen(_ session: TasmeeSession, at date: Date = .now) -> Bool {
        session.kind == .video && session.status == .open && date >= opensAt(session) && date <= closesAt(session)
    }

    static func opensAt(_ session: TasmeeSession) -> Date { session.startsAt.addingTimeInterval(-15 * 60) }
    static func closesAt(_ session: TasmeeSession) -> Date { session.startsAt.addingTimeInterval(3 * 3_600) }

    /// What a call's button says while it can't be joined: when it opens, day and time, or that it has closed.
    static func waitingLabel(_ session: TasmeeSession, at date: Date) -> Text {
        date > closesAt(session) ? Text("This call has closed.") : CallOpening.label(opens: opensAt(session), now: date)
    }

    func join() async {
        guard phase != .joining, phase != .joined else { return }
        phase = .joining
        do {
            let result = try await Functions.functions(region: AccountStore.functionsRegion).httpsCallable("joinCall")
                .call(["sessionId": sessionId])
            guard let data = result.data as? [String: Any], let url = data["url"] as? String, let token = data["token"] as? String else {
                phase = .failed(.failed)
                return
            }
            isTeacher = data["isTeacher"] as? Bool ?? false
            teacherId = data["teacherId"] as? String
            try await room.connect(url: url, token: token)
            phase = .joined
            // Without a camera (or permission for it) the call goes on with audio.
            cameraOn = (try? await room.localParticipant.setCamera(enabled: true)) != nil
            microphoneOn = (try? await room.localParticipant.setMicrophone(enabled: true)) != nil
        } catch {
            phase = .failed(CallProblem(error))
        }
    }

    func toggleMicrophone() async {
        let on = !microphoneOn
        if (try? await room.localParticipant.setMicrophone(enabled: on)) != nil { microphoneOn = on }
    }

    func toggleCamera() async {
        let on = !cameraOn
        if (try? await room.localParticipant.setCamera(enabled: on)) != nil { cameraOn = on }
    }

    func leave() async {
        await room.disconnect()
        phase = .idle
    }
}

/// Why a call couldn't be joined, in words the student understands.
enum CallProblem: Equatable {
    /// The server's word for when it opens, when it gave one.
    case notOpenYet(opensAt: Date?)
    case closed, noSeat, offline, failed

    init(_ error: Error) {
        let error = error as NSError
        guard error.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: error.code) else {
            self = error.domain == NSURLErrorDomain ? .offline : .failed
            return
        }
        switch code {
        case .failedPrecondition:
            // The server says when the call opens if it hasn't yet.
            let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
            if let opensAt = details?["opensAt"] {
                self = .notOpenYet(opensAt: (opensAt as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) })
            } else {
                self = .closed
            }
        case .permissionDenied, .notFound: self = .noSeat
        case .unavailable, .deadlineExceeded: self = .offline
        default: self = .failed
        }
    }

    var message: Text {
        switch self {
        case .notOpenYet(let opensAt):
            // The rule, then the day and the time it means for this session.
            let rule = Text("The call opens a quarter of an hour before the session.")
            return opensAt.map { rule + Text(verbatim: "\n") + CallOpening.label(opens: $0, now: .now) } ?? rule
        case .closed: return Text("This call has closed.")
        case .noSeat: return Text("Only students with a seat join this call.")
        case .offline: return Text("You need an internet connection for this.")
        case .failed: return Text("That didn't work. Please try again.")
        }
    }
}

/// When a call opens, said with its day as well as its time: «تُفتح غدًا الساعة ٨:٤٥ م». A session booked for another
/// day once showed only «قبل الجلسة بربع ساعة», which left the student waiting by the button.
enum CallOpening: Equatable {
    case today, tomorrow, thisWeek, later

    static func day(of opens: Date, from now: Date, calendar: Calendar = .current) -> CallOpening {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: opens)).day ?? 0
        switch days {
        case ...0: return .today
        case 1: return .tomorrow
        case 2...6: return .thisWeek
        default: return .later
        }
    }

    /// «تُفتح اليوم الساعة ٨:٤٥ م», «تُفتح يوم الثلاثاء الساعة ٨:٤٥ م», «تُفتح في ١٤ أكتوبر الساعة ٨:٤٥ م».
    static func label(opens: Date, now: Date) -> Text {
        let time = opens.formatted(date: .omitted, time: .shortened)
        switch day(of: opens, from: now) {
        case .today: return Text("Opens today at \(time)")
        case .tomorrow: return Text("Opens tomorrow at \(time)")
        case .thisWeek: return Text("Opens \(opens.formatted(.dateTime.weekday(.wide))) at \(time)")
        case .later: return Text("Opens on \(opens.formatted(.dateTime.day().month(.wide))) at \(time)")
        }
    }
}

// MARK: - Joining

/// «انضم إلى المكالمة» on a student's booked video session, while its call is open.
struct JoinCallButton: View {
    var session: TasmeeSession

    @State private var joining = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let open = CallModel.isOpen(session, at: timeline.date)
            Button {
                joining = true
            } label: {
                Label { open ? Text("Join the call") : CallModel.waitingLabel(session, at: timeline.date) } icon: { Image(systemName: "video.fill") }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(open ? .white : OnboardingPalette.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(open ? OnboardingPalette.brand : OnboardingPalette.lavender, in: Capsule())
            }
            .buttonStyle(AqraPressStyle())
            .disabled(!open)
        }
        .fullScreenCover(isPresented: $joining) {
            StudentCallView(session: session)
        }
    }
}

// MARK: - The student's call

/// The student's side of a video tasmee': the teacher large, the others in a strip, the student's own picture
/// small, and the controls.
struct StudentCallView: View {
    var session: TasmeeSession

    @Environment(\.dismiss) private var dismiss
    @State private var call: CallModel

    init(session: TasmeeSession) {
        self.session = session
        _call = State(initialValue: CallModel(sessionId: session.id))
    }

    var body: some View {
        CallStage(call: call, room: call.room, title: Text(verbatim: session.teacherName)) {
            Task {
                await call.leave()
                dismiss()
            }
        }
        .task { await call.join() }
    }
}

// MARK: - The teacher's call

/// The teacher's side: everyone in the call, and the students who booked; tapping one opens the marking screen
/// with their video floating over the Mushaf.
struct TeacherCallView: View {
    var session: TasmeeSession
    var store: MushafStore
    var seats: [Seat]

    @Environment(TasmeeStore.self) private var tasmee
    @Environment(\.dismiss) private var dismiss
    @State private var call: CallModel
    @State private var hearing: Seat?

    init(session: TasmeeSession, store: MushafStore, seats: [Seat]) {
        self.session = session
        self.store = store
        self.seats = seats
        _call = State(initialValue: CallModel(sessionId: session.id))
    }

    var body: some View {
        CallStage(call: call, room: call.room, title: Text("Your students")) {
            Task {
                await call.leave()
                dismiss()
            }
        } footer: {
            if !seats.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(seats) { seat in
                            Button {
                                hearing = seat
                            } label: {
                                Label(seat.name, systemImage: "book.pages")
                                    .font(.system(size: 13, weight: .bold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .frame(height: 38)
                                    .foregroundStyle(OnboardingPalette.brand)
                                    .background(.white, in: Capsule())
                            }
                            .buttonStyle(AqraPressStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task { await call.join() }
        .fullScreenCover(item: $hearing) { seat in
            TasmeeMarkingView(store: store, studentName: seat.name, startPage: 1, allowsStageTest: true) { result in
                tasmee.recordTasmee(for: seat, in: session, pages: result.pages, stumbles: result.stumbles,
                                    mistakes: result.mistakes, test: result.test)
            } overlay: {
                ParticipantTile(room: call.room, identity: seat.id, name: seat.name)
                    .frame(width: 120, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            }
        }
    }
}

// MARK: - The call's stage

/// Everyone in a call: the teacher (or, for the teacher, the first student) large, the rest in a strip, the
/// caller's own picture in the corner, and the microphone, camera and leave controls.
private struct CallStage<Footer: View>: View {
    var call: CallModel
    @ObservedObject var room: Room
    var title: Text
    var onLeave: () -> Void
    @ViewBuilder var footer: Footer
    @State private var reporting: PersonRef?
    @State private var blocking: PersonRef?

    init(call: CallModel, room: Room, title: Text, onLeave: @escaping () -> Void, @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.call = call
        self.room = room
        self.title = title
        self.onLeave = onLeave
        self.footer = footer()
    }

    /// Everyone else in the call, to report.
    private var reportable: [PersonRef] {
        others.compactMap { participant in
            participant.identity.map { PersonRef(uid: $0.stringValue, name: participant.name ?? "", context: .call, contextId: call.sessionId) }
        }
    }

    /// The others in the call, the teacher first.
    private var others: [RemoteParticipant] {
        room.remoteParticipants.values.sorted { a, b in
            let aTeacher = a.identity?.stringValue == call.teacherId, bTeacher = b.identity?.stringValue == call.teacherId
            if aTeacher != bTeacher { return aTeacher }
            return (a.name ?? "") < (b.name ?? "")
        }
    }

    var body: some View {
        ZStack {
            Color(light: 0x1B1426, dark: 0x1B1426).ignoresSafeArea()
            VStack(spacing: 12) {
                HStack {
                    title
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(verbatim: "\(others.count + 1)")
                        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                    Image(systemName: "person.2.fill").foregroundStyle(.white.opacity(0.7))
                    // Reporting anyone else in the call to the team.
                    if !reportable.isEmpty {
                        Menu {
                            ForEach(reportable) { person in
                                Button {
                                    reporting = person
                                } label: {
                                    Label("Report \(person.shownName)", systemImage: "flag")
                                }
                            }
                        } label: {
                            Image(systemName: "flag")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: TapTarget.minimum, height: TapTarget.minimum)
                                .contentShape(Rectangle())
                        }
                        .padding(.vertical, -10)
                        .accessibilityLabel(Text("Report"))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Group {
                    switch call.phase {
                    case .idle, .joining:
                        VStack(spacing: 12) {
                            ProgressView().tint(.white)
                            Text("Joining the call…").foregroundStyle(.white.opacity(0.8))
                        }
                    case .failed(let problem):
                        VStack(spacing: 14) {
                            Text(verbatim: "📵").font(.system(size: 48))
                            problem.message
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            Button("Try again") { Task { await call.join() } }
                                .buttonStyle(ChipButtonStyle(filled: true))
                        }
                        .padding(24)
                    case .joined:
                        if let first = others.first {
                            ParticipantTile(room: room, participant: first)
                                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                                .padding(.horizontal, 12)
                        } else {
                            VStack(spacing: 10) {
                                Text(verbatim: "🕌").font(.system(size: 48))
                                Text(call.isTeacher ? "Waiting for your students…" : "Waiting for the teacher…")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    if call.phase == .joined {
                        LocalPreview(room: room, cameraOn: call.cameraOn)
                            .frame(width: 104, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 1))
                            .padding(24)
                    }
                }

                if others.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(others.dropFirst(), id: \.sid) { participant in
                                ParticipantTile(room: room, participant: participant)
                                    .frame(width: 96, height: 128)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                }

                footer

                HStack(spacing: 18) {
                    control(call.microphoneOn ? "mic.fill" : "mic.slash.fill", label: Text("Microphone"), active: call.microphoneOn) {
                        Task { await call.toggleMicrophone() }
                    }
                    control(call.cameraOn ? "video.fill" : "video.slash.fill", label: Text("Camera"), active: call.cameraOn) {
                        Task { await call.toggleCamera() }
                    }
                    Button(action: onLeave) {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Color(light: 0xD93A3A, dark: 0xD93A3A), in: Circle())
                    }
                    .accessibilityLabel(Text("Leave the call"))
                }
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .reportsAndBlocks($reporting, $blocking)
        // The screen stays on through the call, as it would in any call.
        .keepsScreenAwake(call.phase == .joined)
    }

    private func control(_ symbol: String, label: Text, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(active ? .white : Color(light: 0x1B1426, dark: 0x1B1426))
                .frame(width: 56, height: 56)
                .background(active ? .white.opacity(0.18) : .white, in: Circle())
        }
        .accessibilityLabel(label)
        .accessibilityValue(active ? Text("On") : Text("Off"))
    }
}

/// One person in the call: their camera, or their name when it's off.
struct ParticipantTile: View {
    @ObservedObject var room: Room
    private var participant: Participant?
    /// Who to show once they're in the call, when they aren't yet.
    private var identity: String?
    private var name: String?

    init(room: Room, participant: Participant) {
        self.room = room
        self.participant = participant
        self.name = participant.name
    }

    /// Someone by their uid: shown as soon as they join.
    init(room: Room, identity: String, name: String) {
        self.room = room
        self.identity = identity
        self.name = name
    }

    var body: some View {
        let shown = participant ?? room.remoteParticipants.values.first { $0.identity?.stringValue == identity }
        ZStack {
            Color(light: 0x2E2440, dark: 0x2E2440)
            if let shown {
                ObservedParticipant(participant: shown, name: name)
            } else {
                VStack(spacing: 6) {
                    CallInitial(name: name ?? "")
                    Text("Not in the call")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}

/// A participant, redrawn as their tracks come and go.
private struct ObservedParticipant: View {
    @ObservedObject var participant: Participant
    var name: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // The camera's publication is watched on its own: turning a camera off mutes its track, a change on
            // the publication rather than on the participant, and a video view left in place keeps its last frame.
            if let camera = participant.firstCameraPublication {
                ObservedCamera(publication: camera, name: shownName)
            } else {
                CallInitial(name: shownName)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 4) {
                if let microphone = participant.firstAudioPublication {
                    ObservedMicrophoneBadge(publication: microphone)
                } else {
                    MicrophoneOffBadge()
                }
                Text(verbatim: shownName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.35), in: Capsule())
            .padding(8)
        }
    }

    private var shownName: String { name ?? participant.name ?? "" }
}

/// What a tile shows for someone else's camera: their video only while the camera is on and its track has
/// arrived, their initial otherwise, so a camera turned off never leaves its last frame on screen (Android does the
/// same in `ParticipantView`).
enum RemoteCameraTile: Equatable {
    case video, initial

    static func shown(isMuted: Bool, isSubscribed: Bool, hasVideoTrack: Bool) -> RemoteCameraTile {
        !isMuted && isSubscribed && hasVideoTrack ? .video : .initial
    }
}

/// Someone else's camera, redrawn as its track is muted and unmuted.
private struct ObservedCamera: View {
    @ObservedObject var publication: TrackPublication
    var name: String

    var body: some View {
        let track = publication.track as? VideoTrack
        if let track, RemoteCameraTile.shown(isMuted: publication.isMuted, isSubscribed: publication.isSubscribed,
                                             hasVideoTrack: true) == .video {
            SwiftUIVideoView(track, layoutMode: .fill)
        } else {
            CallInitial(name: name)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The crossed microphone beside a name, redrawn as the microphone is muted and unmuted.
private struct ObservedMicrophoneBadge: View {
    @ObservedObject var publication: TrackPublication

    var body: some View {
        if publication.isMuted { MicrophoneOffBadge() }
    }
}

private struct MicrophoneOffBadge: View {
    var body: some View {
        Image(systemName: "mic.slash.fill").font(.system(size: 10, weight: .bold))
    }
}

/// A person's initial in a brand circle, shown in place of their camera.
private struct CallInitial: View {
    var name: String

    var body: some View {
        Text(verbatim: String(name.prefix(1)))
            .font(.system(size: 28, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(OnboardingPalette.brand, in: Circle())
    }
}

/// The caller's own camera.
private struct LocalPreview: View {
    @ObservedObject var room: Room
    var cameraOn: Bool

    var body: some View {
        LocalCamera(participant: room.localParticipant, cameraOn: cameraOn)
    }
}

private struct LocalCamera: View {
    @ObservedObject var participant: LocalParticipant
    var cameraOn: Bool

    var body: some View {
        ZStack {
            Color(light: 0x2E2440, dark: 0x2E2440)
            if cameraOn, let track = participant.localVideoTracks.first?.track as? VideoTrack {
                SwiftUIVideoView(track, layoutMode: .fill, mirrorMode: .mirror)
            } else {
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}
