import SwiftUI

struct MainMenuView: View {
    @Binding var activeMode: ActiveAppMode?
    @State private var animateIn: Bool = false
    @State private var heroScale: CGFloat = 0.92
    @State private var glowPhase: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image("MainMenuBG")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                Color.black.opacity(0.45)

                VStack(spacing: 0) {
                    Spacer().frame(height: geo.safeAreaInsets.top + 20)

                    ppsrHeroCard(geo: geo)

                    Spacer().frame(height: 20)

                    toolsRow

                    Spacer()

                    bottomBar(geo: geo)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.1)) {
                animateIn = true
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                glowPhase = true
            }
            withAnimation(.spring(duration: 1.0, bounce: 0.08).delay(0.15)) {
                heroScale = 1.0
            }
        }
        .onDisappear {
            animateIn = false
            heroScale = 0.92
            glowPhase = false
        }
    }

    private func ppsrHeroCard(geo: GeometryProxy) -> some View {
        let availableHeight = geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom
        return Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                activeMode = .ppsr
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.0, green: 0.15, blue: 0.22),
                                Color(red: 0.0, green: 0.25, blue: 0.35),
                                Color(red: 0.0, green: 0.18, blue: 0.28)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        RadialGradient(
                            colors: [.cyan.opacity(glowPhase ? 0.15 : 0.05), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 200
                        )
                    )

                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.cyan.opacity(0.4), .cyan.opacity(0.1), .teal.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )

                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(.cyan.opacity(glowPhase ? 0.12 : 0.06))
                            .frame(width: 90, height: 90)
                            .blur(radius: 20)

                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .teal],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .cyan.opacity(0.6), radius: 16)
                    }

                    VStack(spacing: 8) {
                        Text("PPSR CHECK")
                            .font(.system(size: 28, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 6)

                        Text("VIN & Card Testing Engine")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.cyan.opacity(0.7))
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("LAUNCH")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(.cyan.opacity(0.25))
                            .overlay(
                                Capsule()
                                    .strokeBorder(.cyan.opacity(0.5), lineWidth: 1)
                            )
                    )
                }
            }
            .frame(height: availableHeight * 0.52)
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(heroScale)
        .opacity(animateIn ? 1 : 0)
        .sensoryFeedback(.impact(weight: .heavy), trigger: activeMode == .ppsr)
    }

    private var toolsRow: some View {
        HStack(spacing: 12) {
            toolButton(
                title: "NORD",
                icon: "shield.checkered",
                color: Color(red: 0.0, green: 0.78, blue: 1.0),
                delay: 0.1
            ) {
                activeMode = .nordConfig
            }

            toolButton(
                title: "IP TEST",
                icon: "network.badge.shield.half.filled",
                color: .indigo,
                delay: 0.2
            ) {
                activeMode = .ipScoreTest
            }

            toolButton(
                title: "DEBUG",
                icon: "doc.text.magnifyingglass",
                color: .purple,
                delay: 0.3
            ) {
                activeMode = .debugLog
            }

            toolButton(
                title: "VAULT",
                icon: "externaldrive.fill",
                color: .teal,
                delay: 0.4
            ) {
                activeMode = .vault
            }
        }
        .padding(.horizontal, 24)
    }

    private func toolButton(title: String, icon: String, color: Color, delay: Double, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                action()
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(color.opacity(0.12))
                        .frame(width: 52, height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(color.opacity(0.25), lineWidth: 0.5)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 20)
        .animation(.spring(duration: 0.6, bounce: 0.1).delay(delay), value: animateIn)
        .sensoryFeedback(.impact(weight: .light), trigger: activeMode)
    }

    private func bottomBar(geo: GeometryProxy) -> some View {
        HStack {
            Spacer()
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.15))
            Spacer()
        }
        .padding(.bottom, geo.safeAreaInsets.bottom + 8)
        .opacity(animateIn ? 1 : 0)
        .animation(.easeOut(duration: 1.0).delay(0.5), value: animateIn)
    }
}

nonisolated enum ActiveAppMode: String, Sendable {
    case ppsr
    case debugLog
    case nordConfig
    case vault
    case ipScoreTest
}
