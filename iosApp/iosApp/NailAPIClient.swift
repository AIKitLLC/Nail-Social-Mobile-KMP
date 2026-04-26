import Foundation

// MARK: - DTOs matching the shared KMP module

struct NailDesignResponseDTO: Codable {
    let designs: [NailDesignDTO]
    let totalPages: Int
    let currentPage: Int
}

struct NailDesignDTO: Codable, Identifiable {
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
}

// MARK: - API Client

actor NailAPIClient {
    static let shared = NailAPIClient()
    private let baseURL = "https://nail.ai-kit.net"
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    func getDesigns(page: Int = 1, limit: Int = 9, hashtag: String? = nil) async throws -> NailDesignResponseDTO {
        var components = URLComponents(string: "\(baseURL)/api/designs")!
        components.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let hashtag = hashtag {
            components.queryItems?.append(URLQueryItem(name: "hashtag", value: hashtag))
        }

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(NailDesignResponseDTO.self, from: data)
    }

    func getDesignById(_ id: String) async throws -> NailDesignDTO {
        let url = URL(string: "\(baseURL)/api/designs/\(id)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(NailDesignDTO.self, from: data)
    }
}
