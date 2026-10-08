import SwiftUI

struct RecordingResult {
    struct Photo {
        var data: Data
        var takenAt: Date
    }

    var segments: [TranscriptSegment]
    var duration: TimeInterval
    var photos: [Photo]
}

struct RecordingView: View {
    let onFinish: (RecordingResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var transcriber = LiveTranscriber()
    @State private var photos: [RecordingResult.Photo] = []
    @State private var isConfirmingDiscard = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                transcriptView
                if !photos.isEmpty {
                    Divider()
                    photoStrip
                }
            }
            .navigationTitle("New Lecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if transcriber.state == .recording {
                        Button("Discard", role: .destructive) {
                            isConfirmingDiscard = true
                        }
                    } else {
                        Button("Cancel") { dismiss() }
                            .disabled(transcriber.state != .idle)
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    AddPhotoButtons { data in
                        photos.append(RecordingResult.Photo(data: data, takenAt: .now))
                    }
                    .disabled(transcriber.state == .finishing)
                }
            }
            .confirmationDialog(
                "Discard this recording?",
                isPresented: $isConfirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard Recording", role: .destructive) {
                    Task {
                        await transcriber.stop()
                        dismiss()
                    }
                }
            } message: {
                Text("The transcript and photos so far will be lost.")
            }
            .safeAreaInset(edge: .bottom) {
                controlButton
            }
        }
        .interactiveDismissDisabled()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 12, height: 12)
                .opacity(transcriber.state == .recording && !transcriber.isInterrupted ? 1 : 0.6)
            Text(statusText)
                .font(.headline)
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(Duration.seconds(transcriber.elapsed), format: .time(pattern: .hourMinuteSecond))
                    .font(.title2.monospacedDigit())
            }
        }
        .padding()
    }

    private var transcriptView: some View {
        ScrollView {
            Group {
                if let error = transcriber.errorMessage, transcriber.state == .idle {
                    ContentUnavailableView(
                        "Can't Record",
                        systemImage: "mic.slash",
                        description: Text(error)
                    )
                } else if transcriber.fullText.isEmpty {
                    Text(placeholderText)
                        .foregroundStyle(.secondary)
                } else {
                    LiveTranscriptView(segments: transcriber.segments, volatileText: transcriber.volatileText)
                }
            }
            .font(.title3)
            .lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .defaultScrollAnchor(.bottom)
    }

    private var photoStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                    if let image = UIImage(data: photo.data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contextMenu {
                                Button("Remove Photo", systemImage: "trash", role: .destructive) {
                                    photos.remove(at: index)
                                }
                            }
                            .accessibilityLabel("Photo \(index + 1)")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var controlButton: some View {
        Group {
            switch transcriber.state {
            case .idle, .preparing:
                Button {
                    Task { await transcriber.start() }
                } label: {
                    Label(transcriber.state == .preparing ? "Starting…" : "Start Recording", systemImage: "mic.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: 360)
                        .padding(.vertical, 8)
                }
                .tint(.accentColor)
                .disabled(transcriber.state == .preparing)

            case .recording, .finishing:
                Button {
                    Task {
                        let duration = transcriber.elapsed
                        let segments = await transcriber.stop()
                        if !segments.isEmpty || !photos.isEmpty {
                            onFinish(RecordingResult(segments: segments, duration: duration, photos: photos))
                        }
                        dismiss()
                    }
                } label: {
                    Label(transcriber.state == .finishing ? "Finishing…" : "Stop & Save", systemImage: "stop.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: 360)
                        .padding(.vertical, 8)
                }
                .tint(.red)
                .disabled(transcriber.state == .finishing)
            }
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }

    private var indicatorColor: Color {
        switch transcriber.state {
        case .recording: transcriber.isInterrupted ? .orange : .red
        default: .secondary
        }
    }

    private var statusText: String {
        switch transcriber.state {
        case .idle: "Ready"
        case .preparing: "Preparing on-device transcription…"
        case .recording: transcriber.isInterrupted ? "Paused by the system — resumes automatically" : "Recording"
        case .finishing: "Finishing transcript…"
        }
    }

    private var placeholderText: String {
        switch transcriber.state {
        case .idle: "Tap Start Recording when the lecture begins. Recording continues if you switch apps or lock your iPad, and only stops when you tap Stop. Use the camera button to photograph slides or the whiteboard."
        case .preparing: "Getting ready…"
        default: "Listening…"
        }
    }
}
