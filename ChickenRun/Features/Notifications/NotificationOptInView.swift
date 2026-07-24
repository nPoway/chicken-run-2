//
//  NotificationOptInView.swift
//  ChickenRun
//

import SwiftUI

/// A primer shown immediately before the system notification authorization alert.
struct NotificationOptInView: View {
    let allowAction: () -> Void
    let skipAction: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ZStack {
            ChickenTheme.pageGradient
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    Group {
                        if verticalSizeClass == .compact {
                            compactLayout
                        } else {
                            regularLayout
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    .padding(.horizontal, 24)
                    .padding(.vertical, verticalSizeClass == .compact ? 14 : 28)
                }
            }
        }
    }

    private var regularLayout: some View {
        VStack(spacing: 20) {
            illustration(width: 166)
            message(compact: false)
            actions
        }
        .frame(maxWidth: 410)
        .padding(24)
        .notificationCard(tint: ChickenTheme.sunflower)
    }

    private var compactLayout: some View {
        HStack(spacing: 20) {
            illustration(width: 116)

            VStack(spacing: 14) {
                message(compact: true)
                actions
            }
        }
        .frame(maxWidth: 670)
        .padding(18)
        .notificationCard(tint: ChickenTheme.sunflower)
    }

    private func illustration(width: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(ChickenTheme.sunflower.opacity(0.16))
                .frame(width: width, height: width)

            Image("TravelerChickenSprite")
                .resizable()
                .scaledToFit()
                .frame(width: width * 0.78, height: width * 0.86)
                .rotationEffect(.degrees(-5))

            Image(systemName: "bell.badge.fill")
                .font(.system(size: width * 0.21, weight: .bold))
                .foregroundStyle(ChickenTheme.coral)
                .padding(width * 0.10)
                .background(.white, in: Circle())
                .offset(x: width * 0.29, y: -width * 0.28)
        }
        .shadow(color: ChickenTheme.ink.opacity(0.12), radius: 12, y: 7)
        .accessibilityHidden(true)
    }

    private func message(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 10) {
            Text("Stay close to the flock")
                .font(.system(compact ? .title2 : .largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(ChickenTheme.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.78)

            Text("Enable notifications for flight updates, fresh challenges, and a quick way back to your journey.")
                .font(compact ? .subheadline : .body)
                .foregroundStyle(ChickenTheme.mutedInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: allowAction) {
                Label("Enable notifications", systemImage: "bell.badge.fill")
            }
            .buttonStyle(ChickenNotificationPrimaryButtonStyle())
            .accessibilityHint("Opens the system notification permission request")

            Button(action: skipAction) {
                Text("Skip for now")
            }
            .buttonStyle(ChickenNotificationSecondaryButtonStyle())
            .accessibilityHint("Continues without enabling notifications")
        }
    }
}

private struct ChickenNotificationPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(ChickenTheme.coral.opacity(configuration.isPressed ? 0.76 : 1), in: Capsule())
    }
}

private struct ChickenNotificationSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(ChickenTheme.ink)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(.white.opacity(configuration.isPressed ? 0.56 : 0.74), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(ChickenTheme.ink.opacity(0.10), lineWidth: 1)
            }
    }
}

private extension View {
    func notificationCard(tint: Color) -> some View {
        background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(tint.opacity(0.26), lineWidth: 1)
            }
            .shadow(color: ChickenTheme.ink.opacity(0.10), radius: 18, y: 10)
    }
}

#Preview {
    NotificationOptInView(allowAction: {}, skipAction: {})
}
