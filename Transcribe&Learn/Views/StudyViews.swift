import SwiftUI

// MARK: - Summary

struct SummaryView: View {
    let summary: LectureSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("Overview", systemImage: "text.alignleft") {
                    Text(summary.overview)
                        .font(.body)
                        .lineSpacing(4)
                }

                section("Key Points", systemImage: "star") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(summary.keyPoints.enumerated()), id: \.offset) { _, point in
                            Label(point, systemImage: "checkmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }

                if !summary.actionItems.isEmpty {
                    section("To Do & Exam Hints", systemImage: "exclamationmark.bubble") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(summary.actionItems.enumerated()), id: \.offset) { _, item in
                                Label(item, systemImage: "calendar.badge.exclamationmark")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 800, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    private func section(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.title2.bold())
            content()
        }
    }
}

// MARK: - Flowchart

struct FlowchartView: View {
    let flowchart: Flowchart

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(flowchart.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)

                ForEach(Array(flowchart.steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 {
                        Image(systemName: "arrow.down")
                            .font(.title2.bold())
                            .foregroundStyle(.tint)
                            .padding(.vertical, 8)
                            .accessibilityHidden(true)
                    }
                    node(step, number: index + 1, isEndpoint: index == 0 || index == flowchart.steps.count - 1)
                }
            }
            .frame(maxWidth: 560)
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    private func node(_ step: Flowchart.Step, number: Int, isEndpoint: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.tint))
            VStack(alignment: .leading, spacing: 4) {
                Text(step.label)
                    .font(.headline)
                Text(step.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: isEndpoint ? 28 : 12)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isEndpoint ? 28 : 12)
                .strokeBorder(.tint.opacity(0.5), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Mind Map

struct MindMapView: View {
    let mindMap: MindMap

    private let palette: [Color] = [.blue, .purple, .orange, .green, .pink, .teal]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(mindMap.centralTopic)
                    .font(.title.bold())
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(.tint.opacity(0.15)))
                    .overlay(Capsule().strokeBorder(.tint, lineWidth: 2))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                    ForEach(Array(mindMap.branches.enumerated()), id: \.offset) { index, branch in
                        branchCard(branch, color: palette[index % palette.count])
                    }
                }
            }
            .padding()
        }
    }

    private func branchCard(_ branch: MindMap.Branch, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(branch.topic)
                .font(.headline)
                .foregroundStyle(color)
            ForEach(Array(branch.ideas.enumerated()), id: \.offset) { _, idea in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                    Text(idea)
                        .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(color.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(color.opacity(0.4)))
    }
}

// MARK: - Flashcards & Key Terms

struct FlashcardsView: View {
    let cards: StudyCards

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !cards.flashcards.isEmpty {
                    Text("Flashcards")
                        .font(.title2.bold())
                    Text("Tap a card to reveal the answer.")
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                        ForEach(Array(cards.flashcards.enumerated()), id: \.offset) { _, card in
                            FlipCard(question: card.question, answer: card.answer)
                        }
                    }
                }

                if !cards.keyTerms.isEmpty {
                    Text("Key Terms")
                        .font(.title2.bold())
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(cards.keyTerms.enumerated()), id: \.offset) { _, term in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(term.term)
                                    .font(.headline)
                                Text(term.definition)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

private struct FlipCard: View {
    let question: String
    let answer: String
    @State private var isFlipped = false

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.4)) {
                isFlipped.toggle()
            }
        } label: {
            VStack(spacing: 8) {
                Text(isFlipped ? "Answer" : "Question")
                    .font(.caption.bold())
                    .textCase(.uppercase)
                    .foregroundStyle(isFlipped ? Color.green : Color.accentColor)
                Text(isFlipped ? answer : question)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(RoundedRectangle(cornerRadius: 18).fill(.background.secondary))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isFlipped ? Color.green : Color.accentColor, lineWidth: 1.5)
            )
            // Counter-rotate the content so the back side isn't mirrored.
            .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .scaleEffect(x: isFlipped ? -1 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityHint(isFlipped ? "Shows the question" : "Shows the answer")
    }
}

// MARK: - Quiz

struct QuizView: View {
    let quiz: Quiz
    /// The option the person chose for each question, keyed by question index.
    @State private var answers: [Int: Int] = [:]

    private var score: Int {
        answers.filter { quiz.questions.indices.contains($0.key) && quiz.questions[$0.key].correctIndex == $0.value }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Text("Quiz")
                        .font(.title2.bold())
                    Spacer()
                    if !answers.isEmpty {
                        Text("Score: \(score)/\(quiz.questions.count)")
                            .font(.headline)
                        Button("Reset") { answers.removeAll() }
                    }
                }

                ForEach(Array(quiz.questions.enumerated()), id: \.offset) { index, question in
                    questionView(question, index: index)
                }
            }
            .frame(maxWidth: 800, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    private func questionView(_ question: Quiz.Question, index: Int) -> some View {
        let chosen = answers[index]

        return VStack(alignment: .leading, spacing: 10) {
            Text("\(index + 1). \(question.prompt)")
                .font(.headline)

            ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                Button {
                    answers[index] = optionIndex
                } label: {
                    HStack {
                        Text(option)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if let chosen, optionIndex == question.correctIndex {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel(chosen == optionIndex ? "Correct" : "Correct answer")
                        } else if chosen == optionIndex {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .accessibilityLabel("Incorrect")
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
                }
                .buttonStyle(.plain)
                .disabled(chosen != nil)
            }

            if chosen != nil {
                Text(question.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
