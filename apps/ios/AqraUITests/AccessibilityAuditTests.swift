import XCTest

/// Xcode's accessibility audit on the app's own screens, reached the way a new student reaches them: the four
/// onboarding pages, «ماذا تحفظ؟», the daily amount, the plan, the four tabs and today's revision.
///
/// Runs against the local Firebase emulators only (`-UseFirebaseEmulator`, see backend/README.md), in English and in
/// Arabic. `AQRA_UI_SHOTS` (passed as `TEST_RUNNER_AQRA_UI_SHOTS`) names a folder for a screenshot of each screen,
/// and `AQRA_AUDIT_LOG` one for every issue the audit reports, ignored ones included.
///
///     xcodebuild test -project Aqra.xcodeproj -scheme AqraUITests -destination "platform=iOS Simulator,id=<UDID>"
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    nonisolated override func setUp() {
        continueAfterFailure = true
    }

    func test1EnglishJourney() throws {
        try journey(language: "en", locale: "en_US")
    }

    func test2ArabicJourney() throws {
        try journey(language: "ar", locale: "ar_SA")
    }

    // MARK: - The journey

    private func journey(language: String, locale: String) throws {
        let app = XCUIApplication()
        // Onboarding and the setup again, whatever an earlier run left: the app clears its settings, its progress and
        // its account first. (Passing the settings themselves as arguments would pin them, and onboarding could never
        // finish.)
        app.launchArguments = ["-UseFirebaseEmulator", "-ResetForUITest", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        let words = Words(language: language)

        // Onboarding: welcome, the منازل, what Aqra offers, and the start.
        try audit(app, "\(language)-onboarding-1-welcome", waitFor: words.begin)
        tap(words.begin, in: app)
        try audit(app, "\(language)-onboarding-2-manazil", waitFor: words.continue)
        tap(words.continue, in: app)
        try audit(app, "\(language)-onboarding-3-features", waitFor: words.continue)
        tap(words.continue, in: app)
        try audit(app, "\(language)-onboarding-4-start", waitFor: words.begin)
        tap(words.begin, in: app)

        // «ماذا تحفظ؟»: juz' 30 memorized, so the wird has pages. The grid only holds the tiles in sight, so it's
        // scrolled until juz' 30 is there; «متابعة» shows once something is chosen.
        let juz30 = app.buttons[words.juz30].firstMatch
        var swipes = 0
        while !(juz30.exists && juz30.isHittable) && swipes < 10 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(juz30.exists, "no \(words.juz30)")
        if (juz30.value as? String)?.contains("100") != true && (juz30.value as? String)?.contains("١٠٠") != true {
            juz30.tap()
        }
        try audit(app, "\(language)-setup-memorized", waitFor: words.continue)
        tap(words.continue, in: app)

        // How firm each juz' is, and where the revision continues from.
        try audit(app, "\(language)-setup-firmness", waitFor: words.firm)
        tap(words.continue, in: app)

        // The daily amount, with «رجوع».
        try audit(app, "\(language)-setup-daily-amount", waitFor: words.begin)
        XCTAssertTrue(app.buttons[words.back].exists, "the daily amount has no \(words.back) button")
        tap(words.begin, in: app)

        // The plan, left for later.
        try audit(app, "\(language)-setup-plan", waitFor: words.notNow)
        tap(words.notNow, in: app)

        // The tabs.
        try audit(app, "\(language)-home", waitFor: words.messages)
        try scrollAndAudit(app, "\(language)-home")
        tap(words.tasmee, in: app)
        try audit(app, "\(language)-tasmee", waitFor: words.tasmee)
        try scrollAndAudit(app, "\(language)-tasmee")
        tap(words.progress, in: app)
        try audit(app, "\(language)-progress", waitFor: words.progress)
        try scrollAndAudit(app, "\(language)-progress")
        tap(words.account, in: app)
        try audit(app, "\(language)-account", waitFor: words.account)
        for title in words.switches {
            XCTAssertTrue(app.switches[title].exists, "no switch named «\(title)»")
        }
        try scrollAndAudit(app, "\(language)-account")

        // Today's revision, with the X named for what it does.
        tap(words.home, in: app)
        let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", words.startRevision)).firstMatch
        if start.waitForExistence(timeout: 10) {
            start.scrollIntoView(in: app)
            start.tap()
            try audit(app, "\(language)-wird", waitFor: words.leaveRevision)
            XCTAssertTrue(app.buttons[words.leaveRevision].exists, "the revision's X isn't «\(words.leaveRevision)»")
        } else {
            XCTFail("no «\(words.startRevision)» on the home")
        }
    }

    // MARK: - Auditing

    /// Audits the screen once it has settled, after a screenshot of it.
    private func audit(_ app: XCUIApplication, _ name: String, waitFor label: String) throws {
        let anchor = app.descendants(matching: .any)[label].firstMatch
        XCTAssertTrue(anchor.waitForExistence(timeout: 30), "\(name): no «\(label)»")
        // Entrances and springs finish within a second and a half.
        Thread.sleep(forTimeInterval: 2)
        shot(app, name)
        try runAudit(app, name)
    }

    /// Scrolls the screen's scroll view to the bottom, auditing what comes into view.
    private func scrollAndAudit(_ app: XCUIApplication, _ name: String) throws {
        let scroll = app.scrollViews.firstMatch
        guard scroll.exists else { return }
        for step in 1...3 {
            scroll.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            shot(app, "\(name)-scrolled-\(step)")
            try runAudit(app, "\(name)-scrolled-\(step)")
        }
        // Back to the top, where the tab bar, minimized by scrolling down, is whole again.
        for _ in 1...5 { scroll.swipeDown() }
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// What fails the test: tap targets, names and traits, the things this audit was written to keep fixed.
    /// Contrast, clipped text and Dynamic Type are audited and logged, not enforced: the composed screens keep a fixed
    /// type scale by design (docs/SRS.md ATT-08), and the audit reads the brand button's gradient and the headlines
    /// scaled to fit one line as failures.
    private static let enforced: XCUIAccessibilityAuditType = [.hitRegion, .sufficientElementDescription, .elementDetection, .trait]

    private func runAudit(_ app: XCUIApplication, _ name: String) throws {
        var log: [String] = []
        try app.performAccessibilityAudit(for: .all) { issue in
            let ignored = Self.ignores(issue)
            let enforced = Self.enforced.contains(issue.auditType)
            let element = issue.element.map { "\($0.elementType.rawValue) «\($0.label)» \($0.frame)" } ?? "-"
            let verdict = ignored ? "IGNORED" : enforced ? "ISSUE" : "LOGGED"
            log.append("\(verdict)\t\(issue.auditType.rawValue)\t\(issue.compactDescription)\t\(element)")
            return ignored || !enforced
        }
        writeLog(log, name)
    }

    /// Issues that aren't the app's to fix: the system's own chrome, and the Mushaf's page, which is drawn glyph by
    /// glyph from the Complex's fonts and read to VoiceOver from the official text instead.
    private static func ignores(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let element = issue.element else { return false }
        // The status bar and the system tab bar belong to iOS.
        if element.elementType == .statusBar || element.identifier.hasPrefix("UIStatusBar") { return true }
        // The account's uid, shown only against the emulators for a tester to copy.
        if element.label.hasPrefix("Emulator · ") { return true }
        return false
    }

    // MARK: - Files

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .deleteOnSuccess
        add(attachment)
        guard let folder = ProcessInfo.processInfo.environment["AQRA_UI_SHOTS"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
    }

    private func writeLog(_ lines: [String], _ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["AQRA_AUDIT_LOG"] else { return }
        let text = lines.isEmpty ? "clean\n" : lines.joined(separator: "\n") + "\n"
        try? text.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
    }

    // MARK: - Driving

    /// Taps the first button with this label that can be tapped, waiting out an entrance.
    private func tap(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 30) {
        let start = Date(), deadline = start.addingTimeInterval(timeout)
        var nudged = false
        while Date() < deadline {
            let matches = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
            if let button = matches.first(where: { $0.exists && $0.isHittable }) {
                button.tap()
                return
            }
            // A tab bar minimized by scrolling comes back when the screen scrolls up.
            if !nudged, Date().timeIntervalSince(start) > 5 {
                app.swipeDown()
                nudged = true
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTFail("no tappable «\(label)»\n\(app.debugDescription.prefix(3000))")
    }
}

/// The labels the journey looks for, in the language it runs in (the app's own catalog wording).
private struct Words {
    var begin, `continue`, juz30, firm, back, notNow, messages, home, tasmee, progress, account, startRevision, leaveRevision: String
    var switches: [String]

    init(language: String) {
        if language == "ar" {
            begin = "ابدأ"; `continue` = "متابعة"; juz30 = "الجزء ٣٠"; firm = "متين"; back = "رجوع"; notNow = "ليس الآن"
            messages = "الرسائل"; home = "الرئيسية"; tasmee = "التسميع"; progress = "تقدّمي"; account = "حسابي"
            startRevision = "راجع وِرد اليوم"; leaveRevision = "الخروج دون تسجيل مراجعة هذه الصفحة"
            switches = ["ألوان التجويد", "ألوان المواضيع", "التذكير اليومي", "الأصوات"]
        } else {
            begin = "Begin"; `continue` = "Continue"; juz30 = "Juz' 30"; firm = "Firm"; back = "Back"; notNow = "Not now"
            messages = "Messages"; home = "Home"; tasmee = "Tasmee'"; progress = "Progress"; account = "Account"
            startRevision = "Revise today's wird"; leaveRevision = "Leave without recording this page"
            switches = ["Tajweed colors", "Topic colors", "Daily reminder", "Sounds"]
        }
    }
}

private extension XCUIElement {
    /// Swipes the screen until the element can be tapped.
    func scrollIntoView(in app: XCUIApplication) {
        var tries = 0
        while !isHittable && tries < 8 {
            app.swipeUp()
            tries += 1
        }
    }
}
