import SwiftUI

enum SpeakerStyle {
    private static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown]

    static func color(for speaker: Int) -> Color {
        palette[(max(speaker, 1) - 1) % palette.count]
    }
}

struct SpeakerTranscriptView: View {
    @Bindable var lecture: Lecture
    @State private var renamingSpeaker: Int?
    @State private var newName = ""
    @State private var didCopy = false

    var body: some View {
        let segments = lecture.segments
        if segments.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Spacer()
                        copyButton
                    }
                    Text(lecture.transcript)
                        .font(.body)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
        } else {
            let speakers = Array(Set(segments.map(\.speaker))).sorted()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    toolbar(speakers: speakers)
                    ForEach(TranscriptFormatting.turns(from: segments)) { turn in
                        turnView(turn, speakers: speakers)
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .alert("Rename Speaker", isPresented: isRenaming) {
                TextField("Name", text: $newName)
                Button("Save") { saveName() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("For example \"Teacher\" or a classmate's name.")
            }
        }
    }

    private func toolbar(speakers: [Int]) -> some View {
        HStack(spacing: 12) {
            Text("\(speakers.count) \(speakers.count == 1 ? "speaker" : "speakers") detected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Section("How many people spoke?") {
                    ForEach(1...6, id: \.self) { count in
                        Button(count == 1 ? "1 person" : "\(count) people") {
                            regroup(into: count)
                        }
                    }
                }
            } label: {
                Label("Re-detect Speakers", systemImage: "person.2.wave.2")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            copyButton
        }
    }

    private var copyButton: some View {
        Button {
            guard let item = BoardExporter.transcriptItem(for: lecture) else { return }
            UIPasteboard.general.setItems([item])
            withAnimation { didCopy = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { didCopy = false }
            }
        } label: {
            Label(didCopy ? "Copied" : "Copy Transcript", systemImage: didCopy ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.bordered)
        .disabled(!BoardExporter.hasTranscript(lecture))
        .accessibilityHint("Copies the whole transcript as text to paste into Freeform or another app")
    }

    private func turnView(_ turn: SpeakerTurn, speakers: [Int]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Menu {
                Section("This passage was spoken by") {
                    speakerChoices(speakers: speakers) { speaker in
                        reassign(turn.segments.map(\.id), to: speaker)
                    }
                }
                Button("Rename \(lecture.name(forSpeaker: turn.speaker))…", systemImage: "pencil") {
                    newName = lecture.speakerNames[turn.speaker] ?? ""
                    renamingSpeaker = turn.speaker
                }
            } label: {
                Text(lecture.name(forSpeaker: turn.speaker))
                    .font(.subheadline.bold())
                    .foregroundStyle(SpeakerStyle.color(for: turn.speaker))
                    .lineLimit(1)
                    .frame(width: 110, alignment: .leading)
            }
            .accessibilityHint("Change who said this, or rename the speaker")

            VStack(alignment: .leading, spacing: 6) {
                ForEach(turn.segments) { segment in
                    Text(segment.text)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Section("This sentence was spoken by") {
                                speakerChoices(speakers: speakers) { speaker in
                                    reassign([segment.id], to: speaker)
                                }
                            }
                            Button("Copy", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = segment.text
                            }
                        }
                }
            }
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(SpeakerStyle.color(for: turn.speaker))
                .frame(width: 3)
        }
    }

    @ViewBuilder
    private func speakerChoices(speakers: [Int], action: @escaping (Int) -> Void) -> some View {
        ForEach(speakers, id: \.self) { speaker in
            Button(lecture.name(forSpeaker: speaker)) { action(speaker) }
        }
        Button("New Speaker", systemImage: "person.badge.plus") {
            action((speakers.max() ?? 0) + 1)
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding {
            renamingSpeaker != nil
        } set: { isPresented in
            if !isPresented { renamingSpeaker = nil }
        }
    }

    private func saveName() {
        guard let speaker = renamingSpeaker else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        var names = lecture.speakerNames
        names[speaker] = trimmed.isEmpty ? nil : trimmed
        lecture.speakerNames = names
        renamingSpeaker = nil
    }

    private func reassign(_ ids: [UUID], to speaker: Int) {
        let ids = Set(ids)
        lecture.segments = lecture.segments.map { segment in
            var segment = segment
            if ids.contains(segment.id) { segment.speaker = speaker }
            return segment
        }
    }

    private func regroup(into count: Int) {
        lecture.segments = SpeakerClusterer.regroup(lecture.segments, speakerCount: count)
        lecture.speakerNames = [:]
    }
}

struct LiveTranscriptView: View {
    let segments: [TranscriptSegment]
    let volatileText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(TranscriptFormatting.turns(from: segments)) { turn in
                VStack(alignment: .leading, spacing: 4) {
                    Text(TranscriptFormatting.defaultName(for: turn.speaker))
                        .font(.subheadline.bold())
                        .foregroundStyle(SpeakerStyle.color(for: turn.speaker))
                    Text(turn.text)
                }
            }
            if !volatileText.isEmpty {
                Text(volatileText)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
