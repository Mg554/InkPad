import Vision

/// Shared handwriting reading for the whole app. One tuned request
/// everywhere: accurate recognition with language correction, English and
/// Arabic where this iPad supports them.
enum InkOCR {
    /// A line of text read from an image, with where it is (0…1, y down).
    struct Line: Sendable {
        let text: String
        let box: CGRect
    }

    /// The languages to read: English and Arabic where this iPad supports them.
    static func languages(for request: VNRecognizeTextRequest) -> [String] {
        let wanted = ["en-US", "ar-SA", "ar"]
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let picked = wanted.filter { supported.contains($0) }
        return picked.isEmpty ? ["en-US"] : picked
    }

    /// A text request tuned for handwriting on paper.
    static func request() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = languages(for: request)
        return request
    }

    /// Lines of text in a picture, in reading order (top to bottom, then
    /// left to right within a row).
    static func lines(in image: CGImage) -> [Line] {
        let request = request()
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return []
        }
        let found: [Line] = (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            let box = observation.boundingBox
            // Vision's origin is bottom-left; ours is top-left.
            return Line(text: text, box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
        }
        return found.sorted { (a: Line, b: Line) in
            if abs(a.box.midY - b.box.midY) > min(a.box.height, b.box.height) * 0.5 { return a.box.midY < b.box.midY }
            return a.box.minX < b.box.minX
        }
    }

    /// Lines read from a picture of a region, with their boxes scaled from
    /// the picture (0…1) into the region's own coordinates.
    static func lines(in image: CGImage, mappedTo canvas: CGRect) -> [(text: String, rect: CGRect)] {
        lines(in: image).map { line in
            let rect = CGRect(
                x: canvas.minX + line.box.minX * canvas.width,
                y: canvas.minY + line.box.minY * canvas.height,
                width: line.box.width * canvas.width,
                height: line.box.height * canvas.height
            )
            return (line.text, rect)
        }
    }

    /// Plain text from lines, one line each.
    static func text(of lines: [Line]) -> String {
        lines.map(\.text).joined(separator: "\n")
    }

    /// The picture's text, one line each.
    static func text(in image: CGImage) -> String {
        text(of: lines(in: image))
    }
}
