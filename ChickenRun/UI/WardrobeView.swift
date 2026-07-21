//
//  WardrobeView.swift
//  ChickenRun
//

import SwiftUI

struct WardrobeView: View {
    @ObservedObject var store: GameStore
    @State private var selectedCategory: CosmeticCategory = .plumage
    @State private var notice: String?

    private var profile: PlayerProfile { store.profile }

    private var categoryItems: [CosmeticItem] {
        GameCatalog.cosmetics.filter { $0.category == selectedCategory }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                header
                wardrobePreview
                categoryPicker

                if let notice {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ChickenTheme.mint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .accessibilityLabel(notice)
                }

                itemGrid
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .accessibilityLabel("Wardrobe")
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wardrobe")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(ChickenTheme.ink)
                Text("Your look changes. Your skills stay the same.")
                    .font(.subheadline)
                    .foregroundStyle(ChickenTheme.mutedInk)
            }

            Spacer()

            ChickenMetricPill(
                symbolName: "leaf.fill",
                title: "feathers",
                value: "\(profile.totalFeathers)",
                tint: ChickenTheme.sunflower
            )
        }
    }

    private var wardrobePreview: some View {
        FeatherCard(tint: ChickenTheme.lavender) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Try On", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ChickenTheme.lavender)

                    Text(ChickenCopy.cosmeticTitle(for: store.equippedItem(in: selectedCategory)))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(ChickenTheme.ink)

                    Text("Switch back to anything you’ve unlocked anytime.")
                        .font(.caption)
                        .foregroundStyle(ChickenTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                ChickenHeroIllustration(
                    plumage: store.equippedItem(in: .plumage),
                    headwear: store.equippedItem(in: .headwear),
                    backpack: store.equippedItem(in: .backpack),
                    size: 132
                )
            }
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(CosmeticCategory.allCases) { category in
                    let isSelected = selectedCategory == category

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedCategory = category
                            notice = nil
                        }
                    } label: {
                        Label(ChickenCopy.categoryTitle(for: category), systemImage: category.symbolName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? .white : ChickenTheme.mutedInk)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(isSelected ? ChickenTheme.ink : .white.opacity(0.70), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ChickenCopy.categoryTitle(for: category))
                    .accessibilityValue(isSelected ? "Selected" : "")
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var itemGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChickenSectionHeader(ChickenCopy.categoryTitle(for: selectedCategory), detail: "\(categoryItems.count) styles")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 155), spacing: 12)],
                spacing: 12
            ) {
                ForEach(categoryItems) { item in
                    CosmeticItemTile(
                        item: item,
                        isUnlocked: store.isUnlocked(item),
                        isEquipped: store.equippedItem(in: selectedCategory)?.id == item.id,
                        action: { activate(item) }
                    )
                }
            }
        }
    }

    private func activate(_ item: CosmeticItem) {
        let wasUnlocked = store.isUnlocked(item)

        guard store.purchaseOrEquip(item) else {
            withAnimation {
                if item.requiresAchievement {
                    notice = "This look unlocks with a milestone."
                } else {
                    notice = "You need \(max(item.price - profile.totalFeathers, 0)) more feathers."
                }
            }
            return
        }

        withAnimation {
            let title = ChickenCopy.cosmeticTitle(for: item)
            notice = wasUnlocked ? "\(title) is already equipped." : "\(title) is unlocked and equipped."
        }
    }
}

private struct CosmeticItemTile: View {
    let item: CosmeticItem
    let isUnlocked: Bool
    let isEquipped: Bool
    let action: () -> Void

    private var tint: Color { Color(chickenHex: item.tintHex) }

    private var status: String {
        if isEquipped { return "Equipped" }
        if isUnlocked { return "Unlocked" }
        if item.requiresAchievement { return "Milestone unlock" }
        return "\(item.price) feathers needed"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: item.symbolName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(isUnlocked ? tint : ChickenTheme.mutedInk.opacity(0.65))
                        .frame(width: 44, height: 44)
                        .background((isUnlocked ? tint : ChickenTheme.mutedInk).opacity(0.15), in: Circle())

                    Spacer()

                    if isEquipped {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ChickenTheme.mint)
                            .accessibilityHidden(true)
                    } else if !isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ChickenTheme.mutedInk)
                            .accessibilityHidden(true)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(ChickenCopy.cosmeticTitle(for: item))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ChickenTheme.ink)
                        .lineLimit(1)

                    Text(ChickenCopy.cosmeticDetail(for: item))
                        .font(.caption)
                        .foregroundStyle(ChickenTheme.mutedInk)
                        .lineLimit(2)
                        .frame(minHeight: 30, alignment: .topLeading)
                }

                Text(status)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isEquipped ? ChickenTheme.mint : (isUnlocked ? ChickenTheme.lavender : ChickenTheme.coral))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background((isEquipped ? ChickenTheme.mint : (isUnlocked ? ChickenTheme.lavender : ChickenTheme.coral)).opacity(0.12), in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white.opacity(0.82))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(isEquipped ? ChickenTheme.mint : .white.opacity(0.65), lineWidth: isEquipped ? 2 : 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ChickenCopy.cosmeticTitle(for: item)). \(status)")
        .accessibilityHint(isUnlocked ? "Double-tap to equip." : "Double-tap to unlock when you have enough feathers.")
    }
}
