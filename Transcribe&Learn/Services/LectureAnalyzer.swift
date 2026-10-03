import Foundation
import FoundationModels

/// Turns a lecture transcript into a summary and study material with the
/// on-device Apple Intelligence model.
///
/// The on-device model has a small context window (about 4,096 tokens), so a
/// long transcript is first split into chunks, each chunk is condensed into
/// notes in its own session, and the combined notes feed the final requests.
@Observable
final class LectureAnalyzer {
    private(set) var isWorking = false
    private(set) var progressMessage = ""
    var errorMessage: String?

    /// Roughly 1,500–2,000 tokens of English text, leaving room for instructions and output.
    private static let chunkLength = 6_000
    private static let maxNotesLength = 6_000

    private static let noteTakerInstructions = """
        You are a careful note-taker for a student. Rewrite the lecture excerpt \
        you're given as concise bullet notes. Keep definitions, facts, examples, \
        formulas, and anything the lecturer stresses as important. Don't add \
        information that isn't in the excerpt.
        """

    private static let tutorInstructions = """
        You are a helpful tutor creating study material from a student's lecture \
        notes. Only use information from the notes.
        """

    /// A message explaining why generation isn't possible, or `nil` when the model is ready.
    static var unavailableMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            "This iPad doesn't support Apple Intelligence, which is needed to create summaries and study notes."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Turn on Apple Intelligence in Settings to create summaries and study notes."
        case .unavailable(.modelNotReady):
            "The on-device model is still downloading. Try again in a few minutes."
        case .unavailable:
            "The on-device language model isn't available right now."
        }
    }

    func analyze(_ lecture: Lecture) async {
        guard !isWorking else { return }
        let transcript = lecture.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            errorMessage = "There's no transcript to study from yet."
            return
        }

        isWorking = true
        errorMessage = nil
        defer {
            isWorking = false
            progressMessage = ""
        }

        do {
            let notes = try await condense(transcript)

            progressMessage = "Writing summary…"
            let summary = try await generate(
                LectureSummary.self,
                task: "Summarize this lecture for a student who missed it.",
                notes: notes
            )
            lecture.summary = summary
            if lecture.titleIsAutomatic, !summary.title.isEmpty {
                lecture.title = summary.title
            }

            progressMessage = "Drawing flowchart…"
            let flowchart = try await generate(
                Flowchart.self,
                task: "Create a flowchart of the main process, sequence, or line of reasoning explained in this lecture.",
                notes: notes
            )

            progressMessage = "Building mind map…"
            let mindMap = try await generate(
                MindMap.self,
                task: "Create a mind map that organizes the topics in this lecture.",
                notes: notes
            )

            progressMessage = "Making flashcards…"
            let cards = try await generate(
                StudyCards.self,
                task: "Extract the key terms and write flashcards to help a student review this lecture.",
                notes: notes
            )

            progressMessage = "Writing quiz…"
            let quiz = try await generate(
                Quiz.self,
                task: "Write a multiple-choice quiz that tests understanding of this lecture.",
                notes: notes
            )

            lecture.studyGuide = StudyGuide(flowchart: flowchart, mindMap: mindMap, cards: cards, quiz: quiz)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Repeatedly condenses text in chunks until it fits comfortably in one request.
    private func condense(_ transcript: String) async throws -> String {
        var text = transcript
        var pass = 1

        while text.count > Self.maxNotesLength {
            let pieces = Self.chunks(of: text, maxLength: Self.chunkLength)
            var notes: [String] = []

            for (index, piece) in pieces.enumerated() {
                progressMessage = pass == 1
                    ? "Reading part \(index + 1) of \(pieces.count)…"
                    : "Condensing notes (\(index + 1) of \(pieces.count))…"
                let session = LanguageModelSession(instructions: Self.noteTakerInstructions)
                let response = try await session.respond(to: "Lecture excerpt:\n\(piece)")
                notes.append(response.content)
            }

            let condensed = notes.joined(separator: "\n")
            // Guard against a pass that doesn't make the text shorter.
            if condensed.count >= text.count {
                text = String(condensed.prefix(Self.maxNotesLength))
                break
            }
            text = condensed
            pass += 1
        }
        return text
    }

    private func generate<Content: Generable>(
        _ type: Content.Type,
        task: String,
        notes: String
    ) async throws -> Content {
        let session = LanguageModelSession(instructions: Self.tutorInstructions)
        let prompt = "\(task)\n\nLecture notes:\n\(notes)"
        return try await session.respond(to: prompt, generating: Content.self).content
    }

    /// Splits text into pieces of at most `maxLength` characters on word boundaries.
    private static func chunks(of text: String, maxLength: Int) -> [String] {
        var result: [String] = []
        var current = ""
        var currentLength = 0

        for word in text.split(whereSeparator: \.isWhitespace) {
            if currentLength + word.count + 1 > maxLength, !current.isEmpty {
                result.append(current)
                current = ""
                currentLength = 0
            }
            if !current.isEmpty {
                current += " "
                currentLength += 1
            }
            current += word
            currentLength += word.count
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}
