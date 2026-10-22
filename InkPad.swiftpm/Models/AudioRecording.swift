import Foundation

/// Audio recorded in a note, stored as `notes/<id>/audio/<file>`.
struct AudioRecording: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    /// File name inside the note's `audio` folder.
    let file: String
    /// When recording began, in seconds since 2001
    /// (`Date.timeIntervalSinceReferenceDate`). A number rather than a date:
    /// ISO 8601 dates drop the fractions of a second that matching ink to
    /// the audio relies on.
    let startTime: TimeInterval
    var duration: TimeInterval

    var startDate: Date { Date(timeIntervalSinceReferenceDate: startTime) }

    /// The span of time the recording covers; ink written in it plays back with it.
    var interval: DateInterval { DateInterval(start: startDate, duration: max(duration, 0)) }
}
