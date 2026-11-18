// swift-tools-version: 6.0
// Layering is enforced by this target graph + ArchitectureTests (mirrors
// test/architecture/import_rules_test.dart in the Flutter repo).
import PackageDescription

let package = Package(
    name: "WorkNexusKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WorkNexusKit", targets: ["CoreDomain", "CorePersistence", "CoreUI", "CoreTools", "SharedKit", "ToolZenTao", "ToolGitLab", "ToolGitHub", "FeatureConnections", "FeatureWorkspaceOverview", "FeatureTicketEditor", "FeatureTranslation", "FeatureNotifications", "FeatureChat", "FeatureMiniApps", "FeatureAppUpdate", "FeaturePets"]),
    ],
    dependencies: [
        // Exact pins, no ranges (same policy as pubspec.yaml).
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.9.0"),
        .package(url: "https://github.com/airbnb/lottie-ios.git", exact: "4.6.1"),
    ],
    targets: [
        .target(name: "CoreDomain", dependencies: []),
        .testTarget(name: "CoreDomainTests", dependencies: ["CoreDomain"]),
        .target(name: "CorePersistence", dependencies: ["CoreDomain", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "CorePersistenceTests", dependencies: ["CorePersistence"]),
        .target(name: "CoreUI", dependencies: ["CoreDomain"]),
        .testTarget(name: "CoreUITests", dependencies: ["CoreUI"]),
        .target(name: "CoreTools", dependencies: ["CoreDomain", "CoreUI"]),
        .testTarget(name: "CoreToolsTests", dependencies: ["CoreTools"]),
        .target(name: "SharedKit", dependencies: ["CoreDomain", "CoreUI", "CoreTools"]),
        .testTarget(name: "SharedKitTests", dependencies: ["SharedKit"]),
        .target(name: "ToolZenTao", dependencies: ["CoreDomain", "CorePersistence", "CoreUI", "CoreTools", "SharedKit", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "ToolZenTaoTests", dependencies: ["ToolZenTao"]),
        .target(name: "ToolGitLab", dependencies: ["CoreDomain", "CorePersistence", "CoreUI", "CoreTools", "SharedKit", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "ToolGitLabTests", dependencies: ["ToolGitLab"]),
        .target(name: "ToolGitHub", dependencies: ["CoreDomain", "CorePersistence", "CoreUI", "CoreTools", "SharedKit", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "ToolGitHubTests", dependencies: ["ToolGitHub"]),
        .target(name: "FeatureConnections", dependencies: ["CoreDomain", "CorePersistence", "CoreUI", "CoreTools", "SharedKit", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "FeatureConnectionsTests", dependencies: ["FeatureConnections"]),
        .target(name: "FeatureWorkspaceOverview", dependencies: ["CoreDomain", "CorePersistence", "CoreUI", "CoreTools", "SharedKit", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "FeatureWorkspaceOverviewTests", dependencies: ["FeatureWorkspaceOverview"]),
        .target(name: "FeatureTicketEditor", dependencies: ["CoreDomain", "CorePersistence", "CoreUI", "CoreTools", "SharedKit", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "FeatureTicketEditorTests", dependencies: ["FeatureTicketEditor"]),
        .target(name: "FeatureTranslation", dependencies: ["CoreDomain", "CorePersistence", "CoreUI", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "FeatureTranslationTests", dependencies: ["FeatureTranslation"]),
        .target(name: "FeatureNotifications", dependencies: ["CoreDomain", "CorePersistence", "CoreUI", "CoreTools", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "FeatureNotificationsTests", dependencies: ["FeatureNotifications"]),
        .target(name: "FeatureChat", dependencies: ["CoreDomain", "CorePersistence", "CoreUI", .product(name: "GRDB", package: "GRDB.swift"), .product(name: "Lottie", package: "lottie-ios")]),
        .testTarget(name: "FeatureChatTests", dependencies: ["FeatureChat"]),
        .target(name: "FeatureMiniApps", dependencies: ["CoreDomain", "CorePersistence", "CoreUI", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "FeatureMiniAppsTests", dependencies: ["FeatureMiniApps"]),
        .target(name: "FeatureAppUpdate", dependencies: ["CoreDomain", "CoreUI"]),
        .testTarget(name: "FeatureAppUpdateTests", dependencies: ["FeatureAppUpdate"]),
        .target(name: "FeaturePets", dependencies: ["CoreDomain", "CoreUI"]),
        .testTarget(name: "FeaturePetsTests", dependencies: ["FeaturePets"], exclude: ["Fixtures"]),
        .testTarget(name: "ArchitectureTests"),
    ],
    swiftLanguageModes: [.v5]
)
