// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SuperVolume",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.6.4")
    ],
    targets: [
        .executableTarget(
            name: "SuperVolume",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/SuperVolume",
            // Sparkle.framework est copié dans Contents/Frameworks par build.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
