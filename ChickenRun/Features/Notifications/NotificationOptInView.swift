//
//  NotificationOptInView.swift
//  ChickenRun
//

import SwiftUI

/// A branded primer shown immediately before the system notification authorization alert.
struct NotificationOptInView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let allowAction: () -> Void
    let skipAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack {
                primerBackground(isLandscape: isLandscape)
                primerHero(isLandscape: isLandscape, in: proxy.size)
                readabilityOverlay(isLandscape: isLandscape)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    Group {
                        if isLandscape {
                            landscapeLayout(in: proxy.size)
                        } else {
                            portraitLayout(in: proxy.size)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    .safeAreaPadding(.horizontal, isLandscape ? 30 : 22)
                    .safeAreaPadding(.vertical, isLandscape ? 14 : 16)
                }
            }
        }
        .background(ChickenTheme.ink)
        .accessibilityElement(children: .contain)
    }

    private func primerBackground(isLandscape: Bool) -> some View {
        GeometryReader { proxy in
            Image("MorningSkyBackdrop")
                .resizable()
                .scaledToFill()
                .scaleEffect(isLandscape ? 1.06 : 1)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func primerHero(isLandscape: Bool, in size: CGSize) -> some View {
        if isLandscape {
            ZStack {
                Image("TravelerChickenSprite")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(size.width * 0.34, 390))
                    .position(x: size.width * 0.16, y: size.height * 0.57)

                Image("TravelerChickenFlightSprite")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(size.width * 0.40, 460))
                    .position(x: size.width * 0.86, y: size.height * 0.52)
            }
            .frame(width: size.width, height: size.height)
            .shadow(color: ChickenTheme.ink.opacity(0.42), radius: 22, y: 14)
            .accessibilityHidden(true)
        } else {
            Image("TravelerChickenFlightSprite")
                .resizable()
                .scaledToFit()
                .frame(width: min(size.width * 1.08, 520))
                .position(x: size.width * 0.55, y: size.height * 0.43)
                .shadow(color: ChickenTheme.ink.opacity(0.42), radius: 24, y: 16)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func readabilityOverlay(isLandscape: Bool) -> some View {
        if isLandscape {
            LinearGradient(
                stops: [
                    .init(color: ChickenTheme.sky.opacity(0.12), location: 0),
                    .init(color: ChickenTheme.ink.opacity(0.06), location: 0.36),
                    .init(color: ChickenTheme.ink.opacity(0.50), location: 0.62),
                    .init(color: ChickenTheme.ink.opacity(0.98), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                stops: [
                    .init(color: ChickenTheme.sky.opacity(0.20), location: 0),
                    .init(color: ChickenTheme.ink.opacity(0.06), location: 0.30),
                    .init(color: ChickenTheme.ink.opacity(0.18), location: 0.50),
                    .init(color: ChickenTheme.ink.opacity(0.90), location: 0.72),
                    .init(color: ChickenTheme.ink.opacity(0.99), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func portraitLayout(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            brandLockup(compact: false)

            Spacer(minLength: max(250, size.height * 0.38))

            messageAndActions(compact: size.height < 700)
                .frame(maxWidth: 440)
        }
        .padding(.top, max(4, size.height * 0.01))
        .padding(.bottom, 2)
    }

    private func landscapeLayout(in size: CGSize) -> some View {
        VStack(spacing: 10) {
            brandLockup(compact: true)

            Spacer(minLength: max(80, size.height * 0.25))

            HStack(alignment: .bottom, spacing: min(40, size.width * 0.04)) {
                messageCopy(compact: false, alignment: .leading)
                    .frame(maxWidth: 420, alignment: .leading)

                Spacer(minLength: 16)

                actionButtons(compact: true)
                    .frame(maxWidth: 380)
            }
            .padding(.bottom, min(28, max(18, size.height * 0.06)))
        }
        .padding(.vertical, 2)
    }

    private func brandLockup(compact: Bool) -> some View {
        Text("ROAD TO\nHEAVEN")
            .font(.system(compact ? .title : .largeTitle, design: .rounded, weight: .black))
            .foregroundStyle(
                LinearGradient(
                    colors: [.white, .white, ChickenTheme.sunflower],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .multilineTextAlignment(.center)
            .lineSpacing(compact ? -7 : -9)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.82 : 0.72)
            .shadow(color: ChickenNotificationPalette.deepCoral, radius: 0, x: -3, y: 0)
            .shadow(color: ChickenNotificationPalette.deepCoral, radius: 0, x: 3, y: 0)
            .shadow(color: ChickenNotificationPalette.deepCoral, radius: 0, x: 0, y: -3)
            .shadow(color: ChickenNotificationPalette.deepCoral, radius: 0, x: 0, y: 4)
            .shadow(color: ChickenTheme.ink.opacity(0.72), radius: 0, y: 8)
            .padding(.horizontal, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Road to Heaven")
    }

    private func messageAndActions(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 14) {
            messageCopy(compact: compact, alignment: .center)
            actionButtons(compact: compact)
        }
    }

    private func messageCopy(compact: Bool, alignment: TextAlignment) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .center, spacing: compact ? 5 : 9) {
            Text("ALLOW NOTIFICATIONS ABOUT BONUSES AND PROMOS")
                .font(.system(compact ? .subheadline : .headline, design: .rounded, weight: .black))
                .foregroundStyle(.white)
                .multilineTextAlignment(alignment)
                .lineLimit(3)
                .minimumScaleFactor(0.72)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)

            Text("Stay tuned with the best casino bonuses, free spins and slot offers.")
                .font(.system(compact ? .footnote : .subheadline, design: .rounded, weight: .medium))
                .italic()
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(alignment)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.42), radius: 3, y: 2)
        }
    }

    private func actionButtons(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            Button(action: allowAction) {
                Text("YES, I WANT BONUSES!")
            }
            .buttonStyle(ChickenNotificationPrimaryButtonStyle(compact: compact))
            .accessibilityHint("Shows the system permission request for casino bonus notifications")

            Button(action: skipAction) {
                Text("SKIP")
            }
            .buttonStyle(ChickenNotificationSecondaryButtonStyle(compact: compact))
            .accessibilityHint("Continues without casino bonus notifications")
        }
    }
}

private enum ChickenNotificationPalette {
    static let deepCoral = Color(red: 0.72, green: 0.23, blue: 0.16)
    static let secondaryButton = Color(red: 0.33, green: 0.36, blue: 0.43)
}

private struct ChickenNotificationPrimaryButtonStyle: ButtonStyle {
    let compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(compact ? .subheadline : .headline, design: .rounded, weight: .black))
            .foregroundStyle(.white)
            .shadow(color: ChickenNotificationPalette.deepCoral, radius: 1, y: 2)
            .frame(maxWidth: .infinity)
            .frame(minHeight: compact ? 44 : 54)
            .background {
                RoundedRectangle(cornerRadius: compact ? 13 : 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1, green: 0.75, blue: 0.12),
                                ChickenTheme.sunflower,
                                ChickenNotificationPalette.deepCoral
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 13 : 16, style: .continuous)
                    .stroke(Color(red: 1, green: 0.82, blue: 0.24), lineWidth: 3)
            }
            .shadow(
                color: ChickenNotificationPalette.deepCoral.opacity(0.9),
                radius: 0,
                y: configuration.isPressed ? 2 : 5
            )
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ChickenNotificationSecondaryButtonStyle: ButtonStyle {
    let compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(compact ? .footnote : .subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.5 : 0.68))
            .frame(maxWidth: .infinity)
            .frame(minHeight: compact ? 34 : 40)
            .background(
                ChickenNotificationPalette.secondaryButton
                    .opacity(configuration.isPressed ? 0.78 : 0.92),
                in: RoundedRectangle(cornerRadius: compact ? 13 : 16, style: .continuous)
            )
    }
}

#Preview("Notification Primer") {
    NotificationOptInView(allowAction: {}, skipAction: {})
}
