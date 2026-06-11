import Foundation

struct PIILabelOption: Identifiable, Codable, Hashable {
    let id: String
    let title: String
}

struct PIILabelGroup: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let labels: [PIILabelOption]
}

enum AccelerationMode: String, CaseIterable, Codable, Identifiable {
    case automatic = "auto"
    case metal
    case cpu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            "Auto (Metal)"
        case .metal:
            "Metal"
        case .cpu:
            "CPU"
        }
    }
}

struct RedactionSettings: Codable, Equatable {
    static let defaultModelIdentifier = "knowledgator/gliner-pii-edge-v1.0"
    static let legacyDefaultModelIdentifiers = ["urchade/gliner_multi_pii-v1"]

    var detectorMode: DetectorMode = .gliner
    var modelIdentifier = Self.defaultModelIdentifier
    var accelerationMode: AccelerationMode = .automatic
    var threshold = 0.50
    var pythonPath = ""
    var allowRegexFallback = true
    var outputFolder: URL?

    var labels: [String] = Self.defaultLabels

    init() {}

    private enum CodingKeys: String, CodingKey {
        case detectorMode
        case modelIdentifier
        case accelerationMode
        case threshold
        case pythonPath
        case allowRegexFallback
        case outputFolder
        case labels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        detectorMode = try container.decodeIfPresent(DetectorMode.self, forKey: .detectorMode) ?? .gliner
        modelIdentifier = try container.decodeIfPresent(String.self, forKey: .modelIdentifier) ?? Self.defaultModelIdentifier
        accelerationMode = try container.decodeIfPresent(AccelerationMode.self, forKey: .accelerationMode) ?? .automatic
        threshold = try container.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.50
        pythonPath = try container.decodeIfPresent(String.self, forKey: .pythonPath) ?? ""
        allowRegexFallback = try container.decodeIfPresent(Bool.self, forKey: .allowRegexFallback) ?? true
        outputFolder = try container.decodeIfPresent(URL.self, forKey: .outputFolder)
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? Self.defaultLabels
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(detectorMode, forKey: .detectorMode)
        try container.encode(modelIdentifier, forKey: .modelIdentifier)
        try container.encode(accelerationMode, forKey: .accelerationMode)
        try container.encode(threshold, forKey: .threshold)
        try container.encode(pythonPath, forKey: .pythonPath)
        try container.encode(allowRegexFallback, forKey: .allowRegexFallback)
        try container.encodeIfPresent(outputFolder, forKey: .outputFolder)
        try container.encode(labels, forKey: .labels)
    }

    static let labelGroups: [PIILabelGroup] = [
        PIILabelGroup(
            id: "identity",
            title: "Identity",
            labels: [
                PIILabelOption(id: "name", title: "Names"),
                PIILabelOption(id: "organization", title: "Organizations"),
                PIILabelOption(id: "dob", title: "Dates of birth"),
                PIILabelOption(id: "medical record number", title: "Medical record numbers"),
            ]
        ),
        PIILabelGroup(
            id: "contact",
            title: "Contact",
            labels: [
                PIILabelOption(id: "email address", title: "Email addresses"),
                PIILabelOption(id: "phone number", title: "Phone numbers"),
                PIILabelOption(id: "location address", title: "Street addresses"),
                PIILabelOption(id: "url", title: "URLs"),
                PIILabelOption(id: "ip address", title: "IP addresses"),
            ]
        ),
        PIILabelGroup(
            id: "government",
            title: "Government IDs",
            labels: [
                PIILabelOption(id: "ssn", title: "Social Security numbers"),
                PIILabelOption(id: "passport number", title: "Passport numbers"),
                PIILabelOption(id: "driver license", title: "Driver licenses"),
                PIILabelOption(id: "tax identification number", title: "Tax IDs"),
            ]
        ),
        PIILabelGroup(
            id: "financial",
            title: "Financial & Accounts",
            labels: [
                PIILabelOption(id: "credit card", title: "Credit card numbers"),
                PIILabelOption(id: "bank account", title: "Bank account numbers"),
                PIILabelOption(id: "username", title: "Usernames"),
                PIILabelOption(id: "password", title: "Passwords"),
            ]
        ),
    ]

    static var defaultLabels: [String] {
        labelGroups.flatMap { group in group.labels.map(\.id) }
    }

    mutating func migrateLegacyLabels() {
        let legacyMap = [
            "person": "name",
            "email": "email address",
            "address": "location address",
            "social security number": "ssn",
            "credit card number": "credit card",
            "bank account number": "bank account",
            "date of birth": "dob",
        ]
        labels = labels.map { legacyMap[$0] ?? $0 }
        normalizeLabels()
    }

    var selectedLabelSummary: String {
        "\(labels.count) of \(Self.defaultLabels.count) selected"
    }

    mutating func setLabel(_ label: String, isEnabled: Bool) {
        guard Self.defaultLabels.contains(label) else { return }
        if isEnabled {
            guard !labels.contains(label) else { return }
            labels.append(label)
            normalizeLabels()
        } else if labels.count > 1 {
            labels.removeAll { $0 == label }
        }
    }

    mutating func enableAllLabels() {
        labels = Self.defaultLabels
    }

    mutating func resetLabels() {
        labels = Self.defaultLabels
    }

    mutating func normalizeLabels() {
        let selected = Set(labels)
        labels = Self.defaultLabels.filter { selected.contains($0) }
        if labels.isEmpty {
            labels = Self.defaultLabels
        }
    }
}
