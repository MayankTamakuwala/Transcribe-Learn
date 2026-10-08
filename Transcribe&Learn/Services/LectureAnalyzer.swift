import Foundation
import FoundationModels
import UIKit
import Vision

@Observable
final class LectureAnalyzer {
    private(set) var isWorking = false
    private(set) var progressMessage = ""
    var errorMessage: String?

    private static let chunkLength = 6_000
    private static let maxNotesLength = 6_000
    private static let maxPhotoNotesLength = 2_000

    private static let permissiveModel = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    private static let noteTakerInstructions = """
        You are a careful note-taker helping a student study. The text you receive \
        is a transcript of a lecture, talk, or class discussion, and it may cover \
        sensitive historical, political, scientific, or medical subjects. Rewrite \
        it as neutral, factual bullet notes. Keep definitions, facts, names, dates, \
        examples, formulas, and anything the speaker stresses. Lines may start \
        with a speaker label such as "Person 1:"; the person who speaks most is \
        usually the lecturer, and questions from others often point to tricky \
        topics, so keep those too. Don't add information that isn't in the \
        transcript and don't add opinions.
        """

    private static let photoInstructions = """
        You help a student take notes from photos taken during a lecture, such as \
        slides, a whiteboard, handouts, or diagrams. Transcribe the important text, \
        formulas, and labels accurately, then briefly describe any diagram, chart, \
        or drawing and what it shows. Be concise and factual.
        """

    private static let tutorInstructions = """
        You are a helpful tutor creating study material from a student's lecture \
        notes. The notes may cover sensitive historical, political, scientific, or \
        medical subjects; treat them factually and neutrally, as a teacher would. \
        Only use information from the notes.
        """

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
        let transcript = lecture.analysisTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let photos = lecture.sortedPhotos
        guard !transcript.isEmpty || !photos.isEmpty else {
            errorMessage = "There's no transcript or photos to study from yet."
            return
        }

        isWorking = true
        errorMessage = nil
        defer {
            isWorking = false
            progressMessage = ""
        }

        let photoNotes = await notes(for: photos)

        var notes: String
        do {
            let budget = Self.maxNotesLength - min(photoNotes.count, Self.maxPhotoNotesLength)
            notes = transcript.isEmpty ? "" : try await makeNotes(from: transcript, maxLength: budget)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        if !photoNotes.isEmpty {
            notes += "\n\nFrom photos of the slides or whiteboard:\n\(photoNotes)"
        }

        progressMessage = "Writing summary…"
        if let summary = await generate(
            LectureSummary.self,
            task: "Summarize this lecture for a student who missed it.",
            fallbackFormat: PlainTextFormats.summary,
            parse: PlainTextFormats.parseSummary,
            notes: notes
        ) {
            lecture.summary = summary
            if lecture.titleIsAutomatic, !summary.title.isEmpty {
                lecture.title = summary.title
            }
        }

        var guide = StudyGuide()

        progressMessage = "Drawing flowchart…"
        guide.flowchart = await generate(
            Flowchart.self,
            task: "Create a flowchart of the main process, sequence of events, or line of reasoning in this lecture.",
            fallbackFormat: PlainTextFormats.flowchart,
            parse: PlainTextFormats.parseFlowchart,
            notes: notes
        )

        progressMessage = "Building mind map…"
        guide.mindMap = await generate(
            MindMap.self,
            task: "Create a mind map that organizes the topics in this lecture.",
            fallbackFormat: PlainTextFormats.mindMap,
            parse: PlainTextFormats.parseMindMap,
            notes: notes
        )

        progressMessage = "Making flashcards…"
        guide.cards = await generate(
            StudyCards.self,
            task: "Extract the key terms and write flashcards to help a student review this lecture.",
            fallbackFormat: PlainTextFormats.cards,
            parse: PlainTextFormats.parseCards,
            notes: notes
        )

        progressMessage = "Writing quiz…"
        guide.quiz = await generate(
            Quiz.self,
            task: "Write a multiple-choice quiz that tests understanding of this lecture.",
            fallbackFormat: PlainTextFormats.quiz,
            parse: PlainTextFormats.parseQuiz,
            notes: notes
        )

        lecture.studyGuide = guide

        if lecture.summary == nil, guide == StudyGuide() {
            errorMessage = "The on-device model declined to create study material for this lecture."
        }
    }

    private func makeNotes(from transcript: String, maxLength: Int) async throws -> String {
        var text = transcript
        var pass = 1

        repeat {
            let pieces = Self.chunks(of: text, maxLength: Self.chunkLength)
            var notes: [String] = []

            for (index, piece) in pieces.enumerated() {
                progressMessage = pass == 1
                    ? "Reading part \(index + 1) of \(pieces.count)…"
                    : "Condensing notes (\(index + 1) of \(pieces.count))…"
                let session = LanguageModelSession(model: Self.permissiveModel, instructions: Self.noteTakerInstructions)
                let response = try await session.respond(to: "Transcript:\n\(piece)")
                notes.append(PlainTextFormats.looksLikeRefusal(response.content) ? piece : response.content)
            }

            let condensed = notes.joined(separator: "\n")
            if pass > 1, condensed.count >= text.count {
                text = String(condensed.prefix(maxLength))
                break
            }
            text = condensed
            pass += 1
        } while text.count > maxLength

        return text
    }

    private func notes(for photos: [LecturePhoto]) async -> String {
        guard !photos.isEmpty else { return "" }

        for (index, photo) in photos.enumerated() where photo.aiNotes == nil {
            progressMessage = "Reading photo \(index + 1) of \(photos.count)…"
            guard let image = photo.image else { continue }
            let notes = await describe(image)
            photo.aiNotes = notes ?? ""
        }

        let perPhoto = max(150, Self.maxPhotoNotesLength / photos.count)
        let lines = photos.enumerated().compactMap { index, photo -> String? in
            guard let notes = photo.aiNotes, !notes.isEmpty else { return nil }
            let time = photo.takenAt.formatted(date: .omitted, time: .shortened)
            return "Photo \(index + 1) (\(time)): \(notes.prefix(perPhoto))"
        }
        return String(lines.joined(separator: "\n").prefix(Self.maxPhotoNotesLength))
    }

    private func describe(_ image: UIImage) async -> String? {
        await Self.readPhoto(image)
    }

    static func readPhoto(_ image: UIImage) async -> String? {
        if SystemLanguageModel.default.capabilities.contains(.vision) {
            do {
                let session = LanguageModelSession(instructions: photoInstructions)
                let reading = try await session.respond(generating: PhotoReading.self) {
                    "Take study notes from this lecture photo."
                    Attachment(image)
                }.content
                let text = reading.formatted
                if !text.isEmpty { return text }
            } catch {
            }

            do {
                let session = LanguageModelSession(model: permissiveModel, instructions: photoInstructions)
                let response = try await session.respond {
                    """
                    Take study notes from this lecture photo. Use plain text without \
                    markdown. Write complete sentences, never trail off with "...", and \
                    leave out any section that has nothing in it.
                    """
                    Attachment(image)
                }
                let text = PlainTextFormats.cleanNotes(response.content)
                if !text.isEmpty, !PlainTextFormats.looksLikeRefusal(text) {
                    return text
                }
            } catch {
            }
        }
        return await recognizeText(in: image)
    }

    private static func recognizeText(in image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        guard let observations = try? await request.perform(on: cgImage) else { return nil }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return lines.isEmpty ? nil : "Text in the photo:\n" + lines.map { "• \($0)" }.joined(separator: "\n")
    }

    private func generate<Content: Generable>(
        _ type: Content.Type,
        task: String,
        fallbackFormat: String,
        parse: (String) -> Content?,
        notes: String
    ) async -> Content? {
        do {
            let session = LanguageModelSession(instructions: Self.tutorInstructions)
            let prompt = "\(task)\n\nLecture notes:\n\(notes)"
            return try await session.respond(to: prompt, generating: Content.self).content
        } catch {
        }

        do {
            let session = LanguageModelSession(model: Self.permissiveModel, instructions: Self.tutorInstructions)
            let prompt = "\(fallbackFormat)\n\nLecture notes:\n\(notes)"
            let text = try await session.respond(to: prompt).content
            return PlainTextFormats.looksLikeRefusal(text) ? nil : parse(text)
        } catch {
            return nil
        }
    }

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
