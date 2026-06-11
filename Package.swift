// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VeilPDF",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VeilPDF", targets: ["VeilPDF"])
    ],
    targets: [
        .executableTarget(
            name: "VeilPDF",
            path: "Sources/VeilPDF"
        )
    ]
)
