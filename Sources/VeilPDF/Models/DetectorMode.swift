import Foundation

enum DetectorMode: String, CaseIterable, Identifiable, Codable {
    case gliner
    case regex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gliner:
            "GLiNER-PII"
        case .regex:
            "Regex Test Mode"
        }
    }
}
