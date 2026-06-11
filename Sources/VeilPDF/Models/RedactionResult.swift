import Foundation

struct RedactionResult: Decodable {
    let input: String
    let output: String
    let detector: String
    let redactions: Int
    let entities: Int
    let pages: Int
    let elapsedMs: Int
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case input
        case output
        case detector
        case redactions
        case entities
        case pages
        case elapsedMs = "elapsed_ms"
        case warnings
    }
}

struct RuntimeCheck: Decodable {
    let python: String
    let helper: String
    let pymupdfAvailable: Bool
    let glinerAvailable: Bool
    let defaultModel: String
    let errors: [String]

    enum CodingKeys: String, CodingKey {
        case python
        case helper
        case pymupdfAvailable = "pymupdf_available"
        case glinerAvailable = "gliner_available"
        case defaultModel = "default_model"
        case errors
    }
}
