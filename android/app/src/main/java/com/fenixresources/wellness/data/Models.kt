package com.fenixresources.wellness.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Profile(
    val id: String,
    @SerialName("full_name") val fullName: String = "",
    val email: String = "",
    val phone: String = "",
    val role: String = "member",
    @SerialName("access_status") val accessStatus: String = "pending",
    @SerialName("induction_completed_at") val inductionCompletedAt: String? = null
) {
    val canBook: Boolean get() = role == "admin" || (accessStatus == "active" && inductionCompletedAt != null)
}

@Serializable
data class AuthResponse(
    @SerialName("access_token") val accessToken: String? = null,
    @SerialName("refresh_token") val refreshToken: String? = null,
    val user: AuthUser? = null
)

@Serializable data class AuthUser(val id: String)

@Serializable
data class FacilityRules(
    @SerialName("allowed_durations_minutes") val allowedDurationsMinutes: List<Int> = listOf(15, 30, 45),
    @SerialName("booking_horizon_days") val bookingHorizonDays: Int = 7
)

@Serializable
data class AvailabilityRow(
    @SerialName("start_time") val startTime: String,
    @SerialName("occupied_count") val occupiedCount: Int,
    @SerialName("remaining_capacity") val remainingCapacity: Int
) {
    val capacity get() = occupiedCount + remainingCapacity
    val remaining get() = remainingCapacity.coerceAtLeast(0)
    val isFull get() = remaining == 0
}

@Serializable
data class Booking(
    val id: String,
    @SerialName("start_time") val startTime: String,
    @SerialName("end_time") val endTime: String
)
