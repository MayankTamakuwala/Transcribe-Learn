import Foundation

nonisolated struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var speaker: Int
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    var voiceprint: [Float]?
}

nonisolated struct SpeakerTurn: Identifiable, Equatable {
    var speaker: Int
    var segments: [TranscriptSegment]

    var id: UUID { segments[0].id }
    var text: String { segments.map(\.text).joined(separator: " ") }
}

nonisolated enum TranscriptFormatting {
    static func turns(from segments: [TranscriptSegment]) -> [SpeakerTurn] {
        var turns: [SpeakerTurn] = []
        for segment in segments {
            if turns.last?.speaker == segment.speaker {
                turns[turns.count - 1].segments.append(segment)
            } else {
                turns.append(SpeakerTurn(speaker: segment.speaker, segments: [segment]))
            }
        }
        return turns
    }

    static func defaultName(for speaker: Int) -> String {
        "Person \(speaker)"
    }

    static func labeledText(_ segments: [TranscriptSegment], names: [Int: String]) -> String {
        turns(from: segments)
            .map { "\(names[$0.speaker] ?? defaultName(for: $0.speaker)): \($0.text)" }
            .joined(separator: "\n")
    }
}
