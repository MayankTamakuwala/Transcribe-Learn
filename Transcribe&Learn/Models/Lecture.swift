import Foundation
import SwiftData

@Model
final class Lecture {
    var title: String
    /// True until the person renames the lecture, so the AI-generated title can replace the placeholder.
    var titleIsAutomatic: Bool
    var createdAt: Date
    var duration: TimeInterval
    var transcript: String
    var summaryData: Data?
    var studyGuideData: Data?

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
}
