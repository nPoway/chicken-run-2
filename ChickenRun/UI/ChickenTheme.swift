//
//  ChickenTheme.swift
//  ChickenRun
//

import Foundation
import SwiftUI

enum ChickenTheme {
    static let ink = Color(red: 0.12, green: 0.20, blue: 0.31)
    static let mutedInk = Color(red: 0.29, green: 0.39, blue: 0.49)
    static let sky = Color(red: 0.55, green: 0.80, blue: 0.95)
    static let skyLight = Color(red: 0.84, green: 0.94, blue: 0.99)
    static let cream = Color(red: 1.00, green: 0.98, blue: 0.92)
    static let sunflower = Color(red: 0.96, green: 0.67, blue: 0.23)
    static let coral = Color(red: 0.94, green: 0.47, blue: 0.40)
    static let mint = Color(red: 0.36, green: 0.72, blue: 0.62)
    static let lavender = Color(red: 0.55, green: 0.53, blue: 0.84)

    static let pageGradient = LinearGradient(
        colors: [skyLight, cream],
        startPoint: .top,
        endPoint: .bottom
    )

    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.38, green: 0.72, blue: 0.95), sky],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(chickenHex: String) {
        let cleaned = chickenHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

struct FeatherCard<Content: View>: View {
    private let tint: Color
    private let content: Content

    init(tint: Color = .white, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(0.88))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(tint.opacity(0.24), lineWidth: 1)
                    }
            }
            .shadow(color: ChickenTheme.ink.opacity(0.07), radius: 16, y: 8)
    }
}

struct ChickenSectionHeader: View {
    let title: String
    let detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(ChickenTheme.ink)

            Spacer(minLength: 8)

            if let detail {
                Text(detail)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ChickenTheme.mutedInk)
            }
        }
    }
}

struct ChickenMetricPill: View {
    let symbolName: String
    let title: String
    let value: String
    var tint: Color = ChickenTheme.sunflower

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ChickenTheme.ink)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(ChickenTheme.mutedInk)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.76), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

struct FeatherProgressTrack: View {
    let progress: Double
    var tint: Color = ChickenTheme.sunflower

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ChickenTheme.ink.opacity(0.08))

                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * clampedProgress)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

struct ChickenHeroIllustration: View {
    let plumage: CosmeticItem?
    let headwear: CosmeticItem?
    let backpack: CosmeticItem?
    var size: CGFloat = 170

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.30))
                .frame(width: size * 0.88, height: size * 0.88)
                .blur(radius: 4)

            if let backpack {
                Image(systemName: backpack.symbolName)
                    .font(.system(size: size * 0.24, weight: .bold))
                    .foregroundStyle(Color(chickenHex: backpack.tintHex))
                    .rotationEffect(.degrees(-14))
                    .offset(x: -size * 0.27, y: size * 0.10)
            }

            Image("TravelerChickenSprite")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.76, height: size * 0.92)
                .shadow(color: ChickenTheme.ink.opacity(0.16), radius: 5, y: 5)
                .rotationEffect(.degrees(-6))

            if let headwear, headwear.id != "head-none" {
                Image(systemName: headwear.symbolName)
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundStyle(Color(chickenHex: headwear.tintHex))
                    .offset(x: -size * 0.04, y: -size * 0.33)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Traveler’s look: \(ChickenCopy.cosmeticTitle(for: plumage))")
    }
}

struct ChickenStatTile: View {
    let symbolName: String
    let title: String
    let value: String
    var tint: Color = ChickenTheme.sunflower

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbolName)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.15), in: Circle())

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(ChickenTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .font(.caption)
                .foregroundStyle(ChickenTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}
