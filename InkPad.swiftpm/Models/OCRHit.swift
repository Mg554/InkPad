import CoreGraphics
import Foundation

/// One line of handwriting read on the iPad, with where it is on its page.
/// Rectangles are fractions of the page (0…1, top-left origin), so they stay
/// correct at any zoom or page size.
struct OCRHit: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String {
        let place = "\(page):\(x):\(y)"
        return place + ":" + text
    }
    var text: String
    var page: Int
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(text: String, page: Int, rect: CGRect) {
        self.text = text
        self.page = page
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.width)
        height = Double(rect.height)
    }

    var box: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

/// What is written to `ocr-hits.json`. Old notes without this file simply
/// have no hits; the plain recognized text still works as before.
struct OCRHitFile: Codable, Sendable {
    var readAt: TimeInterval
    var hits: [OCRHit]
}
