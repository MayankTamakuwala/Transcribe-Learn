import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct AddPhotoButtons: View {
    let onAdd: (Data) -> Void

    @State private var isShowingCamera = false
    @State private var libraryItems: [PhotosPickerItem] = []

    var body: some View {
        if CameraPicker.isAvailable {
            Button("Take Photo", systemImage: "camera") {
                isShowingCamera = true
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker { image in
                    if let data = PhotoProcessing.preparedData(from: image) {
                        onAdd(data)
                    }
                }
                .ignoresSafeArea()
            }
        }

        PhotosPicker(selection: $libraryItems, matching: .images) {
            Label("Add from Photos", systemImage: "photo.on.rectangle")
        }
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let prepared = PhotoProcessing.preparedData(from: image) {
                        onAdd(prepared)
                    }
                }
                libraryItems = []
            }
        }
    }
}

struct LecturePhotosView: View {
    let lecture: Lecture
    @Environment(\.modelContext) private var modelContext
    @State private var selectedPhoto: LecturePhoto?

    var body: some View {
        let photos = lecture.sortedPhotos
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Photos are read by the on-device model and used to enrich the summary, flowchart, and mind map. Regenerate notes after adding new ones.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    AddPhotoButtons { data in
                        let photo = LecturePhoto(imageData: data)
                        photo.lecture = lecture
                        modelContext.insert(photo)
                    }
                    .buttonStyle(.bordered)
                }

                if photos.isEmpty {
                    ContentUnavailableView(
                        "No Photos",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Take photos of slides or the whiteboard to give the AI more to work with.")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        ForEach(photos) { photo in
                            PhotoThumbnail(photo: photo)
                                .onTapGesture { selectedPhoto = photo }
                                .contextMenu {
                                    Button("Delete Photo", systemImage: "trash", role: .destructive) {
                                        modelContext.delete(photo)
                                    }
                                }
                        }
                    }
                }
            }
            .padding()
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoViewer(photos: photos, startingAt: photo)
        }
    }
}

struct PhotoThumbnail: View {
    let photo: LecturePhoto

    var body: some View {
        Color.secondary.opacity(0.1)
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if let image = photo.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomLeading) {
                Text(photo.takenAt, format: .dateTime.hour().minute())
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
            }
            .accessibilityElement()
            .accessibilityLabel("Photo taken at \(photo.takenAt.formatted(date: .omitted, time: .shortened))")
            .accessibilityAddTraits(.isButton)
    }
}

struct PhotoViewer: View {
    let photos: [LecturePhoto]
    @State private var selection: PersistentIdentifier
    @State private var showsNotes = false
    @State private var isReading = false
    @Environment(\.dismiss) private var dismiss

    init(photos: [LecturePhoto], startingAt photo: LecturePhoto) {
        self.photos = photos
        _selection = State(initialValue: photo.persistentModelID)
    }

    private var current: LecturePhoto? {
        photos.first { $0.persistentModelID == selection }
    }

    private var currentNotes: String? {
        guard let notes = current?.aiNotes else { return nil }
        let cleaned = PlainTextFormats.cleanNotes(notes)
        return cleaned.isEmpty ? nil : cleaned
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(photos) { photo in
                    ZoomableImage(image: photo.image, label: accessibilityLabel(for: photo))
                        .tag(photo.persistentModelID)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) {
            if showsNotes {
                notesPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack {
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.title3.bold())
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())

            Spacer()

            if let current, let index = photos.firstIndex(where: { $0.persistentModelID == current.persistentModelID }) {
                VStack(spacing: 2) {
                    if photos.count > 1 {
                        Text("Photo \(index + 1) of \(photos.count)")
                            .font(.headline)
                    }
                    Text(current.takenAt, format: .dateTime.month().day().hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()

            Button("What the AI Saw", systemImage: showsNotes ? "sparkles.rectangle.stack.fill" : "sparkles") {
                withAnimation(.snappy) { showsNotes.toggle() }
            }
            .labelStyle(.iconOnly)
            .font(.title3.bold())
            .padding(12)
            .background(.ultraThinMaterial, in: Circle())
        }
        .padding()
        .environment(\.colorScheme, .dark)
    }

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("What the AI saw", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                if isReading {
                    ProgressView()
                } else {
                    Button(currentNotes == nil ? "Read Photo" : "Read Again", systemImage: "arrow.clockwise") {
                        Task { await readCurrentPhoto() }
                    }
                    .font(.subheadline.bold())
                    .disabled(LectureAnalyzer.unavailableMessage != nil)
                }
            }
            ScrollView {
                Group {
                    if isReading {
                        Text("Reading the photo…")
                            .foregroundStyle(.secondary)
                    } else if let notes = currentNotes {
                        Text(notes)
                            .textSelection(.enabled)
                    } else {
                        Text("This photo hasn't been read yet. It's read automatically when you generate notes, or tap Read Photo.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: 700)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
        .padding(.bottom, 24)
        .environment(\.colorScheme, .dark)
    }

    private func readCurrentPhoto() async {
        guard let photo = current, let image = photo.image else { return }
        isReading = true
        defer { isReading = false }
        if let notes = await LectureAnalyzer.readPhoto(image) {
            photo.aiNotes = notes
        }
    }

    private func accessibilityLabel(for photo: LecturePhoto) -> String {
        "Photo taken at \(photo.takenAt.formatted(date: .omitted, time: .shortened))"
    }
}

struct ZoomableImage: UIViewRepresentable {
    let image: UIImage?
    var label: String = "Photo"

    func makeUIView(context: Context) -> ZoomingScrollView {
        let view = ZoomingScrollView()
        view.image = image
        view.imageAccessibilityLabel = label
        return view
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        if view.image !== image {
            view.image = image
        }
        view.imageAccessibilityLabel = label
    }
}

final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var lastBoundsSize: CGSize = .zero

    var image: UIImage? {
        get { imageView.image }
        set {
            imageView.image = newValue
            lastBoundsSize = .zero
            setNeedsLayout()
        }
    }

    var imageAccessibilityLabel: String? {
        get { imageView.accessibilityLabel }
        set { imageView.accessibilityLabel = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 6
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear

        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) isn't supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastBoundsSize, bounds.width > 0, bounds.height > 0 {
            lastBoundsSize = bounds.size
            zoomScale = 1
            imageView.frame = CGRect(origin: .zero, size: fittedSize())
            contentSize = imageView.frame.size
        }
        centerImage()
    }

    private func fittedSize() -> CGSize {
        guard let size = imageView.image?.size, size.width > 0, size.height > 0 else { return bounds.size }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func centerImage() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let scale: CGFloat = 3
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}
