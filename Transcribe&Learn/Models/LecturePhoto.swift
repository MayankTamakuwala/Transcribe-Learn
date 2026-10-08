import Foundation
import SwiftData
import UIKit

@Model
final class LecturePhoto {
    @Attribute(.externalStorage) var imageData: Data
    var takenAt: Date
    var aiNotes: String?
    var lecture: Lecture?

    init(imageData: Data, takenAt: Date = .now) {
        self.imageData = imageData
        self.takenAt = takenAt
    }

    var image: UIImage? { UIImage(data: imageData) }
}

enum PhotoProcessing {
    static func preparedData(from image: UIImage, maxDimension: CGFloat = 2048) -> Data? {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
