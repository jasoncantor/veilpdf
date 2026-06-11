import Foundation

struct RedactionSettings {
    var detectorMode: DetectorMode = .gliner
    var modelIdentifier = "urchade/gliner_multi_pii-v1"
    var threshold = 0.50
    var pythonPath = ""
    var allowRegexFallback = true
    var outputFolder: URL?

    var labels: [String] = [
        "person",
        "organization",
        "email",
        "phone number",
        "address",
        "social security number",
        "credit card number",
        "bank account number",
        "date of birth",
        "passport number",
        "driver license",
        "medical record number",
        "tax identification number",
        "ip address",
        "username",
        "password",
        "url",
    ]
}
