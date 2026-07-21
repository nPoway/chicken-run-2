//
//  AppShellView.swift
//  ChickenRun
//

import SwiftUI

struct AppShellView: View {
    @ObservedObject var store: GameStore

    var body: some View {
        ZStack {
            ChickenTheme.pageGradient
                .ignoresSafeArea()

            page
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChickenTabBar(selectedTab: $store.selectedTab)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
        .animation(.easeInOut(duration: 0.2), value: store.selectedTab)
        .tint(ChickenTheme.coral)
    }

    @ViewBuilder
    private var page: some View {
        switch store.selectedTab {
        case .flight:
            FlightHomeView(store: store)
        case .wardrobe:
            WardrobeView(store: store)
        case .journey:
            JourneyView(store: store)
        case .coop:
            CoopView(store: store)
        case .nest:
            NestView(store: store)
        }
    }
}

private struct ChickenTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.62), lineWidth: 1)
        }
        .shadow(color: ChickenTheme.ink.opacity(0.14), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Section navigation")
    }

    private func tabButton(for tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Group {
                    if tab == .flight {
                        Image("TravelerChickenSprite")
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .frame(width: 20, height: 20)

                Text(ChickenCopy.tabTitle(for: tab))
                    .font(.caption2.weight(isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? .white : ChickenTheme.mutedInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(isSelected ? ChickenTheme.coral : .clear)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ChickenCopy.tabTitle(for: tab))
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}
