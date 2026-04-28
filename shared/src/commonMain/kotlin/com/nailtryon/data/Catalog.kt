package com.nailtryon.data

/**
 * Shared catalog of high-level nail design tags + layout sizing rules.
 * Both iOS and Android pull from this so the filter UI, category tiles
 * and grid breakpoints stay in lockstep with the recommendation backend.
 */
object NailCatalog {

    /// Common hashtags users browse by. The leading "#" is intentionally
    /// omitted so each platform can render its own affordance.
    val popularHashtags: List<String> = listOf(
        "minimalist",
        "french",
        "glitter",
        "chrome",
        "pastel",
        "bold",
        "floral",
        "darkmood",
        "y2k",
        "holographic"
    )

    /// Curated category groupings for the Trends screen.
    data class Category(
        val key: String,
        val label: String,
        /// SF Symbols / Material icon name hint (optional — UIs may map locally).
        val iconHint: String,
        /// When true, the category surfaces in the featured carousel at top
        /// of the Trends tab. Keep small (2–4) so the carousel stays focused.
        val featured: Boolean = false
    )

    val trendingCategories: List<Category> = listOf(
        Category("minimalist", "Minimalist", "circle.dashed",          featured = true),
        Category("french",     "French",     "drop.fill",              featured = false),
        Category("glitter",    "Glitter",    "sparkle",                featured = true),
        Category("chrome",     "Chrome",     "circle.lefthalf.filled", featured = false),
        Category("bold",       "Bold",       "flame.fill",             featured = true),
        Category("pastel",     "Pastel",     "cloud.fill",             featured = false),
        Category("floral",     "Floral",     "leaf.fill",              featured = false),
        Category("darkmood",   "Dark Mood",  "moon.stars.fill",        featured = false)
    )

    /// Convenience: featured slice for the carousel hero.
    val featuredCategories: List<Category> = trendingCategories.filter { it.featured }
}

/**
 * Cross-platform breakpoints + grid densities. Centralising these keeps
 * iPhone vs iPad — and eventually phone vs tablet on Android — visually
 * coherent. Platforms read these directly from the shared module rather
 * than duplicating magic numbers.
 */
object LayoutSpec {

    /// Column counts for the various grids the app renders. "compact"
    /// matches iOS UIUserInterfaceSizeClass.compact (iPhone portrait),
    /// "regular" matches iPad / large iPhone landscape.
    val designsColumnsCompact:   Int = 2
    val designsColumnsRegular:   Int = 3
    val categoriesColumnsCompact: Int = 2
    val categoriesColumnsRegular: Int = 3
    val galleryColumnsCompact:   Int = 3
    val galleryColumnsRegular:   Int = 5

    /// On iPad / wide screens we cap the inner content rail so lists,
    /// settings and headers don't stretch into uncomfortably long lines.
    val maxContentWidthRegular: Double = 720.0

    /// Featured carousel — fraction of viewport width each card occupies.
    /// 0.86 on phones gives a clear next-card peek; 0.46 on tablets shows
    /// roughly two-and-a-bit cards at once.
    val featuredCardWidthFractionCompact: Double = 0.86
    val featuredCardWidthFractionRegular: Double = 0.46

    /// Featured card aspect ratio (width / height). Square-ish hero.
    val featuredCardAspect: Double = 1.0

    /// Category tile target heights — taller on iPad so the icon + label
    /// don't look cramped when each tile gets more horizontal real estate.
    val categoryTileHeightCompact: Double = 100.0
    val categoryTileHeightRegular: Double = 132.0

    /// Bottom tab bar visual width cap on regular size classes (iPad).
    /// At full iPad width the tabs are spaced too far apart and the bar
    /// stops feeling like a discrete control. Capping at ~520pt keeps it
    /// proportional to common phone widths while staying centered.
    val bottomBarMaxWidthRegular: Double = 520.0

    /// Maximum content width for vertical reading rails (settings, profile,
    /// long lists). Grids that benefit from extra columns ignore this.
    val readingRailMaxWidthRegular: Double = 760.0
}
