import SwiftUI
import UIKit
import UserNotifications

/// حسابي: where the progress lives, the Mushaf's colors, the daily reminder, the app's language, and the sources
/// Aqra is built on. What's memorized and the daily amount are edited from the home. Signing in comes with the
/// second wave.
struct AccountView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("mushaf.tajweed") private var tajweed = true
    @AppStorage("mushaf.topics") private var topicColors = true
    @AppStorage("reminder.on") private var reminderOn = false
    /// Minutes after midnight.
    @AppStorage("reminder.minutes") private var reminderMinutes = 5 * 60 + 30
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Account")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 16)
                        .accessibilityAddTraits(.isHeader)
                    deviceCard

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
                                        .font(.system(size: 15, weight: .bold))
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
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.inkSoft)
                            Button("Open Settings") { openSettings() }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Palette.brand)
                        }
                        .padding(.horizontal, 6)
                    }

                    AqraSectionTitle(title: "App").padding(.top, 10)
                    AqraCard(padding: 0, radius: 24) {
                        VStack(spacing: 0) {
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

                    Text("Version \(version)")
                        .font(.system(size: 12, weight: .semibold))
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
            .reservesTabBarSpace()
            .background(Palette.surface.ignoresSafeArea())
            .fadesUnderStatusBar()
            .toolbar(.hidden, for: .navigationBar)
        }
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .onChange(of: reminderOn) { updateReminder() }
        .onChange(of: reminderMinutes) { updateReminder() }
    }

    /// Progress lives on the device until accounts come; the onboarding's promise, repeated where it's kept.
    private var deviceCard: some View {
        AqraCard(padding: 14, radius: 24) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(icon: "📱", tint: Palette.sky, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("On this device")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    Text("Your progress is saved on your device, and you can link it to your account anytime.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
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
                DailyReminder.schedule(minutes: reminderMinutes)
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

/// The daily reminder of today's wird: one notification a day at the chosen time.
@MainActor
enum DailyReminder {
    private static let identifier = "daily-wird"

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

    static func schedule(minutes: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Today's revision")
        content.body = String(localized: "Your pages for today are waiting for you.")
        content.sound = .default
        var time = DateComponents()
        time.hour = minutes / 60
        time.minute = minutes % 60
        center.add(UNNotificationRequest(identifier: identifier, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: time, repeats: true)))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

/// The sources Aqra is built on, credited as their terms ask (see shared/quran/README.md).
struct SourcesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sources")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    Text("Aqra shows the Quran exactly as published, from these sources, with thanks.")
                        .font(.system(size: 14, weight: .medium))
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
        .reservesTabBarSpace()
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
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    detail
                        .font(.system(size: 12, weight: .semibold))
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
