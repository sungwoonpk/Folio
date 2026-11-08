// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NoteCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NoteCore", targets: ["NoteCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "NoteCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "NoteCoreTests", dependencies: ["NoteCore"]),
    ]
)
