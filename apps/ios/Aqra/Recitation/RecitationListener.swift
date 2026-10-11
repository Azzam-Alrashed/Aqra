@preconcurrency import AVFoundation
import Foundation
import os
import UIKit

/// Listens to the revision of a page and follows it: words are revealed as they're recited, stumbles are marked
/// with what kind they were, and a long pause inside an ayah brings the next word (the prompt, تلقين).
///
/// The microphone's audio is split into stretches at the reciter's pauses, by its loudness against the room's own
/// noise. A stretch still being recited is heard every second or so, to reveal its words as they come; once the
/// reciter pauses, it's heard whole and settled. A stretch that grows past the model's window is cut at its quietest
/// moment, so a long ayah is heard in two parts. Nothing is recorded or kept.
@MainActor @Observable
final class RecitationListener {
    enum Phase: Equatable {
        case preparing
        case listening
        case paused
        case failed(Failure)
    }

    enum Failure: Equatable {
        /// The microphone isn't allowed, or couldn't start.
        case microphone
        /// The model couldn't be loaded.
        case model
    }

    /// What the listener needs from outside: the microphone's permission, the model, and the audio. The app gives
    /// the real ones; the tests give fakes.
    struct Ports {
        var requestMicrophone: @MainActor () async -> Bool
        var hearing: any RecitationHearing
        var audio: @MainActor () -> any RecitationAudioSource

        static var live: Ports {
            Ports(requestMicrophone: { await AVAudioApplication.requestRecordPermission() },
                  hearing: RecitationTranscriber.shared,
                  audio: { RecitationAudio.source() })
        }
    }

    private(set) var phase = Phase.preparing
    /// How loud the voice is now, from 0 to 1, for the meter.
    private(set) var level = 0.0
    private(set) var session: RevisionSession

    private let store: MushafStore
    private let ports: Ports
    private var tracker: RecitationTracker
    // What the deinit, which runs off the main actor, turns off: the microphone (or the recording) while it's on,
    // the tick, the start still under way, and the audio session's notifications.
    @ObservationIgnored nonisolated(unsafe) private var source: (any RecitationAudioSource)?
    @ObservationIgnored nonisolated(unsafe) private var loop: Task<Void, Never>?
    /// Asking for the microphone and loading the model before the microphone goes on; cancelled by a pause or a stop
    /// in the meantime, so neither turns the microphone on afterwards.
    @ObservationIgnored nonisolated(unsafe) private var starting: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var observers: [any NSObjectProtocol] = []
    /// Whether this listener counts in `active`, so the deinit can take it off.
    @ObservationIgnored nonisolated(unsafe) private var countsAsActive = false
    /// Whether an interruption (a call, another app's audio) paused the listening, to carry on when it ends.
    private var pausedByInterruption = false

    // Splitting the audio at pauses.
    private static let rate = 16_000
    private static let frame = 480  // 30 ms
    private var leftover: [Float] = []
    private var noiseFloor: Float = -60
    private var voicedRun = 0
    private var silentRun = 0
    private var preroll: [Float] = []
    private var stretch: [Float]?
    /// How loud each frame of the current stretch was, in dB, to cut a long stretch at its quietest moment.
    private var levels: [Float] = []
    private var lastPartial = 0
    // Hearing stretches, one at a time: settled ones in order, a stretch still being recited when there's time.
    private var settling: [Stretch] = []
    private var busy = false
    private var generation = 0
    /** How long the model took to hear the last stretch. */
    private var lastHearing: TimeInterval = 0
    // Prompting after a pause: when the voice was last heard, and how long the pause before this stretch was.
    private var lastVoice = Date.now
    private var promptsInARow = 0
    private var pauseBefore: TimeInterval = 0

    /// A stretch to settle, with the pause before it, unless a prompt broke that pause.
    private struct Stretch {
        var samples: [Float]
        var pauseBefore: TimeInterval
    }

    /// Seconds of silence inside an ayah before the next word is shown, and between two ayat.
    static let promptInsideAyah: TimeInterval = 4
    static let promptBetweenAyat: TimeInterval = 7
    /// Seconds of recitation a stretch grows to before it's cut; the model's window is 30 s.
    static let longestStretch = 24
    /// The last seconds of a long stretch, searched for the quietest frame to cut at.
    static let splitWindow = 6

    /// How many listeners are getting ready or listening, app-wide: while one is, the model stays loaded through a
    /// memory warning.
    fileprivate(set) static var active = 0

    init(session: RevisionSession, store: MushafStore, ports: Ports = .live) {
        self.session = session
        self.store = store
        self.ports = ports
        tracker = RecitationTracker(page: store.page(session.page), ayahs: session.ayahs, store: store)
        observeAudioSession()
    }

    deinit {
        source?.stop()
        loop?.cancel()
        starting?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        if countsAsActive { Task { @MainActor in RecitationListener.active = max(0, RecitationListener.active - 1) } }
    }

    /// Asks for the microphone if needed, loads the model and starts listening. A pause, or the listener let go, in
    /// the meantime leaves the microphone off: the task holds the listener only between its waits.
    func start() {
        starting?.cancel()
        setPhase(.preparing)
        let ports = self.ports
        starting = Task { [weak self] in
            let allowed = await ports.requestMicrophone()
            guard !Task.isCancelled else { return }
            guard allowed else {
                guard let listener = self else { return }
                listener.starting = nil
                listener.setPhase(.failed(.microphone))
                return
            }
            // Nothing holds the listener while the model loads: let go of in the meantime, it never listens.
            let loaded: Bool
            do {
                try await ports.hearing.load()
                loaded = true
            } catch {
                loaded = false
            }
            guard !Task.isCancelled, let listener = self else { return }
            listener.starting = nil
            if loaded {
                listener.beginAudio()
            } else {
                listener.setPhase(.failed(.model))
            }
        }
    }

    func pause() {
        starting?.cancel()
        starting = nil
        pausedByInterruption = false
        guard phase == .listening || phase == .preparing else { return }
        stopAudio()
        setPhase(.paused)
    }

    /// Listens again after a pause: straight away, or after loading the model again if the app let it go while in
    /// the background.
    func resume() {
        guard source == nil, starting == nil else { return }
        if ports.hearing.isLoaded {
            beginAudio()
        } else {
            start()
        }
    }

    /// Follows another page's revision (the next of today's wird, or the same page again).
    func follow(_ session: RevisionSession) {
        self.session = session
        tracker = RecitationTracker(page: store.page(session.page), ayahs: session.ayahs, store: store)
        generation += 1
        settling.removeAll()
        stretch = nil
        partial = nil
        levels.removeAll()
        preroll.removeAll()
        leftover.removeAll()
        voicedRun = 0
        silentRun = 0
        lastVoice = .now
        promptsInARow = 0
        _ = source?.drain()
    }

    /// Turns the microphone on and follows what it hears.
    private func beginAudio() {
        guard source == nil else { return }
        let source = ports.audio()
        do {
            try source.start()
        } catch {
            setPhase(.failed(.microphone))
            return
        }
        self.source = source
        setPhase(.listening)
        lastVoice = .now
        promptsInARow = 0
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                self.tick()
            }
        }
    }

    /// Turns the microphone off; what was being recited is heard all the same.
    private func stopAudio() {
        source?.stop()
        source = nil
        loop?.cancel()
        loop = nil
        closeStretch()
        level = 0
    }

    private func setPhase(_ next: Phase) {
        phase = next
        let isActive = next == .listening || next == .preparing
        guard isActive != countsAsActive else { return }
        countsAsActive = isActive
        Self.active = max(0, Self.active + (isActive ? 1 : -1))
    }

    // MARK: - Interruptions and route changes

    private func observeAudioSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated { self?.audioSessionInterrupted(began: type == .began, shouldResume: options.contains(.shouldResume)) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            MainActor.assumeIsolated { self?.audioRouteChanged(reason) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        })
    }

    /// A phone call or another app's audio: listening pauses, without a stumble for the silence, and carries on
    /// when the interruption ends if the system says it may.
    func audioSessionInterrupted(began: Bool, shouldResume: Bool) {
        if began {
            guard phase == .listening || phase == .preparing else { return }
            pause()
            pausedByInterruption = true
        } else {
            guard pausedByInterruption else { return }
            pausedByInterruption = false
            if shouldResume { resume() }
        }
    }

    /// Headphones or AirPods put on or taken off mid-page: the microphone's route changed under the audio engine,
    /// so listening pauses rather than carry on deaf, and the student resumes it.
    func audioRouteChanged(_ reason: AVAudioSession.RouteChangeReason) {
        guard phase == .listening else { return }
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable: pause()
        default: break
        }
    }

    // MARK: - Every tenth of a second

    private func tick() {
        guard let source else { return }
        let samples = source.drain()
        if session.isComplete {
            level = 0
            return
        }
        catchUpWithTheSession()
        leftover.append(contentsOf: samples)
        var start = 0
        while leftover.count - start >= Self.frame {
            frame(Array(leftover[start..<start + Self.frame]))
            start += Self.frame
        }
        leftover.removeFirst(start)
        promptIfStuck()
        hearNext()
    }

    /// The student revealed words by hand («الآية التالية», «أظهر الصفحة»): carry on from there. Words the
    /// tracker revealed itself, from a stretch still being recited, aren't counted: that stretch is settled when
    /// the reciter pauses.
    private func catchUpWithTheSession() {
        var index = tracker.reached
        while index < tracker.words.count,
              !session.isVeiled(tracker.words[index].ayah, position: tracker.words[index].position) {
            index += 1
        }
        if index > tracker.reached { tracker.skip(to: index) }
    }

    /// One 30 ms frame: is it voice, against the room's noise, and does a stretch begin or end?
    private func frame(_ samples: [Float]) {
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        let decibels = 20 * log10(sqrt(sum / Float(samples.count)) + 1e-9)
        // The noise floor follows the quietest moments down at once and rises back slowly, about 1 dB a second.
        noiseFloor = decibels < noiseFloor ? max(decibels, -90) : noiseFloor + 0.03
        let voiced = decibels > noiseFloor + 12 && decibels > -52
        if voiced {
            if voicedRun == 0, stretch == nil { pauseBefore = promptsInARow > 0 ? 0 : Date.now.timeIntervalSince(lastVoice) }
            lastVoice = .now
        }
        level = 0.7 * level + 0.3 * Double(min(max((decibels - noiseFloor) / 30, 0), 1))

        if var current = stretch {
            current.append(contentsOf: samples)
            stretch = current
            levels.append(decibels)
            silentRun = voiced ? 0 : silentRun + 1
            if silentRun >= 17 {
                // Half a second of quiet ends a stretch.
                closeStretch()
            } else if current.count >= Self.rate * Self.longestStretch {
                // The model hears 30 s at most: a long ayah is cut at the quietest moment of its last seconds.
                splitStretch()
            } else if hearsWhileReciting, current.count - lastPartial >= Self.rate * 6 / 5, current.count >= Self.rate * 4 / 5 {
                lastPartial = current.count
                partial = current
            }
        } else {
            preroll.append(contentsOf: samples)
            if preroll.count > Self.frame * 8 { preroll.removeFirst(preroll.count - Self.frame * 8) }
            voicedRun = voiced ? voicedRun + 1 : 0
            if voicedRun >= 3 {
                stretch = preroll
                preroll.removeAll()
                silentRun = 0
                lastPartial = 0
                promptsInARow = 0
            }
        }
    }

    /// Whether a stretch is heard while it's still being recited, to reveal its words as they come. Where the model
    /// is slow, it isn't: hearing it would hold up settling the stretch, and the prompt after a pause.
    private var hearsWhileReciting: Bool { lastHearing < Self.slowHearing }

    /// A model that takes longer than this to hear a stretch only hears it once it's settled.
    private static let slowHearing: TimeInterval = 1.5

    private func closeStretch() {
        guard let current = stretch else { return }
        stretch = nil
        partial = nil
        levels.removeAll()
        voicedRun = 0
        settling.append(Stretch(samples: current, pauseBefore: pauseBefore))
        pauseBefore = 0
        hearNext()
    }

    /// Cuts the stretch being recited at the quietest frame of its last `splitWindow` seconds — a breath between
    /// words, so no word is cut in two — and settles what came before it. The rest carries on as the stretch being
    /// recited, so an ayah longer than the model's window is heard in two parts and followed across them.
    private func splitStretch() {
        guard let current = stretch else { return }
        let frames = levels.count
        var quietest = max(1, frames - Self.splitWindow * Self.rate / Self.frame)
        for frame in (quietest + 1)..<frames where levels[frame] < levels[quietest] { quietest = frame }
        // The stretch began with a preroll before its first frame.
        let cut = current.count - frames * Self.frame + quietest * Self.frame
        settling.append(Stretch(samples: Array(current[..<cut]), pauseBefore: pauseBefore))
        stretch = Array(current[cut...])
        levels.removeFirst(quietest)
        pauseBefore = 0
        lastPartial = max(0, lastPartial - cut)
        partial = nil
        hearNext()
    }

    /// The stretch still being recited, waiting to be heard if the model is free.
    private var partial: [Float]?

    private func hearNext() {
        guard !busy else { return }
        let final: Bool
        let samples: [Float]
        var pause: TimeInterval = 0
        if !settling.isEmpty {
            let next = settling.removeFirst()
            samples = next.samples
            pause = next.pauseBefore
            final = true
        } else if let partial {
            samples = partial
            self.partial = nil
            final = false
        } else {
            return
        }
        busy = true
        let generation = generation
        let hearing = ports.hearing
        Task { [weak self] in
            let started = Date.now
            let text = (try? await hearing.transcribe(samples)) ?? ""
            guard let self else { return }
            self.lastHearing = Date.now.timeIntervalSince(started)
            self.busy = false
            guard generation == self.generation else { return }
            #if DEBUG
            Self.log.debug("""
                \(final ? "settled" : "partial", privacy: .public) \(Double(samples.count) / 16_000, format: .fixed(precision: 1), privacy: .public) s \
                in \(Date.now.timeIntervalSince(started), format: .fixed(precision: 2), privacy: .public) s: \(text, privacy: .public)
                """)
            #endif
            // A long pause inside an ayah that no prompt answered (the model was still hearing what came before).
            if final, pause >= Self.promptInsideAyah { self.tracker.hesitated() }
            self.tracker.hear(text, final: final)
            self.apply()
            self.hearNext()
        }
    }

    /// A long pause inside an ayah, or a longer one between two, brings the next word — twice at most in a row,
    /// since a student who says nothing more may have stopped. The pause counts from the last sound of the voice,
    /// once what came before it is heard.
    private func promptIfStuck() {
        guard stretch == nil, settling.isEmpty, !busy, tracker.cursor > 0, !tracker.isComplete,
              promptsInARow < 2 else { return }
        let wait = tracker.isMidAyah ? Self.promptInsideAyah : Self.promptBetweenAyat
        guard Date.now.timeIntervalSince(lastVoice) >= wait else { return }
        tracker.prompt()
        promptsInARow += 1
        lastVoice = .now
        apply()
    }

    /// Shows the tracker's progress on the page.
    private func apply() {
        let words = tracker.words
        if tracker.reached > 0 {
            let last = words[tracker.reached - 1]
            let endsAyah = tracker.reached == words.count || words[tracker.reached].ayah != last.ayah
            session.reveal(through: .init(ayah: last.ayah, position: last.position), endsAyah: endsAyah)
        }
        if tracker.isComplete { session.revealAll() }
        for (ayah, kinds) in tracker.stumbles { session.markStumble(ayah, kinds: kinds) }
        for index in tracker.prompted {
            session.prompt(.init(ayah: words[index].ayah, position: words[index].position))
        }
    }
}

extension RecitationListener {
    nonisolated static let log = Logger(subsystem: "com.azzamalrashed.aqra", category: "Recitation")
}

/// The model as the listener uses it: loaded, asked what a stretch says, and let go of.
protocol RecitationHearing: Sendable {
    /// Whether the model is in memory, ready to hear; checked without waiting on the model.
    var isLoaded: Bool { get }
    func load() async throws
    func transcribe(_ samples: [Float]) async throws -> String
    func unload() async
}

extension RecitationTranscriber: RecitationHearing {}

extension RecitationTranscriber {
    /// One for the app: the model is loaded once and kept while the app is in use.
    static let shared = RecitationTranscriber()

    /// Lets the model go when the app goes to the background, and on a memory warning unless a listener is in the
    /// middle of listening; it's loaded again when listening resumes.
    @MainActor static func unloadsWhenIdle() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Task { await shared.unload() }
        }
        center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard RecitationListener.active == 0 else { return }
                Task { await shared.unload() }
            }
        }
    }
}

// MARK: - Audio

/// Where the recitation's audio comes from: 16 kHz mono samples, taken as they come.
protocol RecitationAudioSource: AnyObject {
    func start() throws
    func stop()
    /// The samples since the last call.
    func drain() -> [Float]
}

enum RecitationAudio {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    /// The microphone — or, for testing, a recording played in real time (`-RecitationTestAudio <path>`).
    @MainActor static func source() -> any RecitationAudioSource {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "RecitationTestAudio") {
            return RecordingSource(url: URL(fileURLWithPath: path))
        }
        #endif
        return MicrophoneSource()
    }

    /// Converts a buffer to 16 kHz mono.
    static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> [Float] {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return [] }
        // The converter asks for input until it's told there's no more: the one buffer is given once.
        let given = Once()
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            guard given.first() else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
    }

    /// Answers yes the first time it's asked, then no: a flag the converter's input block can share.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var asked = false

        func first() -> Bool {
            lock.withLock {
                defer { asked = true }
                return !asked
            }
        }
    }
}

/// The microphone, through the audio engine.
private final class MicrophoneSource: RecitationAudioSource, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []

    func start() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try audioSession.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let converter = AVAudioConverter(from: format, to: RecitationAudio.format) else {
            throw CocoaError(.featureUnsupported)
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            let converted = RecitationAudio.convert(buffer, with: converter)
            self?.lock.withLock { self?.samples.append(contentsOf: converted) }
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func drain() -> [Float] {
        lock.withLock {
            defer { samples.removeAll(keepingCapacity: true) }
            return samples
        }
    }
}

#if DEBUG
/// A recording played as if it were being recited now: its samples come out as time passes.
private final class RecordingSource: RecitationAudioSource {
    private let url: URL
    private var samples: [Float] = []
    private var given = 0
    private var started = Date.now

    init(url: URL) {
        self.url = url
    }

    func start() throws {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              let converter = AVAudioConverter(from: file.processingFormat, to: RecitationAudio.format) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer)
        samples = RecitationAudio.convert(buffer, with: converter)
        started = .now
    }

    func stop() {}

    func drain() -> [Float] {
        let due = min(Int(Date.now.timeIntervalSince(started) * 16_000), samples.count)
        defer { given = max(given, due) }
        return due > given ? Array(samples[given..<due]) : []
    }
}
#endif
