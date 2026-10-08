import Foundation

nonisolated enum PlainTextFormats {
    static let summary = """
        Write a study summary of these lecture notes in exactly this format:
        TITLE: <a short title of at most 8 words>
        OVERVIEW: <3 to 5 sentences>
        KEY POINTS:
        - <one important idea per line, up to 10>
        ACTION ITEMS:
        - <assignments, deadlines, or exam hints, or "None">
        """

    static let flowchart = """
        Describe the main process, sequence of events, or line of reasoning in these \
        lecture notes as a flowchart, in exactly this format:
        TITLE: <what the flowchart shows>
        1. <short label> | <one sentence explaining the step>
        2. <short label> | <one sentence explaining the step>
        (up to 8 steps)
        """

    static let mindMap = """
        Organize the topics in these lecture notes as a mind map, in exactly this format:
        CENTER: <the central topic in 1 to 4 words>
        ## <subtopic>
        - <short fact or idea>
        (up to 6 subtopics, each with up to 4 ideas)
        """

    static let cards = """
        Write study material for these lecture notes in exactly this format:
        TERM: <important term> | <one-sentence definition>
        (up to 8 terms)
        Q: <flashcard question>
        A: <short answer>
        (up to 8 flashcards)
        """

    static let quiz = """
        Write a multiple-choice quiz about these lecture notes, with up to 5 questions, \
        each in exactly this format:
        Q: <question>
        A) <option>
        B) <option>
        C) <option>
        D) <option>
        ANSWER: <A, B, C, or D>
        WHY: <one sentence explaining the answer>
        """

    static func parseSummary(_ text: String) -> LectureSummary? {
        var title = ""
        var overview = ""
        var keyPoints: [String] = []
        var actionItems: [String] = []
        var section = ""

        for line in lines(of: text) {
            if let value = value(of: line, key: "TITLE") {
                title = value
            } else if let value = value(of: line, key: "OVERVIEW") {
                overview = value
                section = "overview"
            } else if line.uppercased().hasPrefix("KEY POINTS") {
                section = "points"
            } else if line.uppercased().hasPrefix("ACTION ITEMS") {
                section = "actions"
            } else if let bullet = bullet(line) {
                if section == "actions" {
                    if !bullet.lowercased().hasPrefix("none") { actionItems.append(bullet) }
                } else {
                    keyPoints.append(bullet)
                }
            } else if section == "overview" {
                overview += " " + line
            }
        }

        guard !overview.isEmpty || !keyPoints.isEmpty else { return nil }
        return LectureSummary(title: title, overview: overview, keyPoints: keyPoints, actionItems: actionItems)
    }

    static func parseFlowchart(_ text: String) -> Flowchart? {
        var title = ""
        var steps: [Flowchart.Step] = []

        for line in lines(of: text) {
            if let value = value(of: line, key: "TITLE") {
                title = value
            } else if let item = numbered(line) ?? bullet(line) {
                let (label, detail) = split(item)
                steps.append(Flowchart.Step(label: label, detail: detail))
            }
        }

        guard !steps.isEmpty else { return nil }
        return Flowchart(title: title.isEmpty ? "Lecture Flow" : title, steps: steps)
    }

    static func parseMindMap(_ text: String) -> MindMap? {
        var center = ""
        var branches: [MindMap.Branch] = []

        for line in lines(of: text) {
            if let value = value(of: line, key: "CENTER") {
                center = value
            } else if line.hasPrefix("#") {
                let topic = line.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).trimmingCharacters(in: .whitespaces)
                branches.append(MindMap.Branch(topic: topic, ideas: []))
            } else if let idea = bullet(line), !branches.isEmpty {
                branches[branches.count - 1].ideas.append(idea)
            }
        }

        guard !branches.isEmpty else { return nil }
        return MindMap(centralTopic: center.isEmpty ? "Lecture" : center, branches: branches)
    }

    static func parseCards(_ text: String) -> StudyCards? {
        var terms: [StudyCards.KeyTerm] = []
        var flashcards: [StudyCards.Flashcard] = []
        var pendingQuestion: String?

        for line in lines(of: text) {
            if let value = value(of: line, key: "TERM") {
                let (term, definition) = split(value)
                terms.append(StudyCards.KeyTerm(term: term, definition: definition))
            } else if let value = value(of: line, key: "Q") {
                pendingQuestion = value
            } else if let value = value(of: line, key: "A"), let question = pendingQuestion {
                flashcards.append(StudyCards.Flashcard(question: question, answer: value))
                pendingQuestion = nil
            }
        }

        guard !terms.isEmpty || !flashcards.isEmpty else { return nil }
        return StudyCards(keyTerms: terms, flashcards: flashcards)
    }

    static func parseQuiz(_ text: String) -> Quiz? {
        var questions: [Quiz.Question] = []
        var prompt: String?
        var options: [String] = []
        var correctIndex: Int?

        func commit(explanation: String) {
            if let prompt, options.count == 4, let correctIndex {
                questions.append(Quiz.Question(prompt: prompt, options: options, correctIndex: correctIndex, explanation: explanation))
            }
            prompt = nil
            options = []
            correctIndex = nil
        }

        for line in lines(of: text) {
            if let value = value(of: line, key: "Q") {
                prompt = value
                options = []
                correctIndex = nil
            } else if let option = choice(line) {
                options.append(option)
            } else if let value = value(of: line, key: "ANSWER") {
                let tokens = value.uppercased().split { !$0.isLetter }
                if let letter = tokens.first(where: { $0.count == 1 && "ABCD".contains($0) })?.first {
                    correctIndex = Array("ABCD").firstIndex(of: letter)
                }
            } else if let value = value(of: line, key: "WHY") {
                commit(explanation: value)
            }
        }
        commit(explanation: "")

        guard !questions.isEmpty else { return nil }
        return Quiz(questions: questions)
    }

    static func cleanNotes(_ text: String) -> String {
        var lines: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .trimmingCharacters(in: .whitespaces)
            while line.hasPrefix("#") {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if let first = line.first, "-*•".contains(first), line.count > 1 {
                line = "• " + line.dropFirst().trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("•"), line.hasSuffix("...") || line.hasSuffix("…") {
                continue
            }
            if line == "•" { continue }
            lines.append(line)
        }

        var result: [String] = []
        for (index, line) in lines.enumerated() {
            if line.hasSuffix(":"), !line.hasPrefix("•") {
                let rest = lines[(index + 1)...]
                let nextContent = rest.first { !$0.isEmpty }
                if nextContent == nil || (nextContent?.hasSuffix(":") == true && nextContent?.hasPrefix("•") == false) {
                    continue
                }
            }
            result.append(line)
        }

        var collapsed: [String] = []
        for line in result where !(line.isEmpty && (collapsed.last?.isEmpty ?? true)) {
            collapsed.append(line)
        }
        return collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func looksLikeRefusal(_ text: String) -> Bool {
        let start = text.prefix(160).lowercased()
        return text.count < 400 && ["sorry", "i can't", "i cannot", "i'm unable", "i am unable"].contains { start.contains($0) }
    }

    private static func lines(of text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "") }
            .filter { !$0.isEmpty }
    }

    private static func value(of line: String, key: String) -> String? {
        let prefix = key + ":"
        guard line.uppercased().hasPrefix(prefix) else { return nil }
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func bullet(_ line: String) -> String? {
        guard let first = line.first, "-•*".contains(first) else { return nil }
        let value = line.dropFirst().trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func numbered(_ line: String) -> String? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let marker = rest.first, ".)".contains(marker) else { return nil }
        let value = rest.dropFirst().trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func choice(_ line: String) -> String? {
        guard line.count > 2,
              let letter = line.first, "ABCDabcd".contains(letter),
              ").".contains(line[line.index(after: line.startIndex)]) else { return nil }
        let value = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func split(_ text: String) -> (String, String) {
        for separator in [" | ", "|", " — ", " – ", " - ", ": "] {
            if let range = text.range(of: separator) {
                let lhs = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let rhs = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !lhs.isEmpty, !rhs.isEmpty { return (lhs, rhs) }
            }
        }
        return (text, "")
    }
}
