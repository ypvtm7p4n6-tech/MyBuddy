// swift-tools-version:5.9
import PackageDescription

// Testpakket voor de rekenlogica. De bronbestanden staan in App/Core en worden
// via de symlink Sources/MyBuddyCore hergebruikt, zodat de app en de tests
// exact dezelfde code compileren.
let package = Package(
    name: "MyBuddyCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "MyBuddyCore", targets: ["MyBuddyCore"])
    ],
    targets: [
        .target(name: "MyBuddyCore", path: "Sources/MyBuddyCore"),
        .testTarget(name: "MyBuddyCoreTests", dependencies: ["MyBuddyCore"], path: "Tests/MyBuddyCoreTests")
    ]
)
