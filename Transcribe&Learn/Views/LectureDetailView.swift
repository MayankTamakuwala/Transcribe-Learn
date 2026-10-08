import SwiftUI
import UniformTypeIdentifiers

struct LectureDetailView: View {
    @Bindable var lecture: Lecture
    @State private var analyzer = LectureAnalyzer()
    @State private var tab: Tab = .summary
    @State private var exportError: String?
    @State private var copiedSummary: String?
    @State private var isShowingTranscriptCopied = false

    enum Tab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case flowchart = "Flowchart"
        case mindMap = "Mind Map"
        case flashcards = "Flashcards"
        case quiz = "Quiz"
        case transcript = "Transcript"
        case photos = "Photos"

        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(titleBinding)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Copy for Freeform", systemImage: "doc.on.clipboard") {
                    copySections()
                }
                .disabled(analyzer.isWorking || !BoardExporter.hasContent(lecture))
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Regenerate Notes", systemImage: "sparkles") {
                    Task { await analyzer.analyze(lecture) }
                }
                .disabled(analyzer.isWorking || LectureAnalyzer.unavailableMessage != nil)
            }
        }
        .alert("Couldn't Copy", isPresented: isShowingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .alert("Copied for Freeform", isPresented: isShowingCopiedAlert) {
            if BoardExporter.hasTranscript(lecture) {
                Button("Copy Transcript Next") { copyTranscriptNext() }
            }
            Button("OK", role: .cancel) {}
        } message: {
            if BoardExporter.hasTranscript(lecture) {
                Text("Copied \(copiedSummary ?? "") to the clipboard.\n\n1. Open a Freeform board, tap an empty spot, and choose Paste.\n2. Come back here and tap Copy Transcript Next, then paste again.\n\nKeep this message open while you paste. Freeform can't paste text and images together, so the transcript is copied second.")
            } else {
                Text("Copied \(copiedSummary ?? "") to the clipboard. Open a Freeform board, tap an empty spot, and choose Paste.")
            }
        }
        .alert("Transcript Copied", isPresented: $isShowingTranscriptCopied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Paste it onto the same Freeform board; it arrives as a text box that fits the whole transcript.")
        }
        .task {
            if lecture.studyGuide == nil, LectureAnalyzer.unavailableMessage == nil {
                await analyzer.analyze(lecture)
            }
        }
    }

    private func copySections() {
        do {
            let contents = try BoardExporter.clipboardContents(for: lecture)
            guard !contents.isEmpty else {
                copyTranscriptNext()
                return
            }
            UIPasteboard.general.setItems(contents.pasteboardItems)

            var parts: [String] = []
            if !contents.sections.isEmpty {
                parts.append(contents.sections.count == 1 ? "1 section" : "\(contents.sections.count) sections")
            }
            if !contents.photos.isEmpty {
                parts.append(contents.photos.count == 1 ? "1 photo" : "\(contents.photos.count) photos")
            }
            copiedSummary = parts.joined(separator: " and ")
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func copyTranscriptNext() {
        guard let item = BoardExporter.transcriptItem(for: lecture) else { return }
        UIPasteboard.general.setItems([item])
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            isShowingTranscriptCopied = true
        }
    }

    private var isShowingCopiedAlert: Binding<Bool> {
        Binding {
            copiedSummary != nil
        } set: { isPresented in
            if !isPresented { copiedSummary = nil }
        }
    }

    private var isShowingExportError: Binding<Bool> {
        Binding {
            exportError != nil
        } set: { isPresented in
            if !isPresented { exportError = nil }
        }
    }

    private var titleBinding: Binding<String> {
        Binding {
            lecture.title
        } set: { newValue in
            lecture.title = newValue
            lecture.titleIsAutomatic = false
        }
    }

    @ViewBuilder
    private var content: some View {
        if tab == .transcript {
            SpeakerTranscriptView(lecture: lecture)
        } else if tab == .photos {
            LecturePhotosView(lecture: lecture)
        } else if analyzer.isWorking {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(analyzer.progressMessage)
                    .font(.headline)
                Text("Everything is processed on this iPad.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if let message = analyzer.errorMessage ?? LectureAnalyzer.unavailableMessage,
                  !hasAnyNotes {
            ContentUnavailableView {
                Label("Couldn't Create Notes", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await analyzer.analyze(lecture) }
                }
                .disabled(LectureAnalyzer.unavailableMessage != nil)
            }
        } else {
            studyContent
        }
    }

    @ViewBuilder
    private var studyContent: some View {
        switch tab {
        case .summary:
            if let summary = lecture.summary {
                SummaryView(summary: summary, photos: lecture.sortedPhotos)
            } else {
                missingSection("Summary", noun: "summary")
            }
        case .flowchart:
            if let flowchart = lecture.studyGuide?.flowchart {
                FlowchartView(flowchart: flowchart)
            } else {
                missingSection("Flowchart", noun: "flowchart")
            }
        case .mindMap:
            if let mindMap = lecture.studyGuide?.mindMap {
                MindMapView(mindMap: mindMap)
            } else {
                missingSection("Mind Map", noun: "mind map")
            }
        case .flashcards:
            if let cards = lecture.studyGuide?.cards {
                FlashcardsView(cards: cards)
            } else {
                missingSection("Flashcards", noun: "set of flashcards")
            }
        case .quiz:
            if let quiz = lecture.studyGuide?.quiz {
                QuizView(quiz: quiz)
                    .id(lecture.studyGuideData)
            } else {
                missingSection("Quiz", noun: "quiz")
            }
        case .transcript, .photos:
            EmptyView()
        }
    }

    private var hasAnyNotes: Bool {
        lecture.summary != nil || (lecture.studyGuide.map { $0 != StudyGuide() } ?? false)
    }

    private func missingSection(_ title: String, noun: String) -> some View {
        ContentUnavailableView {
            Label(
                lecture.studyGuide == nil ? "No Study Notes Yet" : "No \(title) for This Lecture",
                systemImage: "sparkles"
            )
        } description: {
            if lecture.studyGuide != nil {
                Text("The on-device model couldn't create a \(noun) from this transcript. Regenerating sometimes helps.")
            }
        } actions: {
            Button(lecture.studyGuide == nil ? "Generate Notes" : "Regenerate") {
                Task { await analyzer.analyze(lecture) }
            }
        }
    }
}
