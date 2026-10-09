import AuthenticationServices
import SwiftUI
import UIKit
import UserNotifications

/// حسابي: the account the progress is backed up to, the Mushaf's colors, the daily reminder, the app's language,
/// and the sources Aqra is built on. What's memorized and the daily amount are edited from the home.
struct AccountView: View {
    @Environment(AccountStore.self) private var account
    @Environment(PlanStore.self) private var plan
    @Environment(RevisionStore.self) private var revision
    @Environment(MemorizationStore.self) private var memorization
    @Environment(\.openURL) private var openURL
    @AppStorage("sounds.on") private var soundsOn = true
    @AppStorage("mushaf.tajweed") private var tajweed = true
    @AppStorage("mushaf.topics") private var topicColors = true
    @AppStorage("reminder.on") private var reminderOn = false
    /// Minutes after midnight.
    @AppStorage("reminder.minutes") private var reminderMinutes = 5 * 60 + 30
    @State private var notificationsDenied = false
    @State private var confirmingSignOut = false
    @State private var confirmingDeletion = false
    @State private var confirmingBackupDeletion = false
    @State private var showingWallet = false
    @Environment(WalletStore.self) private var wallet

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Account")
                        .aqraFont(size: 30, weight: .heavy)
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 16)
                        .accessibilityAddTraits(.isHeader)
                    AccountCard()

                    if AccountStore.isAvailable {
                        Button {
                            showingWallet = true
                        } label: {
                            AqraCard(padding: 0, radius: 24) {
                                AqraRow(icon: "🪙", tint: Palette.butter, title: Text("Credits"),
                                        detail: account.profile?.isAnonymous == false
                                            ? Text("\(CreditsFormat.credits(wallet.balance)) credits")
                                            : Text("For seats won by bidding"))
                            }
                        }
                        .buttonStyle(AqraPressStyle())
                    }

                    AqraSectionTitle(title: "Mushaf").padding(.top, 10)
                    AqraCard(padding: 0, radius: 24) {
                        VStack(spacing: 0) {
                            AqraRow(icon: "🖍️", tint: Palette.rose, title: Text("Tajweed colors")) { toggle($tajweed) }
                            AqraRowDivider()
                            AqraRow(icon: "🎨", tint: Palette.mint, title: Text("Topic colors")) { toggle($topicColors) }
                        }
                    }

                    AqraSectionTitle(title: "Revision").padding(.top, 10)
                    AqraCard(padding: 0, radius: 24) {
                        VStack(spacing: 0) {
                            AqraRow(icon: "🔔", tint: Palette.sky, title: Text("Daily reminder"),
                                    detail: reminderOn ? Text("Every day at \(reminderTime.wrappedValue.formatted(date: .omitted, time: .shortened))") : nil) {
                                toggle($reminderOn)
                            }
                            if reminderOn {
                                AqraRowDivider()
                                HStack {
                                    Text("Time")
                                        .aqraFont(size: 15, weight: .bold)
                                        .foregroundStyle(Palette.ink)
                                    Spacer()
                                    DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                }
                                .padding(.horizontal, 14)
                                .padding(.leading, 50)
                                .padding(.vertical, 10)
                                .transition(.opacity)
                            }
                        }
                    }
                    if notificationsDenied {
                        HStack(spacing: 8) {
                            Text("Notifications are turned off for Aqra in Settings.")
                                .aqraFont(size: 12, weight: .semibold)
                                .foregroundStyle(Palette.inkSoft)
                            Button("Open Settings") { openSettings() }
                                .aqraFont(size: 12, weight: .bold)
                                .foregroundStyle(Palette.brand)
                        }
                        .padding(.horizontal, 6)
                    }

                    AqraSectionTitle(title: "App").padding(.top, 10)
                    AqraCard(padding: 0, radius: 24) {
                        VStack(spacing: 0) {
                            AqraRow(icon: "🔔", tint: Palette.butter, title: Text("Sounds"),
                                    detail: Text("A gentle chime for rewards")) { toggle($soundsOn) }
                            AqraRowDivider()
                            Button {
                                openSettings()
                            } label: {
                                AqraRow(icon: "🌐", tint: Palette.lavender, title: Text("Language"), detail: Text(verbatim: languageName))
                            }
                            .buttonStyle(.plain)
                            AqraRowDivider()
                            NavigationLink {
                                SourcesView()
                            } label: {
                                AqraRow(icon: "📚", tint: Palette.butter, title: Text("Sources"),
                                        detail: Text("The Quran text, fonts and data"))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if account.profile?.isAnonymous == false {
                        AqraCard(padding: 0, radius: 24) {
                            VStack(spacing: 0) {
                                Button {
                                    confirmingSignOut = true
                                } label: {
                                    AqraRow(icon: "🚪", tint: Palette.lavender, title: Text("Sign out")) { EmptyView() }
                                }
                                .buttonStyle(.plain)
                                AqraRowDivider()
                                Button {
                                    confirmingDeletion = true
                                } label: {
                                    AqraRow(icon: "🗑️", tint: Palette.rose,
                                            title: Text("Delete account").foregroundStyle(Color(light: 0xB3261E, dark: 0xB3261E))) { EmptyView() }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .disabled(account.isWorking)
                        .padding(.top, 10)
                    } else if account.profile?.isAnonymous == true {
                        // Every install backs up to an anonymous account from the start; that backup can be deleted too.
                        AqraCard(padding: 0, radius: 24) {
                            Button {
                                confirmingBackupDeletion = true
                            } label: {
                                AqraRow(icon: "🗑️", tint: Palette.rose,
                                        title: Text("Delete my backup").foregroundStyle(Color(light: 0xB3261E, dark: 0xB3261E)),
                                        detail: Text("The copy of your progress kept online")) { EmptyView() }
                            }
                            .buttonStyle(.plain)
                        }
                        .disabled(account.isWorking)
                        .padding(.top, 10)
                    }

                    Text("Version \(version)")
                        .aqraFont(size: 12, weight: .semibold)
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .animation(.snappy, value: reminderOn)
                .animation(.snappy, value: notificationsDenied)
            }
            .scrollIndicators(.hidden)
            .background(Palette.surface.ignoresSafeArea())
            .fadesUnderStatusBar()
            .toolbar(.hidden, for: .navigationBar)
        }
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .sheet(isPresented: $showingWallet) { WalletView() }
        .onChange(of: reminderOn) { updateReminder() }
        .onChange(of: reminderMinutes) { updateReminder() }
        .alert("Sign out?", isPresented: $confirmingSignOut) {
            Button("Sign out", role: .destructive) { Task { await account.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your progress stays in your account, and this device starts afresh. Sign in again to bring it back.")
        }
        .alert("Delete your account?", isPresented: $confirmingDeletion) {
            Button("Delete", role: .destructive) { Task { await account.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account and the progress backed up in it are deleted for good. The progress on this device stays.")
        }
        .alert("Delete your backup?", isPresented: $confirmingBackupDeletion) {
            Button("Delete", role: .destructive) { Task { await account.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The copy of your progress kept online is deleted for good. The progress on this device stays, and is backed up afresh from now on.")
        }
    }

    private func toggle(_ isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .tint(Palette.brand)
    }

    // MARK: - Reminder

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminderMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private func updateReminder() {
        guard reminderOn else {
            DailyReminder.cancel()
            return
        }
        Task {
            if await DailyReminder.authorize() {
                notificationsDenied = false
                DailyReminder.refresh(minutes: reminderMinutes, revision: revision, plan: plan, memorization: memorization)
            } else {
                notificationsDenied = true
                reminderOn = false
            }
        }
    }

    // MARK: - App

    private var languageName: String {
        let code = Locale.current.language.languageCode?.identifier ?? "ar"
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(short) (\(build))"
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

/// The account the progress is backed up to: an invitation to sign in while anonymous, and who's signed in after.
struct AccountCard: View {
    @Environment(AccountStore.self) private var account
    @Environment(CloudSync.self) private var sync
    @State private var editingName = false
    @State private var name = ""

    var body: some View {
        AqraCard(padding: 14, radius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                if let profile = account.profile, !profile.isAnonymous {
                    signedIn(profile)
                    publicNameRow
                } else {
                    invitation
                    if AccountStore.isAvailable {
                        SignInButtons()
                    }
                }
                if let problem = account.problem {
                    ProblemLine(problem: problem)
                }
                #if DEBUG
                if AccountStore.usesEmulator, let profile = account.profile {
                    EmulatorSignIn(profile: profile)
                }
                #endif
            }
        }
        .animation(.snappy, value: account.profile)
        .animation(.snappy, value: account.problem)
    }

    private var invitation: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(icon: "🪪", tint: Palette.butter, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("Save your progress")
                    .aqraFont(size: 16, weight: .heavy)
                    .foregroundStyle(Palette.ink)
                Text("Your progress is only on this device until you sign in.")
                    .aqraFont(size: 12, weight: .semibold)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func signedIn(_ profile: AccountStore.Profile) -> some View {
        HStack(alignment: .center, spacing: 12) {
            IconTile(icon: profile.provider == .apple ? "🍎" : "🌐", tint: Palette.sky, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: profile.name ?? profile.email ?? "")
                    .aqraFont(size: 16, weight: .heavy)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let email = profile.email, profile.name != nil {
                    Text(verbatim: email)
                        .aqraFont(size: 12, weight: .semibold)
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                }
                Group {
                    if let backup = sync.lastBackup {
                        Text("Backed up \(backup.formatted(.relative(presentation: .named)))")
                    } else {
                        Text("Backing up…")
                    }
                }
                .aqraFont(size: 12, weight: .semibold)
                .foregroundStyle(Palette.brand)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// The name teachers, friends and peers see.
    private var publicNameRow: some View {
        Button {
            name = account.publicName ?? ""
            editingName = true
        } label: {
            HStack(spacing: 10) {
                IconTile(icon: "🏷️", tint: Palette.lavender, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Name others see")
                        .aqraFont(size: 12, weight: .semibold)
                        .foregroundStyle(Palette.inkSoft)
                    Text(verbatim: account.publicName ?? "—")
                        .aqraFont(size: 15, weight: .heavy)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Palette.brand)
                    .frame(width: 30, height: 30)
                    .background(Palette.lavender, in: Circle())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alert("Name others see", isPresented: $editingName) {
            TextField("Your name", text: $name)
            Button("Save") { account.setDisplayName(name) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Teachers, friends and those who hear your tasmee' see this name.")
        }
    }
}

/// Sign in with Apple and with Google, one above the other.
struct SignInButtons: View {
    @Environment(AccountStore.self) private var account

    private static let googleLogo: UIImage? = Bundle.main.url(forResource: "GoogleSignIn_GoogleSignIn", withExtension: "bundle")
        .flatMap(Bundle.init(url:))
        .flatMap { UIImage(named: "google", in: $0, with: nil) }

    var body: some View {
        VStack(spacing: 10) {
            SignInWithAppleButton(.continue) { request in
                account.prepareApple(request)
            } onCompletion: { result in
                Task { await account.completeApple(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .clipShape(Capsule())

            Button {
                Task { await account.signInWithGoogle() }
            } label: {
                // Google's light button: its own logo, from the Google Sign-In package, on white with a grey outline.
                HStack(spacing: 10) {
                    if let logo = Self.googleLogo {
                        Image(uiImage: logo)
                            .resizable()
                            .frame(width: 18, height: 18)
                    }
                    Text("Continue with Google")
                        .aqraFont(size: 17, weight: .semibold, design: .default)
                        .foregroundStyle(Color(light: 0x1F1F1F, dark: 0x1F1F1F))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(.white, in: Capsule())
                .overlay(Capsule().strokeBorder(Color(light: 0x747775, dark: 0x747775), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(AqraPressStyle())
        }
        .disabled(account.isWorking)
        .opacity(account.isWorking ? 0.6 : 1)
        .overlay {
            if account.isWorking { ProgressView().tint(Palette.brand) }
        }
    }
}

#if DEBUG
/// Signing in to the local Auth emulator with any email, and this account's uid for the seed script.
private struct EmulatorSignIn: View {
    var profile: AccountStore.Profile
    @Environment(AccountStore.self) private var account
    @State private var email = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Emulator · \(profile.uid)")
                .font(.system(size: 11, weight: .semibold).monospaced())
                .foregroundStyle(Palette.inkSoft)
                .textSelection(.enabled)
            if profile.isAnonymous {
                HStack(spacing: 8) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .aqraFont(size: 14, weight: .medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .frame(minHeight: 40)
                        .background(Palette.surface, in: Capsule())
                    Button("Sign in to the emulator") {
                        Task { await account.signInToEmulator(email: email.trimmingCharacters(in: .whitespaces)) }
                    }
                    .aqraFont(size: 13, weight: .bold)
                    .foregroundStyle(Palette.brand)
                    .disabled(email.isEmpty || account.isWorking)
                }
            }
        }
    }
}
#endif

/// What went wrong, in one calm line.
struct ProblemLine: View {
    var problem: AccountStore.Problem

    var body: some View {
        Group {
            switch problem {
            case .offline: Text("You need an internet connection for this.")
            case .failed: Text("That didn't work. Please try again.")
            }
        }
        .aqraFont(size: 12, weight: .semibold)
        .foregroundStyle(Color(light: 0x9A3E26, dark: 0x9A3E26))
        .transition(.opacity)
    }
}

/// The daily reminder of today's wird: one notification a day at the chosen time, as dated reminders two weeks
/// ahead, refreshed as the app is used. Today's is left out once today's work is done.
@MainActor
enum DailyReminder {
    nonisolated private static let identifier = "daily-wird"
    nonisolated static let daysAhead = 14

    /// Asks to send notifications the first time; false if they're turned off for the app.
    static func authorize() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    struct Reminder: Equatable {
        /// «daily-wird-2026-10-09»: one per day, so a day's can be taken away alone.
        var id: String
        var fireAt: Date
        /// On the plan's study days, it also mentions the new portion.
        var withPortion: Bool
    }

    /// The reminders to set: one a day at the chosen time for the next two weeks, starting today unless today's time
    /// has passed or today's work is done.
    nonisolated static func reminders(minutes: Int, studyDays: Set<Int>?, todayDone: Bool, now: Date,
                                      calendar: Calendar = .current) -> [Reminder] {
        let today = calendar.startOfDay(for: now)
        return (0..<daysAhead).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fireAt = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  offset > 0 || (!todayDone && fireAt > now) else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let id = String(format: "%@-%04d-%02d-%02d", identifier, parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            return Reminder(id: id, fireAt: fireAt, withPortion: studyDays?.contains(calendar.component(.weekday, from: day)) ?? false)
        }
    }

    /// Whether today's work is done: today's wird complete and, on a study day of an active plan, the new portion
    /// recorded (or nothing left to memorize).
    static func isTodayDone(revision: RevisionStore, plan: PlanStore, memorization: MemorizationStore, now: Date = .now) -> Bool {
        guard let wird = revision.plan, Calendar.current.isDate(wird.day, inSameDayAs: now), wird.isComplete else { return false }
        return !plan.isPortionDue(memorization: memorization, now: now)
    }

    /// Sets the reminders from where the student is today.
    static func refresh(minutes: Int, revision: RevisionStore, plan: PlanStore, memorization: MemorizationStore) {
        schedule(minutes: minutes, studyDays: plan.plan.flatMap { $0.paused ? nil : $0.studyDays },
                 todayDone: isTodayDone(revision: revision, plan: plan, memorization: memorization))
    }

    /// The last change asked for: each waits for the one before, so they never interleave.
    private static var pending: Task<Void, Never>?

    static func schedule(minutes: Int, studyDays: Set<Int>?, todayDone: Bool) {
        let reminders = reminders(minutes: minutes, studyDays: studyDays, todayDone: todayDone, now: .now)
        replace(with: reminders)
    }

    static func cancel() {
        replace(with: [])
    }

    private static func replace(with reminders: [Reminder]) {
        let previous = pending
        pending = Task {
            await previous?.value
            let center = UNUserNotificationCenter.current()
            // Every reminder set before: the dated ones, and the repeating ones of earlier versions.
            let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(identifier) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for reminder in reminders {
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Today's revision")
                content.body = reminder.withPortion
                    ? String(localized: "Your new portion and your pages for today are waiting for you.")
                    : String(localized: "Your pages for today are waiting for you.")
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireAt)
                try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
    }
}

/// A reminder an hour before each tasmee' session booked, kept in step with the bookings. Nothing is asked: the
/// reminders are only set when notifications are already allowed (by the daily reminder).
@MainActor
enum SessionReminders {
    private static let prefix = "session-"

    static func schedule(_ bookings: [Booking]) {
        let center = UNUserNotificationCenter.current()
        Task {
            let settings = await center.notificationSettings()
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
            for booking in bookings {
                let at = booking.startsAt.addingTimeInterval(-3_600)
                guard at > .now else { continue }
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Your tasmee' in an hour")
                content.body = booking.kind == .video
                    ? String(localized: "With \(booking.teacherName), by video.")
                    : String(localized: "With \(booking.teacherName), at \(booking.place).")
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
                try? await center.add(UNNotificationRequest(identifier: prefix + booking.id, content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
    }
}

/// The sources Aqra is built on, credited as their terms ask (see shared/quran/README.md).
struct SourcesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sources")
                        .aqraFont(size: 30, weight: .heavy)
                        .foregroundStyle(Palette.ink)
                    Text("Aqra shows the Quran exactly as published, from these sources, with thanks.")
                        .aqraFont(size: 14, weight: .medium)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                source(icon: "📜", tint: Palette.butter, name: Text("King Fahd Glorious Quran Printing Complex"),
                       detail: Text("The Quran text and its data, in the riwayah of Hafs."))
                source(icon: "🖋️", tint: Palette.lavender, name: Text(verbatim: "Quran Foundation"),
                       detail: Text("The Complex's Mushaf page fonts of the 1441H print, with tajweed colors."))
                source(icon: "🧩", tint: Palette.sky, name: Text(verbatim: "Quranic Universal Library (QUL)"),
                       detail: Text("The Mushaf page layout and the surah headers."))
                source(icon: "🏷️", tint: Palette.mint, name: Text(verbatim: "Ayah by Ayah"),
                       detail: Text("The topic sections, for now."))
                source(icon: "✒️", tint: Palette.rose, name: Text(verbatim: "Amiri"),
                       detail: Text("The typeface of the hadith, under the SIL Open Font License."))
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Palette.surface.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
    }

    private func source(icon: String, tint: Color, name: Text, detail: Text) -> some View {
        AqraCard(padding: 14, radius: 24) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(icon: icon, tint: tint, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    name
                        .aqraFont(size: 16, weight: .heavy)
                        .foregroundStyle(Palette.ink)
                    detail
                        .aqraFont(size: 12, weight: .semibold)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private typealias Palette = OnboardingPalette
