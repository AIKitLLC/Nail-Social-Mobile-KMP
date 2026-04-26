package com.nailtryon.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class DesignResponse(
    @SerialName("designs") val designs: List<Design>,
    @SerialName("totalPages") val totalPages: Int,
    @SerialName("currentPage") val currentPage: Int
)

@Serializable
data class Design(
    @SerialName("id") val id: String,
    @SerialName("userId") val userId: String,
    @SerialName("designPrompt") val designPrompt: String,
    @SerialName("negativePrompt") val negativePrompt: String? = null,
    @SerialName("imageDataUri") val imageDataUri: String,
    @SerialName("extractedNailDataUri") val extractedNailDataUri: String,
    @SerialName("isPublic") val isPublic: Boolean,
    @SerialName("createdAt") val createdAt: String,
    @SerialName("hashtags") val hashtags: List<String>? = null,
    @SerialName("catId") val catId: Int? = null
)
