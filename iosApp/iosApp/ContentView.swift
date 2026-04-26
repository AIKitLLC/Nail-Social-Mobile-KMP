import SwiftUI

struct ContentView: View {
    @State private var selectedDesignId: String?
    @State private var showBrowser = true
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            if showBrowser {
                NailBrowserView { designId in
                    selectedDesignId = designId
                    showBrowser = false
                    showCamera = true
                }
            } else if showCamera, let designId = selectedDesignId {
                NailTryOnCameraView(designId: designId) {
                    showCamera = false
                    showBrowser = true
                }
            } else {
                NailTryOnCameraView(designId: nil) {
                    showCamera = false
                    showBrowser = true
                }
            }
        }
    }
}
