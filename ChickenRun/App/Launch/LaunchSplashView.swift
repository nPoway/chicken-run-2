import SwiftUI

struct LaunchSplashView: View {
    let message: String

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ZStack {
            ChickenTheme.pageGradient
                .ignoresSafeArea()

            backgroundClouds

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Road to Heaven is loading. \(message)")
    }

    private var regularLayout: some View {
        VStack(spacing: 20) {
            branding(size: 144)
            loadingIndicator
                .padding(.top, 2)
        }
        .frame(maxWidth: 380)
    }

    private var compactLayout: some View {
        HStack(spacing: 24) {
            branding(size: 104)
            loadingIndicator
        }
        .frame(maxWidth: 620)
    }

    private func branding(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.48))
                .frame(width: size, height: size)

            Image("logo-chiken")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.76, height: size * 0.76)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        }
        .shadow(color: ChickenTheme.sky.opacity(0.42), radius: 20, y: 10)
        .accessibilityHidden(true)
    }

    private var loadingIndicator: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(ChickenTheme.coral)
            .controlSize(.large)
    }

    private var backgroundClouds: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.38))
                .frame(width: 230, height: 230)
                .blur(radius: 8)
                .offset(x: -150, y: -260)

            Circle()
                .fill(ChickenTheme.sunflower.opacity(0.13))
                .frame(width: 270, height: 270)
                .blur(radius: 12)
                .offset(x: 165, y: 280)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    LaunchSplashView(message: "Loading")
}
