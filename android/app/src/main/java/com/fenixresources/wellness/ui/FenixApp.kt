package com.fenixresources.wellness.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fenixresources.wellness.MainViewModel
import com.fenixresources.wellness.data.AvailabilityRow
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter

@Composable
fun FenixApp(viewModel: MainViewModel) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var register by rememberSaveable { mutableStateOf(false) }
    Scaffold(containerColor = MaterialTheme.colorScheme.background) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            if (state.passwordRecovery) PasswordRecoveryScreen(viewModel)
            else if (state.profile == null) AuthScreen(register, { register = it }, viewModel)
            else BookingScreen(viewModel)
            if (state.isLoading) CircularProgressIndicator(Modifier.align(Alignment.Center))
        }
    }
    state.message?.let { message ->
        AlertDialog(onDismissRequest = viewModel::dismissMessage, confirmButton = { TextButton(viewModel::dismissMessage) { Text("OK") } }, title = { Text("Fenix Wellness Centre") }, text = { Text(message) })
    }
}

@Composable
private fun PasswordRecoveryScreen(viewModel: MainViewModel) {
    var password by rememberSaveable { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center) {
        Text("Choose a new password", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(password, { password = it }, label = { Text("New password") }, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(16.dp))
        Button({ viewModel.updatePassword(password) }, enabled = password.length >= 8, modifier = Modifier.fillMaxWidth()) { Text("Update password") }
    }
}

@Composable
private fun AuthScreen(register: Boolean, setRegister: (Boolean) -> Unit, viewModel: MainViewModel) {
    var name by rememberSaveable { mutableStateOf("") }; var phone by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }; var password by rememberSaveable { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center) {
        Text("Fenix Wellness Centre", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(20.dp))
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            SegmentedButton(!register, { setRegister(false) }, SegmentedButtonDefaults.itemShape(0, 2)) { Text("Sign in") }
            SegmentedButton(register, { setRegister(true) }, SegmentedButtonDefaults.itemShape(1, 2)) { Text("Register") }
        }
        if (register) {
            OutlinedTextField(name, { name = it }, label = { Text("Full name") }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(phone, { phone = it }, label = { Text("Phone (optional)") }, modifier = Modifier.fillMaxWidth())
        }
        OutlinedTextField(email, { email = it }, label = { Text("Work email") }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(password, { password = it }, label = { Text("Password") }, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(16.dp))
        Button(
            onClick = { if (register) viewModel.register(name, email, password, phone) else viewModel.signIn(email, password) },
            enabled = email.isNotBlank() && password.isNotBlank() && (!register || name.isNotBlank()),
            modifier = Modifier.fillMaxWidth()
        ) { Text(if (register) "Create account" else "Sign in") }
        TextButton({ viewModel.sendRecovery(email) }, enabled = email.isNotBlank(), modifier = Modifier.align(Alignment.CenterHorizontally)) { Text("Forgot password?") }
    }
}

@Composable
private fun BookingScreen(viewModel: MainViewModel) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var datePickerOpen by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) { Text("Book a session", style = MaterialTheme.typography.headlineMedium); Text(state.profile?.fullName.orEmpty()) }
            TextButton(viewModel::signOut) { Text("Sign out") }
        }
        if (state.profile?.canBook == false) Text("Booking unlocks after admin induction approval.", color = MaterialTheme.colorScheme.secondary)
        Spacer(Modifier.height(12.dp))
        OutlinedButton({ datePickerOpen = true }) { Text(state.selectedDate.format(DateTimeFormatter.ofPattern("EEE, d MMM"))) }
        if (datePickerOpen) FenixDatePickerDialog(state.selectedDate, { date -> viewModel.selectDate(date); datePickerOpen = false }, { datePickerOpen = false })
        Spacer(Modifier.height(12.dp))
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            state.allowedDurations.forEachIndexed { index, minutes ->
                SegmentedButton(state.durationMinutes == minutes, { viewModel.selectDuration(minutes) }, SegmentedButtonDefaults.itemShape(index, state.allowedDurations.size)) { Text("${minutes}m") }
            }
        }
        Spacer(Modifier.height(20.dp)); Text("Start times", style = MaterialTheme.typography.titleLarge)
        LazyVerticalGrid(GridCells.Adaptive(110.dp), verticalArrangement = Arrangement.spacedBy(10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(top = 12.dp)) {
            items(state.slots) { slot -> Slot(slot, state.profile?.canBook == true) { viewModel.createBooking(slot.startTime) } }
        }
    }
}

@Composable private fun Slot(slot: AvailabilityRow, canBook: Boolean, book: () -> Unit) {
    val time = runCatching { OffsetDateTime.parse(slot.startTime).format(DateTimeFormatter.ofPattern("h:mm a")) }.getOrDefault(slot.startTime)
    OutlinedButton(onClick = book, enabled = !slot.isFull && canBook, modifier = Modifier.fillMaxWidth()) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) { Text(time); Text(if (slot.isFull) "Full" else "${slot.remaining} places", style = MaterialTheme.typography.labelSmall) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun FenixDatePickerDialog(selected: LocalDate, onSelect: (LocalDate) -> Unit, onDismiss: () -> Unit) {
    val picker = rememberDatePickerState(initialSelectedDateMillis = selected.toEpochDay() * 86_400_000)
    androidx.compose.material3.DatePickerDialog(onDismissRequest = onDismiss, confirmButton = { TextButton({ picker.selectedDateMillis?.let { onSelect(LocalDate.ofEpochDay(it / 86_400_000)) } }) { Text("Select") } }, dismissButton = { TextButton(onDismiss) { Text("Cancel") } }) { DatePicker(picker) }
}
