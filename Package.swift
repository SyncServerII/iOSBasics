// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iOSBasics",
    platforms: [
        // iOSSignIn dependency requires iOS 13
        .iOS(.v13),
        
        // Needed for PersistentValue
        .macOS(.v10_11)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "iOSBasics",
            targets: ["iOSBasics"]),
    ],
    dependencies: [
        .package(url: "https://github.com/crspybits/FileMD5Hash.git", .branch("master")),

        .package(url: "https://github.com/SyncServerII/ChangeResolvers.git", .branch("master")),

        .package(path: "../iOSShared"),
        //.package(url: "https://github.com/SyncServerII/iOSShared.git", .branch("master")),
        
        .package(path: "../ServerShared"),
        //.package(url: "https://github.com/SyncServerII/ServerShared.git", .branch("master")),
        
        .package(path: "../iOSSignIn"),
        //.package(url: "https://github.com/SyncServerII/iOSSignIn.git", .branch("master")),
        
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.12.0"),
        .package(url: "https://github.com/mrackwitz/Version.git", from: "0.8.0"),
        //.package(name: "Reachability", url: "https://github.com/ashleymills/Reachability.swift.git", from: "5.0.0"),
        
        // For testing only
        .package(path: "../iOSDropbox"),
        // .package(url: "https://github.com/SyncServerII/iOSDropbox.git", .branch("master")),

    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "iOSBasics",
            dependencies: [
                "ServerShared",
                "iOSShared", "iOSSignIn", "Version", "FileMD5Hash", "ChangeResolvers",
                .product(name: "SQLite", package: "SQLite.swift")
            ]),
        .testTarget(
            name: "iOSBasicsTests",
            dependencies: [
                "iOSBasics", "iOSShared", "iOSSignIn", "Version", "iOSDropbox",
                "ChangeResolvers",
                .product(name: "SQLite", package: "SQLite.swift")
            ]),
        .testTarget(
            name: "ServerTests",
            dependencies: [
                "iOSBasics", "iOSShared", "iOSSignIn", "Version", "iOSDropbox",
                "ChangeResolvers",
                .product(name: "SQLite", package: "SQLite.swift")
            ])
    ]
)
