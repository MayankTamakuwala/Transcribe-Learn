import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Lecture.createdAt, order: .reverse) private var lectures: [Lecture]

    @State private var selection: Lecture?
    @State private var isRecording = false
    @State private var renamingLecture: Lecture?
    @State private var newTitle = ""
    @State private var detailsLecture: Lecture?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(lectures) { lecture in
                    NavigationLink(value: lecture) {
                        LectureRow(lecture: lecture)
                    }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") {
                            newTitle = lecture.title
                            renamingLecture = lecture
                        }
                        Button("Details", systemImage: "info.circle") {
                            detailsLecture = lecture
                        }
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
            RecordingView { result in
                saveLecture(result)
            }
        }
        .alert("Rename Lecture", isPresented: isRenaming) {
            TextField("Title", text: $newTitle)
            Button("Save") { saveTitle() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $detailsLecture) { lecture in
            LectureDetailsSheet(lecture: lecture)
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding {
            renamingLecture != nil
        } set: { isPresented in
            if !isPresented { renamingLecture = nil }
        }
    }

    private func saveTitle() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lecture = renamingLecture, !trimmed.isEmpty {
            lecture.title = trimmed
            lecture.titleIsAutomatic = false
        }
        renamingLecture = nil
    }

    private func saveLecture(_ result: RecordingResult) {
        let lecture = Lecture(createdAt: .now - result.duration, duration: result.duration)
        lecture.segments = result.segments
        modelContext.insert(lecture)
        for captured in result.photos {
            let photo = LecturePhoto(imageData: captured.data, takenAt: captured.takenAt)
            photo.lecture = lecture
            modelContext.insert(photo)
        }
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
                if !lecture.photos.isEmpty {
                    Image(systemName: "photo")
                        .accessibilityLabel("Has photos")
                }
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

private struct LectureDetailsSheet: View {
    let lecture: Lecture
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Recorded") {
                    LabeledContent("Date", value: lecture.createdAt.formatted(date: .complete, time: .omitted))
                    LabeledContent("Started", value: lecture.createdAt.formatted(date: .omitted, time: .standard))
                    LabeledContent("Ended", value: (lecture.createdAt + lecture.duration).formatted(date: .omitted, time: .standard))
                    LabeledContent("Length") {
                        Text(Duration.seconds(lecture.duration), format: .time(pattern: .hourMinuteSecond))
                    }
                }
                Section("Content") {
                    LabeledContent("Words", value: lecture.transcript.split(whereSeparator: \.isWhitespace).count.formatted())
                    let speakers = Set(lecture.segments.map(\.speaker)).count
                    if speakers > 0 {
                        LabeledContent("Speakers", value: speakers.formatted())
                    }
                    LabeledContent("Photos", value: lecture.photos.count.formatted())
                    LabeledContent("Study notes", value: lecture.studyGuide == nil ? "Not generated" : "Ready")
                }
            }
            .navigationTitle(lecture.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Lecture.self, LecturePhoto.self], inMemory: true)
}
