import SwiftUI

struct LectureDetailView: View {
    @Bindable var lecture: Lecture
    @State private var analyzer = LectureAnalyzer()
    @State private var tab: Tab = .summary

    enum Tab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case flowchart = "Flowchart"
        case mindMap = "Mind Map"
        case flashcards = "Flashcards"
        case quiz = "Quiz"
        case transcript = "Transcript"

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
                Button("Regenerate Notes", systemImage: "sparkles") {
                    Task { await analyzer.analyze(lecture) }
                }
                .disabled(analyzer.isWorking || LectureAnalyzer.unavailableMessage != nil)
            }
        }
        .task {
            // Generate study notes automatically the first time a lecture is opened.
            if lecture.studyGuide == nil, LectureAnalyzer.unavailableMessage == nil {
                await analyzer.analyze(lecture)
            }
        }
    }

    /// Renaming the lecture stops the AI from overwriting the title.
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
            TranscriptView(transcript: lecture.transcript)
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
                  lecture.studyGuide == nil {
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
                SummaryView(summary: summary)
            } else {
                missingNotes
            }
        case .flowchart:
            if let guide = lecture.studyGuide {
                FlowchartView(flowchart: guide.flowchart)
            } else {
                missingNotes
            }
        case .mindMap:
            if let guide = lecture.studyGuide {
                MindMapView(mindMap: guide.mindMap)
            } else {
                missingNotes
            }
        case .flashcards:
            if let guide = lecture.studyGuide {
                FlashcardsView(cards: guide.cards)
            } else {
                missingNotes
            }
        case .quiz:
            if let guide = lecture.studyGuide {
                QuizView(quiz: guide.quiz)
                    .id(lecture.studyGuideData)
            } else {
                missingNotes
            }
        case .transcript:
            EmptyView()
        }
    }

    private var missingNotes: some View {
        ContentUnavailableView {
            Label("No Study Notes Yet", systemImage: "sparkles")
        } actions: {
            Button("Generate Notes") {
                Task { await analyzer.analyze(lecture) }
            }
        }
    }
}

private struct TranscriptView: View {
    let transcript: String

    var body: some View {
        ScrollView {
            Text(transcript)
                .font(.body)
                .lineSpacing(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}
