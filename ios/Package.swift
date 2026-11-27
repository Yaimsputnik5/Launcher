// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OSFRCore",
    products: [
        .library(name: "OSFRCore", targets: ["OSFRCore"])
    ],
    targets: [
        .target(
            name: "OSFRCore",
            path: "Launcher",
            exclude: [
                "AppState.swift",
                "LauncherApp.swift",
                "Resources/Assets.xcassets",
                "Resources/ClientAssets",
                "Resources/SanctuaryResources",
                "Resources/Info.plist",
                "Render",
                "Services/CredentialStore.swift",
                "Services/HTTPClient.swift",
                "Services/LoginUDPSession.swift",
                "Services/ServerStatusClient.swift",
                "Views"
            ],
            sources: [
                "Models/Models.swift",
                "Models/DefaultServer.swift",
                "Models/EngineModels.swift",
                "Services/Paths.swift",
                "Services/XXHash64.swift",
                "Services/ManifestParser.swift",
                "Services/URLHelper.swift",
                "Services/ProtocolPrimitives.swift",
                "Services/LoginProtocol.swift",
                "Services/UdpLibraryTransport.swift",
                "Services/AssetContainers.swift",
                "Services/LocalSession.swift",
                "Services/ClientAssetStore.swift",
                "Services/SanctuaryResourceStore.swift",
                "Services/ResourceCatalog.swift",
                "Services/WorldMapModel.swift",
                "Engine/CollectionSpawns.swift",
                "Engine/GameWorld.swift",
                "Engine/ClientTextureCatalog.swift",
                "Engine/ClientZoneManifest.swift",
                "Engine/ClientMaterialCatalog.swift",
                "Engine/ClientChunkCatalog.swift",
                "Engine/ClientTerrainPalette.swift",
                "Engine/OSFREngine.swift",
                "Services/GatewayProtocol.swift",
                "Services/ImageCodecs.swift"
            ]
        ),
        .testTarget(
            name: "OSFRCoreTests",
            dependencies: ["OSFRCore"],
            path: "Tests/OSFRCoreTests"
        )
    ]
)
