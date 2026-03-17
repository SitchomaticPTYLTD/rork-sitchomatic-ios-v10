import SwiftUI

struct MainMenuView: View {
    @Binding var activeMode: ActiveAppMode?
    @State private var animateIn: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image("MainMenuBG")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                Color.black.opacity(0.3)

                VStack(spacing: 0) {
                    Spacer().frame(height: geo.safeAreaInsets.top + 24)

                    ppsrZone(geo: geo)
                        .frame(height: (geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom) * 0.35)

                    HStack(spacing: 0) {
                        nordConfigZone(geo: geo)
                        ipScoreTestZone(geo: geo)
                    }
                    .frame(height: (geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom) * 0.28)

                    Spacer()

                    Spacer().frame(height: geo.safeAreaInsets.bottom + 4)
                }

                VStack {
                    Spacer()

                    HStack {
                        Button {
                            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                                activeMode = .debugLog
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("DEBUG LOG")
                                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            }
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.06))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 16)

                        Spacer()

                        Button {
                            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                                activeMode = .vault
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "externaldrive.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("VAULT")
                                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            }
                            .foregroundStyle(.teal.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(.teal.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.15))
                            .padding(.trailing, 16)
                    }
                    .padding(.bottom, geo.safeAreaInsets.bottom + 6)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.12)) {
                animateIn = true
            }
        }
        .onDisappear {
            animateIn = false
        }
    }

    private func ppsrZone(geo: GeometryProxy) -> some View {
        Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                activeMode = .ppsr
            }
        } label: {
            ZStack {
                LinearGradient(
                    colors: [.blue.opacity(0.05), .cyan.opacity(0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "car.side.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.cyan)
                            .shadow(color: .cyan.opacity(0.5), radius: 8)

                        Text("PPSR")
                            .font(.system(size: 18, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 4)

                        Text("VIN & Card Testing")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.cyan.opacity(0.7))
                    }
                    .padding(.leading, 20)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.cyan)
                            .shadow(color: .cyan.opacity(0.5), radius: 8)

                        Text("CHECK")
                            .font(.system(size: 18, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 4)

                        HStack(spacing: 3) {
                            Text("ENTER")
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.cyan.opacity(0.6))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .heavy))
                                .foregroundStyle(.cyan.opacity(0.4))
                        }
                    }
                    .padding(.trailing, 20)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 30)
        .sensoryFeedback(.impact(weight: .medium), trigger: activeMode == .ppsr)
    }

    private func ipScoreTestZone(geo: GeometryProxy) -> some View {
        Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                activeMode = .ipScoreTest
            }
        } label: {
            ZStack {
                LinearGradient(
                    colors: [.indigo.opacity(0.05), .cyan.opacity(0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [.indigo, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: .indigo.opacity(0.5), radius: 8)

                    Text("IP SCORE")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 4)

                    Text("8x Concurrent")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.indigo.opacity(0.7))

                    HStack(spacing: 3) {
                        Text("TEST")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.indigo.opacity(0.6))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.indigo.opacity(0.4))
                    }
                    .padding(.top, 2)
                }
                .padding(.trailing, 20)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(animateIn ? 1 : 0)
        .offset(x: animateIn ? 0 : 30)
        .sensoryFeedback(.impact(weight: .medium), trigger: activeMode == .ipScoreTest)
    }

    private func nordConfigZone(geo: GeometryProxy) -> some View {
        Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                activeMode = .nordConfig
            }
        } label: {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.0, green: 0.08, blue: 0.12).opacity(0.3), Color(red: 0.0, green: 0.55, blue: 0.9).opacity(0.25)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(red: 0.0, green: 0.78, blue: 1.0))
                            .shadow(color: .cyan.opacity(0.5), radius: 8)

                        Text("NORD CONFIG")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 4)

                        Text("WireGuard & OpenVPN")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.0, green: 0.78, blue: 1.0).opacity(0.7))
                    }
                    .padding(.leading, 20)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.shield.fill")
                            Image(systemName: "lock.shield.fill")
                            Image(systemName: "key.horizontal.fill")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.0, green: 0.78, blue: 1.0).opacity(0.6))

                        HStack(spacing: 3) {
                            Text("GENERATE")
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .foregroundStyle(Color(red: 0.0, green: 0.78, blue: 1.0).opacity(0.6))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .heavy))
                                .foregroundStyle(Color(red: 0.0, green: 0.78, blue: 1.0).opacity(0.4))
                        }
                    }
                    .padding(.trailing, 20)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 30)
        .sensoryFeedback(.impact(weight: .medium), trigger: activeMode == .nordConfig)
    }
}

nonisolated enum ActiveAppMode: String, Sendable {
    case ppsr
    case debugLog
    case nordConfig
    case vault
    case ipScoreTest
}
