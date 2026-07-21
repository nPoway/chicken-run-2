//
//  CoopView.swift
//  ChickenRun
//

import SwiftUI

struct CoopView: View {
    @ObservedObject var store: GameStore
    @State private var selectedEntry: LibraryEntry?

    private var profile: PlayerProfile { store.profile }

    private var unlockedCount: Int {
        GameCatalog.library.filter { profile.unlockedLibraryEntryIDs.contains($0.id) }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                librarySummary

                VStack(alignment: .leading, spacing: 12) {
                    ChickenSectionHeader("Coop Shelves", detail: "\(unlockedCount)/\(GameCatalog.library.count)")

                    ForEach(GameCatalog.library) { entry in
                        LibraryEntryCard(
                            entry: entry,
                            isUnlocked: profile.unlockedLibraryEntryIDs.contains(entry.id),
                            action: { selectedEntry = entry }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .sheet(item: $selectedEntry) { entry in
            LibraryEntrySheet(entry: entry)
                .presentationDetents([.medium, .large])
        }
        .accessibilityLabel("Coop")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Coop")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(ChickenTheme.ink)
            Text("A small library for curious fliers")
                .font(.subheadline)
                .foregroundStyle(ChickenTheme.mutedInk)
        }
    }

    private var librarySummary: some View {
        FeatherCard(tint: ChickenTheme.sky) {
            HStack(spacing: 14) {
                Image(systemName: "book.closed.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ChickenTheme.sky)
                    .frame(width: 52, height: 52)
                    .background(ChickenTheme.sky.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(unlockedCount == 0 ? "Your first article is waiting" : "New articles appear along the way")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ChickenTheme.ink)
                    Text("\(unlockedCount) of \(GameCatalog.library.count) articles unlocked. No feed, no daily check-ins.")
                        .font(.caption)
                        .foregroundStyle(ChickenTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct LibraryEntryCard: View {
    let entry: LibraryEntry
    let isUnlocked: Bool
    let action: () -> Void

    private var tint: Color { Color(chickenHex: entry.tintHex) }

    var body: some View {
        Button {
            guard isUnlocked else { return }
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isUnlocked ? entry.symbolName : "lock.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isUnlocked ? tint : ChickenTheme.mutedInk.opacity(0.72))
                    .frame(width: 48, height: 48)
                    .background((isUnlocked ? tint : ChickenTheme.mutedInk).opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(isUnlocked ? ChickenCopy.libraryEyebrow(for: entry) : "New article")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isUnlocked ? tint : ChickenTheme.mutedInk)

                    Text(isUnlocked ? ChickenCopy.libraryTitle(for: entry) : "Unlocks on future flights")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ChickenTheme.ink)
                        .lineLimit(2)

                    Text(isUnlocked ? ChickenCopy.libraryBody(for: entry) : "Higher climbs and new moves reveal more stories.")
                        .font(.caption)
                        .foregroundStyle(ChickenTheme.mutedInk)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: isUnlocked ? "chevron.right" : "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ChickenTheme.mutedInk)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(.white.opacity(isUnlocked ? 0.84 : 0.58), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isUnlocked ? "\(ChickenCopy.libraryTitle(for: entry)). Open article." : "Locked article. Unlocks on future flights.")
    }
}

private struct LibraryEntrySheet: View {
    let entry: LibraryEntry
    @Environment(\.dismiss) private var dismiss

    private var tint: Color { Color(chickenHex: entry.tintHex) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: entry.symbolName)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 64, height: 64)
                        .background(tint.opacity(0.15), in: Circle())

                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.bold))
                }

                Text(ChickenCopy.libraryEyebrow(for: entry))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .textCase(.uppercase)

                Text(ChickenCopy.libraryTitle(for: entry))
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(ChickenTheme.ink)

                Text(ChickenCopy.libraryBody(for: entry))
                    .font(.body)
                    .foregroundStyle(ChickenTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
        .background(ChickenTheme.pageGradient.ignoresSafeArea())
    }
}
