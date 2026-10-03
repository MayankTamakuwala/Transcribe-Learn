import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Lecture.createdAt, order: .reverse) private var lectures: [Lecture]

    @State private var selection: Lecture?
    @State private var isRecording = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(lectures) { lecture in
                    NavigationLink(value: lecture) {
                        LectureRow(lecture: lecture)
                    }
                }
                .onDelete(perform: deleteLectures)
            }
            .navigationTitle("Lectures")
            .overlay {
                if lectures.isEmpty {
                    ContentUnavailableView(
                        "No Lectures Yet",
                        systemImage: "waveform",
                        description: Text("Tap the record button to transcribe your first lecture.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Record Lecture", systemImage: "record.circle") {
                        isRecording = true
                    }
                }
            }
        } detail: {
            if let selection {
                LectureDetailView(lecture: selection)
                    .id(selection.id)
            } else {
                ContentUnavailableView(
                    "Select a Lecture",
                    systemImage: "text.book.closed",
                    description: Text("Choose a lecture or record a new one.")
                )
            }
        }
        .fullScreenCover(isPresented: $isRecording) {
            RecordingView { transcript, duration in
                saveLecture(transcript: transcript, duration: duration)
            }
        }
    }

    private func saveLecture(transcript: String, duration: TimeInterval) {
        let lecture = Lecture(createdAt: .now - duration, duration: duration, transcript: transcript)
        modelContext.insert(lecture)
        selection = lecture
    }

    private func deleteLectures(at offsets: IndexSet) {
        for index in offsets {
            let lecture = lectures[index]
            if selection == lecture {
                selection = nil
            }
            modelContext.delete(lecture)
        }
    }
}

private struct LectureRow: View {
    let lecture: Lecture

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lecture.title)
                .font(.headline)
                .lineLimit(2)
            HStack {
                Text(lecture.createdAt, format: .dateTime.month().day().hour().minute())
                Text("·")
                Text(Duration.seconds(lecture.duration), format: .time(pattern: .hourMinuteSecond))
                if lecture.studyGuide != nil {
                    Image(systemName: "sparkles")
                        .accessibilityLabel("Study notes ready")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Lecture.self, inMemory: true)
}
