// swift-tools-version: 5.7.1
import PackageDescription

let package = Package(
    name: "ATLAS",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "ATLAS",
            path: ".",
            exclude: [
                "ATLAS.entitlements",
                "Sources/ATLAS/Assets.xcassets"
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
                .copy("Resources/TitanMemory")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
