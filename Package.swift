// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Risper",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Risper", targets: ["Risper"])
    ],
    targets: [
        .executableTarget(
            name: "Risper",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
