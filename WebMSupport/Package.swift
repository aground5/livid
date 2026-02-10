// swift-tools-version: 5.9
import PackageDescription
import Foundation

let package = Package(
    name: "WebMSupport",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "WebMSupport",
            targets: ["WebMSupport"]),
    ],
    targets: [
        .target(
            name: "WebMSupportCpp",
            dependencies: [],
            path: "Sources/WebMSupportCpp",
            cSettings: [
                .headerSearchPath("../../Frameworks/FFmpeg/include")
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("iconv"),
                .linkedLibrary("c++"),  // Required for libzimg (C++ library)
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("IOSurface"),
                .unsafeFlags([
                    "-L\(Package.packageDirectory)/Frameworks/FFmpeg/lib",
                    "-L/opt/homebrew/lib",
                    "-lavformat", "-lavcodec", "-lavfilter", "-lavutil", "-lswscale", "-lx264", "-lx265", "-lzimg", "-ldav1d", "-lplacebo", "-llcms2", "-lshaderc_shared", "-lvulkan", "-lpthread"
                ])
            ]
        ),
        .target(
            name: "WebMSupport",
            dependencies: ["WebMSupportCpp"],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .executableTarget(
            name: "WebMTestExec",
            dependencies: ["WebMSupport"],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)

extension Package {
    static var packageDirectory: String {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
    }
}
