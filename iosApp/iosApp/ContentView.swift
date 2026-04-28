import SwiftUI

/// Root shell — hosts the custom bottom tab bar and routes between primary
/// tabs. The AR camera is presented as a full-screen modal from the central
/// "Try" action so it can claim the entire viewport for the AR experience.
struct ContentView: View {
    @State private var selectedTab: AppTab = ContentView.initialTab()
    @State private var presentedDesignId: String?
    @State private var showCamera = ProcessInfo.processInfo.arguments.contains("--auto-camera")
    @State private var presentedCategory: String?

    /// Allows automated screenshot scripts to launch directly into a tab via
    /// `--initial-tab N` (0=Discover, 1=Trends, 2=Gallery, 3=Profile).
    static func initialTab() -> AppTab {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--initial-tab"),
           i + 1 < args.count,
           let raw = Int(args[i + 1]),
           let tab = AppTab(rawValue: raw) {
            return tab
        }
        return .discover
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Edge-to-edge background, including status bar / dynamic island
            DS.Brand.backgroundGradient
                .ignoresSafeArea()

            // Tab content — cross-fades when switching. Each child manages
            // its own bottom safe-area inset so content clears the floating
            // tab bar.
            Group {
                switch selectedTab {
                case .discover:
                    DiscoverScreen { id in
                        presentedDesignId = id
                        showCamera = true
                    }
                case .trends:
                    TrendsScreen { _ in
                        showCamera = true
                    }
                case .gallery:
                    GalleryScreen()
                case .profile:
                    ProfileScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .animation(.smoothFade, value: selectedTab)

            BottomNavBar(selected: $selectedTab) {
                showCamera = true
            }
            .padding(.bottom, DS.BottomBar.bottomInset)
        }
        .fullScreenCover(isPresented: $showCamera) {
            NailTryOnCameraView(designId: presentedDesignId) {
                showCamera = false
                presentedDesignId = nil
            }
        }
    }
}
