# Transcribe&Learn

An iPad app that records your lectures, transcribes them live, figures out who's talking, and turns the whole thing into study notes: a summary, a flowchart, a mind map, flashcards, and a quiz.

Everything runs on the iPad. Transcription uses Apple's Speech framework and the notes come from the Apple Intelligence on-device model, so nothing is uploaded anywhere and there are no API keys to set up.

## Features

**Recording**
- Live transcript while the lecture is happening
- Keeps recording when the iPad is locked or you switch apps
- Picks back up on its own after phone calls, Siri, or plugging in headphones. It only stops when you tap Stop
- Snap photos of slides or the whiteboard mid-lecture

**Speakers**
- Splits the transcript into "Person 1", "Person 2", etc. based on voice
- Rename speakers (e.g. "Professor"), move a passage or a single sentence to someone else
- If the grouping is off, tell it how many people spoke and it re-sorts everything

**Study notes**
- Summary with key points and any assignments or exam hints that were mentioned
- Flowchart of the main process or argument
- Mind map of the topics
- Flashcards and a glossary of key terms
- A multiple-choice quiz that marks your answers
- Photos get read too, and what's on them is folded into the notes

All of it is drawn in a hand-sketched notebook style.

**Export**
- Copy everything to a Freeform board: each section as an image, plus the photos, then the transcript as text

## Requirements

- iPad with Apple Intelligence support, with Apple Intelligence turned on
- iPadOS 27 or later
- Xcode 27 or later

Recording and transcription work without Apple Intelligence; the study notes don't.

## Getting started

```bash
git clone https://github.com/MayankTamakuwala/Transcribe-Learn.git
cd Transcribe-Learn
open "Transcribe&Learn.xcodeproj"
```

1. Select the **Transcribe&Learn** target, open **Signing & Capabilities**, and choose your own team.
2. If the bundle identifier clashes with one you already use, change it.
3. Run it on a real iPad. The camera isn't available in the simulator, and the on-device model may not be either.

The first time you record, iPadOS may download the speech model for your language, which takes a minute.

## How it works

1. **Transcription:** `SpeechAnalyzer` streams microphone audio into a `SpeechTranscriber` and returns text as it's spoken.
2. **Speaker detection:** the Speech framework doesn't identify speakers, so the app measures each sentence's voice (MFCCs and pitch, computed with Accelerate) and groups similar voices together. When recording ends it runs a cleanup pass over the whole lecture.
3. **Notes:** the on-device model only fits about 4,000 tokens at once, so long transcripts are condensed in chunks first. Each kind of study material is then generated on its own. If the model refuses a topic (it's cautious about things like war or medicine), the app retries with plain-text output and parses that instead.

## Project structure

```
Transcribe&Learn/
├── Models/       SwiftData models (Lecture, LecturePhoto) and the study note types
├── Services/     Live transcription, voice features, speaker clustering, AI analysis
└── Views/        Recording, transcript, photos, study tabs, sketch drawing, Freeform export
```

## Known limitations

- Audio isn't saved, only the transcript, so you can't play a lecture back
- Speaker detection is a heuristic and gets confused by similar voices or a noisy room
- The note quality depends on the on-device model, which is small. Regenerating sometimes gives better results
- iPad only for now
