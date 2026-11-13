// swift-tools-version:5.10
// Command-line build of AsterNUP (works with Xcode or the Command Line Tools alone).
// The Xcode project (project.yml → AsterNUP.xcodeproj) compiles the same sources.
import PackageDescription

let package = Package(
    name: "AsterNUP",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AsterNUP",
            path: "Sources/AsterNUP",
            linkerSettings: [
                .linkedFramework("GameController"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
