import Foundation
import shared

// MARK: - Swift-friendly DTOs (mirror the Kotlin shared models)

struct NailDesignResponseDTO {
    let designs: [NailDesignDTO]
    let totalPages: Int
    let currentPage: Int

    init(_ k: DesignResponse) {
        self.designs = k.designs.map { NailDesignDTO($0) }
        self.totalPages = Int(k.totalPages)
        self.currentPage = Int(k.currentPage)
    }
}

struct NailDesignDTO: Identifiable {
    let id: String
    let userId: String
    let designPrompt: String
    let negativePrompt: String?
    let imageUrl: String
    let extractedNailImageUrl: String?
    let isPublic: Bool
    let createdAt: String
    let hashtags: [String]?
    let slug: String?

    init(_ k: Design) {
        self.id = k.id
        self.userId = k.userId
        self.designPrompt = k.designPrompt
        self.negativePrompt = k.negativePrompt
        self.imageUrl = k.imageUrl
        self.extractedNailImageUrl = k.extractedNailImageUrl
        self.isPublic = k.isPublic
        self.createdAt = k.createdAt
        self.hashtags = k.hashtags
        self.slug = k.slug
    }
}

// MARK: - API Client — thin Swift adapter over shared.NailApiService

actor NailAPIClient {
    static let shared = NailAPIClient()
    private let service = NailApiService(baseUrl: "https://nail.ai-kit.net")

    func getDesigns(page: Int = 1, limit: Int = 9, hashtag: String? = nil) async throws -> NailDesignResponseDTO {
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<NailDesignResponseDTO, Error>) in
            service.getDesigns(page: Int32(page), limit: Int32(limit), hashtag: hashtag) { response, error in
                if let response = response {
                    cont.resume(returning: NailDesignResponseDTO(response))
                } else {
                    cont.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
        }
    }

    func getDesignById(_ id: String) async throws -> NailDesignDTO {
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<NailDesignDTO, Error>) in
            service.getDesignById(id: id) { design, error in
                if let design = design {
                    cont.resume(returning: NailDesignDTO(design))
                } else {
                    cont.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
        }
    }
}
