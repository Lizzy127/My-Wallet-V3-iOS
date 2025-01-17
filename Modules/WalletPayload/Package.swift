// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "WalletPayload",
    platforms: [
        .iOS(.v14), .macOS(.v11)
    ],
    products: [
        .library(name: "WalletPayloadKit", targets: ["WalletPayloadKit"]),
        .library(name: "WalletPayloadDataKit", targets: ["WalletPayloadDataKit"]),
        .library(name: "WalletPayloadKitMock", targets: ["WalletPayloadKitMock"])
    ],
    dependencies: [
        .package(
            name: "RxSwift",
            url: "https://github.com/ReactiveX/RxSwift.git",
            from: "6.2.0"
        ),
        .package(
            name: "DIKit",
            url: "https://github.com/jackpooleybc/DIKit.git",
            .branch("safe-property-wrappers")
        ),
        .package(path: "../Localization"),
        .package(path: "../CommonCrypto"),
        .package(path: "../Keychain"),
        .package(path: "../Network"),
        .package(path: "../NetworkErrors"),
        .package(path: "../Metadata"),
        .package(path: "../Test"),
        .package(path: "../Tool"),
        .package(path: "../RxTool")
    ],
    targets: [
        .target(
            name: "WalletPayloadKit",
            dependencies: [
                .product(name: "Localization", package: "Localization"),
                .product(name: "CommonCryptoKit", package: "CommonCrypto"),
                .product(name: "KeychainKit", package: "Keychain"),
                .product(name: "MetadataKit", package: "Metadata"),
                .product(name: "NetworkError", package: "NetworkErrors"),
                .product(name: "ToolKit", package: "Tool"),
                .product(name: "RxToolKit", package: "RxTool"),
                .product(name: "DIKit", package: "DIKit")
            ]
        ),
        .target(
            name: "WalletPayloadDataKit",
            dependencies: [
                .target(name: "WalletPayloadKit"),
                .product(name: "DIKit", package: "DIKit"),
                .product(name: "KeychainKit", package: "Keychain"),
                .product(name: "ToolKit", package: "Tool"),
                .product(name: "NetworkError", package: "NetworkErrors"),
                .product(name: "NetworkKit", package: "Network")
            ]
        ),
        .target(
            name: "WalletPayloadKitMock",
            dependencies: [
                .target(name: "WalletPayloadKit"),
                .target(name: "WalletPayloadDataKit"),
                .product(name: "RxSwift", package: "RxSwift"),
                .product(name: "RxCocoa", package: "RxSwift")
            ]
        ),
        .testTarget(
            name: "WalletPayloadKitTests",
            dependencies: [
                .target(name: "WalletPayloadDataKit"),
                .target(name: "WalletPayloadKit"),
                .target(name: "WalletPayloadKitMock"),
                .product(name: "MetadataKitMock", package: "Metadata"),
                .product(name: "KeychainKitMock", package: "Keychain"),
                .product(name: "RxSwift", package: "RxSwift"),
                .product(name: "RxTest", package: "RxSwift"),
                .product(name: "NetworkError", package: "NetworkErrors"),
                .product(name: "NetworkKitMock", package: "Network"),
                .product(name: "TestKit", package: "Test"),
                .product(name: "ToolKit", package: "Tool"),
                .product(name: "ToolKitMock", package: "Tool")
            ],
            resources: [
                .copy("Fixtures/wallet-wrapper-v4.json"),
                .copy("Fixtures/wallet-data.json"),
                .copy("Fixtures/address-label.json"),
                .copy("Fixtures/hdaccount.v3.json"),
                .copy("Fixtures/hdaccount.v4.json"),
                .copy("Fixtures/hdaccount.v4.unknown.json"),
                .copy("Fixtures/wallet.v3.json"),
                .copy("Fixtures/wallet.v4.json"),
                .copy("Fixtures/wallet.v4-secpass.json"),
                .copy("Fixtures/hdwallet.v3.json"),
                .copy("Fixtures/hdwallet.v4.json"),
                .copy("Fixtures/hdwallet.unknown.json")
            ]
        )
    ]
)
