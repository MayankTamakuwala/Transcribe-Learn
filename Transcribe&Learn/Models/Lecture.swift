import Foundation
import SwiftData

@Model
final class Lecture {
    var title: String
    var titleIsAutomatic: Bool
    var createdAt: Date
    var duration: TimeInterval
    var transcript: String
    var summaryData: Data?
    var studyGuideData: Data?
    var segmentsData: Data? = nil
    var speakerNamesData: Data? = nil

    @Relationship(deleteRule: .cascade, inverse: \LecturePhoto.lecture)
    var photos: [LecturePhoto] = []

    init(createdAt: Date = .now, duration: TimeInterval = 0, transcript: String = "") {
        self.title = "Lecture – \(createdAt.formatted(date: .abbreviated, time: .shortened))"
        self.titleIsAutomatic = true
        self.createdAt = createdAt
        self.duration = duration
        self.transcript = transcript
    }

    var summary: LectureSummary? {
        get { summaryData.flatMap { try? JSONDecoder().decode(LectureSummary.self, from: $0) } }
        set { summaryData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var studyGuide: StudyGuide? {
        get { studyGuideData.flatMap { try? JSONDecoder().decode(StudyGuide.self, from: $0) } }
        set { studyGuideData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var segments: [TranscriptSegment] {
        get { segmentsData.flatMap { try? JSONDecoder().decode([TranscriptSegment].self, from: $0) } ?? [] }
        set {
            segmentsData = try? JSONEncoder().encode(newValue)
            transcript = newValue.map(\.text).joined(separator: " ")
        }
    }

    var speakerNames: [Int: String] {
        get { speakerNamesData.flatMap { try? JSONDecoder().decode([Int: String].self, from: $0) } ?? [:] }
        set { speakerNamesData = try? JSONEncoder().encode(newValue) }
    }

    func name(forSpeaker speaker: Int) -> String {
        speakerNames[speaker] ?? TranscriptFormatting.defaultName(for: speaker)
    }

    var analysisTranscript: String {
        let segments = segments
        let speakerCount = Set(segments.map(\.speaker)).count
        guard speakerCount > 1 else { return transcript }
        return TranscriptFormatting.labeledText(segments, names: speakerNames)
    }

    var sortedPhotos: [LecturePhoto] {
        photos.sorted { $0.takenAt < $1.takenAt }
    }
}
