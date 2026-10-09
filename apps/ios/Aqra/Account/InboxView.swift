import SwiftUI

/// The bell on the home: messages from the server and the team, newest first.
struct InboxButton: View {
    @Environment(InboxStore.self) private var inbox
    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            Image(systemName: "bell.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(OnboardingPalette.brand)
                .frame(width: 38, height: 38)
                .background(.white, in: Circle())
                .shadow(color: OnboardingPalette.shadow.opacity(0.1), radius: 8, y: 4)
                .overlay(alignment: .topTrailing) {
                    if inbox.unread > 0 {
                        Text(verbatim: min(inbox.unread, 9).formatted())
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 17, height: 17)
                            .background(Color(light: 0xD0505A, dark: 0xD0505A), in: Circle())
                            .offset(x: 3, y: -3)
                            .transition(.scale)
                    }
                }
        }
        .buttonStyle(AqraPressStyle())
        .accessibilityLabel(Text("Messages"))
        .accessibilityValue(inbox.unread > 0 ? Text("\(inbox.unread) unread") : Text(verbatim: ""))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: inbox.unread)
        .sheet(isPresented: $open) {
            InboxView()
        }
    }
}

/// Messages from the server and the team.
struct InboxView: View {
    @Environment(InboxStore.self) private var inbox
    @Environment(TasmeeStore.self) private var tasmee

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Messages")
                    .aqraFont(size: 28, weight: .heavy)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 22)
                if inbox.messages.isEmpty {
                    Text("Nothing new.")
                        .aqraFont(size: 15, weight: .medium)
                        .foregroundStyle(Palette.inkSoft)
                } else {
                    AqraCard(padding: 0, radius: 24) {
                        VStack(spacing: 0) {
                            ForEach(Array(inbox.messages.enumerated()), id: \.element.id) { index, message in
                                if index > 0 { AqraRowDivider() }
                                row(message)
                                    .contextMenu {
                                        Button("Delete", role: .destructive) { inbox.delete(message) }
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
        .environment(\.colorScheme, .light)
        .presentationDragIndicator(.visible)
        .onDisappear { inbox.markAllRead() }
    }

    private func row(_ message: InboxStore.Message) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(icon: icon(message), tint: message.read ? Palette.lavender : Palette.butter, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                text(message)
                    .font(.system(size: 15, weight: message.read ? .semibold : .heavy))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !message.note.isEmpty {
                    Text(verbatim: message.note)
                        .aqraFont(size: 12, weight: .medium)
                        .foregroundStyle(Palette.inkSoft)
                }
                Text(verbatim: message.at.formatted(.relative(presentation: .named)))
                    .aqraFont(size: 11, weight: .semibold)
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private func icon(_ message: InboxStore.Message) -> String {
        switch message.kind {
        case .outbid: "🔔"
        case .won: "🎉"
        case .cancelled: "📅"
        case .refund: "↩️"
        case .tasmee: "🎓"
        case .application: "📜"
        case .payout: "🏦"
        }
    }

    private func text(_ message: InboxStore.Message) -> Text {
        switch message.kind {
        case .outbid: Text("You were outbid in \(message.teacherName)'s session. Your \(message.amount) credits are back.")
        case .won: Text("You won a seat in \(message.teacherName)'s session.")
        case .cancelled, .refund: cancellation(message)
        case .tasmee: Text("\(message.teacherName) recorded your tasmee' of \(message.pages) pages.")
        case .application:
            switch message.status {
            case "interview": Text("Your application to teach was reviewed: the team will be in touch for the interview.")
            case "approved": Text("Your application to teach was approved. Welcome!")
            case "rejected": Text("Your application to teach wasn't accepted.")
            default: Text("Your application to teach was updated.")
            }
        case .payout: Text("A payout of \(message.amount) credits was sent to you.")
        }
    }

    /// A cancelled session, named by its day and time: the server sends its start, and older messages find it among
    /// the bookings. Credits held or paid for it are back.
    private func cancellation(_ message: InboxStore.Message) -> Text {
        guard let startsAt = message.startsAt ?? tasmee.startOfBooked(message.sessionId) else {
            return message.amount > 0
                ? Text("\(message.teacherName) cancelled a session: your \(message.amount) credits are back.")
                : Text("\(message.teacherName) cancelled a session you were in.")
        }
        let when = TasmeeFormat.when(startsAt)
        return message.amount > 0
            ? Text("\(message.teacherName) cancelled their session on \(when): your \(message.amount) credits are back.")
            : Text("\(message.teacherName) cancelled their session on \(when).")
    }
}

private typealias Palette = OnboardingPalette
