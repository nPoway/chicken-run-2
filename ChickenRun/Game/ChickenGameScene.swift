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
    private let effectsLayer = SKNode()
    private let calloutLayer = SKNode()
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
        reducedEffects = profile.settings.reduceEffects || UIAccessibility.isReduceMotionEnabled
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

        effectsLayer.zPosition = 40
        worldLayer.addChild(effectsLayer)

        calloutLayer.zPosition = 70
        worldLayer.addChild(calloutLayer)

        let chicken = ChickenArtwork.makeChicken(appearance: appearance)
        chicken.zPosition = 50
        worldLayer.addChild(chicken)
        chickenNode = chicken

        let snapshot = simulation.snapshot
        render(snapshot)
        deliverSnapshot(snapshot)
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
            let snapshot = simulation.snapshot
            render(snapshot)
            deliverSnapshot(snapshot)
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
        let snapshot = simulation.snapshot
        render(snapshot)
        deliverSnapshot(snapshot)
    }

    func setHorizontalInput(_ input: CGFloat) {
        let nextInput = min(max(input, -1), 1)
        if abs(nextInput) > 0.01, abs(horizontalInput) <= 0.01 {
            chickenNode?.playSwipeFeedback(direction: nextInput, reducedMotion: reducedEffects)
        }
        horizontalInput = nextInput
    }

    func applySwipeImpulse(direction: CGFloat) {
        guard direction != 0, !simulation.snapshot.isPaused, !simulation.snapshot.isFinished else { return }
        swipeImpulseDirection = direction > 0 ? 1 : -1
        swipeImpulseRemaining = 0.22
        chickenNode?.playSwipeFeedback(direction: swipeImpulseDirection, reducedMotion: reducedEffects)
        playActionBurst(at: chickenNode?.position, direction: swipeImpulseDirection)
        playWorldKick(x: swipeImpulseDirection * 2.5, y: 0)
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
        let snapshot = simulation.snapshot
        render(snapshot)
        deliverSnapshot(snapshot)
    }

    func pause() {
        guard !simulation.snapshot.isPaused, !simulation.snapshot.isFinished else { return }
        simulation.pause()
        process(simulation.lastEvents)
        let snapshot = simulation.snapshot
        render(snapshot)
        deliverSnapshot(snapshot)
    }

    func resume() {
        guard simulation.snapshot.isPaused, !simulation.snapshot.isFinished else { return }
        simulation.resume()
        process(simulation.lastEvents)
        let snapshot = simulation.snapshot
        render(snapshot)
        deliverSnapshot(snapshot)
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

        removeAction(forKey: "scene.finishDelivery")
        worldLayer.removeAllActions()
        worldLayer.position = .zero
        effectsLayer.removeAllChildren()
        calloutLayer.removeAllChildren()

        cloudNodes.values.forEach { $0.removeFromParent() }
        featherNodes.values.forEach { $0.removeFromParent() }
        cloudNodes = [:]
        featherNodes = [:]

        chickenNode?.removeFromParent()
        let chicken = ChickenArtwork.makeChicken(appearance: appearance)
        chicken.zPosition = 50
        worldLayer.addChild(chicken)
        chickenNode = chicken

        let snapshot = simulation.snapshot
        render(snapshot)
        deliverSnapshot(snapshot)
    }

    private var resolvedHorizontalInput: CGFloat {
        if abs(horizontalInput) > 0.01 {
            return horizontalInput
        }
        return swipeImpulseRemaining > 0 ? swipeImpulseDirection : 0
    }

    private func process(_ events: [SimulationEvent]) {
        guard !events.isEmpty else { return }

        let activatesAirflow = events.contains { event in
            if case .airflowActivated = event { return true }
            return false
        }

        for event in events {
            switch event {
            case let .landed(cloudID, family, bounceVelocity):
                chickenNode?.playLandingFeedback(reducedMotion: reducedEffects)
                cloudNodes[cloudID]?.playLandingFeedback(reducedMotion: reducedEffects)
                playLandingImpact(
                    cloudID: cloudID,
                    family: family,
                    bounceVelocity: bounceVelocity,
                    showCallout: !activatesAirflow
                )

            case let .featherCollected(featherID, _, flapCharge):
                let pickupPosition = featherNodes[featherID]?.position ?? chickenNode?.position ?? .zero
                if let feather = featherNodes.removeValue(forKey: featherID) {
                    feather.playCollection(reducedMotion: reducedEffects)
                }
                chickenNode?.playPickupFeedback(reducedMotion: reducedEffects)
                playPickupFeedback(at: pickupPosition, flapCharge: flapCharge)

            case .flapActivated:
                playFlapFeedback()

            case .airflowActivated:
                chickenNode?.setFlowActive(true, reducedMotion: reducedEffects)
                playAirflowActivation()

            case .airflowExpired:
                chickenNode?.setFlowActive(false, reducedMotion: reducedEffects)

            case let .stormCloudTriggered(cloudID):
                cloudNodes[cloudID]?.playStormWarning(reducedMotion: reducedEffects)
                playStormFlash(at: cloudNodes[cloudID]?.position)

            case let .stormCloudDissolved(cloudID):
                cloudNodes.removeValue(forKey: cloudID)?.removeFromParent()

            case let .finished(result):
                playSoftFall()
                if !didDeliverResult {
                    didDeliverResult = true
                    let delay = reducedEffects ? 0.12 : 0.34
                    run(.sequence([
                        .wait(forDuration: delay),
                        .run { [weak self] in self?.onFinished?(result) }
                    ]), withKey: "scene.finishDelivery")
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
            var playerPosition = screenPosition(for: snapshot.player.position, cameraY: snapshot.cameraY)
            // The illustration is intentionally much wider than the physics
            // radius. Keep the art readable at the side walls without changing
            // collision rules or the generated route.
            playerPosition.x = min(max(playerPosition.x, 60), size.width - 60)
            chickenNode.position = playerPosition
            chickenNode.updateFlightPose(
                verticalVelocity: snapshot.player.velocity.y,
                horizontalVelocity: snapshot.player.velocity.x,
                elapsedTime: snapshot.elapsedTime,
                isPaused: snapshot.isPaused || snapshot.isFinished,
                reducedMotion: reducedEffects
            )
        }

        let parallaxX = size.width / 2 - snapshot.player.position.x
        skyNode?.setParallaxOffset(x: parallaxX, y: -snapshot.cameraY)
    }

    private func screenPosition(for worldPosition: CGPoint, cameraY: CGFloat) -> CGPoint {
        CGPoint(x: worldPosition.x, y: worldPosition.y - cameraY)
    }

    private func playFlapFeedback() {
        guard let chickenNode else { return }
        chickenNode.playFlapFeedback(reducedMotion: reducedEffects)
        playActionBurst(at: chickenNode.position)
        showCallout(
            "FLAP!",
            at: CGPoint(x: chickenNode.position.x, y: chickenNode.position.y + 132),
            tint: UIColor(red: 1, green: 0.80, blue: 0.26, alpha: 1),
            emphasized: true
        )
        playWorldKick(x: 0, y: -3.5)
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

    private func playLandingImpact(
        cloudID: Int,
        family: CloudFamily,
        bounceVelocity: CGFloat,
        showCallout shouldShowCallout: Bool
    ) {
        guard let cloud = cloudNodes[cloudID] else { return }

        let intensity = min(max(bounceVelocity / 690, 0.85), 1.30)
        let contactPoint = CGPoint(
            x: cloud.position.x,
            y: cloud.position.y + cloud.platformHeight * 0.44
        )
        let burst = ChickenArtwork.makeLandingBurst(family: family, intensity: intensity)
        burst.position = contactPoint
        effectsLayer.addChild(burst)
        burst.playAndRemove(reducedMotion: reducedEffects)

        if shouldShowCallout, family != .storm {
            showCallout(
                landingCallout(for: family),
                at: CGPoint(x: contactPoint.x, y: contactPoint.y + 145),
                tint: landingTint(for: family),
                emphasized: family == .spring || family == .storm
            )
        }

        let kick = family == .spring ? -4.5 : family == .storm ? -4 : -2.2
        playWorldKick(x: 0, y: kick * intensity)
    }

    private func playPickupFeedback(at position: CGPoint, flapCharge: Int) {
        let reward = ChickenArtwork.makeFloatingReward(text: "+1")
        reward.position = CGPoint(x: position.x, y: position.y + 15)
        calloutLayer.addChild(reward)
        reward.playAndRemove(reducedMotion: reducedEffects)

        let sparkle = ChickenArtwork.makeActionBurst(
            tint: UIColor(red: 1, green: 0.82, blue: 0.28, alpha: 1)
        )
        sparkle.position = position
        sparkle.setScale(0.55)
        effectsLayer.addChild(sparkle)
        sparkle.playAndRemove(reducedMotion: reducedEffects)

        if flapCharge >= simulation.snapshot.flapRequirement, let chickenNode {
            showCallout(
                "⚡ FLAP READY!",
                at: CGPoint(x: chickenNode.position.x, y: chickenNode.position.y + 138),
                tint: UIColor(red: 1, green: 0.73, blue: 0.18, alpha: 1),
                emphasized: true
            )
            playActionBurst(at: chickenNode.position)
        }
    }

    private func playAirflowActivation() {
        guard let chickenNode else { return }
        showCallout(
            "FLOW ×2!",
            at: CGPoint(x: chickenNode.position.x, y: chickenNode.position.y + 142),
            tint: UIColor(red: 1, green: 0.86, blue: 0.30, alpha: 1),
            emphasized: true
        )
        playActionBurst(at: chickenNode.position)
        playWorldKick(x: 0, y: -4)
    }

    private func playActionBurst(at position: CGPoint?, direction: CGFloat = 0) {
        guard let position else { return }
        let burst = ChickenArtwork.makeActionBurst(direction: direction)
        burst.position = CGPoint(x: position.x, y: position.y + 34)
        effectsLayer.addChild(burst)
        burst.playAndRemove(reducedMotion: reducedEffects)
    }

    private func playStormFlash(at position: CGPoint?) {
        guard let position else { return }

        if !reducedEffects {
            let flash = SKSpriteNode(color: UIColor.white, size: size)
            flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
            flash.zPosition = 95
            flash.alpha = 0.22
            flash.blendMode = .add
            addChild(flash)
            flash.run(.sequence([
                .fadeOut(withDuration: 0.14),
                .removeFromParent()
            ]))
        }

        showCallout(
            "⚡ ZAP!",
            at: CGPoint(x: position.x, y: position.y + 78),
            tint: UIColor(red: 1, green: 0.86, blue: 0.28, alpha: 1),
            emphasized: true
        )
    }

    private func showCallout(
        _ text: String,
        at position: CGPoint,
        tint: UIColor,
        emphasized: Bool
    ) {
        let callout = ChickenArtwork.makeFloatingReward(
            text: text,
            tint: tint,
            emphasized: emphasized
        )
        callout.position = position
        calloutLayer.addChild(callout)
        callout.playAndRemove(reducedMotion: reducedEffects)
    }

    private func playWorldKick(x: CGFloat, y: CGFloat) {
        guard !reducedEffects else { return }
        worldLayer.removeAction(forKey: "scene.worldKick")
        worldLayer.position = .zero
        let push = SKAction.moveBy(x: x, y: y, duration: 0.045)
        push.timingMode = .easeOut
        let overshoot = SKAction.moveBy(x: -x * 1.35, y: -y * 1.35, duration: 0.065)
        overshoot.timingMode = .easeInEaseOut
        let settle = SKAction.move(to: .zero, duration: 0.08)
        settle.timingMode = .easeOut
        worldLayer.run(.sequence([push, overshoot, settle]), withKey: "scene.worldKick")
    }

    private func landingCallout(for family: CloudFamily) -> String {
        switch family {
        case .fluffy: return "BOUNCE!"
        case .windy: return "WHOOSH!"
        case .spring: return "SUPER JUMP!"
        case .storm: return "⚡ ZAP!"
        }
    }

    private func landingTint(for family: CloudFamily) -> UIColor {
        switch family {
        case .fluffy: return UIColor.white
        case .windy: return UIColor(red: 0.38, green: 0.84, blue: 0.96, alpha: 1)
        case .spring: return UIColor(red: 0.76, green: 0.55, blue: 1, alpha: 1)
        case .storm: return UIColor(red: 1, green: 0.86, blue: 0.28, alpha: 1)
        }
    }

    private func deliverSnapshot(_ snapshot: RunSnapshot) {
        onSnapshot?(snapshot)
    }

    private static func makeSimulation(for size: CGSize) -> RunSimulation {
        let seed = UInt64.random(in: UInt64.min ... UInt64.max)
        return RunSimulation(configuration: .init(viewportSize: size, seed: seed))
    }
}
