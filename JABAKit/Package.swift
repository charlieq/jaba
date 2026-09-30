// swift-tools-version: 6.0
import PackageDescription

// Forecast engine for JABA: data clients, geomagnetic + solar math, and the
// GO / MAYBE / NO scoring. Foundation-only so it can be tested on macOS with
// `swift test` as well as linked into the iOS app.
let package = Package(
    name: "JABAKit",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "JABAKit", targets: ["JABAKit"]),
    ],
    targets: [
        .target(name: "JABAKit"),
        .testTarget(
            name: "JABAKitTests",
            dependencies: ["JABAKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
