package com.nailtryon.data

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.logging.LogLevel
import io.ktor.client.plugins.logging.Logging
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

class NailApiService(
    private val baseUrl: String = "https://nail.ai-kit.net"
) {
    private val client = HttpClient {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                isLenient = true
            })
        }
        install(Logging) {
            level = LogLevel.BODY
        }
    }

    suspend fun getDesigns(
        page: Int = 1,
        limit: Int = 9,
        hashtag: String? = null
    ): DesignResponse {
        return client.get("$baseUrl/api/designs") {
            parameter("page", page)
            parameter("limit", limit)
            hashtag?.let { parameter("hashtag", it) }
        }.body()
    }

    suspend fun getDesignById(id: String): Design {
        return client.get("$baseUrl/api/designs/$id").body()
    }
}
