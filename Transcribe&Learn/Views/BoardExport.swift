import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
enum BoardExporter {
    enum ExportError: LocalizedError {
        case nothingToExport
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .nothingToExport: "Generate study notes first, then copy them to Freeform."
            case .renderFailed: "The sections couldn't be drawn. Try again."
            }
        }
    }

    static func hasContent(_ lecture: Lecture) -> Bool {
        hasNotes(lecture) || !lecture.photos.isEmpty || hasTranscript(lecture)
    }

    private static func hasNotes(_ lecture: Lecture) -> Bool {
        lecture.summary != nil || (lecture.studyGuide.map { $0 != StudyGuide() } ?? false)
    }

    static func hasTranscript(_ lecture: Lecture) -> Bool {
        !lecture.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    struct ClipboardContents {
        var sections: [Data]
        var photos: [Data]

        var pasteboardItems: [[String: Any]] {
            sections.map { [UTType.png.identifier: $0] } + photos.map { [UTType.jpeg.identifier: $0] }
        }

        var isEmpty: Bool { sections.isEmpty && photos.isEmpty }
    }

    static func clipboardContents(for lecture: Lecture) throws -> ClipboardContents {
        guard hasContent(lecture) else { throw ExportError.nothingToExport }
        let sections = hasNotes(lecture) ? try sectionImages(for: lecture) : []
        let photos = lecture.sortedPhotos.map(\.imageData)
        return ClipboardContents(sections: sections, photos: photos)
    }

    static func transcriptItem(for lecture: Lecture) -> [String: Any]? {
        guard hasTranscript(lecture) else { return nil }
        let text = transcriptText(for: lecture)
        var item: [String: Any] = [UTType.utf8PlainText.identifier: text.string]
        if let rtf = try? text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            item[UTType.rtf.identifier] = rtf
        }
        return item
    }

    private static func transcriptText(for lecture: Lecture) -> NSAttributedString {
        let titleFont = UIFont.preferredFont(forTextStyle: .title2).withTraits(.traitBold)
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let speakerFont = bodyFont.withTraits(.traitBold)
        let secondary = UIFont.preferredFont(forTextStyle: .subheadline)

        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 10
        paragraph.lineSpacing = 2

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "\(lecture.title) — Transcript\n", attributes: [.font: titleFont]))
        let date = lecture.createdAt.formatted(date: .abbreviated, time: .shortened)
        result.append(NSAttributedString(string: "Recorded \(date)\n\n", attributes: [.font: secondary, .foregroundColor: UIColor.secondaryLabel]))

        let turns = TranscriptFormatting.turns(from: lecture.segments)
        if Set(lecture.segments.map(\.speaker)).count > 1 {
            for turn in turns {
                result.append(NSAttributedString(string: "\(lecture.name(forSpeaker: turn.speaker)): ", attributes: [.font: speakerFont, .paragraphStyle: paragraph]))
                result.append(NSAttributedString(string: turn.text + "\n", attributes: [.font: bodyFont, .paragraphStyle: paragraph]))
            }
        } else {
            result.append(NSAttributedString(string: lecture.transcript, attributes: [.font: bodyFont, .paragraphStyle: paragraph]))
        }
        return result
    }

    private static func sectionImages(for lecture: Lecture) throws -> [Data] {
        let guide = lecture.studyGuide
        var images: [Data] = []

        if let summary = lecture.summary {
            images.append(try render(sectionPage { SummaryContent(summary: summary) }, width: 1100))
        }
        if let flowchart = guide?.flowchart {
            images.append(try render(sectionPage { FlowchartDiagram(flowchart: flowchart) }, width: 1100))
        }
        if let mindMap = guide?.mindMap {
            images.append(try render(sectionPage { SketchTitle(text: "Mind Map"); MindMapDiagram(mindMap: mindMap).fixedSize() }, width: nil))
        }
        if let cards = guide?.cards {
            images.append(try render(sectionPage {
                SketchTitle(text: "Flashcards")
                BoardGrid(items: Array(cards.flashcards.enumerated()), columns: 2) { index, card in
                    FlashcardContent(card: card, index: index)
                }
                if !cards.keyTerms.isEmpty {
                    GlossaryContent(terms: cards.keyTerms)
                }
            }, width: 1100))
        }
        if let quiz = guide?.quiz, !quiz.questions.isEmpty {
            images.append(try render(sectionPage { SketchTitle(text: "Pop Quiz!"); QuizSheetContent(quiz: quiz) }, width: 1100))
        }
        return images
    }

    private static func sectionPage(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            content()
        }
        .padding(56)
        .background { SketchPaper() }
    }

    private static let maxPixels: CGFloat = 8_000_000

    private static func render(_ view: some View, width: CGFloat?) throws -> Data {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)

        var size = CGSize.zero
        renderer.render { measured, _ in size = measured }
        renderer.scale = min(2, (maxPixels / max(size.width * size.height, 1)).squareRoot())

        guard let data = renderer.uiImage?.pngData() else { throw ExportError.renderFailed }
        return data
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

private struct BoardGrid<Item, Cell: View>: View {
    let items: [Item]
    let columns: Int
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        VStack(alignment: .leading, spacing: 36) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(alignment: .top, spacing: 36) {
                    ForEach(rows[rowIndex].indices, id: \.self) { index in
                        cell(rows[rowIndex][index])
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    ForEach(0..<(columns - rows[rowIndex].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }
}
