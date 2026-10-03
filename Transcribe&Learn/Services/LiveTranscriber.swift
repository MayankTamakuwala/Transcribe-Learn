import AVFoundation
import Foundation
import Speech
import UIKit

/// Records from the microphone and transcribes speech live, entirely on-device,
/// using `SpeechAnalyzer` with a `SpeechTranscriber` module.
///
/// Recording keeps running while the app is in the background (the target has the
/// "audio" background mode) and automatically resumes after system interruptions
/// such as phone calls or Siri. It only ends when `stop()` is called.
@Observable
final class LiveTranscriber {
    enum State: Equatable {
        case idle
        case preparing
        case recording
        case finishing
    }

    enum TranscriberError: LocalizedError {
        case microphoneDenied
        case noMicrophoneInput
        case unsupportedLanguage

        var errorDescription: String? {
            switch self {
            case .microphoneDenied: "Microphone access is off. Turn it on in Settings to record lectures."
            case .noMicrophoneInput: "No microphone input is available right now."
            case .unsupportedLanguage: "On-device transcription doesn't support your current language yet."
            }
        }
    }

    private(set) var state: State = .idle
    /// True while the system has paused the microphone, for example during a phone call.
    private(set) var isInterrupted = false
    /// Text the transcriber has committed to; it won't change.
    private(set) var finalizedText = ""
    /// Tentative text for the most recent audio; it's replaced as the transcriber refines it.
    private(set) var volatileText = ""
    private(set) var startDate: Date?
    var errorMessage: String?

    var fullText: String { Self.join(finalizedText, volatileText) }

    var elapsed: TimeInterval {
        startDate.map { Date.now.timeIntervalSince($0) } ?? 0
    }

    private var analyzer: SpeechAnalyzer?
    private var converter: AnalyzerInputConverter?
    private var engine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var observerTasks: [Task<Void, Never>] = []

    func start() async {
        guard state == .idle else { return }
        state = .preparing
        errorMessage = nil
        isInterrupted = false
        finalizedText = ""
        volatileText = ""

        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw TranscriberError.microphoneDenied }
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
                throw TranscriberError.unsupportedLanguage
            }

            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

            // Download the on-device speech model for this language if needed.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }

            let converter = try await AnalyzerInputConverter.converter(compatibleWith: [transcriber])
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (inputStream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)

            self.converter = converter
            self.analyzer = analyzer
            self.inputContinuation = continuation

            resultsTask = Task {
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        if result.isFinal {
                            finalizedText = Self.join(finalizedText, text)
                            volatileText = ""
                        } else {
                            volatileText = text
                        }
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }

            analysisTask = Task {
                do {
                    if let lastSampleTime = try await analyzer.analyzeSequence(inputStream) {
                        try await analyzer.finalizeAndFinish(through: lastSampleTime)
                    } else {
                        await analyzer.cancelAndFinishNow()
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }

            try activateAudioSession()
            try startEngine()
            observeSystemEvents()

            startDate = .now
            state = .recording
            // Keep the screen awake while the app is in front.
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            errorMessage = error.localizedDescription
            await tearDown()
        }
    }

    /// Stops recording, waits for the final transcription, and returns the full transcript.
    @discardableResult
    func stop() async -> String {
        guard state == .recording else { return fullText }
        state = .finishing

        stopEngine()
        // Push any audio the converter is still holding, then end the input.
        if let converter, let remaining = try? converter.flush() {
            for input in remaining {
                inputContinuation?.yield(input)
            }
        }
        inputContinuation?.finish()

        // Let the analyzer finalize the remaining audio and deliver the last results.
        await analysisTask?.value
        await resultsTask?.value

        finalizedText = fullText
        volatileText = ""
        await tearDown()
        return finalizedText
    }

    // MARK: - Audio

    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
    }

    /// Creates a fresh engine each time so it picks up the current input route and format.
    private func startEngine() throws {
        guard let converter, let inputContinuation else { return }
        let engine = AVAudioEngine()
        try Self.installTap(on: engine.inputNode, converter: converter, continuation: inputContinuation)
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    private func stopEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    /// Restarts the microphone after an interruption or a route change, if we're still recording.
    private func restartEngine() {
        guard state == .recording else { return }
        stopEngine()
        do {
            try activateAudioSession()
            try startEngine()
            isInterrupted = false
        } catch {
            // Usually means another app still holds the mic; we retry when the app becomes active.
            isInterrupted = true
        }
    }

    /// The tap runs on a real-time audio thread, so it's built outside the main actor.
    private nonisolated static func installTap(
        on node: AVAudioInputNode,
        converter: AnalyzerInputConverter,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw TranscriberError.noMicrophoneInput }

        nonisolated(unsafe) let converter = converter
        // `installAudioTap` requires a buffer size between 100 and 400 ms of audio.
        let bufferSize = AVAudioFrameCount(format.sampleRate * 0.1)
        try node.installAudioTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
            // `AnalyzerInputConverter` only accepts `AVAudioBuffer`, so copy the read-only samples into one.
            guard let pcmBuffer = makePCMBuffer(copying: buffer),
                  let inputs = try? converter.convert(pcmBuffer, at: nil) else { return }
            for input in inputs {
                continuation.yield(input)
            }
        }
    }

    /// Copies a read-only tap buffer into a new `AVAudioPCMBuffer` the converter can retain.
    private nonisolated static func makePCMBuffer(copying source: AVReadOnlyAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let frameLength = AVAudioFrameCount(source.frameLength)
        guard let destination = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: frameLength) else { return nil }
        destination.frameLength = frameLength

        source.withUnsafeAudioBufferList { sourceList in
            let sourceBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: sourceList))
            let destinationBuffers = UnsafeMutableAudioBufferListPointer(destination.mutableAudioBufferList)
            for (src, dst) in zip(sourceBuffers, destinationBuffers) {
                guard let srcData = src.mData, let dstData = dst.mData else { continue }
                memcpy(dstData, srcData, Int(min(src.mDataByteSize, dst.mDataByteSize)))
            }
        }
        return destination
    }

    // MARK: - System events

    private func observeSystemEvents() {
        let center = NotificationCenter.default

        // Phone calls, Siri, alarms, and other apps can take the microphone temporarily.
        observerTasks.append(Task { [weak self] in
            for await _ in center.notifications(named: AVAudioSession.didBecomeInactiveNotification) {
                guard self?.state == .recording else { continue }
                self?.isInterrupted = true
                self?.stopEngine()
            }
        })

        // Resume as soon as the system allows it, whatever it recommends: only Stop should end a recording.
        observerTasks.append(Task { [weak self] in
            for await _ in center.notifications(named: AVAudioSession.resumptionRecommendationNotification) {
                guard self?.isInterrupted == true else { continue }
                self?.restartEngine()
            }
        })

        // Plugging in headphones or connecting a Bluetooth mic changes the input format.
        observerTasks.append(Task { [weak self] in
            for await _ in center.notifications(named: .AVAudioEngineConfigurationChange) {
                guard self?.isInterrupted == false else { continue }
                self?.restartEngine()
            }
        })

        // If the mic couldn't be recovered earlier, try again when the person returns to the app.
        observerTasks.append(Task { [weak self] in
            for await _ in center.notifications(named: UIApplication.didBecomeActiveNotification) {
                guard self?.isInterrupted == true else { continue }
                self?.restartEngine()
            }
        })
    }

    // MARK: - Cleanup

    private func tearDown() async {
        stopEngine()
        inputContinuation?.finish()
        analysisTask?.cancel()
        resultsTask?.cancel()
        observerTasks.forEach { $0.cancel() }
        observerTasks = []
        inputContinuation = nil
        analysisTask = nil
        resultsTask = nil
        analyzer = nil
        converter = nil
        isInterrupted = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        UIApplication.shared.isIdleTimerDisabled = false
        state = .idle
    }

    private static func join(_ lhs: String, _ rhs: String) -> String {
        guard !lhs.isEmpty, !rhs.isEmpty else { return lhs + rhs }
        if lhs.last?.isWhitespace == true || rhs.first?.isWhitespace == true {
            return lhs + rhs
        }
        return lhs + " " + rhs
    }
}
