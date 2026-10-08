import Accelerate
import AVFoundation
import Synchronization

nonisolated struct VoiceFrame: Sendable {
    var time: TimeInterval
    var mfcc: [Float]
    var pitch: Float?
    var energy: Float
}

nonisolated final class VoiceFeatureStore: Sendable {
    private let frames = Mutex<[VoiceFrame]>([])

    func append(_ newFrames: [VoiceFrame]) {
        frames.withLock { $0.append(contentsOf: newFrames) }
    }

    func takeFrames(from start: TimeInterval, to end: TimeInterval) -> [VoiceFrame] {
        frames.withLock { frames in
            let selected = frames.filter { $0.time >= start && $0.time < end }
            frames.removeAll { $0.time < start }
            return selected
        }
    }

    func removeAll() {
        frames.withLock { $0.removeAll() }
    }
}

nonisolated final class VoiceFeatureProcessor {
    static let windowSize = 1024
    private static let melBandCount = 24
    private static let coefficientCount = 12

    let store: VoiceFeatureStore

    private var elapsed: TimeInterval = 0
    private var pending: [Float] = []
    private var pendingStart: TimeInterval = 0

    private var sampleRate: Double = 0
    private var dft: vDSP.DiscreteFourierTransform<Float>?
    private var window: [Float] = []
    private var melFilters: [[Float]] = []
    private var dctMatrix: [[Float]] = []

    init(store: VoiceFeatureStore) {
        self.store = store
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        let rate = buffer.format.sampleRate
        let bufferStart = elapsed
        elapsed += Double(frameCount) / rate

        guard let channel = buffer.floatChannelData?[0], frameCount > 0 else { return }
        if rate != sampleRate {
            configure(sampleRate: rate)
        }
        if pending.isEmpty {
            pendingStart = bufferStart
        }
        pending.append(contentsOf: UnsafeBufferPointer(start: channel, count: frameCount))

        var frames: [VoiceFrame] = []
        let size = Self.windowSize
        while pending.count >= size {
            let samples = Array(pending[0..<size])
            pending.removeFirst(size)
            if let frame = analyze(samples, time: pendingStart) {
                frames.append(frame)
            }
            pendingStart += Double(size) / sampleRate
        }
        if !frames.isEmpty {
            store.append(frames)
        }
    }

    private func configure(sampleRate rate: Double) {
        sampleRate = rate
        pending.removeAll()
        let size = Self.windowSize
        dft = try? vDSP.DiscreteFourierTransform<Float>(
            previousDFT: nil,
            count: size,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        )
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        melFilters = Self.makeMelFilters(sampleRate: rate, fftSize: size, bandCount: Self.melBandCount)
        dctMatrix = Self.makeDCTMatrix(inputCount: Self.melBandCount, outputCount: Self.coefficientCount)
    }

    fileprivate func analyze(_ samples: [Float], time: TimeInterval) -> VoiceFrame? {
        guard let dft else { return nil }
        let energy = vDSP.rootMeanSquare(samples)
        guard energy > 0.002 else { return nil }

        let windowed = vDSP.multiply(samples, window)
        let zeros = [Float](repeating: 0, count: samples.count)
        let (real, imaginary) = dft.transform(real: windowed, imaginary: zeros)
        let half = samples.count / 2
        var power = [Float](repeating: 0, count: half)
        for bin in 0..<half {
            power[bin] = real[bin] * real[bin] + imaginary[bin] * imaginary[bin]
        }

        let logMel = melFilters.map { filter in log(vDSP.dot(filter, power) + 1e-6) }
        let mfcc = dctMatrix.map { row in vDSP.dot(row, logMel) }

        return VoiceFrame(time: time, mfcc: mfcc, pitch: estimatePitch(samples), energy: energy)
    }

    fileprivate func estimatePitch(_ samples: [Float]) -> Float? {
        let minLag = Int(sampleRate / 400)
        let maxLag = min(Int(sampleRate / 70), samples.count / 2)
        guard maxLag > minLag else { return nil }

        let padded = samples + [Float](repeating: 0, count: maxLag + 1)
        let correlation = vDSP.correlate(padded, withKernel: samples)
        guard correlation.count > maxLag, let zeroLag = correlation.first, zeroLag > 0 else { return nil }

        var bestLag = 0
        var bestValue: Float = 0
        for lag in minLag...maxLag {
            let value = correlation[lag] / zeroLag * Float(samples.count) / Float(samples.count - lag)
            if value > bestValue {
                bestValue = value
                bestLag = lag
            }
        }
        guard bestValue > 0.45, bestLag > 0 else { return nil }
        return Float(sampleRate) / Float(bestLag)
    }

    private static func makeMelFilters(sampleRate: Double, fftSize: Int, bandCount: Int) -> [[Float]] {
        func mel(_ hz: Double) -> Double { 2595 * log10(1 + hz / 700) }
        func hz(_ mel: Double) -> Double { 700 * (pow(10, mel / 2595) - 1) }

        let binCount = fftSize / 2
        let lowMel = mel(80)
        let highMel = mel(min(7_600, sampleRate / 2))
        let edges = (0...(bandCount + 1)).map { index in
            hz(lowMel + (highMel - lowMel) * Double(index) / Double(bandCount + 1)) * Double(fftSize) / sampleRate
        }

        return (0..<bandCount).map { band in
            let (left, center, right) = (edges[band], edges[band + 1], edges[band + 2])
            return (0..<binCount).map { bin in
                let position = Double(bin)
                if position <= left || position >= right { return 0 }
                return Float(position < center
                    ? (position - left) / (center - left)
                    : (right - position) / (right - center))
            }
        }
    }

    private static func makeDCTMatrix(inputCount: Int, outputCount: Int) -> [[Float]] {
        let scale = sqrt(2 / Double(inputCount))
        return (1...outputCount).map { coefficient in
            (0..<inputCount).map { index in
                Float(scale * cos(Double.pi * Double(coefficient) * (Double(index) + 0.5) / Double(inputCount)))
            }
        }
    }
}

nonisolated enum Voiceprint {
    static let pitchWeight: Float = 3

    static func make(from frames: [VoiceFrame]) -> [Float]? {
        guard frames.count >= 8 else { return nil }

        let energies = frames.map(\.energy).sorted()
        let cutoff = energies[energies.count / 3]
        let loud = frames.filter { $0.energy >= cutoff }

        let coefficientCount = loud[0].mfcc.count
        var mean = [Float](repeating: 0, count: coefficientCount)
        for frame in loud {
            vDSP.add(mean, frame.mfcc, result: &mean)
        }
        mean = vDSP.divide(mean, Float(loud.count))

        let pitches = loud.compactMap(\.pitch).sorted()
        let pitchFeature = pitches.count >= 3 ? log2(pitches[pitches.count / 2] / 150) * pitchWeight : 0
        return mean + [pitchFeature]
    }

    static func distance(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count else { return .infinity }
        return vDSP.distanceSquared(lhs, rhs).squareRoot()
    }
}
