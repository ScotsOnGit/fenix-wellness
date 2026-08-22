package com.fenixresources.wellness.data

import android.content.Context
import com.fenixresources.wellness.BuildConfig
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.*
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.isSuccess
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.LocalDate
import java.net.URI
import java.net.URLDecoder

class SupabaseApi(context: Context, private val session: SessionStore) {
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }
    private val client = HttpClient(OkHttp) { install(ContentNegotiation) { json(json) } }
    private val baseUrl = BuildConfig.SUPABASE_URL.trimEnd('/')
    private val key = BuildConfig.SUPABASE_PUBLISHABLE_KEY

    suspend fun restoreProfile(): Profile? = session.accessToken?.let { fetchProfile() }

    suspend fun signIn(email: String, password: String): Profile {
        val response: AuthResponse = request("/auth/v1/token?grant_type=password", authenticated = false) {
            method = io.ktor.http.HttpMethod.Post
            setBody(buildJsonObject { put("email", email); put("password", password) })
        }
        store(response)
        return requireNotNull(fetchProfile())
    }

    suspend fun register(fullName: String, email: String, password: String, phone: String): Profile {
        val response: AuthResponse = request("/auth/v1/signup", authenticated = false) {
            method = io.ktor.http.HttpMethod.Post
            setBody(buildJsonObject {
                put("email", email); put("password", password)
                put("data", buildJsonObject { put("full_name", fullName); put("phone", phone) })
            })
        }
        check(response.accessToken != null) { "Account created. Confirm the email address, then sign in." }
        store(response)
        return requireNotNull(fetchProfile())
    }

    suspend fun sendPasswordRecovery(email: String) {
        request<Unit>("/auth/v1/recover", authenticated = false) {
            method = io.ktor.http.HttpMethod.Post
            setBody(buildJsonObject {
                put("email", email)
                put("redirect_to", "com.fenixresources.wellness://login-callback")
            })
        }
    }

    suspend fun importPasswordRecovery(uri: String): Profile? {
        val fragment = URI(uri).rawFragment.orEmpty()
        val values = fragment.split("&").mapNotNull {
            val (key, value) = it.split("=", limit = 2).let { parts -> parts.getOrNull(0) to parts.getOrNull(1) }
            if (key == null || value == null) null else key to URLDecoder.decode(value, "UTF-8")
        }.toMap()
        val accessToken = values["access_token"] ?: return null
        session.accessToken = accessToken
        session.refreshToken = values["refresh_token"]
        return fetchProfile()
    }

    suspend fun updatePassword(newPassword: String) {
        request<Unit>("/auth/v1/user") {
            method = io.ktor.http.HttpMethod.Put
            setBody(buildJsonObject { put("password", newPassword) })
        }
    }

    suspend fun fetchRules(): FacilityRules = request<List<FacilityRules>>("/rest/v1/facility_rules?select=allowed_durations_minutes,booking_horizon_days&id=eq.true") {
        method = io.ktor.http.HttpMethod.Get
    }.first()

    suspend fun availability(date: LocalDate, durationMinutes: Int): List<AvailabilityRow> = request("/rest/v1/rpc/get_availability_for_date") {
        method = io.ktor.http.HttpMethod.Post
        setBody(buildJsonObject { put("p_date", date.toString()); put("p_duration_minutes", durationMinutes) })
    }

    suspend fun createBooking(startTime: String, durationMinutes: Int): Booking = request("/rest/v1/rpc/create_booking") {
        method = io.ktor.http.HttpMethod.Post
        setBody(buildJsonObject { put("p_start_time", startTime); put("p_duration_minutes", durationMinutes) })
    }

    fun signOut() = session.clear()

    private suspend fun fetchProfile(): Profile? {
        val token = session.accessToken ?: return null
        val userId = token.split(".").getOrNull(1)?.let { part ->
            runCatching { String(java.util.Base64.getUrlDecoder().decode(part + "=".repeat((4 - part.length % 4) % 4))) }
                .getOrNull()?.let { Regex("\\\"sub\\\":\\\"([^\\\"]+)\\\"").find(it)?.groupValues?.get(1) }
        } ?: return null
        return request<List<Profile>>("/rest/v1/profiles?select=*&id=eq.$userId").firstOrNull()
    }

    private fun store(response: AuthResponse) {
        session.accessToken = requireNotNull(response.accessToken)
        session.refreshToken = response.refreshToken
    }

    private suspend inline fun <reified T> request(path: String, authenticated: Boolean = true, block: HttpRequestBuilder.() -> Unit = {}): T {
        check(baseUrl.startsWith("https://") && key.isNotBlank()) {
            "Configure android/local.properties from local.properties.example."
        }
        val response = client.request("$baseUrl$path") {
            header("apikey", key)
            accept(ContentType.Application.Json)
            header(HttpHeaders.ContentType, ContentType.Application.Json.toString())
            if (authenticated) session.accessToken?.let { header(HttpHeaders.Authorization, "Bearer $it") }
            block()
        }
        if (!response.status.isSuccess()) throw IllegalStateException(response.bodyAsText())
        return response.body()
    }
}
