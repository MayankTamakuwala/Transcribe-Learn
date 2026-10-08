import AVFoundation
import Foundation
import Speech
import UIKit

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
    private(set) var isInterrupted = false
    private(set) var segments: [TranscriptSegment] = []
    private(set) var volatileText = ""
    private(set) var startDate: Date?
    var errorMessage: String?

    var finalizedText: String { segments.map(\.text).joined(separator: " ") }
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

    private let voiceFeatures = VoiceFeatureStore()
    private var featureProcessor: VoiceFeatureProcessor?
    private var clusterer = SpeakerClusterer()

    func start() async {
        guard state == .idle else { return }
        state = .preparing
        errorMessage = nil
        isInterrupted = false
        segments = []
        volatileText = ""
        voiceFeatures.removeAll()
        featureProcessor = VoiceFeatureProcessor(store: voiceFeatures)
        clusterer = SpeakerClusterer()

        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw TranscriberError.microphoneDenied }
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
                throw TranscriberError.unsupportedLanguage
            }

            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

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
                            appendFinalized(text, start: result.range.start.seconds, end: result.range.end.seconds)
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

            try await activateAudioSession()
            try startEngine()
            observeSystemEvents()

            startDate = .now
            state = .recording
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            errorMessage = error.localizedDescription
            await tearDown()
        }
    }

    @discardableResult
    func stop() async -> [TranscriptSegment] {
        guard state == .recording else { return segments }
        state = .finishing

        stopEngine()
        if let converter, let remaining = try? converter.flush() {
            for input in remaining {
                inputContinuation?.yield(input)
            }
        }
        inputContinuation?.finish()

        await analysisTask?.value
        await resultsTask?.value

        if !volatileText.isEmpty {
            appendFinalized(volatileText, start: segments.last?.end ?? 0, end: elapsed)
            volatileText = ""
        }
        segments = SpeakerClusterer.refine(segments)
        await tearDown()
        return segments
    }

    private func appendFinalized(_ text: String, start: TimeInterval, end: TimeInterval) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let validRange = start.isFinite && end.isFinite && end > start
        let frames = validRange ? voiceFeatures.takeFrames(from: start, to: end) : []
        let voiceprint = Voiceprint.make(from: frames)
        let speaker = clusterer.assign(voiceprint)
        segments.append(TranscriptSegment(
            speaker: speaker,
            text: trimmed,
            start: validRange ? start : (segments.last?.end ?? 0),
            end: validRange ? end : (segments.last?.end ?? 0),
            voiceprint: voiceprint
        ))
    }

    private func activateAudioSession() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try await session.activate(options: [])
    }

    private func startEngine() throws {
        guard let converter, let inputContinuation, let featureProcessor else { return }
        let engine = AVAudioEngine()
        try Self.installTap(
            on: engine.inputNode,
            converter: converter,
            featureProcessor: featureProcessor,
            continuation: inputContinuation
        )
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    private func stopEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func restartEngine() async {
        guard state == .recording else { return }
        stopEngine()
        do {
            try await activateAudioSession()
            guard state == .recording else { return }
            try startEngine()
            isInterrupted = false
        } catch {
            isInterrupted = true
        }
    }

    private nonisolated static func installTap(
        on node: AVAudioInputNode,
        converter: AnalyzerInputConverter,
        featureProcessor: VoiceFeatureProcessor,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw TranscriberError.noMicrophoneInput }

        nonisolated(unsafe) let converter = converter
        nonisolated(unsafe) let featureProcessor = featureProcessor
        let bufferSize = AVAudioFrameCount(format.sampleRate * 0.1)
        try node.installAudioTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
            guard let pcmBuffer = makePCMBuffer(copying: buffer) else { return }
            featureProcessor.process(pcmBuffer)
            guard let inputs = try? converter.convert(pcmBuffer, at: nil) else { return }
            for input in inputs {
                continuation.yield(input)
            }
        }
    }

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

    private func observeSystemEvents() {
        let center = NotificationCenter.default

        observerTasks.append(Task { [weak self] in
            for await _ in center.notifications(named: AVAudioSession.didBecomeInactiveNotification) {
                guard self?.state == .recording else { continue }
                self?.isInterrupted = true
                self?.stopEngine()
            }
        })

        observerTasks.append(Task { [weak self] in
            for await _ in center.notifications(named: AVAudioSession.resumptionRecommendationNotification) {
                guard self?.isInterrupted == true else { continue }
                await self?.restartEngine()
            }
        })

        observerTasks.append(Task { [weak self] in
            for await _ in center.notifications(named: .AVAudioEngineConfigurationChange) {
                guard self?.isInterrupted == false else { continue }
                await self?.restartEngine()
            }
        })

        observerTasks.append(Task { [weak self] in
            for await _ in center.notifications(named: UIApplication.didBecomeActiveNotification) {
                guard self?.isInterrupted == true else { continue }
                await self?.restartEngine()
            }
        })
    }

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
        featureProcessor = nil
        voiceFeatures.removeAll()
        isInterrupted = false
        _ = try? await AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation)
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
