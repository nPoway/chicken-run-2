//
//  NoInternetView.swift
//  ChickenRun
//

import SwiftUI

/// The target-branded recovery surface for an unavailable configuration connection.
struct NoInternetView: View {
    let message: String
    let retryAction: () -> Void

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
                    .padding(.vertical, verticalSizeClass == .compact ? 16 : 28)
                }
            }
        }
    }

    private var regularLayout: some View {
        VStack(spacing: 18) {
            statusIcon(size: 88, symbolSize: 38)
            messageBlock
            retryButton
                .padding(.top, 2)
        }
        .frame(maxWidth: 390)
        .padding(22)
        .backgroundCard(tint: ChickenTheme.sky)
    }

    private var compactLayout: some View {
        HStack(spacing: 20) {
            statusIcon(size: 72, symbolSize: 31)

            VStack(spacing: 14) {
                messageBlock
                retryButton
            }
        }
        .frame(maxWidth: 620)
        .padding(18)
        .backgroundCard(tint: ChickenTheme.sky)
    }

    private func statusIcon(size: CGFloat, symbolSize: CGFloat) -> some View {
        Image(systemName: "wifi.slash")
            .font(.system(size: symbolSize, weight: .bold))
            .foregroundStyle(ChickenTheme.coral)
            .frame(width: size, height: size)
            .background(ChickenTheme.coral.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }

    private var messageBlock: some View {
        VStack(spacing: 8) {
            Text("Unable to connect")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(ChickenTheme.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(verticalSizeClass == .compact ? .subheadline : .body)
                .foregroundStyle(ChickenTheme.mutedInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var retryButton: some View {
        Button(action: retryAction) {
            Label("Try Again", systemImage: "arrow.clockwise")
        }
        .buttonStyle(ChickenNoInternetButtonStyle())
        .accessibilityHint("Checks the internet connection and tries again")
    }
}

private struct ChickenNoInternetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(ChickenTheme.coral.opacity(configuration.isPressed ? 0.76 : 1), in: Capsule())
    }
}

private extension View {
    func backgroundCard(tint: Color) -> some View {
        background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(tint.opacity(0.26), lineWidth: 1)
            }
            .shadow(color: ChickenTheme.ink.opacity(0.10), radius: 18, y: 10)
    }
}

#Preview {
    NoInternetView(
        message: "Internet connection is required. Check your connection and try again.",
        retryAction: {}
    )
}
