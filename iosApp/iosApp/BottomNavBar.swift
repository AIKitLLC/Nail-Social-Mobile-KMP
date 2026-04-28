import SwiftUI

/// Tab identifiers — keep stable across the app.
enum AppTab: Int, CaseIterable, Identifiable {
    case discover, trends, gallery, profile
    var id: Int { rawValue }

    var icon: String {
        switch self {
        case .discover: return "sparkles"
        case .trends:   return "flame.fill"
        case .gallery:  return "rectangle.stack.fill"
        case .profile:  return "person.crop.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .discover: return "Discover"
        case .trends:   return "Trends"
        case .gallery:  return "Gallery"
        case .profile:  return "Profile"
        }
    }
}

/// Glassmorphic floating tab bar with 4 tabs + an elevated central
/// "Try" button. Centered Try opens the AR camera.
struct BottomNavBar: View {
    @Binding var selected: AppTab
    var onTryTapped: () -> Void

    @Namespace private var indicator
    @State private var pulse = false

    private let leftTabs: [AppTab] = [.discover, .trends]
    private let rightTabs: [AppTab] = [.gallery, .profile]

    var body: some View {
        ZStack {
            // The bar
            HStack(spacing: 0) {
                tabGroup(leftTabs)
                Spacer().frame(width: 72) // room for the central button
                tabGroup(rightTabs)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(height: DS.BottomBar.height)
            .background(
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(
                        // top edge highlight gives it that lifted glass feel
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.55),
                                        Color.white.opacity(0.08),
                                        Color.white.opacity(0.18)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
                    .shadow(color: DS.Brand.pinkPrimary.opacity(0.10), radius: 24, y: 10)
            )

            // Central elevated Try button
            tryButton
                .offset(y: -18)
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func tabGroup(_ tabs: [AppTab]) -> some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                NavTabItem(
                    tab: tab,
                    isSelected: selected == tab,
                    indicator: indicator
                ) {
                    if selected != tab {
                        Haptics.selection()
                        withAnimation(.snappySpring) {
                            selected = tab
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var tryButton: some View {
        Button(action: {
            Haptics.success()
            onTryTapped()
        }) {
            ZStack {
                // Calmer pulse aura
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.42, blue: 0.62).opacity(0.45),
                                .clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 56
                        )
                    )
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulse ? 1.10 : 0.96)
                    .opacity(pulse ? 0.0 : 0.55)
                    .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false), value: pulse)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.55, blue: 0.72),
                                Color(red: 0.94, green: 0.20, blue: 0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.85), lineWidth: 3)
                    )
                    .shadow(color: Color(red: 0.94, green: 0.20, blue: 0.45).opacity(0.55), radius: 18, y: 4)

                Image(systemName: "wand.and.stars")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
        }
        .buttonStyle(BounceButtonStyle())
        .onAppear { pulse = true }
    }
}

private struct NavTabItem: View {
    let tab: AppTab
    let isSelected: Bool
    let indicator: Namespace.ID
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(DS.Brand.pinkPrimary.opacity(0.14))
                            .frame(width: 38, height: 26)
                            .matchedGeometryEffect(id: "indicator", in: indicator)
                    }
                    Image(systemName: tab.icon)
                        .font(.system(size: 17, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? DS.Brand.pinkPrimary : Color.primary.opacity(0.55))
                        .scaleEffect(isSelected ? 1.05 : 1.0)
                }
                .frame(height: 26)

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DS.Brand.pinkPrimary : Color.primary.opacity(0.50))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel(Text(tab.title))
    }
}

/// Generic spring bounce on press.
struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.snappySpring, value: configuration.isPressed)
    }
}
