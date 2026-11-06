// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NightPayCheckCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "NightPayCheckCore", targets: ["NightPayCheckCore"])],
    targets: [
        .target(
            name: "NightPayCheckCore",
            path: "NightPayCheck",
            exclude: [
                "NightPayCheckApp.swift", "ContentView.swift", "Features", "Assets.xcassets",
                "Services/NightServices.swift",
            ],
            sources: ["Domain", "Engines", "Persistence"]
        ),
        .testTarget(
            name: "NightPayCheckCoreTests",
            dependencies: ["NightPayCheckCore"],
            path: "NightPayCheckTests"
        )
    ]
)
