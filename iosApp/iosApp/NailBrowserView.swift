import SwiftUI
import shared

/// Browse nail designs from the API
struct NailBrowserView: View {
    let onDesignSelected: (String) -> Void

    @State private var designs: [DesignItem] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var searchText: String = ""
    @State private var activeHashtag: String? = nil

    /// Filter chips sourced from the KMP shared catalog so iOS + Android
    /// always show the same set of high-level filters.
    private let hashtags: [String] = NailCatalog.shared.popularHashtags as? [String] ?? []

    @Environment(\.horizontalSizeClass) private var hsc

    private var columns: [GridItem] {
        // Using `.flexible(minimum:)` keeps each column hard-clamped to the
        // proposed width. Plain `.flexible()` was leaving the iPad's first
        // column slightly under-proposed, which collapsed Text intrinsic
        // width inside the cell and caused leading characters to clip.
        Array(
            repeating: GridItem(.flexible(minimum: 100), spacing: DS.Space.md),
            count: SharedLayout.designsColumns(regular: hsc == .regular)
        )
    }

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            searchBar
            hashtagFilterStrip

            if isLoading && designs.isEmpty {
                loadingSkeleton
            } else if let error = errorMessage, designs.isEmpty {
                errorState(error)
            } else if filteredDesigns.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.md) {
                        ForEach(filteredDesigns) { design in
                            DesignCardView(design: design)
                                .onTapGesture {
                                    Haptics.light()
                                    onDesignSelected(design.id)
                                }
                                .onAppear {
                                    if design.id == designs.last?.id {
                                        loadMore()
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.top, DS.Space.sm)

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

    // MARK: - Search + filters

    private var filteredDesigns: [DesignItem] {
        designs.filter { d in
            let matchesText = searchText.isEmpty
                || d.prompt.lowercased().contains(searchText.lowercased())
                || d.hashtags.contains(where: { $0.lowercased().contains(searchText.lowercased()) })
            let matchesTag: Bool
            if let tag = activeHashtag {
                matchesTag = d.hashtags.contains(where: { $0.lowercased() == tag.lowercased() })
            } else {
                matchesTag = true
            }
            return matchesText && matchesTag
        }
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("Search prompts or hashtags", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    Haptics.selection()
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(.primary.opacity(0.05), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, DS.Space.lg)
    }

    @ViewBuilder
    private var hashtagFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.sm) {
                FilterChip(label: "All", isSelected: activeHashtag == nil) {
                    Haptics.selection()
                    withAnimation(.snappySpring) { activeHashtag = nil }
                }
                ForEach(hashtags, id: \.self) { tag in
                    FilterChip(label: "#\(tag)", isSelected: activeHashtag == tag) {
                        Haptics.selection()
                        withAnimation(.snappySpring) {
                            activeHashtag = (activeHashtag == tag) ? nil : tag
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Space.lg)
        }
        .frame(height: 36)
        // Fade chips into the page edges so users get a visual hint that
        // the strip scrolls horizontally.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.04),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    // MARK: - States

    @ViewBuilder
    private var loadingSkeleton: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.md) {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonCard()
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, DS.Space.sm)
        }
        .disabled(true)
    }

    @ViewBuilder
    private func errorState(_ error: String) -> some View {
        VStack(spacing: DS.Space.lg) {
            Spacer()
            ZStack {
                Circle()
                    .fill(DS.Brand.pinkPrimary.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(DS.Brand.pinkPrimary)
            }
            VStack(spacing: 6) {
                Text("Couldn't load designs")
                    .font(.title3.weight(.semibold))
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button(action: {
                Haptics.light()
                loadDesigns(page: 1)
            }) {
                Text("Try again")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(DS.Brand.primaryGradient))
                    .shadow(color: DS.Brand.pinkPrimary.opacity(0.4), radius: 10, y: 4)
            }
            .buttonStyle(BounceButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: DS.Space.md) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(DS.Brand.pinkPrimary.opacity(0.7))
            Text("No designs yet")
                .font(.title3.weight(.semibold))
            Text("Pull down to refresh.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemGray5), Color(.systemGray6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if let url = design.imageUrl, let imageUrl = URL(string: url) {
                    AsyncImage(url: imageUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            placeholderIcon("photo.badge.exclamationmark")
                        case .empty:
                            ProgressView().tint(DS.Brand.pinkPrimary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    placeholderIcon("sparkles")
                }
            }
            .aspectRatio(0.78, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(design.prompt)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !design.hashtags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(design.hashtags.prefix(2).enumerated()), id: \.offset) { _, tag in
                            Text("#\(tag)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(DS.Brand.pinkPrimary.opacity(0.12))
                                .foregroundStyle(DS.Brand.pinkPrimary)
                                .clipShape(Capsule())
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.bottom, DS.Space.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .cardShadow()
    }

    private func placeholderIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 32, weight: .light))
            .foregroundStyle(DS.Brand.pinkPrimary.opacity(0.7))
    }
}
