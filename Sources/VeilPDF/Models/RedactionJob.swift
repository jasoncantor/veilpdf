import Foundation

enum RedactionStatus: String, Codable {
    case queued
    case running
    case complete
    case failed

    var title: String {
        switch self {
        case .queued:
            "Queued"
        case .running:
            "Running"
        case .complete:
            "Complete"
        case .failed:
            "Failed"
        }
    }
}

struct RedactionJob: Identifiable, Equatable {
    let id: UUID
    var inputURL: URL
    var outputURL: URL
    var status: RedactionStatus
    var detector: String
    var redactionCount: Int
    var message: String
    var createdAt: Date
    var completedAt: Date?

    init(inputURL: URL, outputURL: URL) {
        self.id = UUID()
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.status = .queued
        self.detector = ""
        self.redactionCount = 0
        self.message = "Waiting"
        self.createdAt = Date()
        self.completedAt = nil
    }
}
