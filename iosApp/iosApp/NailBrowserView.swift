import SwiftUI

/// Browse nail designs from the API
struct NailBrowserView: View {
    let onDesignSelected: (String) -> Void

    @State private var designs: [DesignItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            Text("Nail Designs")
                .font(.largeTitle)
                .padding(.top)

            if isLoading {
                Spacer()
                ProgressView("Loading designs...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("Failed to load")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        loadDesigns()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            } else if designs.isEmpty {
                Spacer()
                Text("No designs available")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(designs) { design in
                            DesignCardView(design: design)
                                .onTapGesture {
                                    onDesignSelected(design.id)
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear(perform: loadDesigns)
    }

    private func loadDesigns() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let response = try await NailAPIClient.shared.getDesigns()
                await MainActor.run {
                    designs = response.designs.map { DesignItem(from: $0) }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct DesignItem: Identifiable {
    let id: String
    let prompt: String
    let imageUrl: String?
    let hashtags: [String]

    init(from design: NailDesignDTO) {
        self.id = design.id
        self.prompt = design.designPrompt
        // Use image URL or convert base64
        if design.imageDataUri.hasPrefix("data:") {
            self.imageUrl = nil // base64 is handled separately
        } else {
            self.imageUrl = design.imageDataUri
        }
        self.hashtags = design.hashtags ?? []
    }
}

struct DesignCardView: View {
    let design: DesignItem

    var body: some View {
        VStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let url = design.imageUrl, let imageUrl = URL(string: url) {
                        AsyncImage(url: imageUrl) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                            case .empty:
                                ProgressView()
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "sparkles")
                            .font(.largeTitle)
                            .foregroundColor(.pink)
                    }
                }
                .clipped()

            Text(design.prompt)
                .font(.caption)
                .lineLimit(2)
                .padding(.horizontal, 4)

            if !design.hashtags.isEmpty {
                Text(design.hashtags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                    .font(.caption2)
                    .foregroundColor(.pink)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4)
    }
}
