import SwiftUI

/// Centralized design tokens. Edit here, propagate everywhere.
enum DS {

    // MARK: - Spacing

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }

    // MARK: - Corner radii

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let chip: CGFloat = 24
    }

    // MARK: - Bottom bar geometry

    enum BottomBar {
        /// Height of the floating nav bar visual
        static let height: CGFloat = 64
        /// Distance from the very bottom of the safe area. 0 = capsule
        /// sits flush against the home-indicator inset (Apple Maps style)
        /// so we don't fight the system gesture zone or waste space on iPad.
        static let bottomInset: CGFloat = 0
        /// Total reserved space scrollable content should leave at the bottom
        /// so nothing is hidden under the bar.
        static let reservedSpace: CGFloat = 96
    }

    // MARK: - Brand colors

    enum Brand {
        static let pinkPrimary = Color(red: 0.94, green: 0.20, blue: 0.45)
        static let pinkAccent = Color(red: 1.0, green: 0.55, blue: 0.72)
        static let purpleAccent = Color(red: 0.55, green: 0.27, blue: 0.78)

        static let primaryGradient = LinearGradient(
            colors: [pinkAccent, pinkPrimary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Soft brand-tinted gradient. Explicit colors so we render
        /// consistently regardless of system light/dark mode.
        static let backgroundGradient = LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.97, blue: 0.98),
                Color(red: 0.97, green: 0.94, blue: 0.96)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        /// Slightly stronger version for hero sections.
        static let heroGradient = LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.94, blue: 0.96),
                Color(red: 0.94, green: 0.88, blue: 0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Solid fill used by the bottom-of-screen scroll-fade mask. Matches
        /// the lower stop of `backgroundGradient` so content visually melts
        /// into the page behind the floating tab bar.
        static let backgroundFade = Color(red: 0.97, green: 0.94, blue: 0.96)
    }

    // MARK: - Shadows

    enum Shadow {
        static let card = (color: Color.black.opacity(0.10), radius: 8.0, y: 3.0)
        static let elevated = (color: Color.black.opacity(0.18), radius: 14.0, y: 6.0)
    }
}

// MARK: - Modifier helpers

extension View {
    /// Apply standardized bottom inset that clears the floating tab bar.
    /// Adds a soft fade overlay so scrolled content fades into the page
    /// background behind the glass nav bar instead of getting hard-clipped.
    func bottomBarSafeArea() -> some View {
        self
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: DS.BottomBar.reservedSpace)
            }
            .overlay(alignment: .bottom) {
                // The fade is purely decorative — it never intercepts taps.
                LinearGradient(
                    colors: [
                        Color.clear,
                        DS.Brand.backgroundFade.opacity(0.0),
                        DS.Brand.backgroundFade.opacity(0.35),
                        DS.Brand.backgroundFade.opacity(0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: DS.BottomBar.reservedSpace)
                .allowsHitTesting(false)
            }
    }

    /// Standardized card shadow.
    func cardShadow() -> some View {
        self.shadow(color: DS.Shadow.card.color, radius: DS.Shadow.card.radius, x: 0, y: DS.Shadow.card.y)
    }

    func elevatedShadow() -> some View {
        self.shadow(color: DS.Shadow.elevated.color, radius: DS.Shadow.elevated.radius, x: 0, y: DS.Shadow.elevated.y)
    }
}
