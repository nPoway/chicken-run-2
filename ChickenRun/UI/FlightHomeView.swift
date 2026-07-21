//
//  FlightHomeView.swift
//  ChickenRun
//

import SwiftUI
import UIKit

struct FlightHomeView: View {
    @ObservedObject var store: GameStore

    private var profile: PlayerProfile { store.profile }

    private var nextAchievement: AchievementDefinition? {
        GameCatalog.achievements.first { definition in
            !profile.unlockedAchievementIDs.contains(definition.id)
        }
    }

    private var goalProgress: Int {
        guard let nextAchievement else { return 0 }
        return min(nextAchievement.progress(profile), nextAchievement.target)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                FlightHeroCard(profile: profile)

                launchButton

                if store.isPresentingGame {
                    FlightPreparedCard()
                }

                goalCard
                quickStats
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .accessibilityLabel("Flight")
    }

    private var launchButton: some View {
        Button {
            store.startFlight()
        } label: {
            HStack(spacing: 12) {
                Image("TravelerChickenSprite")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.22), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isPresentingGame ? "Flight ready" : "Take flight")
                        .font(.title3.weight(.heavy))
                    Text(store.isPresentingGame ? "Your next climb is ready" : "A quick climb, no extra screens")
                        .font(.caption)
                        .opacity(0.90)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background {
                Capsule()
                    .fill(ChickenTheme.coral)
                    .shadow(color: ChickenTheme.coral.opacity(0.32), radius: 14, y: 8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Take flight")
        .accessibilityHint("Starts a new flight")
    }

    private var goalCard: some View {
        FeatherCard(tint: ChickenTheme.sunflower) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "target")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ChickenTheme.sunflower)
                        .frame(width: 36, height: 36)
                        .background(ChickenTheme.sunflower.opacity(0.16), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next goal")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ChickenTheme.mutedInk)
                        Text(nextAchievement.map { ChickenCopy.achievementTitle(for: $0) } ?? "Your journey is open")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(ChickenTheme.ink)
                    }

                    Spacer()

                    if let nextAchievement {
                        Text("+\(nextAchievement.reward) feathers")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ChickenTheme.sunflower)
                    }
                }

                Text(nextAchievement.map { ChickenCopy.achievementDetail(for: $0) } ?? "All starter milestones are complete—keep exploring the sky.")
                    .font(.subheadline)
                    .foregroundStyle(ChickenTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let nextAchievement {
                    HStack(spacing: 10) {
                        FeatherProgressTrack(
                            progress: Double(goalProgress) / Double(nextAchievement.target),
                            tint: ChickenTheme.sunflower
                        )
                        Text("\(goalProgress)/\(nextAchievement.target)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ChickenTheme.ink)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Goal progress: \(goalProgress) of \(nextAchievement.target)")
                }
            }
        }
    }

    private var quickStats: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChickenSectionHeader("Quick look", detail: "on this device")

            HStack(spacing: 12) {
                ChickenStatTile(
                    symbolName: "leaf.fill",
                    title: "feathers on hand",
                    value: "\(profile.totalFeathers)",
                    tint: ChickenTheme.sunflower
                )
                ChickenStatTile(
                    symbolName: "flame.fill",
                    title: "best streak",
                    value: profile.bestStreak == 0 ? "—" : "\(profile.bestStreak)",
                    tint: ChickenTheme.coral
                )
            }
        }
    }
}

private struct FlightHeroCard: View {
    let profile: PlayerProfile

    var body: some View {
        ZStack {
            if UIImage(named: "MorningSkyBackdrop") != nil {
                Image("MorningSkyBackdrop")
                    .resizable()
                    .scaledToFill()
                    .saturation(0.90)
            } else {
                ChickenTheme.heroGradient
            }

            ChickenTheme.heroGradient.opacity(0.24)

            FlightSkyArtwork()
                .opacity(0.22)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Morning Clouds", systemImage: "sun.max.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.94))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.20), in: Capsule())

                    Spacer()

                    ChickenMetricPill(
                        symbolName: "leaf.fill",
                        title: "on hand",
                        value: "\(profile.totalFeathers)",
                        tint: ChickenTheme.sunflower
                    )
                }

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 5) {
                    Text(profile.bestHeight == 0 ? "First climb" : "Personal best")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))

                    Text(profile.bestHeight == 0 ? "The sky is waiting" : "\(profile.bestHeight) m")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(profile.bestHeight == 0 ? "Choose a safe route and climb higher." : "One more climb and you’ll beat your record.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 190, alignment: .leading)
            }
            .padding(20)

        }
        .frame(height: 294)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Image("TravelerChickenSprite")
                .resizable()
                .scaledToFit()
                .frame(width: 174, height: 206)
                .rotationEffect(.degrees(-5))
                .shadow(color: ChickenTheme.ink.opacity(0.22), radius: 10, y: 7)
                .padding(.trailing, 12)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
        }
        .shadow(color: ChickenTheme.sky.opacity(0.30), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profile.bestHeight == 0 ? "Morning Clouds. Your first climb is ahead." : "Morning Clouds. Personal best: \(profile.bestHeight) meters.")
    }
}

private struct FlightSkyArtwork: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.22))
                .frame(width: 180, height: 180)
                .blur(radius: 5)
                .offset(x: 128, y: -112)

            CloudCluster(scale: 0.56)
                .offset(x: -140, y: -94)

            CloudCluster(scale: 0.78)
                .offset(x: 136, y: 110)

            CloudCluster(scale: 0.44)
                .offset(x: -92, y: 124)
        }
        .allowsHitTesting(false)
    }
}

private struct CloudCluster: View {
    let scale: CGFloat

    var body: some View {
        HStack(alignment: .bottom, spacing: -16) {
            Circle().frame(width: 46, height: 46)
            Circle().frame(width: 68, height: 68)
            Circle().frame(width: 48, height: 48)
        }
        .foregroundStyle(.white.opacity(0.64))
        .scaleEffect(scale)
    }
}

private struct FlightPreparedCard: View {
    var body: some View {
        FeatherCard(tint: ChickenTheme.mint) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(ChickenTheme.mint)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Flight ready")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ChickenTheme.ink)
                    Text("Your next climb will open here in a moment.")
                        .font(.caption)
                        .foregroundStyle(ChickenTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Flight ready.")
    }
}
