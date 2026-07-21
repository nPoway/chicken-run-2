//
//  GameStore.swift
//  ChickenRun
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var profile: PlayerProfile
    @Published var selectedTab: AppTab = .flight
    @Published var isPresentingGame = false
    @Published var lastFlightResult: FlightResult?
    @Published private(set) var latestUnlocks: [AchievementDefinition] = []

    private let profileKey = "com.any.chickenrun.player-profile"
    private var recordedRunIDs = Set<UUID>()

    init() {
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let storedProfile = try? JSONDecoder().decode(PlayerProfile.self, from: data) {
            profile = storedProfile
        } else {
            profile = .starter
        }
        refreshLibraryUnlocks()
    }

    var equippedPlumage: CosmeticItem? {
        equippedItem(in: .plumage)
    }

    func equippedItem(in category: CosmeticCategory) -> CosmeticItem? {
        GameCatalog.cosmetic(id: profile.equippedCosmetics[category.rawValue])
    }

    func isUnlocked(_ item: CosmeticItem) -> Bool {
        item.isStarter || profile.unlockedCosmeticIDs.contains(item.id)
    }

    func startFlight() {
        lastFlightResult = nil
        latestUnlocks = []
        isPresentingGame = true
    }

    func leaveFlight() {
        isPresentingGame = false
    }

    @discardableResult
    func record(_ result: FlightResult) -> FlightResult? {
        guard recordedRunIDs.insert(result.id).inserted else { return nil }

        let wasBestHeight = result.height > profile.bestHeight
        profile.totalFlights += 1
        profile.totalFeathers += result.collectedFeathers
        profile.lifetimeFeathers += result.collectedFeathers
        profile.bestHeight = max(profile.bestHeight, result.height)
        profile.bestScore = max(profile.bestScore, result.score)
        profile.bestStreak = max(profile.bestStreak, result.bestStreak)
        profile.hasCompletedFirstFlight = true
        profile.hasUsedFlap = profile.hasUsedFlap || result.usedFlap
        profile.hasSeenFlowHint = profile.hasSeenFlowHint || result.triggeredFlow

        var resultWithRecord = result
        if wasBestHeight {
            resultWithRecord = FlightResult(
                id: result.id,
                height: result.height,
                score: result.score,
                collectedFeathers: result.collectedFeathers,
                bestStreak: result.bestStreak,
                usedFlap: result.usedFlap,
                triggeredFlow: result.triggeredFlow,
                isNewHeightRecord: true
            )
        }
        lastFlightResult = resultWithRecord

        awardNewAchievements()
        refreshLibraryUnlocks()
        save()
        return resultWithRecord
    }

    func purchaseOrEquip(_ item: CosmeticItem) -> Bool {
        if isUnlocked(item) {
            profile.equippedCosmetics[item.category.rawValue] = item.id
            save()
            return true
        }

        guard item.achievementID == nil, profile.totalFeathers >= item.price else { return false }
        profile.totalFeathers -= item.price
        profile.unlockedCosmeticIDs.insert(item.id)
        profile.equippedCosmetics[item.category.rawValue] = item.id
        save()
        return true
    }

    func updateSettings(_ change: (inout PlayerSettings) -> Void) {
        change(&profile.settings)
        save()
    }

    func resetProgress() {
        profile = .starter
        lastFlightResult = nil
        latestUnlocks = []
        recordedRunIDs = []
        save()
    }

    private func awardNewAchievements() {
        var newUnlocks: [AchievementDefinition] = []
        for definition in GameCatalog.achievements {
            guard !profile.unlockedAchievementIDs.contains(definition.id),
                  definition.progress(profile) >= definition.target else { continue }
            profile.unlockedAchievementIDs.insert(definition.id)
            profile.totalFeathers += definition.reward
            newUnlocks.append(definition)

            for cosmetic in GameCatalog.cosmetics where cosmetic.achievementID == definition.id {
                profile.unlockedCosmeticIDs.insert(cosmetic.id)
            }
        }
        latestUnlocks = newUnlocks
    }

    private func refreshLibraryUnlocks() {
        for entry in GameCatalog.library where entry.unlockCondition(profile) {
            profile.unlockedLibraryEntryIDs.insert(entry.id)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: profileKey)
    }
}
