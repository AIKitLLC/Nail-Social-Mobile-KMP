import SwiftUI
import shared

// MARK: - Layout helpers

/// Bridges KMP `LayoutSpec` to ergonomic Swift values.
enum SharedLayout {
    static var maxContentWidthRegular: CGFloat {
        CGFloat(truncating: LayoutSpec.shared.maxContentWidthRegular as NSNumber)
    }
    static func designsColumns(regular: Bool) -> Int {
        Int(regular ? LayoutSpec.shared.designsColumnsRegular : LayoutSpec.shared.designsColumnsCompact)
    }
    static func categoriesColumns(regular: Bool) -> Int {
        Int(regular ? LayoutSpec.shared.categoriesColumnsRegular : LayoutSpec.shared.categoriesColumnsCompact)
    }
    static func galleryColumns(regular: Bool) -> Int {
        Int(regular ? LayoutSpec.shared.galleryColumnsRegular : LayoutSpec.shared.galleryColumnsCompact)
    }
    static func featuredCardFraction(regular: Bool) -> CGFloat {
        let raw = regular
            ? LayoutSpec.shared.featuredCardWidthFractionRegular
            : LayoutSpec.shared.featuredCardWidthFractionCompact
        return CGFloat(truncating: raw as NSNumber)
    }
    static func categoryTileHeight(regular: Bool) -> CGFloat {
        let raw = regular
            ? LayoutSpec.shared.categoryTileHeightRegular
            : LayoutSpec.shared.categoryTileHeightCompact
        return CGFloat(truncating: raw as NSNumber)
    }
}

extension View {
    /// Constrains content to the iPad reading width on regular size classes
    /// and centers it horizontally; passes through unchanged on compact
    /// (iPhone portrait). Use on screens that look stretched at full iPad
    /// width (forms, settings) but skip on grid screens that benefit from
    /// using the whole canvas (Discover, Gallery).
    @ViewBuilder
    func centeredContentWidth(_ regular: Bool) -> some View {
        if regular {
            self
                .frame(maxWidth: SharedLayout.maxContentWidthRegular, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            self
        }
    }
}

// MARK: - Category gradient palette (iOS-side styling for shared keys)

/// Maps shared `NailCatalog.Category.key` → iOS gradient + scrim treatment.
/// Keys come from the KMP catalog so adding a new tag in shared automatically
/// flows here (with a graceful fallback to brand pink).
private struct CategoryStyle {
    let gradient: [Color]
    /// Whether the gradient is light enough that we need a dark text scrim
    /// instead of inverted-on-dark text. Keeps "Minimalist"/"French"/"Pastel"
    /// readable while keeping vivid gradients on saturated tiles.
    let lightSurface: Bool
}

private enum CategoryStyleMap {
    static func style(for key: String) -> CategoryStyle {
        switch key {
        case "minimalist":
            return CategoryStyle(
                gradient: [Color(red: 0.95, green: 0.92, blue: 0.86), Color(red: 0.78, green: 0.72, blue: 0.62)],
                lightSurface: true
            )
        case "french":
            return CategoryStyle(
                gradient: [Color(red: 0.99, green: 0.93, blue: 0.88), Color(red: 0.91, green: 0.74, blue: 0.66)],
                lightSurface: true
            )
        case "glitter":
            return CategoryStyle(
                gradient: [Color(red: 0.98, green: 0.60, blue: 0.78), Color(red: 0.85, green: 0.20, blue: 0.45)],
                lightSurface: false
            )
        case "chrome":
            return CategoryStyle(
                gradient: [Color(red: 0.85, green: 0.85, blue: 0.92), Color(red: 0.40, green: 0.40, blue: 0.50)],
                lightSurface: false
            )
        case "bold":
            return CategoryStyle(
                gradient: [Color(red: 0.95, green: 0.40, blue: 0.30), Color(red: 0.62, green: 0.10, blue: 0.10)],
                lightSurface: false
            )
        case "pastel":
            return CategoryStyle(
                gradient: [Color(red: 0.88, green: 0.94, blue: 1.00), Color(red: 0.72, green: 0.80, blue: 0.94)],
                lightSurface: true
            )
        case "floral":
            return CategoryStyle(
                gradient: [Color(red: 0.85, green: 0.95, blue: 0.78), Color(red: 0.40, green: 0.62, blue: 0.30)],
                lightSurface: false
            )
        case "darkmood":
            return CategoryStyle(
                gradient: [Color(red: 0.30, green: 0.20, blue: 0.45), Color(red: 0.10, green: 0.05, blue: 0.20)],
                lightSurface: false
            )
        case "y2k":
            return CategoryStyle(
                gradient: [Color(red: 0.74, green: 0.55, blue: 0.95), Color(red: 0.40, green: 0.25, blue: 0.85)],
                lightSurface: false
            )
        case "holographic":
            return CategoryStyle(
                gradient: [Color(red: 0.70, green: 0.90, blue: 0.95), Color(red: 0.85, green: 0.60, blue: 0.95)],
                lightSurface: false
            )
        default:
            return CategoryStyle(
                gradient: [DS.Brand.pinkAccent, DS.Brand.pinkPrimary],
                lightSurface: false
            )
        }
    }
}

// MARK: - Reusable header

struct TabHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                if let s = subtitle {
                    Text(s)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.md)
        .padding(.bottom, DS.Space.sm)
    }
}

// MARK: - Discover (browser wrapped)

struct DiscoverScreen: View {
    let onDesignSelected: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(
                title: "Discover",
                subtitle: "Trending nail designs picked for you"
            )
            NailBrowserView(onDesignSelected: onDesignSelected)
                .bottomBarSafeArea()
        }
    }
}

// MARK: - Trends (categories grid)

struct TrendsScreen: View {
    let onCategoryTap: (String) -> Void

    @State private var featuredKey: String = ""

    /// Pulled from the shared KMP catalog so iOS + Android always show
    /// the same set of tags / icons / featured picks.
    private let categories: [NailCatalog.Category] = NailCatalog.shared.trendingCategories
    private let featured: [NailCatalog.Category] = NailCatalog.shared.featuredCategories

    @Environment(\.horizontalSizeClass) private var hsc

    private var isRegular: Bool { hsc == .regular }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: DS.Space.md),
            count: SharedLayout.categoriesColumns(regular: isRegular)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                TabHeader(
                    title: "Trends",
                    subtitle: "Hot categories blowing up this week"
                )

                featuredCarousel
                pageDots
                categoriesSection
            }
        }
        .bottomBarSafeArea()
        .onAppear {
            if featuredKey.isEmpty, let first = featured.first {
                featuredKey = first.key
            }
        }
    }

    // MARK: Carousel

    /// Computed once per layout pass from the device width so the
    /// carousel's frame height tracks the actual card height — no
    /// GeometryReader chicken-and-egg with the surrounding VStack.
    private var featuredCardSide: CGFloat {
        let screenW = UIScreen.main.bounds.width
        let viewportW = isRegular
            ? min(screenW, SharedLayout.maxContentWidthRegular + 40)
            : screenW
        let raw = viewportW * SharedLayout.featuredCardFraction(regular: isRegular)
        return min(max(raw, 200), 360)
    }

    @ViewBuilder
    private var featuredCarousel: some View {
        let side = featuredCardSide

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.md) {
                ForEach(featured, id: \.key) { cat in
                    FeaturedTrendCard(
                        title: cat.label,
                        gradient: CategoryStyleMap.style(for: cat.key).gradient,
                        width: side,
                        height: side,
                        onTap: { onCategoryTap(cat.label) }
                    )
                    .scrollTransition { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1.0 : 0.94)
                            .opacity(phase.isIdentity ? 1.0 : 0.7)
                    }
                    .id(cat.key)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, DS.Space.xl)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: Binding(
            get: { featuredKey.isEmpty ? nil : featuredKey },
            set: { newValue in
                if let v = newValue { featuredKey = v }
            }
        ))
        .frame(height: side + DS.Space.sm)
    }

    @ViewBuilder
    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(featured, id: \.key) { cat in
                Capsule()
                    .fill(cat.key == featuredKey ? DS.Brand.pinkPrimary : Color.primary.opacity(0.15))
                    .frame(width: cat.key == featuredKey ? 18 : 6, height: 6)
                    .animation(.snappySpring, value: featuredKey)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, DS.Space.xs)
    }

    @ViewBuilder
    private var categoriesSection: some View {
        Text("Categories")
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, DS.Space.xl)

        LazyVGrid(columns: columns, spacing: DS.Space.md) {
            ForEach(categories, id: \.key) { c in
                CategoryTile(
                    category: c,
                    height: SharedLayout.categoryTileHeight(regular: isRegular),
                    onTap: { onCategoryTap(c.label) }
                )
            }
        }
        .padding(.horizontal, DS.Space.xl)
    }
}

private struct FeaturedTrendCard: View {
    let title: String
    let gradient: [Color]
    let width: CGFloat
    let height: CGFloat
    var onTap: () -> Void

    var body: some View {
        Button(action: { Haptics.light(); onTap() }) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)

                Image(systemName: "sparkles")
                    .font(.system(size: 80))
                    .foregroundStyle(.white.opacity(0.18))
                    .rotationEffect(.degrees(-12))
                    .offset(x: width * 0.4, y: -height * 0.4)

                // Subtle scrim so caption text reads on light gradients too.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.35)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Featured")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Tap to explore")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.92))
                }
                .padding(DS.Space.lg)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .shadow(color: gradient.last?.opacity(0.4) ?? .black.opacity(0.3), radius: 14, y: 6)
        }
        .buttonStyle(BounceButtonStyle())
    }
}

private struct CategoryTile: View {
    let category: NailCatalog.Category
    let height: CGFloat
    var onTap: () -> Void

    private var style: CategoryStyle { CategoryStyleMap.style(for: category.key) }

    /// Use dark text on light backgrounds so labels are readable on
    /// minimalist / french / pastel gradients.
    private var textColor: Color {
        style.lightSurface ? Color(red: 0.18, green: 0.10, blue: 0.14) : .white
    }
    private var iconColor: Color {
        style.lightSurface ? Color(red: 0.32, green: 0.18, blue: 0.22) : .white
    }
    private var iconShadow: Color {
        style.lightSurface ? .clear : .black.opacity(0.20)
    }

    var body: some View {
        Button(action: { Haptics.light(); onTap() }) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: category.iconHint)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .shadow(color: iconShadow, radius: 2)
                Text(category.label)
                    .font(.headline)
                    .foregroundStyle(textColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .frame(height: height)
            .background(
                LinearGradient(colors: style.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: style.gradient.last?.opacity(0.35) ?? .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(BounceButtonStyle())
    }
}

// MARK: - Gallery (Documents folder browser)

struct GalleryScreen: View {
    @State private var captures: [URL] = []
    @State private var selected: URL?

    @Environment(\.horizontalSizeClass) private var hsc

    private var isRegular: Bool { hsc == .regular }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: DS.Space.xs),
            count: SharedLayout.galleryColumns(regular: isRegular)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(
                title: "Gallery",
                subtitle: captures.isEmpty ? "Snap your first try-on to see it here" : "\(captures.count) saved looks"
            )

            if captures.isEmpty {
                VStack(spacing: DS.Space.md) {
                    Spacer()
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Empty for now")
                        .font(.title3.weight(.semibold))
                    Text("Tap the wand to try a polish, then capture.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(captures, id: \.absoluteString) { url in
                            GalleryThumb(url: url) {
                                Haptics.light()
                                selected = url
                            }
                        }
                    }
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.top, DS.Space.sm)
                }
            }
        }
        .bottomBarSafeArea()
        .onAppear(perform: refresh)
        .sheet(item: Binding(
            get: { selected.map { IdentifiedURL(url: $0) } },
            set: { newValue in selected = newValue?.url }
        )) { ident in
            if let img = UIImage(contentsOfFile: ident.url.path) {
                CapturePreviewView(image: img, fileURL: ident.url) {
                    selected = nil
                }
            }
        }
    }

    private func refresh() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        if let files = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) {
            captures = files
                .filter { $0.lastPathComponent.hasPrefix("nail-") && $0.pathExtension.lowercased() == "jpg" }
                .sorted { (a, b) -> Bool in
                    let ad = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    let bd = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    return ad > bd
                }
        }
    }
}

private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct GalleryThumb: View {
    let url: URL
    var onTap: () -> Void
    @State private var img: UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Color(.systemGray5)
                if let img {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                }
            }
            .aspectRatio(0.75, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(BounceButtonStyle())
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let i = UIImage(contentsOfFile: url.path)
                DispatchQueue.main.async { self.img = i }
            }
        }
    }
}

// MARK: - Profile (settings list)

struct ProfileScreen: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showAbout = false

    @Environment(\.horizontalSizeClass) private var hsc
    private var isRegular: Bool { hsc == .regular }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                TabHeader(title: "Profile", subtitle: "Your AR vibe lives here")

                profileCard

                sectionHeader("Preferences")
                settingsCard {
                    SettingRow(icon: "hand.wave.fill", title: "Replay onboarding", subtitle: "See the welcome cascade again") {
                        Haptics.light()
                        hasSeenOnboarding = false
                    }
                    Divider().padding(.leading, 56)
                    SettingRow(icon: "heart.text.square.fill", title: "About this app", subtitle: "Version, credits") {
                        Haptics.light()
                        showAbout = true
                    }
                }

                sectionHeader("Connections")
                settingsCard {
                    SettingRow(icon: "link", title: "Share an idea", subtitle: "Send feedback to the team")
                    Divider().padding(.leading, 56)
                    SettingRow(icon: "star.fill", title: "Rate Nail AR", subtitle: "Help us reach more polish lovers")
                }
            }
        }
        .bottomBarSafeArea()
        .sheet(isPresented: $showAbout) {
            AboutSheet()
        }
    }

    private var profileCard: some View {
        HStack(spacing: DS.Space.md) {
            AnimatedAvatar()
                .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("You")
                        .font(.title3.bold())
                    Text("PRO")
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(DS.Brand.primaryGradient)
                        )
                        .foregroundStyle(.white)
                }
                Text("Nail explorer · iOS")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Joined this season")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(DS.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                        .strokeBorder(DS.Brand.pinkPrimary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: DS.Brand.pinkPrimary.opacity(0.10), radius: 12, y: 6)
        )
        .padding(.horizontal, DS.Space.xl)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 28)
            .padding(.top, 8)
    }

    private func settingsCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .padding(.horizontal, 20)
    }
}

private struct SettingRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        LinearGradient(colors: [Color.pink, Color(red: 0.9, green: 0.20, blue: 0.45)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    if let s = subtitle {
                        Text(s)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
    }
}

private struct AboutSheet: View {
    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 40, height: 4)
                .padding(.top, 8)
            Image(systemName: "wand.and.stars")
                .font(.system(size: 50))
                .foregroundStyle(LinearGradient(colors: [.pink, .purple], startPoint: .top, endPoint: .bottom))
            Text("Nail AR")
                .font(.title.bold())
            Text("Try-on nail polish in real time using your camera. Powered by on-device AI.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Text("v1.0 · 2026")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}
