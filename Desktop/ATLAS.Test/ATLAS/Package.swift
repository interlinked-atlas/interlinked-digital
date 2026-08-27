// swift-tools-version: 5.7.1
import PackageDescription

let package = Package(
    name: "ATLAS",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "ATLAS",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: ".",
            exclude: [
                "ATLAS.entitlements",
                "Sources/ATLAS/Assets.xcassets",
                "Tests"
            ],
            sources: [
                "Sources/ATLAS",
                "Core",
                "Engine",
                "UI"
            ],
            resources: [
                .copy("AtlasResources/Add Library for macOS v4.app"),
                .copy("AtlasResources/ATLASLogo.png"),
                .copy("AtlasResources/ATLAS.png"),
                .copy("AtlasResources/AppIcon.icns"),
                .copy("AtlasResources/Bezmiar-Regular.otf"),
                .copy("AtlasResources/SF Intellivised.ttf"),
                .copy("AtlasResources/atlas-splash.mp4"),
                .copy("AtlasResources/atlas-splash-light.mp4"),
                .copy("Resources/TitanMemory")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../lib"])
            ]
        ),
        .testTarget(
            name: "RecoveryKitTests",
            dependencies: [],
            path: "Tests/RecoveryKitTests"
        )
    ]
)
