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
            path: "ninewood-macos/API",
            exclude: [
                "Services",
                "APIClient.swift",
                "APIError.swift",
                "ChatRealtime.swift",
                "KeychainTokenStore.swift",
                "ParityDTOs.swift"
            ],
            sources: [
                "APIConfig.swift",
                "APIResponse.swift",
                "MessageMergeDeduper.swift",
                "DTO/AgentDTOs.swift",
                "DTO/AuthDTOs.swift",
                "DTO/DemandDTOs.swift",
                "DTO/OrderDTOs.swift",
                "DTO/MessageDTOs.swift",
                "DTO/WelfareDTOs.swift"
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
