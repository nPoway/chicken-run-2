//
//  ChickenArtwork.swift
//  ChickenRun
//
//  Lightweight, code-drawn SpriteKit artwork used by gameplay renderers.
//

import SpriteKit
import UIKit

/// A small collection of renderer-friendly SpriteKit nodes for the morning world.
///
/// The helpers in this file deliberately contain no gameplay rules. A scene can
/// position, recycle, and animate these nodes from its own simulation state.
@MainActor
enum ChickenArtwork {
    @MainActor
    struct Appearance {
        var plumageTint: UIColor?
        var headwearTint: UIColor?
        var backpackTint: UIColor?

        init(
            plumageTint: UIColor? = nil,
            headwearTint: UIColor? = nil,
            backpackTint: UIColor? = nil
        ) {
            self.plumageTint = plumageTint
            self.headwearTint = headwearTint
            self.backpackTint = backpackTint
        }

        /// Convenience bridge for the equipped cosmetic items already used by
        /// the app shell. Passing `nil` leaves that part of the character at
        /// its default (plumage) or hidden (accessories) state.
        init(
            plumage: CosmeticItem? = nil,
            headwear: CosmeticItem? = nil,
            backpack: CosmeticItem? = nil
        ) {
            plumageTint = plumage.map { ChickenArtwork.color(hex: $0.tintHex, fallback: Self.defaultPlumage) }

            if headwear?.id == "head-none" {
                headwearTint = nil
            } else {
                headwearTint = headwear.map { ChickenArtwork.color(hex: $0.tintHex, fallback: Self.defaultHeadwear) }
            }

            backpackTint = backpack.map { ChickenArtwork.color(hex: $0.tintHex, fallback: Self.defaultBackpack) }
        }

        static let traveler = Appearance(
            plumageTint: defaultPlumage,
            headwearTint: nil,
            backpackTint: defaultBackpack
        )

        private static let defaultPlumage = UIColor(red: 0.98, green: 0.77, blue: 0.34, alpha: 1)
        private static let defaultHeadwear = UIColor(red: 0.90, green: 0.39, blue: 0.35, alpha: 1)
        private static let defaultBackpack = UIColor(red: 0.58, green: 0.33, blue: 0.20, alpha: 1)
    }

    static func makeChicken(appearance: Appearance? = nil) -> ChickenArtNode {
        ChickenArtNode(appearance: appearance)
    }

    static func makeCloudPlatform(
        family: CloudFamily,
        width: CGFloat,
        height: CGFloat = 42
    ) -> CloudPlatformNode {
        CloudPlatformNode(family: family, width: width, height: height)
    }

    static func makeFeatherCollectible(tint: UIColor? = nil) -> FeatherCollectibleNode {
        FeatherCollectibleNode(tint: tint)
    }

    static func makeFlowEffect(
        radius: CGFloat = 42,
        tint: UIColor? = nil
    ) -> FlowEffectNode {
        FlowEffectNode(radius: radius, tint: tint)
    }

    static func makeSoftFallEffect(tint: UIColor = .white) -> SoftFallEffectNode {
        SoftFallEffectNode(tint: tint)
    }

    static func makeMorningSky(
        size: CGSize,
        seed: UInt64 = 0xC11C_3EED
    ) -> MorningSkyDecorationNode {
        MorningSkyDecorationNode(size: size, seed: seed)
    }
}

// MARK: - Chicken

@MainActor
final class ChickenArtNode: SKNode {
    private var flowEffect: FlowEffectNode?
    private var plumageLayer = SKNode()
    private var wingLayer = SKNode()
    private var accessoryLayer = SKNode()

    private(set) var appearance: ChickenArtwork.Appearance

    init(appearance: ChickenArtwork.Appearance? = nil) {
        self.appearance = appearance ?? .traveler
        super.init()
        name = "art.chicken"
        rebuild()
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    /// Rebuilds only the illustration, leaving the node's position, scale, and
    /// actions under the renderer's control.
    func apply(appearance: ChickenArtwork.Appearance) {
        self.appearance = appearance
        rebuild()
    }

    func setFlowActive(_ isActive: Bool, reducedMotion: Bool = false) {
        guard let flowEffect else { return }
        flowEffect.setActive(isActive, reducedMotion: reducedMotion)
    }

    func playLandingFeedback(reducedMotion: Bool = false) {
        guard !reducedMotion else { return }

        removeAction(forKey: "art.landing")
        let squat = SKAction.scaleY(to: 0.88, duration: 0.06)
        let spring = SKAction.scaleY(to: 1.06, duration: 0.10)
        let settle = SKAction.scaleY(to: 1, duration: 0.11)
        run(.sequence([squat, spring, settle]), withKey: "art.landing")
    }

    func playSoftFall(reducedMotion: Bool = false) {
        guard !reducedMotion else { return }

        removeAction(forKey: "art.softFall")
        let tilt = SKAction.rotate(toAngle: -0.16, duration: 0.10, shortestUnitArc: true)
        let recover = SKAction.rotate(toAngle: 0, duration: 0.22, shortestUnitArc: true)
        run(.sequence([tilt, recover]), withKey: "art.softFall")
    }

    private func rebuild() {
        removeAllChildren()

        // The playable character uses the same adult-hen illustration as the
        // shell, so the run never falls back to a generic bird or a chick.
        if UIImage(named: "TravelerChickenSprite") != nil {
            let shadow = ChickenArtwork.ellipse(
                size: CGSize(width: 54, height: 12),
                fill: UIColor.black.withAlphaComponent(0.12)
            )
            shadow.position = CGPoint(x: -2, y: -47)
            shadow.zPosition = -8
            addChild(shadow)

            let hen = SKSpriteNode(imageNamed: "TravelerChickenSprite")
            hen.name = "art.adultHen"
            hen.size = CGSize(width: 74, height: 132)
            hen.position = CGPoint(x: 0, y: 6)
            hen.zPosition = 2
            hen.color = appearance.plumageTint ?? .white
            hen.colorBlendFactor = appearance.plumageTint == nil ? 0 : 0.06
            addChild(hen)

            let newFlowEffect = ChickenArtwork.makeFlowEffect(radius: 56)
            newFlowEffect.zPosition = -5
            newFlowEffect.alpha = 0
            addChild(newFlowEffect)
            flowEffect = newFlowEffect
            return
        }

        let plumage = appearance.plumageTint ?? ChickenArtwork.Appearance.traveler.plumageTint ?? .systemYellow
        let outline = ChickenArtwork.mixed(plumage, with: .systemBrown, amount: 0.30)
        let lightPlumage = ChickenArtwork.mixed(plumage, with: .white, amount: 0.26)
        let darkPlumage = ChickenArtwork.mixed(plumage, with: .systemBrown, amount: 0.17)

        let shadow = ChickenArtwork.ellipse(
            size: CGSize(width: 48, height: 11),
            fill: UIColor.black.withAlphaComponent(0.12)
        )
        shadow.position = CGPoint(x: -1, y: -28)
        shadow.zPosition = -8
        addChild(shadow)

        let tail = SKNode()
        tail.zPosition = -2
        let tailFeathers: [(CGPoint, CGSize, CGFloat)] = [
            (CGPoint(x: -30, y: 4), CGSize(width: 24, height: 17), -0.52),
            (CGPoint(x: -32, y: 13), CGSize(width: 23, height: 16), -0.19),
            (CGPoint(x: -27, y: 20), CGSize(width: 21, height: 15), 0.16)
        ]
        for feather in tailFeathers {
            let node = ChickenArtwork.ellipse(size: feather.1, fill: lightPlumage, stroke: outline, lineWidth: 1.2)
            node.position = feather.0
            node.zRotation = feather.2
            tail.addChild(node)
        }
        addChild(tail)

        if let backpackTint = appearance.backpackTint {
            let backpack = SKNode()
            backpack.zPosition = -1

            let packOutline = ChickenArtwork.mixed(backpackTint, with: .systemBrown, amount: 0.35)
            let pack = ChickenArtwork.roundedRect(
                width: 24,
                height: 31,
                cornerRadius: 8,
                fill: backpackTint,
                stroke: packOutline,
                lineWidth: 1.5
            )
            pack.position = CGPoint(x: -27, y: 0)
            backpack.addChild(pack)

            let flap = ChickenArtwork.roundedRect(
                width: 20,
                height: 9,
                cornerRadius: 4,
                fill: ChickenArtwork.mixed(backpackTint, with: .white, amount: 0.16),
                stroke: packOutline,
                lineWidth: 1
            )
            flap.position = CGPoint(x: -27, y: 8)
            backpack.addChild(flap)

            let strapPath = UIBezierPath()
            strapPath.move(to: CGPoint(x: -18, y: 13))
            strapPath.addCurve(
                to: CGPoint(x: -5, y: -12),
                controlPoint1: CGPoint(x: -9, y: 11),
                controlPoint2: CGPoint(x: -4, y: -2)
            )
            backpack.addChild(ChickenArtwork.line(path: strapPath, color: packOutline.withAlphaComponent(0.72), width: 2.2))
            addChild(backpack)
        }

        let legs = SKNode()
        legs.zPosition = 0
        for x in [-8.0, 10.0] {
            let legPath = UIBezierPath()
            legPath.move(to: CGPoint(x: x, y: -20))
            legPath.addLine(to: CGPoint(x: x - 1.5, y: -29))
            legPath.addLine(to: CGPoint(x: x + 3.5, y: -29))
            legs.addChild(ChickenArtwork.line(path: legPath, color: UIColor(red: 0.83, green: 0.46, blue: 0.18, alpha: 1), width: 2.1))
        }
        addChild(legs)

        plumageLayer = SKNode()
        plumageLayer.zPosition = 2
        let body = ChickenArtwork.ellipse(
            size: CGSize(width: 57, height: 47),
            fill: plumage,
            stroke: outline,
            lineWidth: 1.6
        )
        body.position = CGPoint(x: -1, y: -2)
        plumageLayer.addChild(body)

        let belly = ChickenArtwork.ellipse(
            size: CGSize(width: 34, height: 24),
            fill: lightPlumage.withAlphaComponent(0.84)
        )
        belly.position = CGPoint(x: 4, y: -8)
        belly.zPosition = 1
        plumageLayer.addChild(belly)

        let head = ChickenArtwork.ellipse(
            size: CGSize(width: 35, height: 34),
            fill: plumage,
            stroke: outline,
            lineWidth: 1.6
        )
        head.position = CGPoint(x: 17, y: 24)
        head.zPosition = 3
        plumageLayer.addChild(head)

        let cheek = ChickenArtwork.ellipse(
            size: CGSize(width: 13, height: 8),
            fill: UIColor(red: 0.96, green: 0.48, blue: 0.42, alpha: 0.48)
        )
        cheek.position = CGPoint(x: 27, y: 17)
        cheek.zPosition = 4
        plumageLayer.addChild(cheek)

        addChild(plumageLayer)

        wingLayer = SKNode()
        wingLayer.zPosition = 5
        let wing = ChickenArtwork.ellipse(
            size: CGSize(width: 30, height: 26),
            fill: darkPlumage,
            stroke: outline,
            lineWidth: 1.2
        )
        wing.position = CGPoint(x: 2, y: -1)
        wing.zRotation = -0.31
        wingLayer.addChild(wing)

        let wingTip = ChickenArtwork.ellipse(
            size: CGSize(width: 13, height: 12),
            fill: lightPlumage.withAlphaComponent(0.78)
        )
        wingTip.position = CGPoint(x: 10, y: -9)
        wingTip.zRotation = -0.31
        wingLayer.addChild(wingTip)
        addChild(wingLayer)

        let face = SKNode()
        face.zPosition = 8
        let eye = ChickenArtwork.ellipse(size: CGSize(width: 6, height: 7), fill: .black)
        eye.position = CGPoint(x: 23, y: 29)
        face.addChild(eye)
        let eyeSpark = ChickenArtwork.ellipse(size: CGSize(width: 2, height: 2), fill: .white)
        eyeSpark.position = CGPoint(x: 24.2, y: 30.6)
        face.addChild(eyeSpark)

        let beakPath = UIBezierPath()
        beakPath.move(to: CGPoint(x: 33, y: 23))
        beakPath.addLine(to: CGPoint(x: 44, y: 20))
        beakPath.addLine(to: CGPoint(x: 34, y: 17))
        beakPath.close()
        face.addChild(ChickenArtwork.shape(path: beakPath, fill: UIColor(red: 0.95, green: 0.49, blue: 0.16, alpha: 1), stroke: outline, lineWidth: 1))

        let combColor = UIColor(red: 0.91, green: 0.29, blue: 0.31, alpha: 1)
        for point in [CGPoint(x: 9, y: 42), CGPoint(x: 16, y: 45), CGPoint(x: 23, y: 42)] {
            let comb = ChickenArtwork.ellipse(size: CGSize(width: 10, height: 11), fill: combColor, stroke: outline, lineWidth: 1)
            comb.position = point
            face.addChild(comb)
        }
        addChild(face)

        accessoryLayer = SKNode()
        accessoryLayer.zPosition = 12
        if let headwearTint = appearance.headwearTint {
            let capOutline = ChickenArtwork.mixed(headwearTint, with: .systemBrown, amount: 0.32)
            let cap = ChickenArtwork.ellipse(
                size: CGSize(width: 32, height: 15),
                fill: headwearTint,
                stroke: capOutline,
                lineWidth: 1.2
            )
            cap.position = CGPoint(x: 16, y: 40)
            accessoryLayer.addChild(cap)

            let brim = ChickenArtwork.roundedRect(
                width: 25,
                height: 5,
                cornerRadius: 2.5,
                fill: ChickenArtwork.mixed(headwearTint, with: .white, amount: 0.12),
                stroke: capOutline,
                lineWidth: 0.9
            )
            brim.position = CGPoint(x: 27, y: 36)
            brim.zRotation = -0.08
            accessoryLayer.addChild(brim)
        }

        let talisman = ChickenArtwork.miniFeather(tint: UIColor(red: 0.97, green: 0.92, blue: 0.56, alpha: 1), scale: 0.58)
        talisman.position = CGPoint(x: -19, y: -5)
        talisman.zRotation = -0.66
        accessoryLayer.addChild(talisman)
        addChild(accessoryLayer)

        let newFlowEffect = ChickenArtwork.makeFlowEffect(radius: 40)
        newFlowEffect.zPosition = -5
        newFlowEffect.alpha = 0
        addChild(newFlowEffect)
        flowEffect = newFlowEffect
    }
}

// MARK: - Clouds

@MainActor
final class CloudPlatformNode: SKNode {
    private var surfaceLayer = SKNode()
    private var glowLayer: SKShapeNode?

    private(set) var family: CloudFamily
    private(set) var platformWidth: CGFloat
    private(set) var platformHeight: CGFloat

    init(family: CloudFamily, width: CGFloat, height: CGFloat = 42) {
        self.family = family
        platformWidth = max(width, 58)
        platformHeight = max(height, 28)
        super.init()
        name = "art.cloud.\(family.rawValue)"
        rebuild()
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func configure(family: CloudFamily, width: CGFloat, height: CGFloat = 42) {
        self.family = family
        platformWidth = max(width, 58)
        platformHeight = max(height, 28)
        name = "art.cloud.\(family.rawValue)"
        rebuild()
    }

    func setFlowActive(_ isActive: Bool, reducedMotion: Bool = false) {
        if isActive {
            if glowLayer == nil {
                let glow = ChickenArtwork.roundedRect(
                    width: platformWidth + 16,
                    height: platformHeight + 13,
                    cornerRadius: (platformHeight + 13) / 2,
                    fill: ChickenArtwork.flowGold.withAlphaComponent(0.28)
                )
                glow.zPosition = -4
                glowLayer = glow
                addChild(glow)
            }

            glowLayer?.alpha = 1
            guard !reducedMotion else { return }
            glowLayer?.removeAction(forKey: "art.flowGlow")
            let pulseOut = SKAction.fadeAlpha(to: 0.50, duration: 0.45)
            let pulseIn = SKAction.fadeAlpha(to: 0.95, duration: 0.45)
            glowLayer?.run(.repeatForever(.sequence([pulseOut, pulseIn])), withKey: "art.flowGlow")
        } else {
            glowLayer?.removeAllActions()
            glowLayer?.alpha = 0
        }
    }

    func playLandingFeedback(reducedMotion: Bool = false) {
        guard !reducedMotion else { return }
        surfaceLayer.removeAction(forKey: "art.cloudLanding")
        let squash = SKAction.scaleY(to: 0.90, duration: 0.06)
        let rebound = SKAction.scaleY(to: 1.035, duration: 0.11)
        let settle = SKAction.scaleY(to: 1, duration: 0.12)
        surfaceLayer.run(.sequence([squash, rebound, settle]), withKey: "art.cloudLanding")
    }

    /// Gives a storm cloud a short visual warning. It does not change its
    /// lifetime; simulation code remains the authority for that behavior.
    func playStormWarning(reducedMotion: Bool = false) {
        guard family == .storm, !reducedMotion else { return }
        surfaceLayer.removeAction(forKey: "art.stormWarning")
        let dim = SKAction.fadeAlpha(to: 0.60, duration: 0.10)
        let bright = SKAction.fadeAlpha(to: 1, duration: 0.12)
        surfaceLayer.run(.sequence([dim, bright, dim, bright]), withKey: "art.stormWarning")
    }

    private func rebuild() {
        removeAllChildren()
        glowLayer = nil
        surfaceLayer = SKNode()
        surfaceLayer.zPosition = 1
        addChild(surfaceLayer)

        let palette = cloudPalette(for: family)
        let width = platformWidth
        let height = platformHeight

        let shadow = ChickenArtwork.roundedRect(
            width: width * 0.84,
            height: height * 0.42,
            cornerRadius: height * 0.21,
            fill: palette.shadow.withAlphaComponent(0.42)
        )
        shadow.position = CGPoint(x: 0, y: -height * 0.26)
        shadow.zPosition = -1
        surfaceLayer.addChild(shadow)

        let base = ChickenArtwork.roundedRect(
            width: width,
            height: height * 0.63,
            cornerRadius: height * 0.31,
            fill: palette.base,
            stroke: palette.outline,
            lineWidth: 1.1
        )
        base.position = CGPoint(x: 0, y: -height * 0.04)
        surfaceLayer.addChild(base)

        let lobeSpecs: [(CGFloat, CGFloat, CGFloat)] = [
            (-0.35, 0.14, 0.34),
            (-0.15, 0.29, 0.42),
            (0.08, 0.34, 0.46),
            (0.31, 0.20, 0.36)
        ]
        for (fraction, vertical, scale) in lobeSpecs {
            let lobe = ChickenArtwork.ellipse(
                size: CGSize(width: width * scale, height: height * (0.76 + scale * 0.42)),
                fill: palette.highlight,
                stroke: palette.outline.withAlphaComponent(0.72),
                lineWidth: 0.9
            )
            lobe.position = CGPoint(x: width * fraction, y: height * vertical)
            lobe.zPosition = 2
            surfaceLayer.addChild(lobe)
        }

        switch family {
        case .fluffy:
            addFluffyDetails(palette: palette)
        case .windy:
            addWindyDetails(palette: palette)
        case .spring:
            addSpringDetails(palette: palette)
        case .storm:
            addStormDetails(palette: palette)
        }
    }

    private func addFluffyDetails(palette: CloudPalette) {
        let shine = ChickenArtwork.ellipse(
            size: CGSize(width: platformWidth * 0.28, height: platformHeight * 0.18),
            fill: UIColor.white.withAlphaComponent(0.38)
        )
        shine.position = CGPoint(x: -platformWidth * 0.16, y: platformHeight * 0.38)
        shine.zPosition = 4
        surfaceLayer.addChild(shine)
    }

    private func addWindyDetails(palette: CloudPalette) {
        let breeze = UIColor(red: 0.29, green: 0.67, blue: 0.79, alpha: 0.84)
        for (offset, widthScale) in [(-0.16, 0.29), (0.06, 0.35), (0.24, 0.22)] {
            let path = UIBezierPath()
            let startX = platformWidth * (offset - widthScale / 2)
            let endX = platformWidth * (offset + widthScale / 2)
            let y = platformHeight * (offset > 0 ? 0.04 : 0.17)
            path.move(to: CGPoint(x: startX, y: y))
            path.addCurve(
                to: CGPoint(x: endX, y: y + 1),
                controlPoint1: CGPoint(x: startX + platformWidth * 0.08, y: y + 6),
                controlPoint2: CGPoint(x: endX - platformWidth * 0.08, y: y - 6)
            )
            let line = ChickenArtwork.line(path: path, color: breeze, width: 1.8)
            line.zPosition = 5
            surfaceLayer.addChild(line)
        }

        let windDot = ChickenArtwork.ellipse(size: CGSize(width: 5, height: 5), fill: breeze)
        windDot.position = CGPoint(x: platformWidth * 0.33, y: platformHeight * 0.20)
        windDot.zPosition = 5
        surfaceLayer.addChild(windDot)
    }

    private func addSpringDetails(palette: CloudPalette) {
        let coilColor = UIColor(red: 0.58, green: 0.39, blue: 0.77, alpha: 0.88)
        let coil = UIBezierPath()
        let coilWidth = min(platformWidth * 0.32, 38)
        coil.move(to: CGPoint(x: -coilWidth / 2, y: -platformHeight * 0.12))
        coil.addCurve(
            to: CGPoint(x: coilWidth / 2, y: -platformHeight * 0.12),
            controlPoint1: CGPoint(x: -coilWidth * 0.26, y: platformHeight * 0.32),
            controlPoint2: CGPoint(x: coilWidth * 0.24, y: -platformHeight * 0.52)
        )
        coil.addCurve(
            to: CGPoint(x: -coilWidth / 2, y: platformHeight * 0.20),
            controlPoint1: CGPoint(x: coilWidth * 0.18, y: platformHeight * 0.46),
            controlPoint2: CGPoint(x: -coilWidth * 0.31, y: -platformHeight * 0.16)
        )
        let coilNode = ChickenArtwork.line(path: coil, color: coilColor, width: 2.4)
        coilNode.zPosition = 6
        surfaceLayer.addChild(coilNode)

        let arrowPath = UIBezierPath()
        arrowPath.move(to: CGPoint(x: 0, y: platformHeight * 0.35))
        arrowPath.addLine(to: CGPoint(x: -6, y: platformHeight * 0.22))
        arrowPath.addLine(to: CGPoint(x: -2.5, y: platformHeight * 0.22))
        arrowPath.addLine(to: CGPoint(x: -2.5, y: platformHeight * 0.08))
        arrowPath.addLine(to: CGPoint(x: 2.5, y: platformHeight * 0.08))
        arrowPath.addLine(to: CGPoint(x: 2.5, y: platformHeight * 0.22))
        arrowPath.addLine(to: CGPoint(x: 6, y: platformHeight * 0.22))
        arrowPath.close()
        let arrow = ChickenArtwork.shape(path: arrowPath, fill: UIColor.white.withAlphaComponent(0.80), stroke: coilColor, lineWidth: 0.8)
        arrow.zPosition = 7
        surfaceLayer.addChild(arrow)
    }

    private func addStormDetails(palette: CloudPalette) {
        let rainColor = UIColor(red: 0.39, green: 0.69, blue: 0.94, alpha: 0.86)
        for x in [-0.22, 0.02, 0.25] {
            let drop = ChickenArtwork.ellipse(size: CGSize(width: 4, height: 8), fill: rainColor)
            drop.position = CGPoint(x: platformWidth * x, y: -platformHeight * 0.48)
            drop.zRotation = -0.22
            drop.zPosition = 5
            surfaceLayer.addChild(drop)
        }

        let bolt = UIBezierPath()
        bolt.move(to: CGPoint(x: 5, y: platformHeight * 0.28))
        bolt.addLine(to: CGPoint(x: -4, y: -platformHeight * 0.02))
        bolt.addLine(to: CGPoint(x: 1, y: -platformHeight * 0.02))
        bolt.addLine(to: CGPoint(x: -6, y: -platformHeight * 0.33))
        bolt.addLine(to: CGPoint(x: 10, y: -platformHeight * 0.01))
        bolt.addLine(to: CGPoint(x: 4, y: -platformHeight * 0.01))
        bolt.close()
        let boltNode = ChickenArtwork.shape(
            path: bolt,
            fill: UIColor(red: 0.99, green: 0.84, blue: 0.34, alpha: 1),
            stroke: palette.outline,
            lineWidth: 0.8
        )
        boltNode.zPosition = 7
        surfaceLayer.addChild(boltNode)
    }

    private func cloudPalette(for family: CloudFamily) -> CloudPalette {
        switch family {
        case .fluffy:
            CloudPalette(
                base: UIColor(red: 0.88, green: 0.96, blue: 1, alpha: 1),
                highlight: UIColor(red: 0.99, green: 1, blue: 1, alpha: 1),
                shadow: UIColor(red: 0.51, green: 0.73, blue: 0.87, alpha: 1),
                outline: UIColor(red: 0.43, green: 0.66, blue: 0.80, alpha: 1)
            )
        case .windy:
            CloudPalette(
                base: UIColor(red: 0.70, green: 0.91, blue: 0.95, alpha: 1),
                highlight: UIColor(red: 0.89, green: 0.99, blue: 1, alpha: 1),
                shadow: UIColor(red: 0.31, green: 0.65, blue: 0.74, alpha: 1),
                outline: UIColor(red: 0.23, green: 0.54, blue: 0.67, alpha: 1)
            )
        case .spring:
            CloudPalette(
                base: UIColor(red: 0.86, green: 0.78, blue: 0.96, alpha: 1),
                highlight: UIColor(red: 0.97, green: 0.93, blue: 1, alpha: 1),
                shadow: UIColor(red: 0.58, green: 0.43, blue: 0.77, alpha: 1),
                outline: UIColor(red: 0.48, green: 0.33, blue: 0.68, alpha: 1)
            )
        case .storm:
            CloudPalette(
                base: UIColor(red: 0.37, green: 0.48, blue: 0.67, alpha: 1),
                highlight: UIColor(red: 0.54, green: 0.64, blue: 0.81, alpha: 1),
                shadow: UIColor(red: 0.18, green: 0.25, blue: 0.42, alpha: 1),
                outline: UIColor(red: 0.14, green: 0.21, blue: 0.38, alpha: 1)
            )
        }
    }
}

private struct CloudPalette {
    let base: UIColor
    let highlight: UIColor
    let shadow: UIColor
    let outline: UIColor
}

// MARK: - Collectibles and effects

@MainActor
final class FeatherCollectibleNode: SKNode {
    private let feather: SKNode
    private var isCollecting = false

    init(tint: UIColor? = nil) {
        let resolvedTint = tint ?? ChickenArtwork.featherGold
        feather = ChickenArtwork.miniFeather(tint: resolvedTint, scale: 1)
        super.init()
        name = "art.feather"

        let halo = ChickenArtwork.ellipse(
            size: CGSize(width: 22, height: 22),
            fill: resolvedTint.withAlphaComponent(0.18)
        )
        halo.zPosition = -1
        addChild(halo)

        addChild(feather)
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func setIdleMotionEnabled(_ isEnabled: Bool) {
        removeAction(forKey: "art.featherIdle")
        guard isEnabled else {
            zRotation = 0
            return
        }

        let tiltRight = SKAction.rotate(toAngle: 0.16, duration: 0.52, shortestUnitArc: true)
        let tiltLeft = SKAction.rotate(toAngle: -0.14, duration: 0.52, shortestUnitArc: true)
        run(.repeatForever(.sequence([tiltRight, tiltLeft])), withKey: "art.featherIdle")
    }

    func playCollection(removeWhenFinished: Bool = true, reducedMotion: Bool = false) {
        guard !isCollecting else { return }
        isCollecting = true
        removeAllActions()

        if reducedMotion {
            alpha = 0
            if removeWhenFinished {
                removeFromParent()
            }
            return
        }

        let rise = SKAction.moveBy(x: 0, y: 18, duration: 0.16)
        let scale = SKAction.scale(to: 1.45, duration: 0.16)
        let fade = SKAction.fadeOut(withDuration: 0.16)
        var actions: [SKAction] = [.group([rise, scale, fade])]
        if removeWhenFinished {
            actions.append(.removeFromParent())
        }
        run(.sequence(actions), withKey: "art.featherCollect")
    }
}

@MainActor
final class FlowEffectNode: SKNode {
    private let radius: CGFloat
    private let tint: UIColor
    private let rotatingLayer = SKNode()

    init(radius: CGFloat = 42, tint: UIColor? = nil) {
        self.radius = max(radius, 16)
        self.tint = tint ?? ChickenArtwork.flowGold
        super.init()
        name = "art.flow"
        build()
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func setActive(_ isActive: Bool, reducedMotion: Bool = false) {
        if isActive {
            alpha = 1
            guard !reducedMotion else { return }
            rotatingLayer.removeAction(forKey: "art.flowRotate")
            rotatingLayer.run(
                .repeatForever(.rotate(byAngle: -.pi * 2, duration: 1.8)),
                withKey: "art.flowRotate"
            )
            removeAction(forKey: "art.flowPulse")
            let smaller = SKAction.scale(to: 0.94, duration: 0.46)
            let larger = SKAction.scale(to: 1.05, duration: 0.46)
            run(.repeatForever(.sequence([smaller, larger])), withKey: "art.flowPulse")
        } else {
            removeAllActions()
            rotatingLayer.removeAllActions()
            alpha = 0
            setScale(1)
        }
    }

    private func build() {
        let halo = ChickenArtwork.ellipse(
            size: CGSize(width: radius * 1.46, height: radius * 0.92),
            fill: tint.withAlphaComponent(0.13),
            stroke: tint.withAlphaComponent(0.42),
            lineWidth: 1.1
        )
        halo.zPosition = -1
        addChild(halo)

        for index in 0..<8 {
            let angle = CGFloat(index) / 8 * (.pi * 2)
            let feather = ChickenArtwork.miniFeather(tint: tint.withAlphaComponent(0.86), scale: 0.46)
            feather.position = CGPoint(x: cos(angle) * radius * 0.68, y: sin(angle) * radius * 0.38)
            feather.zRotation = angle + .pi / 2
            rotatingLayer.addChild(feather)
        }
        addChild(rotatingLayer)
    }
}

@MainActor
final class SoftFallEffectNode: SKNode {
    private let tint: UIColor

    init(tint: UIColor = .white) {
        self.tint = tint
        super.init()
        name = "art.softFall"
        build()
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    /// The renderer can add this node at the landing position and trigger the
    /// one-shot effect without managing individual puff children.
    func playAndRemove(reducedMotion: Bool = false) {
        removeAllActions()
        if reducedMotion {
            removeFromParent()
            return
        }

        let spread = SKAction.group([
            .scale(to: 1.55, duration: 0.28),
            .fadeOut(withDuration: 0.28)
        ])
        run(.sequence([spread, .removeFromParent()]), withKey: "art.softFallRemove")
    }

    private func build() {
        let positions: [CGPoint] = [
            CGPoint(x: -18, y: 0), CGPoint(x: -8, y: 4), CGPoint(x: 4, y: 3),
            CGPoint(x: 15, y: 0), CGPoint(x: 24, y: 2)
        ]
        for (index, point) in positions.enumerated() {
            let size = CGFloat(15 + (index % 3) * 4)
            let puff = ChickenArtwork.ellipse(
                size: CGSize(width: size, height: size * 0.62),
                fill: tint.withAlphaComponent(index.isMultiple(of: 2) ? 0.72 : 0.52)
            )
            puff.position = point
            puff.zPosition = CGFloat(index)
            addChild(puff)
        }

        for point in [CGPoint(x: -28, y: 8), CGPoint(x: 29, y: 9)] {
            let feather = ChickenArtwork.miniFeather(tint: tint.withAlphaComponent(0.82), scale: 0.30)
            feather.position = point
            feather.zRotation = point.x < 0 ? -0.62 : 0.62
            feather.zPosition = 8
            addChild(feather)
        }
    }
}

// MARK: - Morning sky

@MainActor
final class MorningSkyDecorationNode: SKNode {
    private var renderedSize: CGSize
    private var seed: UInt64
    private let distantLayer = SKNode()
    private let cloudLayer = SKNode()

    init(size: CGSize, seed: UInt64 = 0xC11C_3EED) {
        renderedSize = size
        self.seed = seed
        super.init()
        name = "art.morningSky"
        rebuild()
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func resize(to size: CGSize) {
        guard size != renderedSize else { return }
        renderedSize = size
        rebuild()
    }

    /// Allows a scene to add a subtle parallax shift without giving the artwork
    /// ownership of camera or gameplay timing.
    func setParallaxOffset(x: CGFloat, y: CGFloat = 0) {
        distantLayer.position = CGPoint(x: x * 0.16, y: y * 0.08)
        cloudLayer.position = CGPoint(x: x * 0.32, y: y * 0.18)
    }

    private func rebuild() {
        removeAllChildren()
        distantLayer.removeAllChildren()
        cloudLayer.removeAllChildren()

        let width = max(renderedSize.width, 1)
        let height = max(renderedSize.height, 1)
        let bounds = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)

        let sky = SKShapeNode(rect: bounds)
        sky.fillColor = UIColor(red: 0.46, green: 0.78, blue: 0.96, alpha: 1)
        sky.strokeColor = .clear
        sky.zPosition = -200
        addChild(sky)

        let lowerGlow = SKShapeNode(rect: CGRect(x: bounds.minX, y: bounds.minY, width: width, height: height * 0.42))
        lowerGlow.fillColor = UIColor(red: 0.78, green: 0.92, blue: 1, alpha: 0.64)
        lowerGlow.strokeColor = .clear
        lowerGlow.zPosition = -199
        addChild(lowerGlow)

        let sunGlow = ChickenArtwork.ellipse(
            size: CGSize(width: min(width * 0.38, 190), height: min(width * 0.38, 190)),
            fill: UIColor(red: 1, green: 0.89, blue: 0.49, alpha: 0.20)
        )
        sunGlow.position = CGPoint(x: -width * 0.28, y: height * 0.23)
        sunGlow.zPosition = -196
        distantLayer.addChild(sunGlow)

        let sun = ChickenArtwork.ellipse(
            size: CGSize(width: min(width * 0.20, 96), height: min(width * 0.20, 96)),
            fill: UIColor(red: 1, green: 0.81, blue: 0.31, alpha: 0.94)
        )
        sun.position = sunGlow.position
        sun.zPosition = -195
        distantLayer.addChild(sun)

        let rayColor = UIColor(red: 1, green: 0.93, blue: 0.59, alpha: 0.74)
        let rayRadius = min(width * 0.15, 72)
        for index in 0..<8 {
            let angle = CGFloat(index) / 8 * (.pi * 2)
            let start = CGPoint(
                x: sun.position.x + cos(angle) * rayRadius,
                y: sun.position.y + sin(angle) * rayRadius
            )
            let end = CGPoint(
                x: sun.position.x + cos(angle) * (rayRadius + 11),
                y: sun.position.y + sin(angle) * (rayRadius + 11)
            )
            let rayPath = UIBezierPath()
            rayPath.move(to: start)
            rayPath.addLine(to: end)
            let ray = ChickenArtwork.line(path: rayPath, color: rayColor, width: 2)
            ray.zPosition = -196
            distantLayer.addChild(ray)
        }
        addChild(distantLayer)

        var random = ArtworkRandom(seed: seed)
        for index in 0..<6 {
            let cloudWidth = width * (0.18 + random.nextUnit() * 0.16)
            let cloudHeight = cloudWidth * (0.24 + random.nextUnit() * 0.10)
            let x = bounds.minX + width * (0.08 + random.nextUnit() * 0.84)
            let y = bounds.minY + height * (0.18 + random.nextUnit() * 0.68)
            let cloud = makeSkyWisp(width: cloudWidth, height: cloudHeight, alpha: 0.22 + random.nextUnit() * 0.18)
            cloud.position = CGPoint(x: x, y: y)
            cloud.zPosition = -190 + CGFloat(index)
            cloudLayer.addChild(cloud)
        }

        for index in 0..<3 {
            let bird = makeDistantBird()
            bird.position = CGPoint(
                x: bounds.minX + width * (0.52 + random.nextUnit() * 0.40),
                y: bounds.minY + height * (0.55 + random.nextUnit() * 0.24)
            )
            bird.setScale(0.65 + CGFloat(index) * 0.13)
            bird.zPosition = -180
            cloudLayer.addChild(bird)
        }
        addChild(cloudLayer)
    }

    private func makeSkyWisp(width: CGFloat, height: CGFloat, alpha: CGFloat) -> SKNode {
        let wisp = SKNode()
        let color = UIColor.white.withAlphaComponent(alpha)
        let lobeData: [(CGFloat, CGFloat, CGFloat)] = [(-0.28, 0.0, 0.42), (-0.04, 0.15, 0.54), (0.25, 0.02, 0.45)]
        for (x, y, scale) in lobeData {
            let lobe = ChickenArtwork.ellipse(
                size: CGSize(width: width * scale, height: height * (0.72 + scale * 0.22)),
                fill: color
            )
            lobe.position = CGPoint(x: width * x, y: height * y)
            wisp.addChild(lobe)
        }
        return wisp
    }

    private func makeDistantBird() -> SKNode {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -7, y: 0))
        path.addQuadCurve(to: CGPoint(x: 0, y: 2), controlPoint: CGPoint(x: -3.5, y: 4))
        path.addQuadCurve(to: CGPoint(x: 7, y: 0), controlPoint: CGPoint(x: 3.5, y: 4))
        let bird = ChickenArtwork.line(path: path, color: UIColor.white.withAlphaComponent(0.74), width: 1.25)
        return bird
    }
}

// MARK: - Drawing primitives

private extension ChickenArtwork {
    static let featherGold = UIColor(red: 0.98, green: 0.78, blue: 0.24, alpha: 1)
    static let flowGold = UIColor(red: 1, green: 0.91, blue: 0.46, alpha: 1)

    static func color(hex: String, fallback: UIColor) -> UIColor {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return fallback }

        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    static func mixed(_ base: UIColor, with other: UIColor, amount: CGFloat) -> UIColor {
        let amount = min(max(amount, 0), 1)
        var baseRed: CGFloat = 0
        var baseGreen: CGFloat = 0
        var baseBlue: CGFloat = 0
        var baseAlpha: CGFloat = 0
        var otherRed: CGFloat = 0
        var otherGreen: CGFloat = 0
        var otherBlue: CGFloat = 0
        var otherAlpha: CGFloat = 0

        guard base.getRed(&baseRed, green: &baseGreen, blue: &baseBlue, alpha: &baseAlpha),
              other.getRed(&otherRed, green: &otherGreen, blue: &otherBlue, alpha: &otherAlpha)
        else {
            return base
        }

        return UIColor(
            red: baseRed + (otherRed - baseRed) * amount,
            green: baseGreen + (otherGreen - baseGreen) * amount,
            blue: baseBlue + (otherBlue - baseBlue) * amount,
            alpha: baseAlpha + (otherAlpha - baseAlpha) * amount
        )
    }

    static func ellipse(
        size: CGSize,
        fill: UIColor,
        stroke: UIColor = .clear,
        lineWidth: CGFloat = 0
    ) -> SKShapeNode {
        let node = SKShapeNode(ellipseOf: size)
        node.fillColor = fill
        node.strokeColor = stroke
        node.lineWidth = lineWidth
        node.isAntialiased = true
        return node
    }

    static func roundedRect(
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        fill: UIColor,
        stroke: UIColor = .clear,
        lineWidth: CGFloat = 0
    ) -> SKShapeNode {
        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        let node = SKShapeNode(rect: rect, cornerRadius: cornerRadius)
        node.fillColor = fill
        node.strokeColor = stroke
        node.lineWidth = lineWidth
        node.isAntialiased = true
        return node
    }

    static func shape(
        path: UIBezierPath,
        fill: UIColor,
        stroke: UIColor = .clear,
        lineWidth: CGFloat = 0
    ) -> SKShapeNode {
        let node = SKShapeNode(path: path.cgPath)
        node.fillColor = fill
        node.strokeColor = stroke
        node.lineWidth = lineWidth
        node.lineJoin = .round
        node.lineCap = .round
        node.isAntialiased = true
        return node
    }

    static func line(path: UIBezierPath, color: UIColor, width: CGFloat) -> SKShapeNode {
        let node = SKShapeNode(path: path.cgPath)
        node.fillColor = .clear
        node.strokeColor = color
        node.lineWidth = width
        node.lineCap = .round
        node.lineJoin = .round
        node.isAntialiased = true
        return node
    }

    static func miniFeather(tint: UIColor, scale: CGFloat) -> SKNode {
        let feather = SKNode()
        feather.setScale(scale)

        let plumePath = UIBezierPath()
        plumePath.move(to: CGPoint(x: 0, y: -12))
        plumePath.addCurve(
            to: CGPoint(x: 8, y: 11),
            controlPoint1: CGPoint(x: 8, y: -7),
            controlPoint2: CGPoint(x: 10, y: 6)
        )
        plumePath.addCurve(
            to: CGPoint(x: 0, y: 15),
            controlPoint1: CGPoint(x: 6, y: 14),
            controlPoint2: CGPoint(x: 2, y: 16)
        )
        plumePath.addCurve(
            to: CGPoint(x: -7, y: -3),
            controlPoint1: CGPoint(x: -8, y: 10),
            controlPoint2: CGPoint(x: -10, y: 0)
        )
        plumePath.close()

        let plume = shape(
            path: plumePath,
            fill: tint,
            stroke: mixed(tint, with: .systemOrange, amount: 0.25),
            lineWidth: 0.8
        )
        feather.addChild(plume)

        let shaft = UIBezierPath()
        shaft.move(to: CGPoint(x: -1, y: -15))
        shaft.addLine(to: CGPoint(x: 1, y: 14))
        feather.addChild(line(path: shaft, color: UIColor.white.withAlphaComponent(0.68), width: 0.8))

        return feather
    }
}

private struct ArtworkRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func nextUnit() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return CGFloat(Double(value) / Double(UInt64.max))
    }
}
