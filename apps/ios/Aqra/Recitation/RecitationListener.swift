@preconcurrency import AVFoundation
import Foundation
import os

/// Listens to the revision of a page and follows it: words are revealed as they're recited, stumbles are marked
/// with what kind they were, and a long pause inside an ayah brings the next word (the prompt, تلقين).
///
/// The microphone's audio is split into stretches at the reciter's pauses, by its loudness against the room's own
/// noise. A stretch still being recited is heard every second or so, to reveal its words as they come; once the
/// reciter pauses, it's heard whole and settled. Nothing is recorded or kept.
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

    private(set) var phase = Phase.preparing
    /// How loud the voice is now, from 0 to 1, for the meter.
    private(set) var level = 0.0
    private(set) var session: RevisionSession

    private let store: MushafStore
    private var tracker: RecitationTracker
    private var source: (any RecitationAudioSource)?
    private var loop: Task<Void, Never>?

    // Splitting the audio at pauses.
    private static let rate = 16_000
    private static let frame = 480  // 30 ms
    private var leftover: [Float] = []
    private var noiseFloor: Float = -60
    private var voicedRun = 0
    private var silentRun = 0
    private var preroll: [Float] = []
    private var stretch: [Float]?
    private var lastPartial = 0
    // Hearing stretches, one at a time: settled ones in order, a stretch still being recited when there's time.
    private var settling: [[Float]] = []
    private var busy = false
    private var generation = 0
    // Prompting after a pause: when the voice was last heard.
    private var lastVoice = Date.now
    private var promptsInARow = 0

    /// Seconds of silence inside an ayah before the next word is shown, and between two ayat.
    static let promptInsideAyah: TimeInterval = 4
    static let promptBetweenAyat: TimeInterval = 7

    init(session: RevisionSession, store: MushafStore) {
        self.session = session
        self.store = store
        tracker = RecitationTracker(page: store.page(session.page), ayahs: session.ayahs, store: store)
    }

    /// Asks for the microphone if needed, loads the model and starts listening.
    func start() async {
        phase = .preparing
        guard await AVAudioApplication.requestRecordPermission() else {
            phase = .failed(.microphone)
            return
        }
        do {
            try await RecitationTranscriber.shared.load()
        } catch {
            phase = .failed(.model)
            return
        }
        resume()
    }

    func pause() {
        guard phase == .listening else { return }
        source?.stop()
        source = nil
        loop?.cancel()
        loop = nil
        // What was being recited is heard all the same.
        closeStretch()
        level = 0
        phase = .paused
    }

    func resume() {
        guard source == nil else { return }
        let source = RecitationAudio.source()
        do {
            try source.start()
        } catch {
            phase = .failed(.microphone)
            return
        }
        self.source = source
        phase = .listening
        lastVoice = .now
        promptsInARow = 0
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.tick()
            }
        }
    }

    /// Follows another page's revision (the next of today's wird, or the same page again).
    func follow(_ session: RevisionSession) {
        self.session = session
        tracker = RecitationTracker(page: store.page(session.page), ayahs: session.ayahs, store: store)
        generation += 1
        settling.removeAll()
        stretch = nil
        preroll.removeAll()
        leftover.removeAll()
        voicedRun = 0
        silentRun = 0
        lastVoice = .now
        promptsInARow = 0
        _ = source?.drain()
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
        if voiced { lastVoice = .now }
        level = 0.7 * level + 0.3 * Double(min(max((decibels - noiseFloor) / 30, 0), 1))

        if var current = stretch {
            current.append(contentsOf: samples)
            stretch = current
            silentRun = voiced ? 0 : silentRun + 1
            if silentRun >= 17 || current.count >= Self.rate * 24 {
                // Half a second of quiet ends a stretch, and the model hears 30 s at most.
                closeStretch()
            } else if current.count - lastPartial >= Self.rate * 6 / 5, current.count >= Self.rate * 4 / 5 {
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

    private func closeStretch() {
        guard let current = stretch else { return }
        stretch = nil
        partial = nil
        voicedRun = 0
        settling.append(current)
        hearNext()
    }

    /// The stretch still being recited, waiting to be heard if the model is free.
    private var partial: [Float]?

    private func hearNext() {
        guard !busy else { return }
        let final: Bool
        let samples: [Float]
        if !settling.isEmpty {
            samples = settling.removeFirst()
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
        Task { [weak self] in
            let started = Date.now
            let text = (try? await RecitationTranscriber.shared.transcribe(samples)) ?? ""
            guard let self else { return }
            self.busy = false
            guard generation == self.generation else { return }
            #if DEBUG
            Self.log.debug("""
                \(final ? "settled" : "partial", privacy: .public) \(Double(samples.count) / 16_000, format: .fixed(precision: 1), privacy: .public) s \
                in \(Date.now.timeIntervalSince(started), format: .fixed(precision: 2), privacy: .public) s: \(text, privacy: .public)
                """)
            #endif
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

extension RecitationTranscriber {
    /// One for the app: the model is loaded once and kept while the app runs.
    static let shared = RecitationTranscriber()
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
        var given = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if given {
                status.pointee = .noDataNow
                return nil
            }
            given = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
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
