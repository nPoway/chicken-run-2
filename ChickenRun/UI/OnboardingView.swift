//
//  OnboardingView.swift
//  ChickenRun
//

import SwiftUI

struct OnboardingView: View {
    let onFinished: () -> Void

    @State private var page = 0

    private let slides = [
        OnboardingSlide(
            eyebrow: "WELCOME, TRAVELER",
            title: "A little higher, every time.",
            detail: "Meet the smallest pilot in the sky coop. One soft landing is all it takes to begin a route.",
            actionTitle: "Next"
        ),
        OnboardingSlide(
            eyebrow: "CHOOSE A ROUTE",
            title: "Guide every bounce.",
            detail: "Hold the left or right side of the field to steer toward the next cloud. Safe landings keep the journey going.",
            actionTitle: "Next"
        ),
        OnboardingSlide(
            eyebrow: "TRAVEL LIGHT",
            title: "Save feathers for a bright day.",
            detail: "Collect feathers to charge a rescue Flap and unlock a new look. Your record always comes from the route you choose.",
            actionTitle: "Start my first flight"
        )
    ]

    var body: some View {
        ZStack {
            ChickenTheme.heroGradient
                .ignoresSafeArea()

            OnboardingSkyArtwork(page: page)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                header

                TabView(selection: $page) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        OnboardingSlideView(slide: slide, page: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicator
                    .padding(.bottom, 22)

                actionArea
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 22)
        }
        .tint(ChickenTheme.ink)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("logo-chiken")
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.72), lineWidth: 1)
                }

            Text("Chicken Run")
                .font(.headline.weight(.heavy))
                .foregroundStyle(.white)

            Spacer()

            if page < slides.count - 1 {
                Button("Skip") {
                    finishOnboarding()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 10)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chicken Run onboarding")
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(slides.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? .white : .white.opacity(0.34))
                    .frame(width: index == page ? 28 : 8, height: 8)
                    .animation(.spring(response: 0.28, dampingFraction: 0.8), value: page)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(page + 1) of \(slides.count)")
    }

    private var actionArea: some View {
        VStack(spacing: 10) {
            Button {
                if page == slides.count - 1 {
                    finishOnboarding()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        page += 1
                    }
                }
            } label: {
                HStack(spacing: 9) {
                    Text(slides[page].actionTitle)

                    Image(systemName: page == slides.count - 1 ? "arrow.up.right" : "arrow.right")
                }
                .font(.headline.weight(.heavy))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .accessibilityHint(page == slides.count - 1 ? "Opens your flight home" : "Shows the next introduction step")

            Text(page == slides.count - 1 ? "Your first climb begins from home." : "A gentle sky game with no pressure to hurry.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.80))
                .multilineTextAlignment(.center)
                .frame(minHeight: 16)
        }
    }

    private func finishOnboarding() {
        withAnimation(.easeInOut(duration: 0.26)) {
            onFinished()
        }
    }
}

private struct OnboardingSlide: Identifiable {
    let eyebrow: String
    let title: String
    let detail: String
    let actionTitle: String

    var id: String { title }
}

private struct OnboardingSlideView: View {
    let slide: OnboardingSlide
    let page: Int

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            OnboardingHeroArtwork(page: page)
                .frame(height: 290)
                .padding(.bottom, 24)

            VStack(spacing: 14) {
                Text(slide.eyebrow)
                    .font(.caption.weight(.heavy))
                    .tracking(1.4)
                    .foregroundStyle(ChickenTheme.sunflower)

                Text(slide.title)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(slide.detail)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.86))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 330)
            }

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingHeroArtwork: View {
    let page: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 244, height: 244)
                .blur(radius: 4)

            switch page {
            case 0:
                Image("logo-chiken")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(.white.opacity(0.80), lineWidth: 5)
                    }
                    .shadow(color: ChickenTheme.ink.opacity(0.22), radius: 16, y: 10)

            case 1:
                Image("TravelerChickenSprite")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 230)
                    .rotationEffect(.degrees(-5))
                    .offset(x: 3, y: 10)
                    .shadow(color: ChickenTheme.ink.opacity(0.22), radius: 8, y: 6)

                RouteArrow(direction: .left)
                    .offset(x: -112, y: 24)
                RouteArrow(direction: .right)
                    .offset(x: 112, y: -22)

            default:
                Image("TravelerChickenSprite")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 166, height: 244)
                    .rotationEffect(.degrees(5))
                    .shadow(color: ChickenTheme.ink.opacity(0.22), radius: 8, y: 6)
                    .offset(y: 5)

                Image(systemName: "leaf.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(ChickenTheme.sunflower)
                    .rotationEffect(.degrees(-24))
                    .offset(x: -106, y: 58)

                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 45, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .offset(x: 96, y: -54)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct OnboardingSkyArtwork: View {
    let page: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(ChickenTheme.sunflower.opacity(0.32))
                .frame(width: 250, height: 250)
                .blur(radius: 8)
                .offset(x: 150, y: -300)

            CloudBubble(size: 118)
                .offset(x: -155, y: page == 1 ? -110 : -186)

            CloudBubble(size: 92)
                .offset(x: 160, y: page == 2 ? 160 : 82)

            CloudBubble(size: 68)
                .offset(x: -130, y: 308)
        }
    }
}

private struct CloudBubble: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: size, height: size * 0.62)
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: size * 0.58, height: size * 0.58)
                .offset(x: -size * 0.22, y: -size * 0.15)
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: size * 0.52, height: size * 0.52)
                .offset(x: size * 0.24, y: -size * 0.11)
        }
    }
}

private enum RouteDirection {
    case left
    case right

    var symbolName: String {
        switch self {
        case .left: "arrow.left"
        case .right: "arrow.right"
        }
    }
}

private struct RouteArrow: View {
    let direction: RouteDirection

    var body: some View {
        Image(systemName: direction.symbolName)
            .font(.title2.weight(.heavy))
            .foregroundStyle(ChickenTheme.ink)
            .frame(width: 58, height: 58)
            .background(.white.opacity(0.88), in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.90), lineWidth: 2)
            }
            .shadow(color: ChickenTheme.ink.opacity(0.16), radius: 8, y: 5)
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(ChickenTheme.ink)
            .background(.white, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    OnboardingView(onFinished: {})
}
