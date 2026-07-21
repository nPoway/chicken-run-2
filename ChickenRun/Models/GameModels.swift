//
//  GameModels.swift
//  ChickenRun
//
//  Shared, local-only models for the first playable release.
//

import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case flight
    case wardrobe
    case journey
    case coop
    case nest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flight: "Flight"
        case .wardrobe: "Wardrobe"
        case .journey: "Journey"
        case .coop: "Coop"
        case .nest: "Nest"
        }
    }

    var symbolName: String {
        switch self {
        case .flight: "arrow.up.circle.fill"
        case .wardrobe: "backpack.fill"
        case .journey: "medal.fill"
        case .coop: "book.closed.fill"
        case .nest: "house.fill"
        }
    }
}

enum CloudFamily: String, CaseIterable, Codable, Identifiable {
    case fluffy
    case windy
    case spring
    case storm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fluffy: "Fluffy"
        case .windy: "Windy"
        case .spring: "Springy"
        case .storm: "Stormy"
        }
    }

    var shortTitle: String {
        switch self {
        case .fluffy: "fluff"
        case .windy: "wind"
        case .spring: "spring"
        case .storm: "storm"
        }
    }

    var symbolName: String {
        switch self {
        case .fluffy: "cloud.fill"
        case .windy: "wind"
        case .spring: "arrow.up.circle.fill"
        case .storm: "cloud.bolt.rain.fill"
        }
    }
}

enum CosmeticCategory: String, CaseIterable, Codable, Identifiable {
    case plumage
    case headwear
    case backpack
    case trail
    case clouds
    case sky

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plumage: "Plumage"
        case .headwear: "Headwear"
        case .backpack: "Backpack"
        case .trail: "Trail"
        case .clouds: "Clouds"
        case .sky: "Sky"
        }
    }

    var symbolName: String {
        switch self {
        case .plumage: "paintpalette.fill"
        case .headwear: "party.popper.fill"
        case .backpack: "backpack.fill"
        case .trail: "sparkles"
        case .clouds: "cloud.fill"
        case .sky: "sun.max.fill"
        }
    }
}

struct CosmeticItem: Identifiable, Codable, Hashable {
    let id: String
    let category: CosmeticCategory
    let title: String
    let subtitle: String
    let symbolName: String
    let tintHex: String
    let price: Int
    let achievementID: String?
    let isStarter: Bool

    var requiresAchievement: Bool { achievementID != nil }
}

struct AchievementDefinition: Identifiable {
    let id: String
    let group: String
    let title: String
    let detail: String
    let symbolName: String
    let reward: Int
    let progress: (PlayerProfile) -> Int
    let target: Int
}

struct LibraryEntry: Identifiable {
    let id: String
    let title: String
    let eyebrow: String
    let body: String
    let symbolName: String
    let tintHex: String
    let unlockCondition: (PlayerProfile) -> Bool
}

struct PlayerSettings: Codable, Equatable {
    var musicEnabled = true
    var soundEnabled = true
    var hapticsEnabled = true
    var useSwipeControl = true
    var reduceEffects = false
}

struct PlayerProfile: Codable, Equatable {
    var schemaVersion: Int = 1
    var totalFeathers: Int = 0
    var lifetimeFeathers: Int = 0
    var bestHeight: Int = 0
    var bestScore: Int = 0
    var bestStreak: Int = 0
    var totalFlights: Int = 0
    var unlockedCosmeticIDs: Set<String> = []
    var equippedCosmetics: [String: String] = [:]
    var unlockedAchievementIDs: Set<String> = []
    var unlockedLibraryEntryIDs: Set<String> = ["clouds", "morning-light", "feather-atlas"]
    var settings = PlayerSettings()
    var hasCompletedFirstFlight = false
    var hasUsedFlap = false
    var hasSeenFlowHint = false

    static let starter: PlayerProfile = {
        var profile = PlayerProfile()
        profile.unlockedCosmeticIDs = Set(GameCatalog.cosmetics.filter(\.isStarter).map(\.id))
        for category in CosmeticCategory.allCases {
            if let item = GameCatalog.cosmetics.first(where: { $0.category == category && $0.isStarter }) {
                profile.equippedCosmetics[category.rawValue] = item.id
            }
        }
        return profile
    }()
}

struct FlightResult: Identifiable, Equatable {
    let id: UUID
    let height: Int
    let score: Int
    let collectedFeathers: Int
    let bestStreak: Int
    let usedFlap: Bool
    let triggeredFlow: Bool
    let isNewHeightRecord: Bool

    init(
        id: UUID = UUID(),
        height: Int,
        score: Int,
        collectedFeathers: Int,
        bestStreak: Int,
        usedFlap: Bool,
        triggeredFlow: Bool,
        isNewHeightRecord: Bool = false
    ) {
        self.id = id
        self.height = height
        self.score = score
        self.collectedFeathers = collectedFeathers
        self.bestStreak = bestStreak
        self.usedFlap = usedFlap
        self.triggeredFlow = triggeredFlow
        self.isNewHeightRecord = isNewHeightRecord
    }
}

enum GameBalance {
    static let feathersForFlap = 5
    static let flowDuration: TimeInterval = 5
    static let flowScoreMultiplier = 2
    static let morningZoneHeight = 0
}

enum GameCatalog {
    static let cosmetics: [CosmeticItem] = [
        .init(id: "plumage-sunrise", category: .plumage, title: "Sunshine", subtitle: "A warm everyday plumage", symbolName: "sun.max.fill", tintHex: "F7C95C", price: 0, achievementID: nil, isStarter: true),
        .init(id: "plumage-bluebell", category: .plumage, title: "Bluebell", subtitle: "Soft blue feathers", symbolName: "drop.fill", tintHex: "83B9E5", price: 45, achievementID: nil, isStarter: false),
        .init(id: "plumage-berry", category: .plumage, title: "Berry", subtitle: "Berry-bright plumage", symbolName: "heart.fill", tintHex: "E987A9", price: 90, achievementID: nil, isStarter: false),
        .init(id: "head-none", category: .headwear, title: "No Hat", subtitle: "Wind in your feathers", symbolName: "circle.slash", tintHex: "FFFFFF", price: 0, achievementID: nil, isStarter: true),
        .init(id: "head-leaf", category: .headwear, title: "Leaf", subtitle: "A lucky leaf from the field", symbolName: "leaf.fill", tintHex: "6CB872", price: 35, achievementID: nil, isStarter: false),
        .init(id: "head-star", category: .headwear, title: "Star", subtitle: "For your first big climb", symbolName: "star.fill", tintHex: "F5C451", price: 0, achievementID: "height-100", isStarter: false),
        .init(id: "backpack-map", category: .backpack, title: "Map", subtitle: "Your first travel backpack", symbolName: "map.fill", tintHex: "C58C62", price: 0, achievementID: nil, isStarter: true),
        .init(id: "backpack-berry", category: .backpack, title: "Berry Pack", subtitle: "For long routes", symbolName: "bag.fill", tintHex: "D86F85", price: 70, achievementID: nil, isStarter: false),
        .init(id: "trail-soft", category: .trail, title: "Soft Feather", subtitle: "A gentle jump trail", symbolName: "leaf.fill", tintHex: "FFFFFF", price: 0, achievementID: nil, isStarter: true),
        .init(id: "trail-spark", category: .trail, title: "Sparkles", subtitle: "A bright airy trail", symbolName: "sparkles", tintHex: "F7D86C", price: 60, achievementID: nil, isStarter: false),
        .init(id: "clouds-milk", category: .clouds, title: "Milk-White", subtitle: "Classic fluffy clouds", symbolName: "cloud.fill", tintHex: "FFFFFF", price: 0, achievementID: nil, isStarter: true),
        .init(id: "clouds-peach", category: .clouds, title: "Peach", subtitle: "Warm peach cloud edges", symbolName: "cloud.sun.fill", tintHex: "FFD8B0", price: 50, achievementID: nil, isStarter: false),
        .init(id: "sky-morning", category: .sky, title: "Morning Sky", subtitle: "A clear start to the journey", symbolName: "sun.max.fill", tintHex: "86C8F1", price: 0, achievementID: nil, isStarter: true),
        .init(id: "sky-sunset", category: .sky, title: "Sunset Sky", subtitle: "A first glimpse of a future zone", symbolName: "sunset.fill", tintHex: "F5A66E", price: 110, achievementID: nil, isStarter: false)
    ]

    static let achievements: [AchievementDefinition] = [
        .init(id: "first-flight", group: "First Steps", title: "First Flight", detail: "Finish your first climb", symbolName: "arrow.up.right.circle.fill", reward: 5, progress: { $0.totalFlights }, target: 1),
        .init(id: "first-flap", group: "First Steps", title: "Rescue Flap", detail: "Use a fully charged flap", symbolName: "hand.raised.fill", reward: 8, progress: { $0.hasUsedFlap ? 1 : 0 }, target: 1),
        .init(id: "first-flow", group: "Mastery", title: "Airflow", detail: "Land on three clouds from the same family in a row", symbolName: "wind", reward: 15, progress: { $0.hasSeenFlowHint ? 1 : 0 }, target: 1),
        .init(id: "height-100", group: "Height", title: "Above the Barn", detail: "Reach a height of 100", symbolName: "arrow.up.circle.fill", reward: 12, progress: { $0.bestHeight }, target: 100),
        .init(id: "height-500", group: "Height", title: "Above the Clouds", detail: "Reach a height of 500", symbolName: "cloud.sun.fill", reward: 30, progress: { $0.bestHeight }, target: 500),
        .init(id: "streak-5", group: "Mastery", title: "Steady Route", detail: "Land five times in a row on the same cloud family", symbolName: "flame.fill", reward: 20, progress: { $0.bestStreak }, target: 5),
        .init(id: "feathers-50", group: "Exploration", title: "Collector", detail: "Collect 50 feathers across all flights", symbolName: "leaf.fill", reward: 20, progress: { $0.lifetimeFeathers }, target: 50),
        .init(id: "flights-10", group: "Exploration", title: "Traveler", detail: "Finish 10 flights", symbolName: "map.fill", reward: 25, progress: { $0.totalFlights }, target: 10)
    ]

    static let library: [LibraryEntry] = [
        // Welcome shelf — always available to a new traveler.
        .init(id: "clouds", title: "How Clouds Work", eyebrow: "Sky Coop", body: "Fluffy clouds reward a steady landing. Windy clouds wander, springy clouds send you higher, and storm clouds are best treated like a quick hello rather than a place to rest.", symbolName: "cloud.fill", tintHex: "8FC9F1", unlockCondition: { _ in true }),
        .init(id: "morning-light", title: "The First Light Above the Field", eyebrow: "Morning Journal", body: "Up here, sunrise does not arrive all at once. It settles first on the softest clouds, then slips into every open patch of sky. A good flight begins by noticing it.", symbolName: "sunrise.fill", tintHex: "F6C85F", unlockCondition: { _ in true }),
        .init(id: "feather-atlas", title: "A Feather Is a Fine Compass", eyebrow: "Traveler's Kit", body: "A feather drifting past your beak is not asking to be chased. Let it show you the calm side of the route, then make the landing that keeps the journey going.", symbolName: "leaf.fill", tintHex: "E9A85D", unlockCondition: { _ in true }),

        // First flight discoveries.
        .init(id: "first-flight", title: "Why Do Chickens Run So Funny?", eyebrow: "Traveler's Note", body: "Quick little steps help our tiny traveler balance before each big jump. They are not wasted motion; they are a cheerful way to collect courage while the next cloud comes into view.", symbolName: "figure.run", tintHex: "F4B860", unlockCondition: { $0.hasCompletedFirstFlight }),
        .init(id: "takeoff-ritual", title: "The Tiny Takeoff Ritual", eyebrow: "After Your First Flight", body: "Every route has a first decision: wait, hop, or turn. The best pilots do not hurry that moment. They choose one small movement and let the sky answer.", symbolName: "arrow.up.right.circle.fill", tintHex: "F2A65A", unlockCondition: { $0.hasCompletedFirstFlight }),
        .init(id: "cloud-shadows", title: "Cloud Shadows Have Somewhere to Go", eyebrow: "Field Observation", body: "A cloud may look still from above, yet its shadow can be racing quietly over the field. When the ground moves beneath you, the sky feels even wider.", symbolName: "cloud.sun.fill", tintHex: "9DC9E8", unlockCondition: { $0.hasCompletedFirstFlight }),
        .init(id: "tiny-wings", title: "Small Wings, Big Intentions", eyebrow: "Flight Desk", body: "Tiny wings are excellent at celebrating a close call. They cannot promise every landing, but they can make one well-timed flap feel like a new chapter.", symbolName: "bird.fill", tintHex: "F5B971", unlockCondition: { $0.hasCompletedFirstFlight }),
        .init(id: "kind-landings", title: "A Kind Landing Is a Fast One", eyebrow: "Cloud Etiquette", body: "Landing softly is not the same as landing slowly. Arrive with your feet ready, keep the next cloud in mind, and leave room for the route to surprise you.", symbolName: "shoeprints.fill", tintHex: "C88A6B", unlockCondition: { $0.hasCompletedFirstFlight }),
        .init(id: "map-of-up", title: "There Is No Map of Up", eyebrow: "Route Secret", body: "A paper map can name the barn, the field, and the far hills. Only a flight can draw the line between this cloud and the next one.", symbolName: "map.fill", tintHex: "79B6A8", unlockCondition: { $0.hasCompletedFirstFlight }),
        .init(id: "pocket-sunrise", title: "Keep a Little Sunrise", eyebrow: "Traveler's Note", body: "When a flight ends early, take the bright part with you: one good turn, one saved feather, or one cloud that felt friendly. Tomorrow's route can begin there.", symbolName: "sparkles", tintHex: "F5CC62", unlockCondition: { $0.hasCompletedFirstFlight }),

        // Flap discoveries.
        .init(id: "rescue-flap", title: "The Rescue Flap", eyebrow: "Flight Move", body: "A full feather charge is not a promise that nothing will go wrong. It is a second chance held close until the route truly needs it. Spend it with a clear little plan.", symbolName: "hand.raised.fill", tintHex: "E98A72", unlockCondition: { $0.hasUsedFlap }),
        .init(id: "feather-charge", title: "How a Feather Charge Feels", eyebrow: "Flight Move", body: "The best moment to use a charge is often just before panic arrives. A calm flap buys a little room, and a little room is enough to see a better landing.", symbolName: "bolt.heart.fill", tintHex: "F0A56D", unlockCondition: { $0.hasUsedFlap }),
        .init(id: "second-chance", title: "Second Chances Have Direction", eyebrow: "Flight Lesson", body: "A rescue flap works best when it points toward something, not merely away from trouble. Find the next soft edge, then let the tiny wings do their brave work.", symbolName: "arrow.uturn.up.circle.fill", tintHex: "D98290", unlockCondition: { $0.hasUsedFlap }),

        // Low-altitude observations.
        .init(id: "above-the-fence", title: "Above the Fence", eyebrow: "Height 25", body: "From a few clouds up, the fence stops being an ending and becomes a small brown line. That is the first secret of climbing: familiar places can look wonderfully different.", symbolName: "arrow.up.circle.fill", tintHex: "99C982", unlockCondition: { $0.bestHeight >= 25 }),
        .init(id: "wind-lanes", title: "The Sky Has Lanes", eyebrow: "Height 25", body: "Wind rarely pushes everywhere at once. One lane may feel quiet while another tugs at your feathers. A small side step can be smarter than a hard push forward.", symbolName: "wind", tintHex: "7FB8D4", unlockCondition: { $0.bestHeight >= 25 }),
        .init(id: "looking-down", title: "A Good Reason to Look Down", eyebrow: "Height 25", body: "Looking down is not for getting dizzy. It helps you remember how far you have come, which makes the next cloud feel less like a risk and more like an invitation.", symbolName: "eye.fill", tintHex: "77B9B0", unlockCondition: { $0.bestHeight >= 25 }),

        .init(id: "cloud-shapes", title: "Clouds Change Their Minds", eyebrow: "Height 50", body: "A round cloud can stretch into a bridge before you finish your next jump. Do not expect the route to stay posed for you; learn its rhythm and travel with it.", symbolName: "cloud.drizzle.fill", tintHex: "9CCCE8", unlockCondition: { $0.bestHeight >= 50 }),
        .init(id: "springy-clouds", title: "Springy Clouds Like Commitment", eyebrow: "Height 50", body: "A springy cloud gives back the energy you bring to it. Meet it in the middle, keep your balance, and it may turn one ordinary landing into a lovely leap.", symbolName: "arrow.up.to.line.compact", tintHex: "A9C96E", unlockCondition: { $0.bestHeight >= 50 }),
        .init(id: "gentle-turns", title: "The Secret of Gentle Turns", eyebrow: "Height 50", body: "Turning is easier before the route becomes urgent. Start with a little shift of weight, then let the open air finish the curve instead of fighting it.", symbolName: "arrow.triangle.turn.up.right.circle.fill", tintHex: "B98FD6", unlockCondition: { $0.bestHeight >= 50 }),

        // High-sky notes.
        .init(id: "wind", title: "A Traveler's Note on Wind", eyebrow: "Height 100", body: "The air is easier to follow when you listen for its rhythm. Sometimes a small turn is safer than pushing against a gust, and sometimes waiting one beat opens the whole route.", symbolName: "wind", tintHex: "78B7CF", unlockCondition: { $0.bestHeight >= 100 }),
        .init(id: "sky-quiet", title: "The Quiet Above the Barn", eyebrow: "Height 100", body: "There is a height where the busy sounds below become a soft hum. The sky is not silent, but it gives you enough space to hear your own next decision.", symbolName: "speaker.slash.fill", tintHex: "8FADE2", unlockCondition: { $0.bestHeight >= 100 }),
        .init(id: "high-blue", title: "Why the Blue Looks Deeper", eyebrow: "Height 100", body: "The higher route does not need to be rushed. With each safe landing, the blue seems to make more room around you, as if the morning is learning your name.", symbolName: "circle.lefthalf.filled", tintHex: "658FDC", unlockCondition: { $0.bestHeight >= 100 }),
        .init(id: "route-markers", title: "Make Your Own Route Markers", eyebrow: "Height 100", body: "A bright cloud, a feather trail, a sharp gust—each can be a marker for the next pass. Great travelers notice patterns before they need them.", symbolName: "mappin.and.ellipse", tintHex: "D99465", unlockCondition: { $0.bestHeight >= 100 }),

        // Airflow and streak mastery.
        .init(id: "flow", title: "Three Clouds, One Airflow", eyebrow: "Route Secret", body: "Land on three clouds from one family in a row and the route answers with a gentle airflow. It is not magic—just a good feel for rhythm, repeated three times.", symbolName: "sparkles", tintHex: "F3CE64", unlockCondition: { $0.hasSeenFlowHint }),
        .init(id: "same-family", title: "When Clouds Speak the Same Language", eyebrow: "Airflow Discovered", body: "Clouds from one family tend to ask for the same kind of attention. Spot that shared rhythm early, and a scattered route begins to feel like a conversation.", symbolName: "link", tintHex: "A58ED2", unlockCondition: { $0.hasSeenFlowHint }),
        .init(id: "current-manners", title: "Good Manners in an Air Current", eyebrow: "Airflow Discovered", body: "An airflow is a gift, not a shortcut to forget the basics. Keep looking ahead, land cleanly, and let the current carry confidence instead of carelessness.", symbolName: "wind.circle.fill", tintHex: "73BED0", unlockCondition: { $0.hasSeenFlowHint }),

        .init(id: "steady-feet", title: "Steady Feet Make a Steady Route", eyebrow: "Three-Landing Streak", body: "A streak begins with ordinary landings done well. When each cloud gets the same quiet attention, three in a row starts to feel less like luck.", symbolName: "figure.walk.motion", tintHex: "D5A56E", unlockCondition: { $0.bestStreak >= 3 }),
        .init(id: "three-landings", title: "Three Landings, One Thought", eyebrow: "Three-Landing Streak", body: "For a short while, let every landing answer the same question: where is the next safe edge? A simple question can make a fast sky feel wonderfully readable.", symbolName: "3.circle.fill", tintHex: "91BA78", unlockCondition: { $0.bestStreak >= 3 }),
        .init(id: "patience", title: "Patience Is a Flight Skill", eyebrow: "Three-Landing Streak", body: "Patience does not mean standing still. It means choosing the right small move before the larger one is forced on you. Clouds notice the difference.", symbolName: "hourglass", tintHex: "B39CCB", unlockCondition: { $0.bestStreak >= 3 }),

        // Feather collecting and repeat flights.
        .init(id: "feather-finder", title: "The Feather Finder's Rule", eyebrow: "10 Feathers Gathered", body: "Take the feather that fits the route in front of you. The prettiest detour is still a detour, while a calm collection can carry you into the next good landing.", symbolName: "feather", tintHex: "E7A65D", unlockCondition: { $0.lifetimeFeathers >= 10 }),
        .init(id: "feather-compass", title: "Feathers Point to Possibility", eyebrow: "10 Feathers Gathered", body: "A feather is a little vote for going on. Gather enough of them and even a tricky flight leaves behind proof that you found something useful in the sky.", symbolName: "location.north.circle.fill", tintHex: "D68E6B", unlockCondition: { $0.lifetimeFeathers >= 10 }),
        .init(id: "soft-treasures", title: "Soft Treasures Travel Light", eyebrow: "10 Feathers Gathered", body: "The best travel treasures never make your backpack heavy. A few feathers, a remembered breeze, and one new route are plenty for a very fine morning.", symbolName: "backpack.fill", tintHex: "B5896B", unlockCondition: { $0.lifetimeFeathers >= 10 }),

        .init(id: "fifty-feathers", title: "Fifty Small Bright Things", eyebrow: "50 Feathers Gathered", body: "Fifty feathers do not arrive in one grand moment. They come from dozens of choices to look, turn, land, and keep going. That is a collection worth admiring.", symbolName: "50.circle.fill", tintHex: "EEB25D", unlockCondition: { $0.lifetimeFeathers >= 50 }),
        .init(id: "gathered-light", title: "What Gathered Light Looks Like", eyebrow: "50 Feathers Gathered", body: "Feathers catch the morning in different ways: gold near sunrise, pale in the clouds, silver where the wind is cool. Together, they make a tiny travel lantern.", symbolName: "lightbulb.max.fill", tintHex: "F2CE68", unlockCondition: { $0.lifetimeFeathers >= 50 }),
        .init(id: "good-backpack", title: "A Backpack Full of Stories", eyebrow: "50 Feathers Gathered", body: "A map pack holds more than maps. It carries each route you tried, every near miss you turned into a landing, and the next bright idea waiting to happen.", symbolName: "bag.fill", tintHex: "BE876B", unlockCondition: { $0.lifetimeFeathers >= 50 }),

        .init(id: "second-sky", title: "The Second Sky Feels Different", eyebrow: "Three Flights Finished", body: "On the first flight, every cloud is a question. By the third, the sky begins to offer familiar answers—and a few delightful new ones.", symbolName: "2.circle.fill", tintHex: "8CB9D2", unlockCondition: { $0.totalFlights >= 3 }),
        .init(id: "route-notes", title: "Leave Notes for Tomorrow", eyebrow: "Three Flights Finished", body: "You do not need a notebook to keep a route. Remember the cloud that bounced high, the gust that turned you, and the place where a calm landing saved the day.", symbolName: "note.text", tintHex: "A895CB", unlockCondition: { $0.totalFlights >= 3 }),
        .init(id: "leaving-room", title: "Always Leave a Little Room", eyebrow: "Three Flights Finished", body: "A route is kinder when it has room for a surprise. Do not fill every jump with a plan; keep a small pocket of sky open for the better idea.", symbolName: "rectangle.inset.filled.and.person.filled", tintHex: "82BFA6", unlockCondition: { $0.totalFlights >= 3 }),

        .init(id: "traveler", title: "A Traveler Learns by Returning", eyebrow: "Ten Flights Finished", body: "Returning to the sky is not repeating yourself. Each flight starts with a new wind, a new feather trail, and a wiser version of the chicken who left the nest.", symbolName: "figure.hiking", tintHex: "6DB89A", unlockCondition: { $0.totalFlights >= 10 }),
        .init(id: "familiar-clouds", title: "Familiar Clouds, Fresh Routes", eyebrow: "Ten Flights Finished", body: "The clouds may look familiar, but their order is never quite the same. That is why practice feels less like memorizing and more like making friends.", symbolName: "cloud.fill", tintHex: "8DBFE6", unlockCondition: { $0.totalFlights >= 10 }),
        .init(id: "game-of-return", title: "The Lovely Game of Return", eyebrow: "Ten Flights Finished", body: "Each new flight is an invitation, not a test you have to pass perfectly. Bring your best landing habits, then see what the morning gives back.", symbolName: "arrow.counterclockwise.circle.fill", tintHex: "E89C70", unlockCondition: { $0.totalFlights >= 10 }),

        // Long-range discoveries.
        .init(id: "barn-small", title: "When the Barn Looks Small", eyebrow: "Height 250", body: "At this height, the barn becomes a warm little shape in a much bigger picture. It is a lovely reminder that home can stay close even when you have flown far.", symbolName: "house.fill", tintHex: "C98968", unlockCondition: { $0.bestHeight >= 250 }),
        .init(id: "border-of-weather", title: "At the Edge of Weather", eyebrow: "Height 250", body: "Weather has borders softer than fences. One cloud can be sunlit while its neighbor carries a cool gray hush. Read the edge, then choose where to go.", symbolName: "cloud.sun.rain.fill", tintHex: "829CD0", unlockCondition: { $0.bestHeight >= 250 }),
        .init(id: "long-view", title: "The Long View Is Made of Landings", eyebrow: "Height 250", body: "A tall climb can sound like one enormous leap. In truth, it is built from small, careful landings placed end to end until the field is far below.", symbolName: "binoculars.fill", tintHex: "78AFA4", unlockCondition: { $0.bestHeight >= 250 }),

        .init(id: "above-clouds", title: "Above the Clouds", eyebrow: "Height 500", body: "Reaching this high does not mean the sky has run out of ideas. It simply means you have earned a quieter view and a grander collection of possible routes.", symbolName: "cloud.sun.fill", tintHex: "9ABBE8", unlockCondition: { $0.bestHeight >= 500 }),
        .init(id: "patient-peak", title: "The Patient Peak", eyebrow: "Height 500", body: "The highest route is rarely the loudest one. It belongs to the traveler who can stay calm when the clouds speed up and still spot the next kind landing.", symbolName: "mountain.2.fill", tintHex: "9D90C8", unlockCondition: { $0.bestHeight >= 500 }),
        .init(id: "future-zone", title: "A Glimpse of the Next Zone", eyebrow: "Height 500", body: "Far ahead, the morning changes its color. Perhaps there are peach clouds, distant storms, or another field beyond the blue. The route is not finished; it is opening.", symbolName: "sunset.fill", tintHex: "F1A476", unlockCondition: { $0.bestHeight >= 500 }),

        .init(id: "thunder-distant", title: "Listen to Distant Thunder", eyebrow: "Height 750", body: "Distant thunder is not always a warning to rush. Sometimes it is the sky asking for a little more attention: shorter plans, cleaner turns, and one cloud at a time.", symbolName: "cloud.bolt.fill", tintHex: "7775B6", unlockCondition: { $0.bestHeight >= 750 }),
        .init(id: "dawn-again", title: "Dawn Begins Again Up Here", eyebrow: "Height 750", body: "At great height, light seems to arrive twice—once over the field and once in the open air around you. Keep flying gently and let the second sunrise keep you company.", symbolName: "sun.max.fill", tintHex: "F3C65E", unlockCondition: { $0.bestHeight >= 750 }),
        .init(id: "sky-legend", title: "The Sky Keeps Your Legend", eyebrow: "Height 1000", body: "A height of one thousand is not the end of a tale. It is proof that a small traveler, a patient route, and many good landings can make a very big morning.", symbolName: "star.circle.fill", tintHex: "E4B968", unlockCondition: { $0.bestHeight >= 1000 })
    ]

    static func cosmetic(id: String?) -> CosmeticItem? {
        guard let id else { return nil }
        return cosmetics.first(where: { $0.id == id })
    }
}
