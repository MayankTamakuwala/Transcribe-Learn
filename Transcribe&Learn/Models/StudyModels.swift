import Foundation
import FoundationModels

@Generable
nonisolated struct LectureSummary: Codable, Equatable {
    @Guide(description: "A short, descriptive title for the lecture, at most 8 words.")
    var title: String

    @Guide(description: "A 3 to 5 sentence overview of the whole lecture.")
    var overview: String

    @Guide(description: "The most important ideas a student must remember, each one sentence.", .maximumCount(10))
    var keyPoints: [String]

    @Guide(description: "Assignments, deadlines, or exam hints the lecturer mentioned. Empty if none.", .maximumCount(5))
    var actionItems: [String]
}

@Generable
nonisolated struct Flowchart: Codable, Equatable {
    @Guide(description: "What the flowchart shows, for example 'How TCP establishes a connection'.")
    var title: String

    @Guide(description: "The steps of the main process or line of reasoning in the lecture, in order.", .maximumCount(8))
    var steps: [Step]

    @Generable
    nonisolated struct Step: Codable, Equatable {
        @Guide(description: "A short label of 2 to 6 words.")
        var label: String

        @Guide(description: "One sentence explaining this step.")
        var detail: String
    }
}

@Generable
nonisolated struct MindMap: Codable, Equatable {
    @Guide(description: "The central topic of the lecture in 1 to 4 words.")
    var centralTopic: String

    @Guide(description: "Main subtopics that branch from the central topic.", .maximumCount(6))
    var branches: [Branch]

    @Generable
    nonisolated struct Branch: Codable, Equatable {
        @Guide(description: "The subtopic name in 1 to 4 words.")
        var topic: String

        @Guide(description: "Short facts or ideas under this subtopic.", .maximumCount(4))
        var ideas: [String]
    }
}

@Generable
nonisolated struct StudyCards: Codable, Equatable {
    @Guide(description: "Important terms defined in the lecture.", .maximumCount(8))
    var keyTerms: [KeyTerm]

    @Guide(description: "Question-and-answer flashcards that test understanding.", .maximumCount(8))
    var flashcards: [Flashcard]

    @Generable
    nonisolated struct KeyTerm: Codable, Equatable {
        var term: String
        @Guide(description: "A one-sentence definition.")
        var definition: String
    }

    @Generable
    nonisolated struct Flashcard: Codable, Equatable {
        var question: String
        @Guide(description: "A short answer.")
        var answer: String
    }
}

@Generable
nonisolated struct Quiz: Codable, Equatable {
    @Guide(description: "Multiple-choice questions about the lecture.", .maximumCount(5))
    var questions: [Question]

    @Generable
    nonisolated struct Question: Codable, Equatable {
        var prompt: String

        @Guide(description: "Exactly four answer options.", .count(4))
        var options: [String]

        @Guide(description: "The index (0 to 3) of the correct option.", .range(0...3))
        var correctIndex: Int

        @Guide(description: "One sentence explaining why the answer is correct.")
        var explanation: String
    }
}

@Generable
nonisolated struct PhotoReading {
    @Guide(description: "One or two complete sentences describing what the photo shows, for example a slide, a whiteboard, a handout, or a video on a screen.")
    var description: String

    @Guide(description: "The important words, titles, formulas, and labels visible in the photo, each copied exactly and in full. Empty if there's no readable text.", .maximumCount(12))
    var visibleText: [String]

    @Guide(description: "What a student should remember from this photo, each as one complete sentence. Empty if nothing is worth noting.", .maximumCount(6))
    var keyPoints: [String]

    var formatted: String {
        var parts = [description.trimmingCharacters(in: .whitespacesAndNewlines)]
        let text = visibleText.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !text.isEmpty {
            parts.append("Text in the photo:\n" + text.map { "• \($0)" }.joined(separator: "\n"))
        }
        let points = keyPoints.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !points.isEmpty {
            parts.append("Key points:\n" + points.map { "• \($0)" }.joined(separator: "\n"))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

nonisolated struct StudyGuide: Codable, Equatable {
    var flowchart: Flowchart?
    var mindMap: MindMap?
    var cards: StudyCards?
    var quiz: Quiz?
}
