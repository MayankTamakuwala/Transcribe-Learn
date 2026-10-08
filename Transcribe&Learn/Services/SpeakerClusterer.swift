import Foundation

nonisolated struct SpeakerClusterer {
    static let sameSpeakerDistance: Float = 7
    static let continuityBonus: Float = 0.5
    static let maxSpeakers = 8

    private var centroids: [Int: [Float]] = [:]
    private var counts: [Int: Int] = [:]
    private var lastSpeaker: Int?

    mutating func assign(_ voiceprint: [Float]?) -> Int {
        guard let voiceprint else {
            return lastSpeaker ?? startNewSpeaker(with: nil)
        }
        let distances = centroids.mapValues { Voiceprint.distance($0, voiceprint) }
        guard let (closest, closestDistance) = distances.min(by: { $0.value < $1.value }) else {
            return startNewSpeaker(with: voiceprint)
        }

        let speaker: Int
        if let lastSpeaker, let lastDistance = distances[lastSpeaker],
           lastDistance < Self.sameSpeakerDistance + Self.continuityBonus {
            speaker = lastSpeaker
        } else if closestDistance < Self.sameSpeakerDistance || centroids.count >= Self.maxSpeakers {
            speaker = closest
        } else {
            return startNewSpeaker(with: voiceprint)
        }

        learn(voiceprint, for: speaker)
        lastSpeaker = speaker
        return speaker
    }

    private mutating func startNewSpeaker(with voiceprint: [Float]?) -> Int {
        let speaker = (centroids.keys.max() ?? 0) + 1
        if let voiceprint {
            centroids[speaker] = voiceprint
            counts[speaker] = 1
        }
        lastSpeaker = speaker
        return speaker
    }

    private mutating func learn(_ voiceprint: [Float], for speaker: Int) {
        guard let centroid = centroids[speaker] else {
            centroids[speaker] = voiceprint
            counts[speaker] = 1
            return
        }
        let count = Float(min(counts[speaker, default: 1], 50))
        centroids[speaker] = zip(centroid, voiceprint).map { ($0 * count + $1) / (count + 1) }
        counts[speaker, default: 1] += 1
    }

    static func refine(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        let speakers = Set(segments.map(\.speaker))
        guard speakers.count > 1 else { return renumbered(segments) }

        var result = segments
        for _ in 0..<2 {
            let centroids = Self.centroids(of: result)
            for index in result.indices {
                guard let voiceprint = result[index].voiceprint else { continue }
                if let nearest = centroids.min(by: {
                    Voiceprint.distance($0.value, voiceprint) < Voiceprint.distance($1.value, voiceprint)
                })?.key {
                    result[index].speaker = nearest
                }
            }
        }

        result = mergeTinySpeakers(result)
        result = smoothBlips(result)
        return renumbered(result)
    }

    static func regroup(_ segments: [TranscriptSegment], speakerCount: Int) -> [TranscriptSegment] {
        let measured = segments.indices.filter { segments[$0].voiceprint != nil }
        guard speakerCount > 1, measured.count >= speakerCount else {
            return renumbered(segments.map { var segment = $0; segment.speaker = 1; return segment })
        }

        var centers: [[Float]] = [segments[measured[0]].voiceprint ?? []]
        while centers.count < speakerCount {
            let next = measured.max { lhs, rhs in
                nearestDistance(segments[lhs].voiceprint ?? [], centers) < nearestDistance(segments[rhs].voiceprint ?? [], centers)
            }
            guard let next, let voiceprint = segments[next].voiceprint else { break }
            centers.append(voiceprint)
        }

        var result = segments
        for _ in 0..<10 {
            for index in measured {
                guard let voiceprint = result[index].voiceprint else { continue }
                let nearest = centers.indices.min { Voiceprint.distance(centers[$0], voiceprint) < Voiceprint.distance(centers[$1], voiceprint) } ?? 0
                result[index].speaker = nearest + 1
            }
            for (offset, _) in centers.enumerated() {
                let members = measured.compactMap { result[$0].speaker == offset + 1 ? result[$0].voiceprint : nil }
                if let mean = mean(of: members) {
                    centers[offset] = mean
                }
            }
        }

        var previous = 1
        for index in result.indices {
            if result[index].voiceprint == nil {
                result[index].speaker = previous
            }
            previous = result[index].speaker
        }
        return renumbered(smoothBlips(result))
    }

    private static func centroids(of segments: [TranscriptSegment]) -> [Int: [Float]] {
        Dictionary(grouping: segments.filter { $0.voiceprint != nil }, by: \.speaker)
            .compactMapValues { mean(of: $0.compactMap(\.voiceprint)) }
    }

    private static func mean(of vectors: [[Float]]) -> [Float]? {
        guard let first = vectors.first else { return nil }
        var sum = [Float](repeating: 0, count: first.count)
        for vector in vectors where vector.count == sum.count {
            for index in sum.indices { sum[index] += vector[index] }
        }
        return sum.map { $0 / Float(vectors.count) }
    }

    private static func nearestDistance(_ voiceprint: [Float], _ centers: [[Float]]) -> Float {
        centers.map { Voiceprint.distance($0, voiceprint) }.min() ?? .infinity
    }

    private static func mergeTinySpeakers(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        let durations = Dictionary(grouping: segments, by: \.speaker)
            .mapValues { $0.reduce(0) { $0 + ($1.end - $1.start) } }
        let tiny = Set(durations.filter { $0.value < 2 }.keys)
        guard !tiny.isEmpty, tiny.count < durations.count else { return segments }

        let centroids = centroids(of: segments).filter { !tiny.contains($0.key) }
        guard let fallback = durations.filter({ !tiny.contains($0.key) }).max(by: { $0.value < $1.value })?.key else {
            return segments
        }

        return segments.map { segment in
            guard tiny.contains(segment.speaker) else { return segment }
            var segment = segment
            if let voiceprint = segment.voiceprint,
               let nearest = centroids.min(by: { Voiceprint.distance($0.value, voiceprint) < Voiceprint.distance($1.value, voiceprint) })?.key {
                segment.speaker = nearest
            } else {
                segment.speaker = fallback
            }
            return segment
        }
    }

    private static func smoothBlips(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        guard segments.count >= 3 else { return segments }
        var result = segments
        for index in 1..<(result.count - 1) {
            let before = result[index - 1].speaker
            let after = result[index + 1].speaker
            let segment = result[index]
            if before == after, segment.speaker != before, segment.end - segment.start < 1.5 {
                result[index].speaker = before
            }
        }
        return result
    }

    static func renumbered(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        var mapping: [Int: Int] = [:]
        return segments.map { segment in
            var segment = segment
            if mapping[segment.speaker] == nil {
                mapping[segment.speaker] = mapping.count + 1
            }
            segment.speaker = mapping[segment.speaker] ?? 1
            return segment
        }
    }
}
