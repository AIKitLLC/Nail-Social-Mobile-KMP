import Foundation
import shared

/// Live link to the KMP shared module. The full Kotlin algorithm objects
/// (`ConnectedComponents`, `TextureMapper`) are reachable here as
/// `shared.ConnectedComponents`, but the Swift app currently has local
/// classes with the same name (`ConnectedComponents.swift`,
/// `TextureMapper.swift`) — those are next-iter cleanup targets.
///
/// Migration plan:
///   1. Delete `ConnectedComponents.swift` + `TextureMapper.swift`
///   2. Update `HandPoseDetector` to emit `shared.FingerOrientation`
///   3. Update `NailDetectorIOS` pipeline to call `shared.ConnectedComponents.shared`
///      and `shared.TextureMapper.shared` via the bridge helpers below
///   4. Replace `NailAPIClient.swift` + DTOs with `shared.NailApiService`
///
/// For this iter we just verify the framework links and is reachable.
enum SharedBridge {

    /// Smoke test — calls a top-level Kotlin function so the linker pulls in
    /// the framework. Used during initial wiring to fail-fast if the module
    /// isn't actually loadable.
    static func smokeTestDescription() -> String {
        let platform = Platform_iosKt.platformName()
        let uuid = Platform_iosKt.createUUID()
        return "shared reachable · platform=\(platform) · uuid=\(uuid.prefix(8))"
    }
}
