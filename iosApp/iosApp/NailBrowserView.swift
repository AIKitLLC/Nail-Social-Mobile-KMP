import SwiftUI

/// Browse nail designs from the API
struct NailBrowserView: View {
    let onDesignSelected: (String) -> Void

    @State private var designs: [DesignItem] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var currentPage = 1
    @State private var totalPages = 1

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && designs.isEmpty {
                Spacer()
                ProgressView("Loading designs...")
                Spacer()
            } else if let error = errorMessage, designs.isEmpty {
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
                        loadDesigns(page: 1)
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
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(designs) { design in
                            DesignCardView(design: design)
                                .onTapGesture {
                                    onDesignSelected(design.id)
                                }
                                .onAppear {
                                    if design.id == designs.last?.id {
                                        loadMore()
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                    if isLoadingMore {
                        ProgressView()
                            .padding()
                    }
                }
                .refreshable {
                    await refreshDesigns()
                }
            }
        }
        .task {
            if designs.isEmpty {
                loadDesigns(page: 1)
            }
        }
    }

    private func loadDesigns(page: Int) {
        if page == 1 {
            isLoading = true
        }
        errorMessage = nil

        Task {
            do {
                let response = try await NailAPIClient.shared.getDesigns(page: page)
                await MainActor.run {
                    let newItems = response.designs.map { DesignItem(from: $0) }
                    if page == 1 {
                        designs = newItems
                    } else {
                        designs.append(contentsOf: newItems)
                    }
                    currentPage = response.currentPage
                    totalPages = response.totalPages
                    isLoading = false
                    isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                    isLoadingMore = false
                }
            }
        }
    }

    private func loadMore() {
        guard !isLoadingMore, currentPage < totalPages else { return }
        isLoadingMore = true
        loadDesigns(page: currentPage + 1)
    }

    private func refreshDesigns() async {
        let response = try? await NailAPIClient.shared.getDesigns(page: 1)
        if let response {
            designs = response.designs.map { DesignItem(from: $0) }
            currentPage = response.currentPage
            totalPages = response.totalPages
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
        self.imageUrl = design.imageUrl
        self.hashtags = design.hashtags ?? []
    }
}

struct DesignCardView: View {
    let design: DesignItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 10)
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
                                    .font(.title2)
                                    .foregroundColor(.gray)
                            case .empty:
                                ProgressView()
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundColor(.pink)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(design.prompt)
                .font(.caption2)
                .lineLimit(2)
                .padding(.horizontal, 2)

            if !design.hashtags.isEmpty {
                Text(design.hashtags.prefix(2).map { "#\($0)" }.joined(separator: " "))
                    .font(.caption2)
                    .foregroundColor(.pink)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 2)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.08), radius: 3)
    }
}
