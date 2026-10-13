// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tendedero",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Tendedero", path: "Sources/Tendedero",
                          resources: [.copy("Resources/tomato.png"), .copy("Resources/bear.png"),
                                      .copy("Resources/tote.png"), .copy("Resources/paperbag.png"),
                                      .copy("Resources/clock.png"), .copy("Resources/screwdriver.png"),
                                      .copy("Resources/hammer.png")])
    ]
)
