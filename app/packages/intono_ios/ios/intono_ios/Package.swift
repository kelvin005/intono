// swift-tools-version: 5.9
// Intono's iOS plugin (ADR 0010), in the form of Flutter 3.50.1's plugin template (Swift Package Manager). IntonoNative.xcframework is
// built from this repository by ios/shim/build_xcframework.sh (libintono, the portable shim core and the AVAudioEngine session).
import PackageDescription

let package = Package(
    name: "intono_ios",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "intono-ios", targets: ["intono_ios"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .binaryTarget(name: "IntonoNative", path: "IntonoNative.xcframework"),
        .target(
            name: "intono_ios",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "IntonoNative",
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("AVFAudio"),
                .linkedFramework("AVFoundation"),
            ]
        )
    ]
)
