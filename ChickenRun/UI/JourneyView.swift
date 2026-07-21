//
//  JourneyView.swift
//  ChickenRun
//

import SwiftUI

struct JourneyView: View {
    @ObservedObject var store: GameStore

    private let groupOrder = ChickenCopy.AchievementSection.allCases

    private var profile: PlayerProfile { store.profile }

    private var unlockedCount: Int {
        profile.unlockedAchievementIDs.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                pathSummary
                statGrid

                VStack(alignment: .leading, spacing: 12) {
                    ChickenSectionHeader("Flight Map", detail: "\(unlockedCount)/\(GameCatalog.achievements.count)")

                    ForEach(groupOrder) { group in
                        AchievementGroup(
                            title: group.title,
                            achievements: GameCatalog.achievements.filter { group.contains($0) },
                            profile: profile
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .accessibilityLabel("Journey")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Journey")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(ChickenTheme.ink)
            Text("Every milestone is a real trace of your flights")
                .font(.subheadline)
                .foregroundStyle(ChickenTheme.mutedInk)
        }
    }

    private var pathSummary: some View {
        FeatherCard(tint: ChickenTheme.lavender) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(ChickenTheme.lavender.opacity(0.15))
                        .frame(width: 74, height: 74)
                    Image(systemName: unlockedCount == GameCatalog.achievements.count ? "medal.fill" : "map.fill")
                        .font(.title.weight(.bold))
                        .foregroundStyle(ChickenTheme.lavender)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(unlockedCount == 0 ? "Your first trail is ahead" : "Your route is growing")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ChickenTheme.ink)

                    Text("\(unlockedCount) of \(GameCatalog.achievements.count) badges unlocked")
                        .font(.subheadline)
                        .foregroundStyle(ChickenTheme.mutedInk)

                    FeatherProgressTrack(
                        progress: Double(unlockedCount) / Double(GameCatalog.achievements.count),
                        tint: ChickenTheme.lavender
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Flight Map. \(unlockedCount) of \(GameCatalog.achievements.count) badges unlocked.")
    }

    private var statGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ChickenStatTile(
                symbolName: "arrow.up.circle.fill",
                title: "top height",
                value: profile.bestHeight == 0 ? "—" : "\(profile.bestHeight) m",
                tint: ChickenTheme.sky
            )
            ChickenStatTile(
                symbolName: "arrow.up.circle.fill",
                title: "flights",
                value: "\(profile.totalFlights)",
                tint: ChickenTheme.coral
            )
            ChickenStatTile(
                symbolName: "leaf.fill",
                title: "feathers collected",
                value: "\(profile.lifetimeFeathers)",
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

private struct AchievementGroup: View {
    let title: String
    let achievements: [AchievementDefinition]
    let profile: PlayerProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ChickenTheme.mutedInk)
                .padding(.leading, 4)

            ForEach(achievements) { achievement in
                AchievementRow(
                    achievement: achievement,
                    profile: profile,
                    isUnlocked: profile.unlockedAchievementIDs.contains(achievement.id)
                )
            }
        }
    }
}

private struct AchievementRow: View {
    let achievement: AchievementDefinition
    let profile: PlayerProfile
    let isUnlocked: Bool

    private var currentProgress: Int {
        min(achievement.progress(profile), achievement.target)
    }

    private var tint: Color {
        isUnlocked ? ChickenTheme.mint : ChickenTheme.lavender
    }

    var body: some View {
        FeatherCard(tint: tint) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: achievement.symbolName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ChickenCopy.achievementTitle(for: achievement))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(ChickenTheme.ink)
                        Spacer(minLength: 8)
                        Text(isUnlocked ? "Unlocked" : "+\(achievement.reward) feathers")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                    }

                    Text(ChickenCopy.achievementDetail(for: achievement))
                        .font(.caption)
                        .foregroundStyle(ChickenTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        FeatherProgressTrack(
                            progress: Double(currentProgress) / Double(achievement.target),
                            tint: tint
                        )
                        Text("\(currentProgress)/\(achievement.target)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ChickenTheme.ink)
                            .monospacedDigit()
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ChickenCopy.achievementTitle(for: achievement)). \(ChickenCopy.achievementDetail(for: achievement)). \(isUnlocked ? "Unlocked" : "Progress \(currentProgress) of \(achievement.target)")")
    }
}
