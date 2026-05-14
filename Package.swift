// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "swift-knowledge-graph",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .macCatalyst(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(
            name: "KnowledgeGraph",
            targets: ["KnowledgeGraph"]
        ),
        .library(
            name: "KnowledgeGraphParsers",
            targets: ["KnowledgeGraphParsers"]
        ),
    ],
    targets: [
        .target(name: "KnowledgeGraph"),
        .target(
            name: "KnowledgeGraphParsers",
            dependencies: ["KnowledgeGraph"]
        ),
        .testTarget(
            name: "KnowledgeGraphTests",
            dependencies: ["KnowledgeGraph"]
        ),
        .testTarget(
            name: "KnowledgeGraphParsersTests",
            dependencies: ["KnowledgeGraphParsers"],
            resources: [
                .copy("Resources/turtle-tests"),
                .copy("Resources/trig-tests"),
                .copy("Resources/rdfxml-tests"),
                .copy("Resources/jsonld-tests"),
            ]
        ),
    ]
)
