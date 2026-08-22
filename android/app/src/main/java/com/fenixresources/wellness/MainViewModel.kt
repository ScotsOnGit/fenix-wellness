package com.fenixresources.wellness

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fenixresources.wellness.data.AvailabilityRow
import com.fenixresources.wellness.data.Profile
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId

data class AppState(
    val isLoading: Boolean = true,
    val profile: Profile? = null,
    val selectedDate: LocalDate = LocalDate.now(ZoneId.of("Australia/Perth")),
    val durationMinutes: Int = 30,
    val allowedDurations: List<Int> = listOf(15, 30, 45),
    val slots: List<AvailabilityRow> = emptyList(),
    val passwordRecovery: Boolean = false,
    val message: String? = null
)

class MainViewModel(private val api: com.fenixresources.wellness.data.SupabaseApi) : ViewModel() {
    private val _state = MutableStateFlow(AppState())
    val state = _state.asStateFlow()

    init { restoreSession() }

    fun signIn(email: String, password: String) = viewModelScope.launch {
        loading {
            val profile = api.signIn(email.trim(), password)
            loadBookings(profile)
        }
    }

    fun register(name: String, email: String, password: String, phone: String) = viewModelScope.launch {
        loading {
            val profile = api.register(name.trim(), email.trim(), password, phone.trim())
            loadBookings(profile)
        }
    }

    fun sendRecovery(email: String) = viewModelScope.launch {
        loading { api.sendPasswordRecovery(email.trim()); _state.value = _state.value.copy(message = "Password-reset email sent.") }
    }

    fun handleDeepLink(uri: String?) {
        if (uri.isNullOrBlank()) return
        viewModelScope.launch {
            loading {
                val profile = api.importPasswordRecovery(uri)
                if (profile != null) _state.value = _state.value.copy(profile = profile, passwordRecovery = true, isLoading = false)
            }
        }
    }

    fun updatePassword(newPassword: String) = viewModelScope.launch {
        loading {
            api.updatePassword(newPassword)
            _state.value = _state.value.copy(passwordRecovery = false, message = "Password updated. You can now book a session.")
            _state.value.profile?.let { loadBookings(it) }
        }
    }

    fun selectDate(date: LocalDate) { _state.value = _state.value.copy(selectedDate = date); refreshAvailability() }
    fun selectDuration(minutes: Int) { _state.value = _state.value.copy(durationMinutes = minutes); refreshAvailability() }
    fun dismissMessage() { _state.value = _state.value.copy(message = null) }

    fun createBooking(startTime: String) = viewModelScope.launch {
        loading {
            api.createBooking(startTime, _state.value.durationMinutes)
            _state.value = _state.value.copy(message = "Booking confirmed.")
            refreshAvailability()
        }
    }

    fun signOut() { api.signOut(); _state.value = AppState(isLoading = false) }
    fun refreshAvailability() = viewModelScope.launch { loadAvailability() }

    private fun restoreSession() = viewModelScope.launch {
        loading {
            val profile = api.restoreProfile()
            if (profile == null) _state.value = AppState(isLoading = false)
            else loadBookings(profile)
        }
    }

    private suspend fun loadBookings(profile: Profile) {
        val rules = api.fetchRules()
        _state.value = _state.value.copy(profile = profile, allowedDurations = rules.allowedDurationsMinutes.sorted(), isLoading = false)
        loadAvailability()
    }

    private suspend fun loadAvailability() {
        val current = _state.value
        val slots = api.availability(current.selectedDate, current.durationMinutes)
        _state.value = _state.value.copy(slots = slots, isLoading = false)
    }

    private suspend fun loading(block: suspend () -> Unit) {
        _state.value = _state.value.copy(isLoading = true, message = null)
        runCatching { block() }.onFailure {
            _state.value = _state.value.copy(isLoading = false, message = it.message ?: "Something went wrong.")
        }
    }
}
