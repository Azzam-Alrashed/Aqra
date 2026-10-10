import SwiftUI

/// How stages are named across the app.
enum StageFormat {
    /// «الأجزاء ٧–٩»
    static func juz(of stage: Int) -> Text {
        let juz = Curriculum.juz(ofStage: stage)
        return Text("Juz' \(juz.lowerBound)–\(juz.upperBound)")
    }

    static func requirement(_ requirement: StageStatus.Requirement, policy: StagePolicy) -> Text {
        switch requirement {
        case .memorized: Text("Memorize every ayah of it")
        case .mastered: Text("Master \(Int((policy.requiredMastered * 100).rounded()))% of it")
        case .test: Text("Pass its test in the app")
        case .sheikh: Text("Pass a teacher's test of it")
        }
    }
}

/// Two thin bars: how much of something is memorized, and how much of it is mastered.
struct ProgressBars: View {
    var memorized: Double
    var mastered: Double
    var tint: Color = OnboardingPalette.brand

    var body: some View {
        VStack(spacing: 4) {
            bar(memorized, color: tint.opacity(0.35))
            bar(mastered, color: tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Memorized \(memorized.formatted(.percent.precision(.fractionLength(0)))), mastered \(mastered.formatted(.percent.precision(.fractionLength(0))))"))
    }

    private func bar(_ value: Double, color: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(OnboardingPalette.lavender)
                Capsule().fill(color).frame(width: max(geometry.size.width * min(max(value, 0), 1), value > 0 ? 6 : 0))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Every stage

/// The ten stages, each with how much is memorized and mastered, and whether it's passed.
struct StagesSection: View {
    var store: MushafStore

    @Environment(MemorizationStore.self) private var memorization
    @Environment(AssessmentStore.self) private var assessments
    @State private var opened: StageRoute?

    var body: some View {
        AqraCard(padding: 0, radius: 24) {
            VStack(spacing: 0) {
                ForEach(1...Curriculum.stageCount, id: \.self) { stage in
                    if stage > 1 { AqraRowDivider() }
                    row(stage)
                }
            }
        }
        .sheet(item: $opened) { route in
            NavigationStack { StageDetailView(store: store, stage: route.stage) }
        }
    }

    private func row(_ stage: Int) -> some View {
        let status = assessments.status(of: stage, store: store, memorization: memorization)
        let face = ManazilStairs.face(forJuz: Curriculum.juz(ofStage: stage).lowerBound)
        return Button {
            opened = StageRoute(stage: stage)
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: stage.formatted())
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 38, height: 38)
                    .background(face.top, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        StageFormat.juz(of: stage)
                            .aqraFont(size: 14, weight: .heavy)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        if status.isPassed {
                            Text("Passed")
                                .aqraFont(size: 11, weight: .bold)
                                .foregroundStyle(Color(light: 0x1F7A4D, dark: 0x1F7A4D))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .frame(minHeight: 22)
                                .background(Palette.mint, in: Capsule())
                        }
                    }
                    ProgressBars(memorized: status.progress.memorizedShare, mastered: status.progress.masteredShare, tint: face.bottom)
                }
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct StageRoute: Identifiable, Hashable {
    var stage: Int
    var id: Int { stage }
}

// MARK: - A stage

/// One stage: its juz', how far it's come, what passing it asks and how far each is met, and its test.
struct StageDetailView: View {
    var store: MushafStore
    var stage: Int

    @Environment(MemorizationStore.self) private var memorization
    @Environment(AssessmentStore.self) private var assessments
    @Environment(\.dismiss) private var dismiss
    @State private var testing = false

    var body: some View {
        let status = assessments.status(of: stage, store: store, memorization: memorization)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stage \(stage)").foregroundStyle(Palette.ink)
                    StageFormat.juz(of: stage).foregroundStyle(Palette.brand)
                }
                .aqraFont(size: 28, weight: .heavy)
                .padding(.top, 8)

                if let passedAt = status.passedAt {
                    AqraCard(padding: 14, radius: 24) {
                        HStack(spacing: 12) {
                            IconTile(icon: "🏅", tint: Palette.butter, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Stage passed")
                                    .aqraFont(size: 16, weight: .heavy)
                                    .foregroundStyle(Palette.ink)
                                Text(verbatim: passedAt.formatted(date: .long, time: .omitted))
                                    .aqraFont(size: 12, weight: .semibold)
                                    .foregroundStyle(Palette.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                HStack(spacing: 10) {
                    stat(icon: "📖", tint: Palette.sky, value: status.progress.memorizedShare, label: Text("Memorized"))
                    stat(icon: "💪", tint: Palette.mint, value: status.progress.masteredShare, label: Text("Mastered"))
                    stat(icon: "🎓", tint: Palette.butter, value: status.progress.verifiedShare, label: Text("Verified"))
                }

                AqraSectionTitle(title: "To pass this stage").padding(.top, 6)
                AqraCard(padding: 0, radius: 24) {
                    VStack(spacing: 0) {
                        ForEach(Array(status.requirements.enumerated()), id: \.element) { index, requirement in
                            if index > 0 { AqraRowDivider() }
                            requirementRow(requirement, status: status)
                        }
                    }
                }
                Text("Mastered: revised clean until it stays with you for two months. A teacher records a stage test from a tasmee' in one of their sessions.")
                    .aqraFont(size: 12, weight: .medium)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)

                testButton(status)
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $testing) {
            StageTestView(store: store, stage: stage)
        }
    }

    private func requirementRow(_ requirement: StageStatus.Requirement, status: StageStatus) -> some View {
        let met = status.isMet(requirement)
        return HStack(spacing: 12) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .aqraFont(size: 22, weight: .semibold)
                .foregroundStyle(met ? Color(light: 0x2E9B63, dark: 0x2E9B63) : Palette.lavender)
            VStack(alignment: .leading, spacing: 2) {
                StageFormat.requirement(requirement, policy: status.policy)
                    .aqraFont(size: 15, weight: .bold)
                    .foregroundStyle(Palette.ink)
                Group {
                    switch requirement {
                    case .memorized:
                        Text("\(status.progress.memorized) of \(status.progress.total) ayat")
                    case .mastered:
                        Text("\(status.progress.mastered) of \(status.progress.total) ayat")
                    case .test:
                        if let score = status.bestScore {
                            Text("Best score \(score.formatted(.percent.precision(.fractionLength(0))))")
                        } else {
                            Text("Not taken yet")
                        }
                    case .sheikh:
                        Text(status.sheikhPassed ? "Passed" : "Book a tasmee' and ask for a stage test")
                    }
                }
                .aqraFont(size: 12, weight: .semibold)
                .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func testButton(_ status: StageStatus) -> some View {
        if status.canTakeTest() {
            BrandButton(status.testPassed ? "Take the test again" : "Take the stage test",
                        metrics: OnboardingButtonMetrics(height: 54, fontSize: 17, compact: false)) {
                testing = true
            }
        } else if let retestAt = status.retestAt {
            Text("You can take the test again \(retestAt.formatted(.relative(presentation: .named)))")
                .aqraFont(size: 13, weight: .semibold)
                .foregroundStyle(Palette.inkSoft)
                .frame(maxWidth: .infinity)
        } else {
            Text("The test opens once every ayah of the stage is memorized.")
                .aqraFont(size: 13, weight: .semibold)
                .foregroundStyle(Palette.inkSoft)
                .frame(maxWidth: .infinity)
        }
    }

    private func stat(icon: String, tint: Color, value: Double, label: Text) -> some View {
        AqraCard(padding: 12, radius: 20) {
            VStack(alignment: .leading, spacing: 8) {
                IconTile(icon: icon, tint: tint, size: 32)
                Text(verbatim: value.formatted(.percent.precision(.fractionLength(0))))
                    .aqraFont(size: 20, weight: .heavy, monospacedDigit: true)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                label
                    .aqraFont(size: 11, weight: .semibold)
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The stage's test

/// A stage's in-app test: questions on its memorized ayat, each answered at once with the right answer shown, and
/// the score at the end. Ayat are shown in the Complex's text and Hafs Smart font, exactly as published.
struct StageTestView: View {
    var store: MushafStore
    var stage: Int

    @Environment(MemorizationStore.self) private var memorization
    @Environment(AssessmentStore.self) private var assessments
    @Environment(\.dismiss) private var dismiss
    @State private var questions: [TestQuestion] = []
    @State private var index = 0
    @State private var chosen: Int?
    @State private var correct = 0
    @State private var finished = false
    @State private var confirmingLeave = false

    /// Once the first answer is given, the test counts: leaving records it, so it can't be restarted until the
    /// questions suit.
    private var hasStarted: Bool { !finished && (index > 0 || chosen != nil) }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    if hasStarted { confirmingLeave = true } else { dismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Palette.brand)
                        .frame(width: 38, height: 38)
                        .background(Palette.lavender, in: Circle())
                }
                .accessibilityLabel(Text("Close"))
                Spacer()
                if !questions.isEmpty && !finished {
                    Text("\(index + 1) of \(questions.count)")
                        .aqraFont(size: 14, weight: .bold, monospacedDigit: true)
                        .foregroundStyle(Palette.brand)
                }
            }
            .padding(.top, 12)

            if finished {
                result
            } else if questions.indices.contains(index) {
                question(questions[index])
            } else {
                Spacer()
                Text("There isn't enough memorized in this stage for a test yet.")
                    .aqraFont(size: 15, weight: .semibold)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .environment(\.colorScheme, .light)
        .sensoryFeedback(trigger: chosen) { _, chosen in
            guard let chosen, questions.indices.contains(index) else { return nil }
            return chosen == questions[index].answer ? .success : .error
        }
        .interactiveDismissDisabled(hasStarted)
        .alert("Leave the test?", isPresented: $confirmingLeave) {
            Button("Leave", role: .destructive) {
                // The questions not answered count as wrong.
                record()
                dismiss()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("It counts as taken: the questions you haven't answered count as wrong.")
        }
        .onAppear {
            guard questions.isEmpty else { return }
            var generator = SystemRandomNumberGenerator()
            questions = TestQuestion.test(stage: stage, count: assessments.policy.testQuestions, store: store,
                                          memorization: memorization, using: &generator)
        }
    }

    private func question(_ question: TestQuestion) -> some View {
        VStack(spacing: 14) {
            Text(question.kind == .nextAyah ? "Which ayah comes next?" : "Which surah is this ayah from?")
                .aqraFont(size: 20, weight: .heavy)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            ayahCard(question.ayah, emphasized: true)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(question.options, id: \.self) { option in
                        optionButton(option, in: question)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            if chosen != nil {
                BrandButton(index + 1 < questions.count ? "Next" : "See the result",
                            metrics: OnboardingButtonMetrics(height: 54, fontSize: 17, compact: false)) {
                    advance()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: chosen)
    }

    private func optionButton(_ option: Int, in question: TestQuestion) -> some View {
        let isAnswer = option == question.answer
        let state: OptionState = chosen == nil ? .open : isAnswer ? .right : chosen == option ? .wrong : .faded
        return Button {
            guard chosen == nil else { return }
            chosen = option
            if isAnswer { correct += 1 }
        } label: {
            Group {
                if question.kind == .nextAyah {
                    // Without their numbers: the right option would be the one numbered after the question's.
                    AyahText(text: store.ayahTexts[option], spoken: store.ayahPlainTexts[option], size: 21, showsNumber: false)
                } else {
                    Text(verbatim: store.surahNames[option] ?? "")
                        .aqraFont(size: 18, weight: .bold)
                }
            }
            .foregroundStyle(MushafStyle.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(state.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(state.border, lineWidth: 2))
            .opacity(state == .faded ? 0.5 : 1)
            .environment(\.layoutDirection, .rightToLeft)
        }
        .buttonStyle(AqraPressStyle())
    }

    private enum OptionState {
        case open, right, wrong, faded

        var fill: Color {
            switch self {
            case .right: Color(light: 0xD8F2E3, dark: 0xD8F2E3)
            case .wrong: Color(light: 0xFCDCE7, dark: 0xFCDCE7)
            default: .white
            }
        }

        var border: Color {
            switch self {
            case .right: Color(light: 0x2E9B63, dark: 0x2E9B63)
            case .wrong: Color(light: 0xD0505A, dark: 0xD0505A)
            default: OnboardingPalette.lavender
            }
        }
    }

    private func ayahCard(_ ayah: Int, emphasized: Bool) -> some View {
        AyahText(text: store.ayahTexts[ayah], spoken: store.ayahPlainTexts[ayah], size: emphasized ? 24 : 20)
            .foregroundStyle(MushafStyle.ink)
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(MushafStyle.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MushafStyle.gold.opacity(0.5), lineWidth: 1))
            .environment(\.layoutDirection, .rightToLeft)
    }

    private func advance() {
        if index + 1 < questions.count {
            index += 1
            chosen = nil
        } else {
            record()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { finished = true }
        }
    }

    private func record() {
        assessments.record(AssessmentStore.TestResult(stage: stage, date: .now, questions: questions.count, correct: correct))
        assessments.checkPasses(store: store, memorization: memorization)
    }

    private var result: some View {
        let score = Double(correct) / Double(max(questions.count, 1))
        let passed = score >= assessments.policy.testPassScore - 0.000_1
        return VStack(spacing: 14) {
            Spacer()
            Text(verbatim: passed ? "🏅" : "🌱").font(.system(size: 72))
            Text(verbatim: score.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 48, weight: .heavy).monospacedDigit())
                .foregroundStyle(Palette.brand)
            Text(passed ? "You passed the stage's test" : "Not passed yet")
                .aqraFont(size: 22, weight: .heavy)
                .foregroundStyle(Palette.ink)
            Text(passed ? "\(correct) of \(questions.count) right. May Allah bless you." : "\(correct) of \(questions.count) right. Revise the stage and try again tomorrow.")
                .aqraFont(size: 15, weight: .medium)
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
            Spacer()
            BrandButton("Done", metrics: OnboardingButtonMetrics(height: 54, fontSize: 17, compact: false)) { dismiss() }
        }
    }
}

private typealias Palette = OnboardingPalette
