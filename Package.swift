// swift-tools-version: 6.2

import PackageDescription
import Foundation

// Some Command Line Tools installations ship a partial libc++ include directory.
// Use the matching SDK headers only when the normal toolchain header is absent.
let sdkCxxHeaders = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1"
let toolchainComplexHeader = "/Library/Developer/CommandLineTools/usr/include/c++/v1/complex"
let needsSDKCxxHeaderFallback =
    !FileManager.default.fileExists(atPath: toolchainComplexHeader)
    && FileManager.default.fileExists(atPath: sdkCxxHeaders + "/complex")
var signalsmithCxxSettings: [CXXSetting] = [
    .headerSearchPath("../../Vendor/SignalsmithStretch/include")
]
if needsSDKCxxHeaderFallback {
    signalsmithCxxSettings.append(.unsafeFlags(["-isystem", sdkCxxHeaders]))
}

let package = Package(
    name: "AudioPlayer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AudioPlayer",
            targets: ["AudioPlayer"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AudioPlayer",
            dependencies: ["SoundTouchPlayback", "SignalsmithPlayback"],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "SoundTouchCore",
            path: "Vendor/SoundTouch",
            sources: [
                "source/SoundTouch/AAFilter.cpp",
                "source/SoundTouch/FIFOSampleBuffer.cpp",
                "source/SoundTouch/FIRFilter.cpp",
                "source/SoundTouch/InterpolateCubic.cpp",
                "source/SoundTouch/InterpolateLinear.cpp",
                "source/SoundTouch/InterpolateShannon.cpp",
                "source/SoundTouch/PeakFinder.cpp",
                "source/SoundTouch/RateTransposer.cpp",
                "source/SoundTouch/SoundTouch.cpp",
                "source/SoundTouch/TDStretch.cpp",
                "source/SoundTouch/cpu_detect_x86.cpp",
            ],
            publicHeadersPath: "include"
        ),
        .target(
            name: "SoundTouchPlayback",
            dependencies: ["SoundTouchBridge"],
            path: "Sources/SoundTouchPlayback"
        ),
        .target(
            name: "SoundTouchBridge",
            dependencies: ["SoundTouchCore"],
            path: "Sources/SoundTouchBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../../Vendor/SoundTouch/include")
            ]
        ),
        .target(
            name: "SignalsmithPlayback",
            dependencies: ["SignalsmithBridge"],
            path: "Sources/SignalsmithPlayback"
        ),
        .target(
            name: "SignalsmithBridge",
            path: "Sources/SignalsmithBridge",
            publicHeadersPath: "include",
            cxxSettings: signalsmithCxxSettings
        )
    ]
)
