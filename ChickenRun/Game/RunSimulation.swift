//
//  RunSimulation.swift
//  ChickenRun
//
//  Deterministic, renderer-agnostic gameplay for one Chicken Run flight.
//  SpriteKit (or any other renderer) owns presentation and calls `advance` or
//  `step`; this file owns only simulation state, scoring, and generated routes.
//

import Foundation
import CoreGraphics

/// A frame's worth of player intent.
///
/// `horizontal` is continuously sampled in the -1...1 range. `flapPressed`
/// and `pauseTogglePressed` are edge-triggered values and should be `true`
/// only on the update where the corresponding control was pressed.
struct RunInput: Equatable {
    let horizontal: CGFloat
    let flapPressed: Bool
    let pauseTogglePressed: Bool

    init(
        horizontal: CGFloat = 0,
        flapPressed: Bool = false,
        pauseTogglePressed: Bool = false
    ) {
        let safeHorizontal = horizontal.isFinite ? horizontal : 0
        self.horizontal = min(max(safeHorizontal, -1), 1)
        self.flapPressed = flapPressed
        self.pauseTogglePressed = pauseTogglePressed
    }

    static let neutral = RunInput()
}

/// Presentation-neutral player data in world coordinates (points and points per second).
struct SimulationPlayer: Equatable {
    let position: CGPoint
    let velocity: CGPoint
    let radius: CGFloat
    let isAirflowActive: Bool
}

/// Presentation-neutral cloud data. `position` is the cloud's center in world coordinates.
struct SimulationCloud: Equatable, Identifiable {
    let id: Int
    let family: CloudFamily
    let position: CGPoint
    let size: CGSize
    let isAvailable: Bool
    let isStormDissolving: Bool
}

/// A feather collectible in world coordinates.
struct SimulationFeather: Equatable, Identifiable {
    let id: Int
    let position: CGPoint
    let value: Int
}

/// Discrete facts emitted during the most recent call to `advance` or `step`.
/// A renderer can use these for particles, sound, haptics, or state transitions.
enum SimulationEvent: Equatable {
    case landed(cloudID: Int, family: CloudFamily, bounceVelocity: CGFloat)
    case featherCollected(featherID: Int, totalCollected: Int, flapCharge: Int)
    case flapActivated
    case airflowActivated(duration: TimeInterval)
    case airflowExpired
    case stormCloudTriggered(cloudID: Int)
    case stormCloudDissolved(cloudID: Int)
    case paused
    case resumed
    case finished(FlightResult)
}

/// A complete immutable read model for a future SpriteKit renderer.
struct RunSnapshot: Equatable {
    let elapsedTime: TimeInterval
    let player: SimulationPlayer
    let clouds: [SimulationCloud]
    let feathers: [SimulationFeather]
    /// Bottom edge of the upward-only camera in world coordinates.
    let cameraY: CGFloat
    let height: Int
    let score: Int
    let collectedFeathers: Int
    let flapCharge: Int
    let flapRequirement: Int
    let currentStreak: Int
    let bestStreak: Int
    let airflowRemaining: TimeInterval
    let isPaused: Bool
    let isFinished: Bool
    let finishedResult: FlightResult?
}

/// Fixed-step, deterministic flight simulation.
///
/// The same seed, sequence of `RunInput` values, and fixed-step calls produce
/// the same world. `advance(by:input:)` is convenient for display loops and
/// internally consumes the configured fixed time step; `step(input:)` is for
/// hosts that already own a fixed-timestep loop.
final class RunSimulation {
    struct Configuration: Equatable {
        let viewportSize: CGSize
        let fixedTimeStep: TimeInterval
        let seed: UInt64

        init(
            viewportSize: CGSize = CGSize(width: 390, height: 844),
            fixedTimeStep: TimeInterval = 1.0 / 120.0,
            seed: UInt64 = 0xC1C0_0000_0000_0001
        ) {
            let safeWidth = viewportSize.width.isFinite ? viewportSize.width : 390
            let safeHeight = viewportSize.height.isFinite ? viewportSize.height : 844
            let safeTimeStep = fixedTimeStep.isFinite ? fixedTimeStep : 1.0 / 120.0
            self.viewportSize = CGSize(
                width: max(safeWidth, 200),
                height: max(safeHeight, 300)
            )
            self.fixedTimeStep = min(max(safeTimeStep, 1.0 / 240.0), 1.0 / 30.0)
            self.seed = seed
        }
    }

    let configuration: Configuration
    private(set) var lastEvents: [SimulationEvent] = []
    private(set) var finishedResult: FlightResult?

    /// The current complete render model. It contains no SpriteKit types.
    var snapshot: RunSnapshot {
        RunSnapshot(
            elapsedTime: elapsedTime,
            player: SimulationPlayer(
                position: player.position,
                velocity: player.velocity,
                radius: Self.playerRadius,
                isAirflowActive: airflowRemaining > 0
            ),
            clouds: clouds
                .map { cloud in
                    SimulationCloud(
                        id: cloud.id,
                        family: cloud.family,
                        position: cloud.position(at: elapsedTime),
                        size: cloud.size,
                        isAvailable: cloud.isAvailable,
                        isStormDissolving: cloud.stormDissolveRemaining != nil
                    )
                }
                .sorted { lhs, rhs in lhs.position.y < rhs.position.y },
            feathers: feathers
                .map { SimulationFeather(id: $0.id, position: $0.position, value: $0.value) }
                .sorted { lhs, rhs in lhs.position.y < rhs.position.y },
            cameraY: cameraY,
            height: highestHeight,
            score: score,
            collectedFeathers: collectedFeathers,
            flapCharge: flapCharge,
            flapRequirement: GameBalance.feathersForFlap,
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            airflowRemaining: max(0, airflowRemaining),
            isPaused: isPaused,
            isFinished: isFinished,
            finishedResult: finishedResult
        )
    }

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        random = SplitMix64(seed: configuration.seed)
        player = PlayerState(position: .zero, velocity: .zero)
        resetWorld(seed: configuration.seed)
    }

    /// Advances by a render-frame duration while preserving fixed simulation steps.
    /// Durations longer than a quarter second are clamped to avoid a catch-up spiral.
    @discardableResult
    func advance(by elapsed: TimeInterval, input: RunInput = .neutral) -> [SimulationEvent] {
        beginEventCollection()

        if input.pauseTogglePressed {
            setPaused(!isPaused)
            finishEventCollection()
            return lastEvents
        }

        guard !isPaused, !isFinished else {
            finishEventCollection()
            return lastEvents
        }

        pendingFlapPress = pendingFlapPress || input.flapPressed
        let safeElapsed = elapsed.isFinite ? elapsed : 0
        let clampedElapsed = min(max(safeElapsed, 0), Self.maximumFrameDelta)
        accumulator += clampedElapsed

        var steps = 0
        while accumulator >= configuration.fixedTimeStep, steps < Self.maximumStepsPerAdvance, !isFinished {
            let fixedInput = RunInput(
                horizontal: input.horizontal,
                flapPressed: pendingFlapPress,
                pauseTogglePressed: false
            )
            pendingFlapPress = false
            simulateFixedStep(input: fixedInput)
            accumulator -= configuration.fixedTimeStep
            steps += 1
        }

        // Drop excess time after a very slow frame rather than simulating an old input burst.
        if steps == Self.maximumStepsPerAdvance {
            accumulator = 0
        }

        finishEventCollection()
        return lastEvents
    }

    /// Advances exactly one configured fixed time step.
    @discardableResult
    func step(input: RunInput = .neutral) -> [SimulationEvent] {
        beginEventCollection()

        if input.pauseTogglePressed {
            setPaused(!isPaused)
            finishEventCollection()
            return lastEvents
        }

        guard !isPaused, !isFinished else {
            finishEventCollection()
            return lastEvents
        }

        let fixedInput = RunInput(
            horizontal: input.horizontal,
            flapPressed: pendingFlapPress || input.flapPressed,
            pauseTogglePressed: false
        )
        pendingFlapPress = false
        simulateFixedStep(input: fixedInput)
        finishEventCollection()
        return lastEvents
    }

    /// Freezes simulation immediately. Calling it while already paused is a no-op.
    func pause() {
        beginEventCollection()
        setPaused(true)
        finishEventCollection()
    }

    /// Resumes a paused, unfinished run. Calling it while running is a no-op.
    func resume() {
        beginEventCollection()
        setPaused(false)
        finishEventCollection()
    }

    /// Starts a fresh deterministic run. Passing a seed is useful for replay tests.
    func restart(seed: UInt64? = nil) {
        resetWorld(seed: seed ?? configuration.seed)
        lastEvents = []
    }

    // MARK: - Fixed-step simulation

    private func simulateFixedStep(input: RunInput) {
        let dt = configuration.fixedTimeStep
        elapsedTime += dt

        updateStormClouds(by: dt)
        updateAirflow(by: dt)
        applyHorizontalInput(input.horizontal, deltaTime: dt)

        if input.flapPressed {
            activateFlapIfReady()
        }

        let previousPosition = player.position
        player.velocity.y += Self.gravity * CGFloat(dt)
        player.position.x += player.velocity.x * CGFloat(dt)
        player.position.y += player.velocity.y * CGFloat(dt)
        constrainPlayerToHorizontalBounds()

        if player.velocity.y <= 0 {
            resolveLanding(from: previousPosition)
        }

        collectTouchedFeathers()
        updateHeightAndScore()
        updateCamera()
        generateRoute(until: cameraY + configuration.viewportSize.height + Self.generationLookAhead)
        pruneOffscreenObjects()

        if player.position.y + Self.playerRadius < cameraY - Self.deathPadding {
            finishRun()
        }
    }

    private func applyHorizontalInput(_ input: CGFloat, deltaTime: TimeInterval) {
        let direction = min(max(input, -1), 1)
        let dt = CGFloat(deltaTime)

        player.velocity.x += direction * Self.horizontalAcceleration * dt
        if abs(direction) < 0.01 {
            let deceleration = Self.horizontalDeceleration * dt
            if abs(player.velocity.x) <= deceleration {
                player.velocity.x = 0
            } else {
                player.velocity.x -= player.velocity.x.sign == .minus ? -deceleration : deceleration
            }
        }
        player.velocity.x = min(max(player.velocity.x, -Self.maximumHorizontalSpeed), Self.maximumHorizontalSpeed)
    }

    private func constrainPlayerToHorizontalBounds() {
        let minimumX = Self.playerRadius
        let maximumX = configuration.viewportSize.width - Self.playerRadius

        if player.position.x < minimumX {
            player.position.x = minimumX
            player.velocity.x = max(0, player.velocity.x)
        } else if player.position.x > maximumX {
            player.position.x = maximumX
            player.velocity.x = min(0, player.velocity.x)
        }
    }

    private func resolveLanding(from previousPosition: CGPoint) {
        let previousBottom = previousPosition.y - Self.playerRadius
        let currentBottom = player.position.y - Self.playerRadius
        guard currentBottom <= previousBottom else { return }

        var bestCandidate: (index: Int, topY: CGFloat)?
        for index in clouds.indices {
            let cloud = clouds[index]
            guard cloud.isAvailable else { continue }

            let cloudPosition = cloud.position(at: elapsedTime)
            let topY = cloudPosition.y + cloud.size.height / 2
            let horizontalReach = cloud.size.width / 2 + Self.playerRadius
            let overlapsHorizontally = abs(player.position.x - cloudPosition.x) <= horizontalReach

            guard
                overlapsHorizontally,
                previousBottom >= topY,
                currentBottom <= topY
            else {
                continue
            }

            if bestCandidate == nil || topY > bestCandidate!.topY {
                bestCandidate = (index, topY)
            }
        }

        guard let candidate = bestCandidate else { return }
        let cloud = clouds[candidate.index]

        player.position.y = candidate.topY + Self.playerRadius
        registerLanding(on: cloud)

        if cloud.family == .storm {
            clouds[candidate.index].stormDissolveRemaining = Self.stormDissolveDuration
            emit(.stormCloudTriggered(cloudID: cloud.id))
        }

        var bounceVelocity = cloud.family == .spring ? Self.springBounceVelocity : Self.normalBounceVelocity
        if pendingAirflowBounce {
            bounceVelocity *= Self.airflowBounceMultiplier
            pendingAirflowBounce = false
        }
        player.velocity.y = bounceVelocity
        emit(.landed(cloudID: cloud.id, family: cloud.family, bounceVelocity: bounceVelocity))
    }

    private func registerLanding(on cloud: CloudState) {
        if lastLandingFamily == cloud.family {
            currentStreak += 1
        } else {
            currentStreak = 1
            lastLandingFamily = cloud.family
        }
        bestStreak = max(bestStreak, currentStreak)

        guard currentStreak == Self.landingsForAirflow else { return }
        airflowRemaining = GameBalance.flowDuration
        pendingAirflowBounce = true
        didTriggerAirflow = true
        emit(.airflowActivated(duration: GameBalance.flowDuration))
    }

    private func activateFlapIfReady() {
        guard flapCharge >= GameBalance.feathersForFlap else { return }
        flapCharge = 0
        player.velocity.y = max(player.velocity.y, Self.flapVelocity)
        didUseFlap = true
        emit(.flapActivated)
    }

    private func collectTouchedFeathers() {
        var uncollected: [FeatherState] = []
        for feather in feathers {
            let dx = player.position.x - feather.position.x
            let dy = player.position.y - feather.position.y
            let reach = Self.playerRadius + Self.featherRadius
            if dx * dx + dy * dy <= reach * reach {
                collectedFeathers += feather.value
                flapCharge = min(GameBalance.feathersForFlap, flapCharge + feather.value)
                score += Self.featherScore * feather.value * currentScoreMultiplier
                emit(.featherCollected(
                    featherID: feather.id,
                    totalCollected: collectedFeathers,
                    flapCharge: flapCharge
                ))
            } else {
                uncollected.append(feather)
            }
        }
        feathers = uncollected
    }

    private func updateHeightAndScore() {
        let rawHeight = max(0, Int((player.position.y - startingCloudTop).rounded(.down)))
        guard rawHeight > highestHeight else { return }

        score += (rawHeight - highestHeight) * currentScoreMultiplier
        highestHeight = rawHeight
    }

    private func updateAirflow(by deltaTime: TimeInterval) {
        guard airflowRemaining > 0 else { return }
        airflowRemaining -= deltaTime
        if airflowRemaining <= 0 {
            airflowRemaining = 0
            emit(.airflowExpired)
        }
    }

    private func updateStormClouds(by deltaTime: TimeInterval) {
        var dissolvedCloudIDs: [Int] = []
        for index in clouds.indices {
            guard let remaining = clouds[index].stormDissolveRemaining else { continue }
            let nextRemaining = remaining - deltaTime
            if nextRemaining <= 0 {
                dissolvedCloudIDs.append(clouds[index].id)
            } else {
                clouds[index].stormDissolveRemaining = nextRemaining
            }
        }

        guard !dissolvedCloudIDs.isEmpty else { return }
        let dissolvedSet = Set(dissolvedCloudIDs)
        clouds.removeAll { dissolvedSet.contains($0.id) }
        for id in dissolvedCloudIDs {
            emit(.stormCloudDissolved(cloudID: id))
        }
    }

    private func updateCamera() {
        let desiredCameraY = player.position.y - configuration.viewportSize.height * Self.cameraPlayerHeightFraction
        cameraY = max(cameraY, desiredCameraY)
    }

    // MARK: - Safe procedural route

    /// Adds tiers until both the visible area and a generous buffer have a safe route.
    /// Every tier contains a wide stationary fluffy cloud. The optional specialty
    /// cloud is a voluntary risk beside it, so it can never be the only route up.
    private func generateRoute(until targetY: CGFloat) {
        while lastSafeCloudY < targetY {
            appendSafeRouteTier()
        }
    }

    private func appendSafeRouteTier() {
        let progress = Self.routeDifficultyProgress(
            at: lastSafeCloudY,
            startingCloudTop: startingCloudTop
        )
        let gap = random.value(in: Self.minimumSafeGap...Self.maximumSafeGap(progress: progress))
        let safeWidth = Self.safeCloudWidth(progress: progress)
        let previousSafeX = lastSafeCloudX
        let safeY = lastSafeCloudY + gap
        let preferredDirection: CGFloat = random.bool() ? 1 : -1
        let preferredIsTurnaround = lastSafeTravelDirection.map { $0 != preferredDirection } ?? false
        let offsetUnit = random.value(in: 0...1)
        let preferredOffset = Self.safeHorizontalOffset(
            progress: progress,
            isTurnaround: preferredIsTurnaround,
            unit: offsetUnit
        )
        let preferredSafeX = clampCloudX(
            previousSafeX + preferredDirection * preferredOffset,
            width: safeWidth,
            horizontalAmplitude: 0
        )
        let alternateDirection = -preferredDirection
        let alternateIsTurnaround = lastSafeTravelDirection.map { $0 != alternateDirection } ?? false
        let alternateOffset = Self.safeHorizontalOffset(
            progress: progress,
            isTurnaround: alternateIsTurnaround,
            unit: offsetUnit
        )
        let alternateSafeX = clampCloudX(
            previousSafeX + alternateDirection * alternateOffset,
            width: safeWidth,
            horizontalAmplitude: 0
        )
        // A direction change is deliberately short: it gives the player time
        // to cancel the previous lateral velocity before the route heads back
        // across the sky. At an edge, prefer the candidate that keeps moving.
        let safeX = abs(alternateSafeX - previousSafeX) > abs(preferredSafeX - previousSafeX)
            ? alternateSafeX
            : preferredSafeX

        appendCloud(
            family: .fluffy,
            position: CGPoint(x: safeX, y: safeY),
            size: CGSize(width: safeWidth, height: Self.cloudHeight),
            horizontalAmplitude: 0,
            windAngularVelocity: 0,
            phase: 0
        )

        let previousSafeY = lastSafeCloudY
        lastSafeCloudX = safeX
        lastSafeCloudY = safeY
        if abs(safeX - previousSafeX) > 0.5 {
            lastSafeTravelDirection = safeX > previousSafeX ? 1 : -1
        }

        // The opening provides enough feathers to teach the rescue flap. Once
        // the route starts asking for steering, feathers become a deliberate
        // reward instead of an automatic refill every five landings.
        if shouldAppendFeather {
            let featherOffset = Self.featherHorizontalOffset(progress: progress)
            let featherX = min(
                max(safeX + random.value(in: -featherOffset...featherOffset), Self.featherRadius),
                configuration.viewportSize.width - Self.featherRadius
            )
            appendFeather(position: CGPoint(x: featherX, y: previousSafeY + gap * 0.52))
        }

        appendSpecialtyCloud(
            previousSafeX: previousSafeX,
            previousSafeY: previousSafeY,
            safeX: safeX,
            safeY: safeY,
            progress: progress
        )
        generatedTierCount += 1
    }

    /// Adds an optional detour only every few safe tiers. It lives halfway
    /// between two safe platforms and fully outside their horizontal route, so
    /// it cannot visually stack on or steal a landing from the main path.
    private func appendSpecialtyCloud(
        previousSafeX: CGFloat,
        previousSafeY: CGFloat,
        safeX: CGFloat,
        safeY: CGFloat,
        progress: CGFloat
    ) {
        guard shouldAppendSpecialtyCloud else { return }

        let specialtyFamilies: [CloudFamily] = [.windy, .spring, .storm]
        let specialtyIndex = (generatedTierCount + 1) / Self.specialtyTierInterval - 1
        let family = specialtyFamilies[specialtyIndex % specialtyFamilies.count]
        let size = Self.specialtyCloudSize(for: family, progress: progress)
        let amplitude = family == .windy ? 20 + 28 * progress : 0
        let windSpeed = family == .windy ? 1.2 + 1.1 * progress : 0
        let y = previousSafeY + (safeY - previousSafeY) * random.value(in: Self.specialtyVerticalFractionRange)
        let routeClearance = size.width / 2 + Self.playerRadius + amplitude + Self.specialtyRouteClearance
        let preferredDirection: CGFloat = random.bool() ? 1 : -1

        for direction in [preferredDirection, -preferredDirection] {
            let routeEdge = direction > 0
                ? max(previousSafeX, safeX)
                : min(previousSafeX, safeX)
            let x = clampCloudX(
                routeEdge + direction * routeClearance,
                width: size.width,
                horizontalAmplitude: amplitude
            )

            guard
                abs(x - previousSafeX) >= routeClearance,
                abs(x - safeX) >= routeClearance,
                hasCloudClearance(
                    at: CGPoint(x: x, y: y),
                    size: size,
                    horizontalAmplitude: amplitude
                )
            else {
                continue
            }

            appendCloud(
                family: family,
                position: CGPoint(x: x, y: y),
                size: size,
                horizontalAmplitude: amplitude,
                windAngularVelocity: windSpeed,
                phase: random.value(in: 0...(2 * .pi))
            )
            return
        }
    }

    private func appendCloud(
        family: CloudFamily,
        position: CGPoint,
        size: CGSize,
        horizontalAmplitude: CGFloat,
        windAngularVelocity: CGFloat,
        phase: CGFloat
    ) {
        clouds.append(CloudState(
            id: nextCloudID,
            family: family,
            basePosition: position,
            size: size,
            horizontalAmplitude: horizontalAmplitude,
            windAngularVelocity: windAngularVelocity,
            phase: phase,
            stormDissolveRemaining: nil
        ))
        nextCloudID += 1
    }

    private func appendFeather(position: CGPoint) {
        feathers.append(FeatherState(id: nextFeatherID, position: position, value: 1))
        nextFeatherID += 1
    }

    private func clampCloudX(_ x: CGFloat, width: CGFloat, horizontalAmplitude: CGFloat) -> CGFloat {
        let inset = width / 2 + horizontalAmplitude + Self.cloudHorizontalInset
        let lower = min(inset, configuration.viewportSize.width / 2)
        let upper = max(lower, configuration.viewportSize.width - inset)
        return min(max(x, lower), upper)
    }

    /// Tests the visual envelope rather than only the collision rectangle.
    /// Windy clouds include their full travel amplitude so they cannot drift
    /// into another cloud after generation.
    private func hasCloudClearance(
        at position: CGPoint,
        size: CGSize,
        horizontalAmplitude: CGFloat
    ) -> Bool {
        clouds.allSatisfy { cloud in
            let verticalDistance = abs(position.y - cloud.basePosition.y)
            let requiredVerticalClearance = max(size.height, Self.renderedCloudMinimumHeight) / 2
                + max(cloud.size.height, Self.renderedCloudMinimumHeight) / 2
                + Self.cloudVerticalClearance

            guard verticalDistance < requiredVerticalClearance else { return true }

            let horizontalDistance = abs(position.x - cloud.basePosition.x)
            let requiredHorizontalClearance = size.width / 2
                + cloud.size.width / 2
                + horizontalAmplitude
                + cloud.horizontalAmplitude
                + Self.cloudHorizontalClearance
            return horizontalDistance >= requiredHorizontalClearance
        }
    }

    private func pruneOffscreenObjects() {
        let cutoffY = cameraY - Self.pruneDistanceBelowCamera
        clouds.removeAll { cloud in
            cloud.position(at: elapsedTime).y + cloud.size.height / 2 < cutoffY
        }
        feathers.removeAll { $0.position.y < cutoffY }
    }

    // MARK: - Lifecycle and events

    private func resetWorld(seed: UInt64) {
        random = SplitMix64(seed: seed)
        elapsedTime = 0
        accumulator = 0
        cameraY = 0
        highestHeight = 0
        score = 0
        collectedFeathers = 0
        flapCharge = 0
        currentStreak = 0
        bestStreak = 0
        lastLandingFamily = nil
        airflowRemaining = 0
        pendingAirflowBounce = false
        didUseFlap = false
        didTriggerAirflow = false
        isPaused = false
        isFinished = false
        finishedResult = nil
        pendingFlapPress = false
        runID = UUID()
        clouds = []
        feathers = []
        nextCloudID = 1
        nextFeatherID = 1
        generatedTierCount = 0
        lastSafeTravelDirection = nil

        let startingCloudSize = CGSize(width: 192, height: Self.cloudHeight)
        let startingCloudPosition = CGPoint(x: configuration.viewportSize.width / 2, y: Self.startingCloudCenterY)
        startingCloudTop = startingCloudPosition.y + startingCloudSize.height / 2
        lastSafeCloudX = startingCloudPosition.x
        lastSafeCloudY = startingCloudPosition.y
        player = PlayerState(
            position: CGPoint(x: startingCloudPosition.x, y: startingCloudTop + Self.playerRadius),
            velocity: CGPoint(x: 0, y: Self.normalBounceVelocity)
        )

        appendCloud(
            family: .fluffy,
            position: startingCloudPosition,
            size: startingCloudSize,
            horizontalAmplitude: 0,
            windAngularVelocity: 0,
            phase: 0
        )
        generateRoute(until: configuration.viewportSize.height + Self.generationLookAhead)
    }

    private func finishRun() {
        guard !isFinished else { return }
        isFinished = true
        isPaused = false
        accumulator = 0
        currentStreak = 0
        lastLandingFamily = nil

        let result = FlightResult(
            id: runID,
            height: highestHeight,
            score: score,
            collectedFeathers: collectedFeathers,
            bestStreak: bestStreak,
            usedFlap: didUseFlap,
            triggeredFlow: didTriggerAirflow,
            isNewHeightRecord: false
        )
        finishedResult = result
        emit(.finished(result))
    }

    private func setPaused(_ shouldPause: Bool) {
        guard !isFinished, isPaused != shouldPause else { return }
        isPaused = shouldPause
        accumulator = 0
        if shouldPause {
            pendingFlapPress = false
        }
        emit(shouldPause ? .paused : .resumed)
    }

    private func beginEventCollection() {
        eventBuffer.removeAll(keepingCapacity: true)
    }

    private func finishEventCollection() {
        lastEvents = eventBuffer
    }

    private func emit(_ event: SimulationEvent) {
        eventBuffer.append(event)
    }

    private var currentScoreMultiplier: Int {
        airflowRemaining > 0 ? GameBalance.flowScoreMultiplier : 1
    }

    // MARK: - Internal state

    private struct PlayerState {
        var position: CGPoint
        var velocity: CGPoint
    }

    private struct CloudState {
        let id: Int
        let family: CloudFamily
        let basePosition: CGPoint
        let size: CGSize
        let horizontalAmplitude: CGFloat
        let windAngularVelocity: CGFloat
        let phase: CGFloat
        var stormDissolveRemaining: TimeInterval?

        var isAvailable: Bool {
            stormDissolveRemaining == nil
        }

        func position(at time: TimeInterval) -> CGPoint {
            guard family == .windy else { return basePosition }
            let angle = Double(time) * Double(windAngularVelocity) + Double(phase)
            return CGPoint(
                x: basePosition.x + CGFloat(sin(angle)) * horizontalAmplitude,
                y: basePosition.y
            )
        }
    }

    private struct FeatherState {
        let id: Int
        let position: CGPoint
        let value: Int
    }

    /// SplitMix64 keeps procedural generation reproducible without GameplayKit.
    private struct SplitMix64 {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }

        mutating func bool() -> Bool {
            next() & 1 == 0
        }

        mutating func value(in range: ClosedRange<CGFloat>) -> CGFloat {
            let unit = Double(next() >> 11) / Double(1 << 53)
            return range.lowerBound + CGFloat(unit) * (range.upperBound - range.lowerBound)
        }
    }

    private var random: SplitMix64
    private var runID = UUID()
    private var player: PlayerState
    private var clouds: [CloudState] = []
    private var feathers: [FeatherState] = []
    private var eventBuffer: [SimulationEvent] = []
    private var elapsedTime: TimeInterval = 0
    private var accumulator: TimeInterval = 0
    private var cameraY: CGFloat = 0
    private var startingCloudTop: CGFloat = 0
    private var lastSafeCloudX: CGFloat = 0
    private var lastSafeCloudY: CGFloat = 0
    private var highestHeight = 0
    private var score = 0
    private var collectedFeathers = 0
    private var flapCharge = 0
    private var currentStreak = 0
    private var bestStreak = 0
    private var lastLandingFamily: CloudFamily?
    private var airflowRemaining: TimeInterval = 0
    private var pendingAirflowBounce = false
    private var didUseFlap = false
    private var didTriggerAirflow = false
    private var isPaused = false
    private var isFinished = false
    private var pendingFlapPress = false
    private var nextCloudID = 1
    private var nextFeatherID = 1
    private var generatedTierCount = 0
    private var lastSafeTravelDirection: CGFloat?

    private var shouldAppendFeather: Bool {
        generatedTierCount < Self.guaranteedFeatherTierCount
            || generatedTierCount.isMultiple(of: Self.featherTierInterval)
    }

    private var shouldAppendSpecialtyCloud: Bool {
        (generatedTierCount + 1).isMultiple(of: Self.specialtyTierInterval)
    }

    // MARK: - Tuned constants

    private static let maximumFrameDelta: TimeInterval = 0.25
    private static let maximumStepsPerAdvance = 30
    private static let gravity: CGFloat = -1_100
    private static let playerRadius: CGFloat = 18
    private static let normalBounceVelocity: CGFloat = 690
    private static let springBounceVelocity: CGFloat = 825
    private static let flapVelocity: CGFloat = 610
    private static let airflowBounceMultiplier: CGFloat = 1.16
    private static let horizontalAcceleration: CGFloat = 1_380
    private static let horizontalDeceleration: CGFloat = 1_750
    private static let maximumHorizontalSpeed: CGFloat = 315
    private static let cameraPlayerHeightFraction: CGFloat = 0.32
    private static let deathPadding: CGFloat = 8
    private static let cloudHeight: CGFloat = 26
    private static let cloudHorizontalInset: CGFloat = 10
    private static let featherRadius: CGFloat = 11
    private static let featherScore = 12
    private static let landingsForAirflow = 3
    private static let stormDissolveDuration: TimeInterval = 0.55
    private static let startingCloudCenterY: CGFloat = 58
    private static let generationLookAhead: CGFloat = 280
    private static let pruneDistanceBelowCamera: CGFloat = 230
    private static let difficultyWarmupHeight: CGFloat = 300
    private static let fullDifficultyHeight: CGFloat = 3_600
    private static let minimumSafeGap: CGFloat = 118
    private static let guaranteedFeatherTierCount = 5
    private static let featherTierInterval = 2
    private static let specialtyTierInterval = 3
    private static let specialtyVerticalFractionRange: ClosedRange<CGFloat> = 0.42...0.58
    private static let specialtyRouteClearance: CGFloat = 12
    private static let renderedCloudMinimumHeight: CGFloat = 28
    private static let cloudHorizontalClearance: CGFloat = 18
    private static let cloudVerticalClearance: CGFloat = 16

    private static func maximumSafeGap(progress: CGFloat) -> CGFloat {
        140 + 36 * progress
    }

    private static func safeCloudWidth(progress: CGFloat) -> CGFloat {
        172 - 52 * progress
    }

    private static func minimumSafeHorizontalOffset(progress: CGFloat) -> CGFloat {
        20 + 84 * progress
    }

    private static func maximumSafeHorizontalOffset(progress: CGFloat) -> CGFloat {
        64 + 96 * progress
    }

    private static func turnaroundMinimumSafeHorizontalOffset(progress: CGFloat) -> CGFloat {
        20 + 12 * progress
    }

    private static func turnaroundMaximumSafeHorizontalOffset(progress: CGFloat) -> CGFloat {
        38 + 10 * progress
    }

    private static func safeHorizontalOffset(
        progress: CGFloat,
        isTurnaround: Bool,
        unit: CGFloat
    ) -> CGFloat {
        let lower = isTurnaround
            ? turnaroundMinimumSafeHorizontalOffset(progress: progress)
            : minimumSafeHorizontalOffset(progress: progress)
        let upper = isTurnaround
            ? turnaroundMaximumSafeHorizontalOffset(progress: progress)
            : maximumSafeHorizontalOffset(progress: progress)
        return lower + min(max(unit, 0), 1) * (upper - lower)
    }

    private static func featherHorizontalOffset(progress: CGFloat) -> CGFloat {
        20 + 28 * progress
    }

    private static func routeDifficultyProgress(at safeY: CGFloat, startingCloudTop: CGFloat) -> CGFloat {
        let heightAboveStart = max(0, safeY - startingCloudTop)
        let rampHeight = max(1, fullDifficultyHeight - difficultyWarmupHeight)
        return min(max((heightAboveStart - difficultyWarmupHeight) / rampHeight, 0), 1)
    }

    private static func specialtyCloudSize(for family: CloudFamily, progress: CGFloat) -> CGSize {
        let width: CGFloat
        switch family {
        case .fluffy:
            width = safeCloudWidth(progress: progress)
        case .windy:
            width = 122 - 16 * progress
        case .spring:
            width = 112 - 12 * progress
        case .storm:
            width = 104 - 10 * progress
        }
        return CGSize(width: width, height: cloudHeight)
    }
}
