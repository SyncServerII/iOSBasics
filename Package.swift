// swift-tools-version:5.3
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
        .package(url: "https://github.com/crspybits/FileMD5Hash.git", from: "2.1.0"),

        .package(url: "https://github.com/SyncServerII/ChangeResolvers.git", from: "0.0.2"),

        //.package(path: "../iOSShared"),
        .package(url: "https://github.com/SyncServerII/iOSShared.git", from: "0.0.2"),
        
        //.package(path: "../ServerShared"),
        .package(url: "https://github.com/SyncServerII/ServerShared.git", from: "0.0.4"),
        
        //.package(path: "../iOSSignIn"),
        .package(url: "https://github.com/SyncServerII/iOSSignIn.git", from: "0.0.2"),
        
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.12.0"),
        .package(url: "https://github.com/mrackwitz/Version.git", from: "0.8.0"),
        //.package(name: "Reachability", url: "https://github.com/ashleymills/Reachability.swift.git", from: "5.0.0"),
        
        // For testing only
        // .package(path: "../iOSDropbox"),
        .package(url: "https://github.com/SyncServerII/iOSDropbox.git", from: "0.0.3"),

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
        
        // This wasn't working with .testTarget, but changed it to .target and it works: https://stackoverflow.com/questions/63716793
        .target(
            name: "TestsCommon",
            dependencies: [
                "iOSBasics", "iOSShared", "iOSSignIn", "Version", "iOSDropbox",
                "ChangeResolvers",
                .product(name: "SQLite", package: "SQLite.swift")],
            path: "Tests/TestsCommon",
            resources: [
                .copy("Example.txt"),
                .copy("Cat.jpg")]
            ),

        .testTarget(
            name: "iOSBasicsTests",
            dependencies: [
                "TestsCommon",
                "iOSBasics", "iOSShared", "iOSSignIn", "Version", "iOSDropbox",
                "ChangeResolvers",
                .product(name: "SQLite", package: "SQLite.swift")
            ]),
        .testTarget(
            name: "SyncServerTests",
            dependencies: [
                "TestsCommon",
                "iOSBasics", "iOSShared", "iOSSignIn", "Version", "iOSDropbox",
                "ChangeResolvers",
                .product(name: "SQLite", package: "SQLite.swift")
            ]),
        .testTarget(
            name: "ServerTests",
            dependencies: [
                "TestsCommon",
                "iOSBasics", "iOSShared", "iOSSignIn", "Version", "iOSDropbox",
                "ChangeResolvers",
                .product(name: "SQLite", package: "SQLite.swift")
            ])
    ]
)
