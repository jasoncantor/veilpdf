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

struct RedactionSettings: Codable, Equatable {
    var detectorMode: DetectorMode = .gliner
    var modelIdentifier = "urchade/gliner_multi_pii-v1"
    var threshold = 0.50
    var pythonPath = ""
    var allowRegexFallback = true
    var outputFolder: URL?

    var labels: [String] = Self.defaultLabels

    static let labelGroups: [PIILabelGroup] = [
        PIILabelGroup(
            id: "identity",
            title: "Identity",
            labels: [
                PIILabelOption(id: "person", title: "Names"),
                PIILabelOption(id: "organization", title: "Organizations"),
                PIILabelOption(id: "date of birth", title: "Dates of birth"),
                PIILabelOption(id: "medical record number", title: "Medical record numbers"),
            ]
        ),
        PIILabelGroup(
            id: "contact",
            title: "Contact",
            labels: [
                PIILabelOption(id: "email", title: "Email addresses"),
                PIILabelOption(id: "phone number", title: "Phone numbers"),
                PIILabelOption(id: "address", title: "Street addresses"),
                PIILabelOption(id: "url", title: "URLs"),
                PIILabelOption(id: "ip address", title: "IP addresses"),
            ]
        ),
        PIILabelGroup(
            id: "government",
            title: "Government IDs",
            labels: [
                PIILabelOption(id: "social security number", title: "Social Security numbers"),
                PIILabelOption(id: "passport number", title: "Passport numbers"),
                PIILabelOption(id: "driver license", title: "Driver licenses"),
                PIILabelOption(id: "tax identification number", title: "Tax IDs"),
            ]
        ),
        PIILabelGroup(
            id: "financial",
            title: "Financial & Accounts",
            labels: [
                PIILabelOption(id: "credit card number", title: "Credit card numbers"),
                PIILabelOption(id: "bank account number", title: "Bank account numbers"),
                PIILabelOption(id: "username", title: "Usernames"),
                PIILabelOption(id: "password", title: "Passwords"),
            ]
        ),
    ]

    static var defaultLabels: [String] {
        labelGroups.flatMap { group in group.labels.map(\.id) }
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
