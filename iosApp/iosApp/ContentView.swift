import SwiftUI

struct ContentView: View {
    @State private var selectedDesignId: String?
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            if showCamera {
                NailTryOnCameraView(designId: selectedDesignId) {
                    showCamera = false
                    selectedDesignId = nil
                }
                .navigationBarHidden(true)
            } else {
                NailBrowserView { designId in
                    selectedDesignId = designId
                    showCamera = true
                }
                .navigationTitle("Nail Try-On")
            }
        }
    }
}
