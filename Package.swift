// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iOSBasics",
        platforms: [
        // iOSSignIn dependency requires iOS 13
        .iOS(.v13),
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "iOSBasics",
            targets: ["iOSBasics"]),
    ],
    dependencies: [
        .package(path: "../iOSShared"),
        .package(path: "../ServerShared"),
        
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.12.0"),

        // Only for test target
        .package(path: "../iOSSignIn")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "iOSBasics",
            dependencies: [
                "iOSShared", "ServerShared",
                .product(name: "SQLite", package: "SQLite.swift")
            ]),
        .testTarget(
            name: "iOSBasicsTests",
            dependencies: [
                "iOSBasics", "iOSShared", "iOSSignIn"
            ]),
    ]
)
