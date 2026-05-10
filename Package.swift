// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LayerLensCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "LayerLensCore",
            targets: ["LayerLensCore"]
        ),
        .executable(
            name: "layerlens-probe",
            targets: ["LayerLensProbe"]
        ),
        .executable(
            name: "LayerLens",
            targets: ["LayerLens"]
        )
    ],
    dependencies: [
        // Sparkle drives the in-app auto-update flow (release notes dialog,
        // signed-dmg download with progress, atomic relaunch). EdDSA-signed
        // appcast + dmgs are produced by .github/workflows/release.yml.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
        // SWCompression for LZMA1: Vial keyboards embed their layout JSON
        // compressed with raw LZMA1 (dict_size=65536, default props). Apple's
        // built-in `Compression.framework` only handles LZMA2 in xz containers,
        // which doesn't fit Vial's wire format. Pure-Swift, no system deps.
        .package(url: "https://github.com/tsolomko/SWCompression", from: "4.8.6"),
        // TelemetryDeck for opt-in anonymous usage analytics. Initialised
        // only when the user enables telemetry in Settings or onboarding;
        // see Sources/LayerLens/Telemetry.swift. Privacy-first: no PII,
        // no IP, anonymous user hash. See PRIVACY.md.
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "LayerLensCore",
            dependencies: [
                .product(name: "SWCompression", package: "SWCompression")
            ],
            path: "Sources/LayerLensCore",
            resources: [
                .copy("Resources/via_keyboards_manifest.json")
            ]
        ),
        .executableTarget(
            name: "LayerLensProbe",
            dependencies: ["LayerLensCore"],
            path: "Sources/LayerLensProbe"
        ),
        .executableTarget(
            name: "LayerLens",
            dependencies: [
                "LayerLensCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "TelemetryDeck", package: "SwiftSDK")
            ],
            path: "Sources/LayerLens",
            linkerSettings: [
                // Tell dyld to look for embedded frameworks in the standard
                // .app/Contents/Frameworks/ location. SPM doesn't add this
                // rpath for executableTargets (Xcode app targets do); without
                // it Sparkle.framework can't be loaded after we package the
                // SPM binary into our hand-rolled .app bundle.
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        ),
        .testTarget(
            name: "LayerLensCoreTests",
            dependencies: ["LayerLensCore"],
            path: "Tests/LayerLensCoreTests",
            resources: [.process("Fixtures")]
        )
    ]
)
