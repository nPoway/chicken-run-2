//
//  NestView.swift
//  ChickenRun
//

import SwiftUI

struct NestView: View {
    @ObservedObject var store: GameStore
    @State private var isShowingResetConfirmation = false

    private var profile: PlayerProfile { store.profile }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                profileCard
                settingsCard
                legalCard
                rulesCard
                resetButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .confirmationDialog(
            "Reset local progress?",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Everything", role: .destructive) {
                store.resetProgress()
                store.leaveFlight()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your records, feathers, look, and on-device settings will return to the beginning. This can’t be undone.")
        }
        .accessibilityLabel("Nest")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nest")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(ChickenTheme.ink)
            Text("A quiet corner for this device")
                .font(.subheadline)
                .foregroundStyle(ChickenTheme.mutedInk)
        }
    }

    private var profileCard: some View {
        FeatherCard(tint: ChickenTheme.mint) {
            HStack(spacing: 14) {
                ChickenHeroIllustration(
                    plumage: store.equippedItem(in: .plumage),
                    headwear: store.equippedItem(in: .headwear),
                    backpack: store.equippedItem(in: .backpack),
                    size: 106
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text(profile.totalFlights == 0 ? "New traveler" : "Sky traveler")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ChickenTheme.ink)
                    Text("Flights: \(profile.totalFlights) · Best: \(profile.bestHeight == 0 ? "—" : "\(profile.bestHeight) m")")
                        .font(.subheadline)
                        .foregroundStyle(ChickenTheme.mutedInk)
                    Text("Everything stays on this device.")
                        .font(.caption)
                        .foregroundStyle(ChickenTheme.mint)
                }
            }
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChickenSectionHeader("Settings")

            FeatherCard(tint: ChickenTheme.sky) {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        symbolName: "music.note",
                        title: "Music",
                        detail: "A gentle soundtrack during flights",
                        isOn: settingBinding(\.musicEnabled)
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        symbolName: "speaker.wave.2.fill",
                        title: "Sounds",
                        detail: "Landings, feathers, and airflow",
                        isOn: settingBinding(\.soundEnabled)
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        symbolName: "wave.3.right",
                        title: "Haptics",
                        detail: "A small pulse for key moments",
                        isOn: settingBinding(\.hapticsEnabled)
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        symbolName: "hand.draw.fill",
                        title: "Swipe boost",
                        detail: "Use a quick swipe for extra steering",
                        isOn: settingBinding(\.useSwipeControl)
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        symbolName: "eye.slash.fill",
                        title: "Reduce effects",
                        detail: "Fewer flashes and sudden motions",
                        isOn: settingBinding(\.reduceEffects)
                    )
                }
            }
        }
    }

    private var rulesCard: some View {
        FeatherCard(tint: ChickenTheme.sunflower) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Your chicken bounces on her own. Hold the left or right side of the field to choose a route. Collected feathers charge one rescue Flap.")
                    Text("Three landings in a row on clouds from the same family trigger an airflow: your next bounce goes higher and your score grows faster.")
                }
                .font(.subheadline)
                .foregroundStyle(ChickenTheme.mutedInk)
                .padding(.top, 10)
            } label: {
                Label("How to fly", systemImage: "questionmark.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ChickenTheme.ink)
            }
            .tint(ChickenTheme.sunflower)
        }
    }

    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChickenSectionHeader("Legal")

            FeatherCard(tint: ChickenTheme.sunflower) {
                VStack(spacing: 0) {
                    SettingsLinkRow(
                        symbolName: "hand.raised.fill",
                        title: "Privacy Policy",
                        detail: "How the app handles your information",
                        destination: AppLinks.privacyPolicyURL
                    )
                    SettingsDivider()
                    SettingsLinkRow(
                        symbolName: "questionmark.circle.fill",
                        title: "Support",
                        detail: "Get help with Road to Heaven:Luetti",
                        destination: AppLinks.supportURL
                    )
                }
            }
        }
    }

    private var resetButton: some View {
        Button(role: .destructive) {
            isShowingResetConfirmation = true
        } label: {
            Label("Reset local progress", systemImage: "arrow.counterclockwise")
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .tint(ChickenTheme.coral)
        .accessibilityHint("Confirmation required")
    }

    private func settingBinding(_ keyPath: WritableKeyPath<PlayerSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.profile.settings[keyPath: keyPath] },
            set: { newValue in
                store.updateSettings { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }
}

private struct SettingsToggleRow: View {
    let symbolName: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    init(symbolName: String, title: String, detail: String, isOn: Binding<Bool>) {
        self.symbolName = symbolName
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 11) {
                Image(systemName: symbolName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ChickenTheme.sky)
                    .frame(width: 30, height: 30)
                    .background(ChickenTheme.sky.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ChickenTheme.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(ChickenTheme.mutedInk)
                }
            }
        }
        .tint(ChickenTheme.mint)
        .padding(.vertical, 8)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(ChickenTheme.ink.opacity(0.08))
            .padding(.leading, 41)
            .padding(.vertical, 4)
    }
}

private struct SettingsLinkRow: View {
    let symbolName: String
    let title: String
    let detail: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 11) {
                Image(systemName: symbolName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ChickenTheme.sunflower)
                    .frame(width: 30, height: 30)
                    .background(ChickenTheme.sunflower.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(ChickenTheme.mutedInk)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ChickenTheme.mutedInk)
            }
            .foregroundStyle(ChickenTheme.ink)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .accessibilityHint("Opens in your browser")
    }
}
