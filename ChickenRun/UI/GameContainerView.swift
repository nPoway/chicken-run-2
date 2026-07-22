//
//  GameContainerView.swift
//  ChickenRun
//

import SpriteKit
import SwiftUI
import UIKit
import Combine

@MainActor
private final class FlightPresentationModel: ObservableObject {
    struct HUD: Equatable {
        var elapsedTime: TimeInterval = 0
        var height = 0
        var score = 0
        var feathers = 0
        var flapCharge = 0
        var flapRequirement = GameBalance.feathersForFlap
        var currentStreak = 0
        var airflowRemaining: TimeInterval = 0
        var isPaused = false

        init() {}

        init(snapshot: RunSnapshot) {
            elapsedTime = snapshot.elapsedTime
            height = snapshot.height
            score = snapshot.score
            feathers = snapshot.collectedFeathers
            flapCharge = snapshot.flapCharge
            flapRequirement = snapshot.flapRequirement
            currentStreak = snapshot.currentStreak
            airflowRemaining = snapshot.airflowRemaining
            isPaused = snapshot.isPaused
        }
    }

    @Published var hud = HUD()
    @Published var result: FlightResult?

    private var recordedResultIDs = Set<UUID>()

    func accept(_ snapshot: RunSnapshot) {
        hud = HUD(snapshot: snapshot)
    }

    func finish(_ result: FlightResult) -> Bool {
        guard recordedResultIDs.insert(result.id).inserted else { return false }
        self.result = result
        return true
    }

    func beginNextFlight() {
        hud = HUD()
        result = nil
    }
}

@MainActor
private enum GameplayHaptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let notification = UINotificationFeedbackGenerator()

    static func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        rigidImpact.prepare()
        heavyImpact.prepare()
        softImpact.prepare()
        notification.prepare()
    }

    static func landing(on family: CloudFamily) {
        switch family {
        case .fluffy:
            lightImpact.impactOccurred(intensity: 0.72)
        case .windy:
            mediumImpact.impactOccurred(intensity: 0.72)
        case .spring:
            rigidImpact.impactOccurred(intensity: 1)
        case .storm:
            heavyImpact.impactOccurred(intensity: 0.92)
        }
        prepare()
    }

    static func pickup() {
        softImpact.impactOccurred(intensity: 0.82)
        softImpact.prepare()
    }

    static func flap() {
        rigidImpact.impactOccurred(intensity: 0.92)
        rigidImpact.prepare()
    }

    static func flow() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    static func finish() {
        mediumImpact.impactOccurred(intensity: 0.86)
        mediumImpact.prepare()
    }
}

struct GameContainerView: View {
    @ObservedObject var store: GameStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var presentation = FlightPresentationModel()
    @State private var scene: ChickenGameScene?
    @State private var didApplySwipe = false
    @State private var showExitConfirmation = false
    @State private var sceneSize: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.42, green: 0.75, blue: 0.95)
                    .ignoresSafeArea()

                if let scene {
                    SpriteView(
                        scene: scene,
                        options: [.shouldCullNonVisibleNodes]
                    )
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(steeringGesture(in: proxy.size))
                    .accessibilityLabel("Game field. Hold the left or right side of the screen to guide your chicken.")
                }

                GameHUDView(
                    hud: presentation.hud,
                    requestPause: { scene?.togglePause() }
                )
                .allowsHitTesting(presentation.result == nil && !presentation.hud.isPaused)

                if presentation.hud.flapCharge >= presentation.hud.flapRequirement {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            FlapButton(
                                charge: presentation.hud.flapCharge,
                                requirement: presentation.hud.flapRequirement,
                                action: { scene?.requestFlap() }
                            )
                        }
                        .padding(.trailing, 24)
                        .padding(.bottom, 44)
                    }
                    .allowsHitTesting(presentation.result == nil && !presentation.hud.isPaused)
                }

                if shouldShowTutorial {
                    TutorialHint(hud: presentation.hud)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .allowsHitTesting(false)
                }

                if presentation.hud.isPaused && presentation.result == nil {
                    PauseOverlay(
                        onResume: { scene?.resume() },
                        onRestart: restartFlight,
                        onLeave: requestLeave
                    )
                }

                if let result = presentation.result {
                    FlightResultOverlay(
                        result: result,
                        unlocks: store.latestUnlocks,
                        onAgain: restartFlight,
                        onHome: { store.leaveFlight() }
                    )
                }
            }
            .onAppear {
                installScene(ifNeededFor: proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                installScene(ifNeededFor: newSize)
            }
        }
        .ignoresSafeArea()
        .confirmationDialog(
            "Leave flight?",
            isPresented: $showExitConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave for Home", role: .destructive) {
                store.leaveFlight()
            }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("This unfinished climb will not be saved.")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                scene?.pause()
            }
        }
    }

    private var shouldShowTutorial: Bool {
        !store.profile.hasCompletedFirstFlight
            && presentation.result == nil
            && !presentation.hud.isPaused
            && presentation.hud.elapsedTime < 15
    }

    private func installScene(ifNeededFor size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard scene == nil else { return }
        sceneSize = size
        scene = makeScene(size: size)
    }

    private func makeScene(size: CGSize) -> ChickenGameScene {
        if store.profile.settings.hapticsEnabled {
            GameplayHaptics.prepare()
        }
        let newScene = ChickenGameScene(size: size, profile: store.profile)
        newScene.onSnapshot = { snapshot in
            presentation.accept(snapshot)
        }
        newScene.onEvents = { events in
            playFeedback(for: events)
        }
        newScene.onFinished = { result in
            guard let savedResult = store.record(result) else { return }
            _ = presentation.finish(savedResult)
        }
        return newScene
    }

    private func restartFlight() {
        presentation.beginNextFlight()
        if let scene {
            scene.restart()
        } else if sceneSize.width > 0, sceneSize.height > 0 {
            scene = makeScene(size: sceneSize)
        }
    }

    private func requestLeave() {
        if presentation.hud.height > 0 {
            showExitConfirmation = true
        } else {
            store.leaveFlight()
        }
    }

    private func steeringGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let direction: CGFloat = value.location.x < size.width / 2 ? -1 : 1
                scene?.setHorizontalInput(direction)

                let horizontalDistance = value.translation.width
                let isHorizontalSwipe = abs(horizontalDistance) > 18 && abs(horizontalDistance) > abs(value.translation.height)
                if store.profile.settings.useSwipeControl && isHorizontalSwipe && !didApplySwipe {
                    scene?.applySwipeImpulse(direction: horizontalDistance)
                    didApplySwipe = true
                }
            }
            .onEnded { _ in
                scene?.setHorizontalInput(0)
                didApplySwipe = false
            }
    }

    private func playFeedback(for events: [SimulationEvent]) {
        guard store.profile.settings.hapticsEnabled else { return }

        for event in events {
            switch event {
            case let .landed(_, family, _):
                GameplayHaptics.landing(on: family)
            case .featherCollected:
                GameplayHaptics.pickup()
            case .flapActivated:
                GameplayHaptics.flap()
            case .airflowActivated:
                GameplayHaptics.flow()
            case .finished:
                GameplayHaptics.finish()
            default:
                break
            }
        }
    }
}

private struct GameHUDView: View {
    let hud: FlightPresentationModel.HUD
    let requestPause: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HEIGHT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.78))
                    Text("\(hud.height) m")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Spacer(minLength: 0)

                HStack(spacing: 7) {
                    Image(systemName: "leaf.fill")
                        .foregroundStyle(ChickenTheme.sunflower)
                    Text("\(hud.feathers)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(.black.opacity(0.18), in: Capsule())
                .accessibilityLabel("Feathers collected: \(hud.feathers)")

                Button(action: requestPause) {
                    Image(systemName: "pause.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 43, height: 43)
                        .background(.black.opacity(0.20), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pause")
            }

            if hud.airflowRemaining > 0 {
                Label("Airflow ×2 · \(Int(ceil(hud.airflowRemaining)))s", systemImage: "wind")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ChickenTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ChickenTheme.sunflower.opacity(0.94), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Airflow active. Score multiplier times two.")
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        // The game deliberately fills the display, but the live HUD stays
        // below the native status area and Dynamic Island.
        .padding(.top, 58)
        .animation(.easeInOut(duration: 0.18), value: hud.airflowRemaining > 0)
    }
}

private struct FlapButton: View {
    let charge: Int
    let requirement: Int
    let action: () -> Void

    private var isReady: Bool { charge >= requirement }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isReady ? ChickenTheme.coral : ChickenTheme.ink.opacity(0.40))
                    .frame(width: 78, height: 78)
                    .overlay {
                        Circle().strokeBorder(.white.opacity(isReady ? 0.75 : 0.26), lineWidth: 2)
                    }
                    .shadow(color: isReady ? ChickenTheme.coral.opacity(0.42) : .clear, radius: 15, y: 7)

                VStack(spacing: 2) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.headline.weight(.bold))
                    Text(isReady ? "FLAP" : "\(charge)/\(requirement)")
                        .font(.caption2.weight(.heavy))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isReady)
        .accessibilityLabel(isReady ? "Flap ready" : "Flap charging: \(charge) of \(requirement) feathers")
        .accessibilityHint(isReady ? "Tap for a short lift" : "Collect more feathers")
    }
}

private struct TutorialHint: View {
    let hud: FlightPresentationModel.HUD

    private var message: String {
        if hud.feathers == 0 {
            return "Hold the left or right side of the sky to guide your chicken."
        }
        if hud.flapCharge < hud.flapRequirement {
            return "Collect feathers—five charge a rescue Flap."
        }
        return "Flap is ready. Tap the button below for a short lift."
    }

    var body: some View {
        VStack {
            Spacer()
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ChickenTheme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: ChickenTheme.ink.opacity(0.12), radius: 12, y: 6)
                .padding(.horizontal, 36)
                .padding(.bottom, 132)
            Spacer().frame(height: 40)
        }
    }
}

private struct PauseOverlay: View {
    let onResume: () -> Void
    let onRestart: () -> Void
    let onLeave: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.30).ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(ChickenTheme.sunflower)

                Text("The sky can wait")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(ChickenTheme.ink)
                Text("Your flight is paused. Continue when you’re ready.")
                    .font(.subheadline)
                    .foregroundStyle(ChickenTheme.mutedInk)
                    .multilineTextAlignment(.center)

                Button("Continue", action: onResume)
                    .buttonStyle(FlightPrimaryButtonStyle())

                Button("Restart", action: onRestart)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ChickenTheme.ink)
                    .padding(.vertical, 6)

                Button("Home", action: onLeave)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ChickenTheme.coral)
            }
            .frame(maxWidth: 320)
            .padding(24)
            .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 28, y: 12)
            .padding(24)
        }
    }
}

private struct FlightResultOverlay: View {
    let result: FlightResult
    let unlocks: [AchievementDefinition]
    let onAgain: () -> Void
    let onHome: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.34).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    Image(systemName: result.isNewHeightRecord ? "star.circle.fill" : "cloud.sun.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(result.isNewHeightRecord ? ChickenTheme.sunflower : ChickenTheme.sky)

                    Text(result.isNewHeightRecord ? "New personal best!" : "Soft landing")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(ChickenTheme.ink)
                    Text(result.isNewHeightRecord ? "The sky feels a little closer." : "Every flight helps you find your next route.")
                        .font(.subheadline)
                        .foregroundStyle(ChickenTheme.mutedInk)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 10) {
                        ResultMetric(value: "\(result.height) m", title: "height", symbol: "arrow.up.circle.fill", tint: ChickenTheme.sky)
                        ResultMetric(value: "\(result.collectedFeathers)", title: "feathers", symbol: "leaf.fill", tint: ChickenTheme.sunflower)
                        ResultMetric(value: result.bestStreak == 0 ? "—" : "\(result.bestStreak)", title: "streak", symbol: "flame.fill", tint: ChickenTheme.coral)
                    }

                    HStack {
                        Text("Final score")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ChickenTheme.mutedInk)
                        Spacer()
                        Text("\(result.score)")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(ChickenTheme.ink)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(ChickenTheme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if let unlock = unlocks.first {
                        Label("Unlocked: \(ChickenCopy.achievementTitle(for: unlock)) +\(unlock.reward) feathers", systemImage: unlock.symbolName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ChickenTheme.mint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(ChickenTheme.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Button("Fly again", action: onAgain)
                        .buttonStyle(FlightPrimaryButtonStyle())

                    Button("Home", action: onHome)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ChickenTheme.ink)
                        .padding(.vertical, 4)
                }
                .padding(22)
                .background(.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: .black.opacity(0.23), radius: 28, y: 12)
                .padding(.horizontal, 22)
                .padding(.vertical, 50)
            }
        }
    }
}

private struct ResultMetric: View {
    let value: String
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(ChickenTheme.ink)
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(ChickenTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct FlightPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(ChickenTheme.coral.opacity(configuration.isPressed ? 0.76 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
