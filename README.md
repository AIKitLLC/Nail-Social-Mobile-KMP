# Nail Social Mobile — KMP

**Kotlin Multiplatform project** cho Nail Try-On AR app, kết nối với backend tại `https://nail.ai-kit.net`.

## 🏗️ Kiến trúc

```
Nail-Social-Mobile-KMP/
├── shared/                          ← Code dùng chung (KMP)
│   └── src/
│       ├── commonMain/              ← 💜 Business logic (models, API, algorithms)
│       │   └── kotlin/com/nailtryon/
│       │       ├── data/
│       │       │   ├── Models.kt          ← Design, DesignResponse
│       │       │   └── NailApiService.kt  ← Ktor API client
│       │       └── domain/
│       │           ├── ConnectedComponents.kt  ← CCL algorithm (pure Kotlin)
│       │           └── TextureMapper.kt        ← Texture mapping + FingerOrientation
│       ├── androidMain/             ← Android-specific
│       │   └── kotlin/com/nailtryon/ml/
│       │       ├── NailDetector.kt         ← TFLite interpreter
│       │       └── HandOrientationDetector.kt ← MediaPipe hand tracking
│       └── iosMain/                 ← iOS-specific (future)
│           └── kotlin/com/nailtryon/ml/   ← CoreML wrappers
├── androidApp/                      ← 📱 Android app (Jetpack Compose)
│   ├── src/main/
│   │   ├── java/com/nailtryon/android/
│   │   │   ├── MainActivity.kt           ← Entry point + navigation
│   │   │   └── ui/
│   │   │       ├── NailBrowserScreen.kt  ← Browse designs gallery
│   │   │       └── NailTryOnScreen.kt    ← AR try-on camera
│   │   ├── assets/
│   │   │   ├── hand_landmarker.task      ← MediaPipe model (7.5MB)
│   │   │   └── nail_detect_model.tflite  ← TFLite model (3.4MB)
│   │   └── res/
│   └── build.gradle.kts
└── iosApp/                          ← 📱 iOS app (SwiftUI)
    ├── iosApp.xcodeproj/
    ├── iosApp/
    │   ├── NailTryOnApp.swift             ← Entry point
    │   ├── ContentView.swift              ← Navigation
    │   ├── NailBrowserView.swift          ← Browse designs
    │   ├── NailTryOnCameraView.swift      ← Camera + AR try-on
    │   ├── NailAPIClient.swift            ← URLSession API client
    │   └── Info.plist
    └── project.yml                  ← XcodeGen config
```

## 🚀 Build & Run

### Android
```bash
export ANDROID_HOME=~/Library/Android/sdk
cd Nail-Social-Mobile-KMP
./gradlew :androidApp:assembleDebug
# Hoặc mở trong Android Studio
```

### iOS
```bash
cd Nail-Social-Mobile-KMP/iosApp
xcodegen generate
open iosApp.xcodeproj
# Chọn simulator + Run (⌘R)
```

## 📦 Dependencies

| Layer | Công nghệ |
|-------|-----------|
| **Backend** | `https://nail.ai-kit.net` (NextJS + Firebase) |
| **Shared networking** | Ktor (multiplatform HTTP client) |
| **Shared serialization** | kotlinx.serialization |
| **Android ML** | TensorFlow Lite + MediaPipe Tasks Vision |
| **Android UI** | Jetpack Compose + CameraX |
| **iOS ML** | CoreML + Vision (future) |
| **iOS UI** | SwiftUI + AVFoundation |

## 🔄 Flow

```
Browse Designs ──tap──> Select Pattern ──> Camera Preview
(nail.ai-kit.net)                            │
                                             ├─ MediaPipe hand landmarks
                                             ├─ TFLite nail segmentation
                                             ├─ Connected Components (shared)
                                             └─ Texture Mapping (shared) → AR Overlay
```
