import SwiftUI

struct SketchHeading: View {
    let title: String
    var highlight: Color = SketchTheme.yellowHighlighter

    var body: some View {
        Text(title.uppercased())
            .font(SketchTheme.label)
            .foregroundStyle(SketchTheme.ink)
            .padding(.horizontal, 6)
            .sketchHighlight(highlight, seed: SketchRandom.seed(title))
            .accessibilityAddTraits(.isHeader)
    }
}

struct SketchNumber: View {
    let number: Int
    var color: Color = SketchTheme.ink

    var body: some View {
        Text("\(number)")
            .font(SketchTheme.label)
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .overlay { SketchShape(kind: .ellipse, seed: UInt64(number) &* 31, passes: 1).sketchStroke(color) }
            .accessibilityHidden(true)
    }
}

struct TapedPhoto: View {
    let photo: LecturePhoto
    var width: CGFloat = 200

    var body: some View {
        let seed = SketchRandom.seed(photo.takenAt.description)
        var rng = SketchRandom(seed: seed)
        let tilt = Double(rng.next()) * 3

        VStack(spacing: 6) {
            Group {
                if let image = photo.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    SketchTheme.paper
                }
            }
            .frame(width: width, height: width * 0.75)
            .clipped()

            Text(photo.takenAt, format: .dateTime.hour().minute())
                .font(SketchTheme.note)
                .foregroundStyle(SketchTheme.ink)
        }
        .padding(10)
        .background(SketchTheme.card)
        .shadow(color: .black.opacity(0.15), radius: 3, x: 1, y: 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SketchTheme.yellowHighlighter)
                .frame(width: width * 0.4, height: 22)
                .rotationEffect(.degrees(-tilt * 2))
                .offset(y: -11)
        }
        .rotationEffect(.degrees(tilt))
        .accessibilityElement()
        .accessibilityLabel("Photo taken at \(photo.takenAt.formatted(date: .omitted, time: .shortened))")
    }
}

private struct SketchPage<Content: View>: View {
    var maxWidth: CGFloat = 860
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 28)
                .padding(.vertical, 32)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .background { SketchPaper().ignoresSafeArea() }
    }
}

struct SummaryView: View {
    let summary: LectureSummary
    var photos: [LecturePhoto] = []

    var body: some View {
        SketchPage {
            SummaryContent(summary: summary, photos: photos)
        }
    }
}

struct SummaryContent: View {
    let summary: LectureSummary
    var photos: [LecturePhoto] = []
    var showsTitle = true
    @State private var openedPhoto: LecturePhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if showsTitle {
                SketchTitle(text: summary.title)
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 12) {
                SketchHeading(title: "The big picture")
                Text(summary.overview)
                    .font(SketchTheme.body)
                    .foregroundStyle(SketchTheme.ink)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay { SketchShape(kind: .roundedRectangle, seed: SketchRandom.seed(summary.overview)).sketchStroke() }
            }

            if !summary.keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SketchHeading(title: "Key points", highlight: SketchTheme.blueHighlighter)
                    ForEach(Array(summary.keyPoints.enumerated()), id: \.offset) { index, point in
                        HStack(alignment: .top, spacing: 12) {
                            SketchNumber(number: index + 1)
                            Text(point)
                                .font(SketchTheme.body)
                                .foregroundStyle(SketchTheme.ink)
                                .padding(.top, 4)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if !summary.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SketchHeading(title: "Don't forget!", highlight: SketchTheme.pinkHighlighter)
                    ForEach(Array(summary.actionItems.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("!")
                                .font(SketchTheme.title(size: 24))
                                .foregroundStyle(SketchTheme.redInk)
                            Text(item)
                                .font(SketchTheme.body)
                                .foregroundStyle(SketchTheme.ink)
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    SketchShape(kind: .octagon, seed: SketchRandom.seed(summary.actionItems.joined()))
                        .sketchStroke(dashed: true)
                }
            }

            if !photos.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    SketchHeading(title: "From the board", highlight: SketchTheme.yellowHighlighter)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 24)], spacing: 28) {
                        ForEach(photos) { photo in
                            Button {
                                openedPhoto = photo
                            } label: {
                                TapedPhoto(photo: photo)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the photo full screen")
                        }
                    }
                    .fullScreenCover(item: $openedPhoto) { photo in
                        PhotoViewer(photos: photos, startingAt: photo)
                    }
                }
            }
        }
    }
}

struct FlashcardsView: View {
    let cards: StudyCards

    var body: some View {
        SketchPage(maxWidth: 1000) {
            VStack(alignment: .leading, spacing: 32) {
                if !cards.flashcards.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        SketchHeading(title: "Flashcards", highlight: SketchTheme.blueHighlighter)
                        Text("Tap a card to flip it.")
                            .font(SketchTheme.note)
                            .foregroundStyle(SketchTheme.ink)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 24)], spacing: 24) {
                            ForEach(Array(cards.flashcards.enumerated()), id: \.offset) { index, card in
                                FlipIndexCard(card: card, index: index)
                            }
                        }
                    }
                }
                if !cards.keyTerms.isEmpty {
                    GlossaryContent(terms: cards.keyTerms)
                }
            }
        }
    }
}

struct IndexCard<Content: View>: View {
    let seed: UInt64
    var minHeight: CGFloat = 180
    @ViewBuilder let content: Content

    var body: some View {
        var rng = SketchRandom(seed: seed)
        let tilt = Double(rng.next()) * 1.5

        content
            .padding(.horizontal, 22)
            .padding(.top, 34)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(SketchTheme.card))
                    var y: CGFloat = 54
                    while y < size.height - 8 {
                        context.stroke(Path { $0.move(to: CGPoint(x: 8, y: y)); $0.addLine(to: CGPoint(x: size.width - 8, y: y)) },
                                       with: .color(SketchTheme.ruledLine), lineWidth: 1)
                        y += 28
                    }
                    context.stroke(Path { $0.move(to: CGPoint(x: 8, y: 26)); $0.addLine(to: CGPoint(x: size.width - 8, y: 26)) },
                                   with: .color(SketchTheme.marginLine), lineWidth: 1.5)
                }
            }
            .overlay { SketchShape(kind: .rectangle, seed: seed).sketchStroke(lineWidth: 1.5) }
            .shadow(color: .black.opacity(0.12), radius: 3, x: 1, y: 2)
            .rotationEffect(.degrees(tilt))
    }
}

private struct FlipIndexCard: View {
    let card: StudyCards.Flashcard
    let index: Int
    @State private var isFlipped = false

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.45)) {
                isFlipped.toggle()
            }
        } label: {
            IndexCard(seed: SketchRandom.seed(card.question)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(isFlipped ? "A." : "Q\(index + 1).")
                        .font(SketchTheme.label)
                        .foregroundStyle(isFlipped ? SketchTheme.greenInk : SketchTheme.redInk)
                    Text(isFlipped ? card.answer : card.question)
                        .font(SketchTheme.bodyBold)
                        .foregroundStyle(SketchTheme.ink)
                        .multilineTextAlignment(.leading)
                }
            }
            .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .scaleEffect(x: isFlipped ? -1 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFlipped ? "Answer: \(card.answer)" : "Question: \(card.question)")
        .accessibilityHint(isFlipped ? "Shows the question" : "Shows the answer")
    }
}

struct FlashcardContent: View {
    let card: StudyCards.Flashcard
    let index: Int

    var body: some View {
        IndexCard(seed: SketchRandom.seed(card.question), minHeight: 150) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Q\(index + 1).  \(card.question)")
                    .font(SketchTheme.bodyBold)
                    .foregroundStyle(SketchTheme.ink)
                SketchSquiggle(seed: SketchRandom.seed(card.answer))
                    .sketchStroke(SketchTheme.ruledLine, lineWidth: 1.2)
                    .frame(height: 8)
                Text("A.  \(card.answer)")
                    .font(SketchTheme.body)
                    .foregroundStyle(SketchTheme.greenInk)
            }
        }
    }
}

struct GlossaryContent: View {
    let terms: [StudyCards.KeyTerm]
    var showsHeading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHeading {
                SketchHeading(title: "Key terms", highlight: SketchTheme.pinkHighlighter)
            }
            ForEach(Array(terms.enumerated()), id: \.offset) { index, term in
                VStack(alignment: .leading, spacing: 4) {
                    Text(term.term)
                        .font(SketchTheme.bodyBold)
                        .foregroundStyle(SketchTheme.ink)
                        .padding(.horizontal, 4)
                        .sketchHighlight(SketchTheme.yellowHighlighter, seed: SketchRandom.seed(term.term))
                    Text(term.definition)
                        .font(SketchTheme.body)
                        .foregroundStyle(SketchTheme.ink)
                }
                .accessibilityElement(children: .combine)
                if index < terms.count - 1 {
                    SketchSquiggle(seed: SketchRandom.seed(term.definition))
                        .sketchStroke(SketchTheme.ink.opacity(0.35), lineWidth: 1.2)
                        .frame(width: 120, height: 8)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

struct QuizView: View {
    let quiz: Quiz
    @State private var answers: [Int: Int] = [:]

    private var score: Int {
        answers.filter { quiz.questions.indices.contains($0.key) && quiz.questions[$0.key].correctIndex == $0.value }.count
    }

    var body: some View {
        SketchPage {
            VStack(alignment: .leading, spacing: 34) {
                HStack(alignment: .center) {
                    SketchTitle(text: "Pop Quiz!")
                    Spacer()
                    if !answers.isEmpty {
                        grade
                        Button("Reset") { answers.removeAll() }
                            .font(SketchTheme.label)
                            .foregroundStyle(SketchTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .overlay { SketchShape(kind: .roundedRectangle, seed: 7).sketchStroke(lineWidth: 1.4) }
                    }
                }

                ForEach(Array(quiz.questions.enumerated()), id: \.offset) { index, question in
                    questionView(question, index: index)
                }
            }
        }
    }

    private var grade: some View {
        Text("\(score)/\(quiz.questions.count)")
            .font(SketchTheme.title(size: 26))
            .foregroundStyle(SketchTheme.redInk)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .overlay { SketchShape(kind: .ellipse, seed: UInt64(score) &+ 5).sketchStroke(SketchTheme.redInk, lineWidth: 2) }
            .accessibilityLabel("Score: \(score) out of \(quiz.questions.count)")
    }

    private func questionView(_ question: Quiz.Question, index: Int) -> some View {
        let chosen = answers[index]

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SketchNumber(number: index + 1)
                Text(question.prompt)
                    .font(SketchTheme.bodyBold)
                    .foregroundStyle(SketchTheme.ink)
                    .padding(.top, 4)
            }

            ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                Button {
                    answers[index] = optionIndex
                } label: {
                    QuizOption(
                        letter: QuizOption.letter(optionIndex),
                        text: option,
                        mark: mark(for: optionIndex, chosen: chosen, correct: question.correctIndex),
                        seed: SketchRandom.seed(option)
                    )
                }
                .buttonStyle(.plain)
                .disabled(chosen != nil)
                .padding(.leading, 46)
            }

            if chosen != nil, !question.explanation.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    SketchArrow(start: UnitPoint(x: 0, y: 0.1), end: UnitPoint(x: 1, y: 0.8), bend: 0.3, seed: SketchRandom.seed(question.explanation))
                        .sketchStroke(SketchTheme.greenInk, lineWidth: 1.4)
                        .frame(width: 30, height: 24)
                    Text(question.explanation)
                        .font(SketchTheme.note)
                        .foregroundStyle(SketchTheme.greenInk)
                }
                .padding(.leading, 46)
            }
        }
    }

    private func mark(for option: Int, chosen: Int?, correct: Int) -> QuizOption.Mark {
        guard let chosen else { return .none }
        if option == correct { return .correct }
        if option == chosen { return .wrong }
        return .none
    }
}

struct QuizOption: View {
    enum Mark {
        case none, correct, wrong
    }

    let letter: String
    let text: String
    var mark: Mark = .none
    let seed: UInt64

    static func letter(_ index: Int) -> String {
        ["A", "B", "C", "D", "E", "F"].indices.contains(index) ? ["A", "B", "C", "D", "E", "F"][index] : "\(index + 1)"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(letter))")
                .font(SketchTheme.label)
            Text(text)
                .font(SketchTheme.body)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            switch mark {
            case .correct:
                Text("✓").font(SketchTheme.title(size: 24)).foregroundStyle(SketchTheme.greenInk)
            case .wrong:
                Text("✗").font(SketchTheme.title(size: 24)).foregroundStyle(SketchTheme.redInk)
            case .none:
                EmptyView()
            }
        }
        .foregroundStyle(SketchTheme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay {
            switch mark {
            case .correct:
                SketchShape(kind: .ellipse, seed: seed).sketchStroke(SketchTheme.greenInk, lineWidth: 2.2)
            case .wrong:
                SketchArrowlessLine(seed: seed).sketchStroke(SketchTheme.redInk, lineWidth: 2.2)
            case .none:
                SketchShape(kind: .roundedRectangle, seed: seed, passes: 1).sketchStroke(SketchTheme.ink.opacity(0.55), lineWidth: 1.2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(mark == .correct ? "Correct answer" : mark == .wrong ? "Incorrect" : "")
    }
}

private nonisolated struct SketchArrowlessLine: Shape {
    var seed: UInt64

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var rng = SketchRandom(seed: seed)
        Sketch.line(
            from: CGPoint(x: rect.minX + 8, y: rect.midY + 2),
            to: CGPoint(x: rect.maxX - 8, y: rect.midY - 2),
            to: &path,
            rng: &rng
        )
        return path
    }
}

struct QuizSheetContent: View {
    let quiz: Quiz

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(Array(quiz.questions.enumerated()), id: \.offset) { index, question in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        SketchNumber(number: index + 1)
                        Text(question.prompt)
                            .font(SketchTheme.bodyBold)
                            .foregroundStyle(SketchTheme.ink)
                            .padding(.top, 4)
                    }
                    ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                        Text("\(QuizOption.letter(optionIndex)))  \(option)")
                            .font(SketchTheme.body)
                            .foregroundStyle(SketchTheme.ink)
                            .padding(.leading, 46)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SketchHeading(title: "Answer key", highlight: SketchTheme.yellowHighlighter)
                ForEach(Array(quiz.questions.enumerated()), id: \.offset) { index, question in
                    Text("\(index + 1). \(QuizOption.letter(question.correctIndex))\(question.explanation.isEmpty ? "" : " — \(question.explanation)")")
                        .font(SketchTheme.note)
                        .foregroundStyle(SketchTheme.greenInk)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay { SketchShape(kind: .rectangle, seed: 4242).sketchStroke(dashed: true) }
        }
    }
}
#Preview("Summary") {
    SummaryView(summary: LectureSummary(
        title: "Photosynthesis 101",
        overview: "Plants turn light, water, and carbon dioxide into glucose and oxygen. The process has two stages: the light reactions in the thylakoids and the Calvin cycle in the stroma.",
        keyPoints: ["Chlorophyll absorbs mostly red and blue light.", "Light reactions make ATP and NADPH.", "The Calvin cycle fixes CO₂ into sugar."],
        actionItems: ["Lab report due Friday", "Chloroplast diagram will be on the exam"]
    ))
}

#Preview("Flashcards") {
    FlashcardsView(cards: StudyCards(
        keyTerms: [.init(term: "Chlorophyll", definition: "The green pigment that absorbs light."),
                   .init(term: "Stroma", definition: "Fluid where the Calvin cycle runs.")],
        flashcards: [.init(question: "Where do the light reactions happen?", answer: "In the thylakoid membranes."),
                     .init(question: "What gas is released?", answer: "Oxygen."),
                     .init(question: "What powers the Calvin cycle?", answer: "ATP and NADPH.")]
    ))
}

#Preview("Quiz") {
    QuizView(quiz: Quiz(questions: [
        .init(prompt: "Where does the Calvin cycle take place?", options: ["Thylakoid", "Stroma", "Nucleus", "Cell wall"], correctIndex: 1, explanation: "It runs in the fluid stroma."),
        .init(prompt: "Which is a product of photosynthesis?", options: ["CO₂", "Nitrogen", "Oxygen", "Water"], correctIndex: 2, explanation: "Splitting water releases O₂."),
    ]))
}
