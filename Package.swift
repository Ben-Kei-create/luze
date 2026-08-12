// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LuzeCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "LuzeCore", targets: ["LuzeCore"])],
    targets: [
        .target(
            name: "LuzeCore",
            path: "luze",
            exclude: ["AppStore.swift", "Assets.xcassets", "ContentView.swift", "SecondaryViews.swift", "luzeApp.swift"],
            sources: ["Models.swift", "StatementImporting.swift", "TransactionClassification.swift", "SpreadsheetExporting.swift"]
        ),
        .testTarget(
            name: "LuzeCoreTests",
            dependencies: ["LuzeCore"],
            path: "Tests/LuzeCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
