// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "FeatureCards",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "FeatureCards",
            targets: ["FeatureCardsData", "FeatureCardsDomain", "FeatureCardsUI"]
        ),
        .library(
            name: "FeatureCardsUI",
            targets: ["FeatureCardsUI"]
        ),
        .library(
            name: "FeatureCardsDomain",
            targets: ["FeatureCardsDomain"]
        )
    ],
    dependencies: [
        .package(
            name: "DIKit",
            url: "https://github.com/jackpooleybc/DIKit.git",
            .branch("safe-property-wrappers")
        ),
        .package(
            name: "swift-composable-architecture",
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            from: "0.18.0"
        ),
        .package(
            name: "Stripe",
            url: "https://github.com/stripe/stripe-ios",
            from: "21.9.0"
        ),
        .package(
            name: "Frames",
            url: "https://github.com/checkout/frames-ios.git",
            .upToNextMajor(from: "3.0.0")
        ),
        .package(path: "../Analytics"),
        .package(path: "../ComposableArchitectureExtensions"),
        .package(path: "../Localization"),
        .package(path: "../Network"),
        .package(path: "../NetworkErrors"),
        .package(path: "../Tool"),
        .package(path: "../UIComponents"),
        .package(path: "../Money")
    ],
    targets: [
        .target(
            name: "FeatureCardsDomain",
            dependencies: [
                .product(name: "NabuNetworkError", package: "NetworkErrors"),
                .product(name: "NetworkError", package: "NetworkErrors"),
                .product(name: "NetworkKit", package: "Network"),
                .product(name: "ToolKit", package: "Tool"),
                .product(name: "MoneyKit", package: "Money")
            ]
        ),
        .target(
            name: "FeatureCardsData",
            dependencies: [
                .target(name: "FeatureCardsDomain"),
                .product(name: "DIKit", package: "DIKit"),
                .product(name: "NetworkKit", package: "Network"),
                .product(name: "NetworkError", package: "NetworkErrors"),
                .product(name: "Frames", package: "Frames"),
                .product(name: "Stripe", package: "Stripe"),
                .product(name: "ToolKit", package: "Tool"),
                .product(name: "MoneyKit", package: "Money")
            ]
        ),
        .target(
            name: "FeatureCardsUI",
            dependencies: [
                .target(name: "FeatureCardsDomain"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "ComposableNavigation", package: "ComposableArchitectureExtensions"),
                .product(name: "AnalyticsKit", package: "Analytics"),
                .product(name: "Localization", package: "Localization"),
                .product(name: "ToolKit", package: "Tool"),
                .product(name: "UIComponents", package: "UIComponents"),
                .product(name: "Frames", package: "Frames"),
                .product(name: "Stripe", package: "Stripe")
            ]
        )
    ]
)
