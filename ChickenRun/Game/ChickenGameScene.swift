//
//  ChickenGameScene.swift
//  ChickenRun
//
//  SpriteKit is intentionally only a renderer here. Rules, generation and
//  scoring live in RunSimulation, making a run deterministic and testable.
//

import SpriteKit
import UIKit

@MainActor
final class ChickenGameScene: SKScene {
    var onSnapshot: ((RunSnapshot) -> Void)?
    var onEvents: (([SimulationEvent]) -> Void)?
    var onFinished: ((FlightResult) -> Void)?

    private let appearance: ChickenArtwork.Appearance
    private let reducedEffects: Bool
    private var simulation: RunSimulation
    private var horizontalInput: CGFloat = 0
    private var swipeImpulseDirection: CGFloat = 0
    private var swipeImpulseRemaining: TimeInterval = 0
    private var flapRequested = false
    private var lastUpdateTime: TimeInterval = 0
    private var didDeliverResult = false
    private var didBuildScene = false
    private var isFlowVisible = false

    private let worldLayer = SKNode()
    private var backdropNode: SKSpriteNode?
    private var skyNode: MorningSkyDecorationNode?
    private var chickenNode: ChickenArtNode?
    private var cloudNodes: [Int: CloudPlatformNode] = [:]
    private var featherNodes: [Int: FeatherCollectibleNode] = [:]

    init(size: CGSize, profile: PlayerProfile) {
        appearance = ChickenArtwork.Appearance(
            plumage: GameCatalog.cosmetic(id: profile.equippedCosmetics[CosmeticCategory.plumage.rawValue]),
            headwear: GameCatalog.cosmetic(id: profile.equippedCosmetics[CosmeticCategory.headwear.rawValue]),
            backpack: GameCatalog.cosmetic(id: profile.equippedCosmetics[CosmeticCategory.backpack.rawValue])
        )
        reducedEffects = profile.settings.reduceEffects
        simulation = ChickenGameScene.makeSimulation(for: size)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = .zero
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    override func didMove(to view: SKView) {
        guard !didBuildScene else { return }
        didBuildScene = true

        if let backgroundImage = UIImage(named: "MorningSkyBackdrop") {
            let backdrop = SKSpriteNode(texture: SKTexture(image: backgroundImage))
            backdrop.size = size
            backdrop.position = CGPoint(x: size.width / 2, y: size.height / 2)
            backdrop.zPosition = -100
            addChild(backdrop)
            backdropNode = backdrop
        } else {
            // Keep a complete code-drawn fallback while the asset catalog is
            // unavailable, for example in previews or a partial checkout.
            let sky = ChickenArtwork.makeMorningSky(size: size)
            sky.position = CGPoint(x: size.width / 2, y: size.height / 2)
            sky.zPosition = -100
            addChild(sky)
            skyNode = sky
        }

        worldLayer.zPosition = 0
        addChild(worldLayer)

        let chicken = ChickenArtwork.makeChicken(appearance: appearance)
        chicken.zPosition = 50
        worldLayer.addChild(chicken)
        chickenNode = chicken

        render(simulation.snapshot)
        deliverSnapshot()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        backdropNode?.size = size
        backdropNode?.position = CGPoint(x: size.width / 2, y: size.height / 2)
        skyNode?.resize(to: size)
        skyNode?.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    override func update(_ currentTime: TimeInterval) {
        guard didBuildScene else { return }

        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            render(simulation.snapshot)
            deliverSnapshot()
            return
        }

        let frameDelta = min(max(currentTime - lastUpdateTime, 0), 0.12)
        lastUpdateTime = currentTime

        if swipeImpulseRemaining > 0 {
            swipeImpulseRemaining = max(0, swipeImpulseRemaining - frameDelta)
            if swipeImpulseRemaining == 0 {
                swipeImpulseDirection = 0
            }
        }

        let input = RunInput(
            horizontal: resolvedHorizontalInput,
            flapPressed: flapRequested,
            pauseTogglePressed: false
        )
        flapRequested = false

        let events = simulation.advance(by: frameDelta, input: input)
        process(events)
        render(simulation.snapshot)
        deliverSnapshot()
    }

    func setHorizontalInput(_ input: CGFloat) {
        horizontalInput = min(max(input, -1), 1)
    }

    func applySwipeImpulse(direction: CGFloat) {
        guard direction != 0, !simulation.snapshot.isPaused, !simulation.snapshot.isFinished else { return }
        swipeImpulseDirection = direction > 0 ? 1 : -1
        swipeImpulseRemaining = 0.22
    }

    func requestFlap() {
        guard !simulation.snapshot.isPaused, !simulation.snapshot.isFinished else { return }
        flapRequested = true
    }

    func togglePause() {
        if simulation.snapshot.isPaused {
            simulation.resume()
        } else {
            simulation.pause()
        }
        process(simulation.lastEvents)
        render(simulation.snapshot)
        deliverSnapshot()
    }

    func pause() {
        guard !simulation.snapshot.isPaused, !simulation.snapshot.isFinished else { return }
        simulation.pause()
        process(simulation.lastEvents)
        render(simulation.snapshot)
        deliverSnapshot()
    }

    func resume() {
        guard simulation.snapshot.isPaused, !simulation.snapshot.isFinished else { return }
        simulation.resume()
        process(simulation.lastEvents)
        render(simulation.snapshot)
        deliverSnapshot()
    }

    func restart() {
        simulation = Self.makeSimulation(for: size)
        horizontalInput = 0
        swipeImpulseDirection = 0
        swipeImpulseRemaining = 0
        flapRequested = false
        didDeliverResult = false
        lastUpdateTime = 0
        isFlowVisible = false

        cloudNodes.values.forEach { $0.removeFromParent() }
        featherNodes.values.forEach { $0.removeFromParent() }
        cloudNodes = [:]
        featherNodes = [:]

        render(simulation.snapshot)
        deliverSnapshot()
    }

    private var resolvedHorizontalInput: CGFloat {
        if abs(horizontalInput) > 0.01 {
            return horizontalInput
        }
        return swipeImpulseRemaining > 0 ? swipeImpulseDirection : 0
    }

    private func process(_ events: [SimulationEvent]) {
        guard !events.isEmpty else { return }

        for event in events {
            switch event {
            case let .landed(cloudID, _, _):
                chickenNode?.playLandingFeedback(reducedMotion: reducedEffects)
                cloudNodes[cloudID]?.playLandingFeedback(reducedMotion: reducedEffects)

            case let .featherCollected(featherID, _, _):
                if let feather = featherNodes.removeValue(forKey: featherID) {
                    feather.playCollection(reducedMotion: reducedEffects)
                }

            case .flapActivated:
                playFlapFeedback()

            case .airflowActivated:
                chickenNode?.setFlowActive(true, reducedMotion: reducedEffects)

            case .airflowExpired:
                chickenNode?.setFlowActive(false, reducedMotion: reducedEffects)

            case let .stormCloudTriggered(cloudID):
                cloudNodes[cloudID]?.playStormWarning(reducedMotion: reducedEffects)

            case let .stormCloudDissolved(cloudID):
                cloudNodes.removeValue(forKey: cloudID)?.removeFromParent()

            case let .finished(result):
                playSoftFall()
                if !didDeliverResult {
                    didDeliverResult = true
                    onFinished?(result)
                }

            case .paused, .resumed:
                break
            }
        }

        onEvents?(events)
    }

    private func render(_ snapshot: RunSnapshot) {
        guard didBuildScene else { return }

        let flowActive = snapshot.airflowRemaining > 0
        if flowActive != isFlowVisible {
            isFlowVisible = flowActive
            chickenNode?.setFlowActive(flowActive, reducedMotion: reducedEffects)
            cloudNodes.values.forEach { $0.setFlowActive(flowActive, reducedMotion: reducedEffects) }
        }

        let visibleCloudIDs = Set(snapshot.clouds.map(\.id))
        let staleCloudIDs = cloudNodes.keys.filter { !visibleCloudIDs.contains($0) }
        for id in staleCloudIDs {
            cloudNodes.removeValue(forKey: id)?.removeFromParent()
        }

        for cloud in snapshot.clouds {
            let node: CloudPlatformNode
            if let existing = cloudNodes[cloud.id] {
                node = existing
            } else {
                node = ChickenArtwork.makeCloudPlatform(
                    family: cloud.family,
                    width: cloud.size.width,
                    height: cloud.size.height
                )
                node.zPosition = 10
                node.setFlowActive(flowActive, reducedMotion: reducedEffects)
                worldLayer.addChild(node)
                cloudNodes[cloud.id] = node
            }
            node.position = screenPosition(for: cloud.position, cameraY: snapshot.cameraY)
            node.alpha = cloud.isStormDissolving ? 0.58 : 1
        }

        let visibleFeatherIDs = Set(snapshot.feathers.map(\.id))
        let staleFeatherIDs = featherNodes.keys.filter { !visibleFeatherIDs.contains($0) }
        for id in staleFeatherIDs {
            featherNodes.removeValue(forKey: id)?.removeFromParent()
        }

        for feather in snapshot.feathers {
            let node: FeatherCollectibleNode
            if let existing = featherNodes[feather.id] {
                node = existing
            } else {
                node = ChickenArtwork.makeFeatherCollectible()
                node.zPosition = 28
                node.setIdleMotionEnabled(!reducedEffects)
                worldLayer.addChild(node)
                featherNodes[feather.id] = node
            }
            node.position = screenPosition(for: feather.position, cameraY: snapshot.cameraY)
        }

        if let chickenNode {
            chickenNode.position = screenPosition(for: snapshot.player.position, cameraY: snapshot.cameraY)
            chickenNode.zRotation = min(max(snapshot.player.velocity.x / 2_800, -0.13), 0.13)
        }

        let parallaxX = size.width / 2 - snapshot.player.position.x
        skyNode?.setParallaxOffset(x: parallaxX, y: -snapshot.cameraY)
    }

    private func screenPosition(for worldPosition: CGPoint, cameraY: CGFloat) -> CGPoint {
        CGPoint(x: worldPosition.x, y: worldPosition.y - cameraY)
    }

    private func playFlapFeedback() {
        guard let chickenNode, !reducedEffects else { return }
        chickenNode.removeAction(forKey: "scene.flap")
        let lift = SKAction.moveBy(x: 0, y: 5, duration: 0.08)
        let settle = SKAction.moveBy(x: 0, y: -5, duration: 0.11)
        chickenNode.run(.sequence([lift, settle]), withKey: "scene.flap")
    }

    private func playSoftFall() {
        chickenNode?.playSoftFall(reducedMotion: reducedEffects)
        guard let chickenNode else { return }
        let effect = ChickenArtwork.makeSoftFallEffect()
        effect.position = CGPoint(x: chickenNode.position.x, y: max(22, chickenNode.position.y - 24))
        effect.zPosition = 46
        worldLayer.addChild(effect)
        effect.playAndRemove(reducedMotion: reducedEffects)
    }

    private func deliverSnapshot() {
        onSnapshot?(simulation.snapshot)
    }

    private static func makeSimulation(for size: CGSize) -> RunSimulation {
        let seed = UInt64.random(in: UInt64.min ... UInt64.max)
        return RunSimulation(configuration: .init(viewportSize: size, seed: seed))
    }
}
