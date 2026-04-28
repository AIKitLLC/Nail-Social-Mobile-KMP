import SwiftUI

@main
struct NailTryOnApp: App {
    init() {
        // Confirms the KMP shared.xcframework actually links at runtime.
        // Visible in device console so we can spot regressions.
        print("[KMP] \(SharedBridge.smokeTestDescription())")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
    }
}
