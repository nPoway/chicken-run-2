//
//  ChickenCopy.swift
//  ChickenRun
//

import Foundation

enum ChickenCopy {
    static func tabTitle(for tab: AppTab) -> String {
        switch tab {
        case .flight: return "Flight"
        case .wardrobe: return "Wardrobe"
        case .journey: return "Journey"
        case .coop: return "Coop"
        case .nest: return "Nest"
        }
    }

    static func categoryTitle(for category: CosmeticCategory) -> String {
        switch category {
        case .plumage: return "Plumage"
        case .headwear: return "Headwear"
        case .backpack: return "Backpack"
        case .trail: return "Trail"
        case .clouds: return "Clouds"
        case .sky: return "Sky"
        }
    }

    static func cosmeticTitle(for item: CosmeticItem?) -> String {
        guard let item else { return "Sunbeam" }
        return cosmeticTitle(for: item)
    }

    static func cosmeticTitle(for item: CosmeticItem) -> String {
        switch item.id {
        case "plumage-sunrise": return "Sunbeam"
        case "plumage-bluebell": return "Bluebell"
        case "plumage-berry": return "Berry"
        case "head-none": return "No Hat"
        case "head-leaf": return "Leaf"
        case "head-star": return "Star"
        case "backpack-map": return "Map Pack"
        case "backpack-berry": return "Berry Pack"
        case "trail-soft": return "Soft Feather"
        case "trail-spark": return "Sparkles"
        case "clouds-milk": return "Milky"
        case "clouds-peach": return "Peachy"
        case "sky-morning": return "Morning"
        case "sky-sunset": return "Sunset"
        default: return "New Look"
        }
    }

    static func cosmeticDetail(for item: CosmeticItem) -> String {
        switch item.id {
        case "plumage-sunrise": return "A warm starter plumage"
        case "plumage-bluebell": return "Soft sky-blue feathers"
        case "plumage-berry": return "A rosy travel plumage"
        case "head-none": return "Wind in your feathers"
        case "head-leaf": return "A lucky field find"
        case "head-star": return "Unlocked by a height milestone"
        case "backpack-map": return "Your first travel backpack"
        case "backpack-berry": return "For longer routes"
        case "trail-soft": return "A gentle jump trail"
        case "trail-spark": return "A bright trail through the air"
        case "clouds-milk": return "Classic fluffy clouds"
        case "clouds-peach": return "Warm cloud edges"
        case "sky-morning": return "A clear start to the journey"
        case "sky-sunset": return "A glimpse of a future zone"
        default: return "A new look for your next flight"
        }
    }

    static func achievementTitle(for achievement: AchievementDefinition) -> String {
        switch achievement.id {
        case "first-flight": return "First Flight"
        case "first-flap": return "Rescue Flap"
        case "first-flow": return "Airflow"
        case "height-100": return "Above the Barn"
        case "height-500": return "Above the Clouds"
        case "streak-5": return "Steady Route"
        case "feathers-50": return "Feather Finder"
        case "flights-10": return "Trailblazer"
        default: return "New Milestone"
        }
    }

    static func achievementDetail(for achievement: AchievementDefinition) -> String {
        switch achievement.id {
        case "first-flight": return "Finish your first climb"
        case "first-flap": return "Use a full feather charge"
        case "first-flow": return "Land on three clouds from the same family in a row"
        case "height-100": return "Reach height 100"
        case "height-500": return "Reach height 500"
        case "streak-5": return "Make a streak of five landings"
        case "feathers-50": return "Collect 50 feathers across all flights"
        case "flights-10": return "Finish 10 flights"
        default: return "Keep flying to discover this milestone"
        }
    }

    enum AchievementSection: String, CaseIterable, Identifiable {
        case firstSteps
        case height
        case skill
        case exploration

        var id: String { rawValue }

        var title: String {
            switch self {
            case .firstSteps: "First Steps"
            case .height: "Height"
            case .skill: "Skill"
            case .exploration: "Exploration"
            }
        }

        func contains(_ achievement: AchievementDefinition) -> Bool {
            switch self {
            case .firstSteps:
                return ["first-flight", "first-flap"].contains(achievement.id)
            case .height:
                return ["height-100", "height-500"].contains(achievement.id)
            case .skill:
                return ["first-flow", "streak-5"].contains(achievement.id)
            case .exploration:
                return ["feathers-50", "flights-10"].contains(achievement.id)
            }
        }
    }

    static func libraryEyebrow(for entry: LibraryEntry) -> String {
        entry.eyebrow
    }

    static func libraryTitle(for entry: LibraryEntry) -> String {
        entry.title
    }

    static func libraryBody(for entry: LibraryEntry) -> String {
        entry.body
    }
}
