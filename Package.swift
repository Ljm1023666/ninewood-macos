// swift-tools-version: 6.2

import PackageDescription

/// 仅承载可独立验证的纯领域规则。
///
/// macOS App 仍由 Xcode 工程构建；此包让核心规则无需启动 UI 或访问云端即可回归测试。
let package = Package(
    name: "NinewoodDomain",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "NinewoodPublishDomain", targets: ["NinewoodPublishDomain"]),
        .library(name: "NinewoodOrderDomain", targets: ["NinewoodOrderDomain"]),
        .library(name: "NinewoodAPIContracts", targets: ["NinewoodAPIContracts"]),
    ],
    targets: [
        .target(
            name: "NinewoodPublishDomain",
            path: "ninewood-macos/Domain/Publish"
        ),
        .target(
            name: "NinewoodOrderDomain",
            path: "ninewood-macos/Domain/Orders"
        ),
        .target(
            name: "NinewoodAPIContracts",
            path: "ninewood-macos",
            exclude: [
                "App", "Data", "Theme", "Views", "Store",
                "Core/Dependencies",
                "Domain/NaturalLoop", "Domain/Orders", "Domain/Publish", "Domain/User",
                "API/Services", "API/ChatRealtime.swift", "API/ParityDTOs.swift",
                "Models/LoopModels.swift",
                "Assets.xcassets", "Domain/Messages/MessageMapperSupport.swift",
                "Features/Discover/DemandDetailFeatureModel.swift",
                "Features/Orders/OrderDetailFeatureModel.swift",
                "Features/Messages/ChatDetailFeatureModel.swift",
                "ContentView.swift", "ninewood-macos.entitlements"
            ],
            sources: [
                "API/APIClient.swift",
                "API/APIDate.swift",
                "API/APIError.swift",
                "API/APIConfig.swift",
                "API/APIResponse.swift",
                "API/KeychainTokenStore.swift",
                "API/MessageMergeDeduper.swift",
                "API/DTO/AgentDTOs.swift",
                "API/DTO/AuthDTOs.swift",
                "API/DTO/DemandDTOs.swift",
                "API/DTO/OrderDTOs.swift",
                "API/DTO/MessageDTOs.swift",
                "API/DTO/WelfareDTOs.swift",
                "Models/Models.swift",
                "Domain/Messages/RealtimeIncomingMessage.swift",
                "Domain/Messages/ChatRealtimePayload.swift",
                "Features/Discover/DiscoverFeatureModel.swift",
                "Features/Orders/OrdersFeatureModel.swift",
                "Features/Messages/MessagesFeatureModel.swift",
                "Core/Session/InboxState.swift",
                "Core/Session/AuthSession.swift"
            ]
        ),
        .testTarget(
            name: "NinewoodPublishDomainTests",
            dependencies: [
                "NinewoodPublishDomain",
                "NinewoodOrderDomain",
                "NinewoodAPIContracts"
            ],
            path: "Tests/NinewoodPublishDomainTests"
        )
    ]
)
