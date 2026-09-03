//
//  AdminBookingsView.swift
//  fenix
//
//  Created by Codex on 5/6/2026.
//

import SwiftUI

struct AdminBookingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var bookingToCancel: GymBooking?

    private var selectedDayBookings: [GymBooking] {
        appModel.adminBookings
    }

    private var activeCount: Int {
        selectedDayBookings.filter { $0.status == .active }.count
    }

    private var cancelledCount: Int {
        selectedDayBookings.filter { $0.status == .cancelled }.count
    }

    private var completedCount: Int {
        selectedDayBookings.filter { $0.status == .completed }.count
    }

    var body: some View {
        List {
            Section {
                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { appModel.selectedDate },
                        set: { appModel.selectDate($0) }
                    ),
                    displayedComponents: .date
                )
                .tint(FenixTheme.orange)
                .foregroundStyle(.white)
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Summary") {
                HStack(spacing: 10) {
                    AdminSummaryTile(title: "Active", value: "\(activeCount)", color: .green)
                    AdminSummaryTile(title: "Complete", value: "\(completedCount)", color: FenixTheme.darkSecondaryText)
                    AdminSummaryTile(title: "Cancelled", value: "\(cancelledCount)", color: FenixTheme.alertRed)
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Bookings") {
                if appModel.adminBookings.isEmpty {
                    ContentUnavailableView("No bookings", systemImage: "person.2.slash")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                        .listRowBackground(FenixTheme.darkCard)
                } else {
                    ForEach(appModel.adminBookings) { booking in
                        AdminBookingRow(booking: booking) {
                            bookingToCancel = booking
                        }
                            .listRowBackground(FenixTheme.darkCard)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(FenixTheme.loginBlue.ignoresSafeArea())
        .navigationTitle("Admin")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(FenixTheme.loginBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            await appModel.refreshBookings()
        }
        .task {
            await appModel.refreshBookings()
        }
        .alert("Cancel booking?", isPresented: Binding(
            get: { bookingToCancel != nil },
            set: { if !$0 { bookingToCancel = nil } }
        ), presenting: bookingToCancel) { booking in
            Button("Keep Booking", role: .cancel) {
                bookingToCancel = nil
            }
            Button("Cancel Booking", role: .destructive) {
                bookingToCancel = nil
                Task { await appModel.cancel(booking) }
            }
        } message: { booking in
            Text("\(booking.memberName)\n\(FacilityTime.dateText(booking.startTime))\n\(FacilityTime.intervalText(start: booking.startTime, end: booking.endTime))")
        }
    }
}

struct AdminSummaryTile: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AdminBookingRow: View {
    let booking: GymBooking
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(booking.memberName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(booking.status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(booking.status.tint)
            }

            Text(FacilityTime.intervalText(start: booking.startTime, end: booking.endTime))
                .foregroundStyle(FenixTheme.darkSecondaryText)

            HStack(spacing: 8) {
                Text("\(booking.durationMinutes) minutes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(FenixTheme.glowGold.opacity(0.20), in: Capsule())

                if booking.status == .active {
                    Button(role: .destructive, action: cancel) {
                        Label("Cancel", systemImage: "xmark.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AdminOperationsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AdminBookingRulesView()
                } label: {
                    AdminOperationsLinkRow(
                        title: "Booking Rules",
                        subtitle: "Capacity, booking window, daily limits, and cancellation cutoff.",
                        systemImage: "checklist.checked"
                    )
                }

                NavigationLink {
                    AdminOpeningHoursView()
                } label: {
                    AdminOperationsLinkRow(
                        title: "Opening Hours",
                        subtitle: "Set the selectable session times for each day.",
                        systemImage: "clock"
                    )
                }

                NavigationLink {
                    AdminWellnessContactView()
                } label: {
                    AdminOperationsLinkRow(
                        title: "Wellbeing Facility Information",
                        subtitle: "Contact details shown to staff in their profile.",
                        systemImage: "info.circle"
                    )
                }

                NavigationLink {
                    AdminAcknowledgementView()
                } label: {
                    AdminOperationsLinkRow(
                        title: "Acknowledgement",
                        subtitle: "Edit the wording staff must accept before using the facility.",
                        systemImage: "checkmark.seal"
                    )
                }

                NavigationLink {
                    AdminBlackoutPeriodsView()
                } label: {
                    AdminOperationsLinkRow(
                        title: "Blackout Periods",
                        subtitle: "Block availability for closures, maintenance, or events.",
                        systemImage: "calendar.badge.exclamationmark"
                    )
                }

                NavigationLink {
                    AdminResourcesView()
                } label: {
                    AdminOperationsLinkRow(
                        title: "Wellbeing Resources",
                        subtitle: "Publish shared links and PDFs for staff.",
                        systemImage: "doc.text"
                    )
                }

                NavigationLink {
                    AdminChallengesView()
                } label: {
                    AdminOperationsLinkRow(
                        title: "Wellbeing Challenges",
                        subtitle: "Create manual-entry challenges, metrics, rules, and leaderboards.",
                        systemImage: "figure.run"
                    )
                }
            } footer: {
                Text("Changes apply to member availability after the next refresh. Existing bookings remain visible for admin review.")
            }
            .listRowBackground(FenixTheme.darkCard)

        }
        .adminListStyle(title: "Operations")
    }
}

private struct AdminOperationsLinkRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(FenixTheme.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(FenixTheme.darkSecondaryText)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct AdminBookingRulesView: View {
    @Environment(AppModel.self) private var appModel
    @State private var editableRules = FacilityRules.fenixDefault

    private var rulesAreValid: Bool {
        editableRules.capacity > 0 &&
            editableRules.bookingHorizonDays > 0 &&
            editableRules.maxFutureBookings > 0 &&
            editableRules.maxActiveBookingsPerDay > 0 &&
            editableRules.cancellationCutoffMinutes >= 0
    }

    var body: some View {
        List {
            Section {
                Stepper("Capacity \(editableRules.capacity)", value: $editableRules.capacity, in: 1...100)
                Stepper("Booking window \(editableRules.bookingHorizonDays) days", value: $editableRules.bookingHorizonDays, in: 1...60)
                Stepper("Future bookings \(editableRules.maxFutureBookings)", value: $editableRules.maxFutureBookings, in: 1...30)
                Stepper("Daily bookings \(editableRules.maxActiveBookingsPerDay)", value: $editableRules.maxActiveBookingsPerDay, in: 1...10)
                Stepper("Cancel cutoff \(editableRules.cancellationCutoffMinutes)m", value: $editableRules.cancellationCutoffMinutes, in: 0...240, step: 15)
            } footer: {
                Text("Changes apply immediately to new member bookings. Existing bookings remain visible for admin review.")
            }
            .listRowBackground(FenixTheme.darkCard)

            if !rulesAreValid {
                Section {
                    Text("Booking rules must be greater than zero. Cancellation cutoff can be zero.")
                        .foregroundStyle(FenixTheme.amber)
                }
                .listRowBackground(FenixTheme.darkCard)
            }

            if let accountMessage = appModel.accountMessage(for: .bookingRules) {
                Section {
                    Text(accountMessage)
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                }
                .listRowBackground(FenixTheme.darkCard)
            }
        }
        .adminListStyle(title: "Booking Rules")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await appModel.updateRules(editableRules) }
                }
                .disabled(!rulesAreValid || appModel.loadState == .loading)
            }
        }
        .onAppear {
            editableRules = appModel.rules ?? .fenixDefault
        }
    }
}

private struct AdminOpeningHoursView: View {
    @Environment(AppModel.self) private var appModel
    @State private var editableHours: [OpeningHours] = []

    private var hoursAreValid: Bool {
        editableHours.allSatisfy { $0.isClosed || $0.opensAtMinutes < $0.closesAtMinutes }
    }

    private var affectedBookingsCount: Int {
        appModel.adminBookings.filter { booking in
            guard let hours = editableHours.first(where: { $0.weekday == FacilityTime.calendar.component(.weekday, from: booking.startTime) - 1 }) else {
                return false
            }
            if hours.isClosed { return true }
            let startMinutes = minutesAfterMidnight(booking.startTime)
            let endMinutes = minutesAfterMidnight(booking.endTime)
            return startMinutes < hours.opensAtMinutes || endMinutes > hours.closesAtMinutes
        }.count
    }

    var body: some View {
        List {
            Section {
                ForEach($editableHours) { $hours in
                    OpeningHoursEditorRow(hours: $hours)
                }
            } header: {
                Text("Opening Hours")
            } footer: {
                Text("Changes apply to member booking slots after the next refresh. Existing bookings remain in place for admin review.")
            }
            .listRowBackground(FenixTheme.darkCard)

            if let accountMessage = appModel.accountMessage(for: .openingHours) {
                Section {
                    Text(accountMessage)
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                }
                .listRowBackground(FenixTheme.darkCard)
            }

            if affectedBookingsCount > 0 {
                Section {
                    Label("\(affectedBookingsCount) existing booking\(affectedBookingsCount == 1 ? "" : "s") would sit outside these hours. Existing bookings remain in place for admin review.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(FenixTheme.amber)
                }
                .listRowBackground(FenixTheme.darkCard)
            }
        }
        .adminListStyle(title: "Opening Hours")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await appModel.updateOpeningHours(editableHours) }
                }
                .disabled(!hoursAreValid || appModel.loadState == .loading)
            }
        }
        .onAppear {
            editableHours = appModel.openingHours.isEmpty ? OpeningHours.fenixDefaultWeek : appModel.openingHours
            Task { await appModel.refreshBookings() }
        }
    }

    private func minutesAfterMidnight(_ date: Date) -> Int {
        let components = FacilityTime.calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

private struct AdminWellnessContactView: View {
    @Environment(AppModel.self) private var appModel
    @State private var contact = FacilityContact.fenixDefault

    var body: some View {
        List {
            Section {
                TextField("Display name", text: $contact.displayName)
                    .textContentType(.organizationName)
                TextField("Address", text: $contact.address, axis: .vertical)
                    .textContentType(.fullStreetAddress)
                TextField("Phone", text: $contact.phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                TextField("Email", text: $contact.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Notes", text: $contact.notes, axis: .vertical)
            }
            .listRowBackground(FenixTheme.darkCard)

            if let accountMessage = appModel.accountMessage(for: .contact) {
                Section {
                    Text(accountMessage)
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                }
                .listRowBackground(FenixTheme.darkCard)
            }
        }
        .adminListStyle(title: "Facility Info")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await appModel.updateFacilityContact(contact) }
                }
                .disabled(appModel.loadState == .loading)
            }
        }
        .onAppear {
            contact = appModel.facilityContact
        }
    }
}

private struct AdminAcknowledgementView: View {
    @Environment(AppModel.self) private var appModel
    @State private var title = ""
    @State private var acknowledgementBody = ""
    @State private var capacityText = ""
    @State private var fairUseText = ""
    @State private var medicalText = ""

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !acknowledgementBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !fairUseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !medicalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            appModel.loadState != .loading
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Current version", value: appModel.activeAcknowledgement.version)
                if let publishedAt = appModel.activeAcknowledgement.publishedAt {
                    LabeledContent("Published", value: FacilityTime.dateText(publishedAt))
                }
            } footer: {
                Text("Saving publishes a new version. Members will need to accept the updated acknowledgement next time they open the app.")
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Main Wording") {
                TextField("Title", text: $title)
                TextField("Intro wording", text: $acknowledgementBody, axis: .vertical)
                    .lineLimit(3...6)
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Acknowledgement Points") {
                TextField("Medical advice wording", text: $medicalText, axis: .vertical)
                    .lineLimit(2...5)
                TextField("Capacity wording", text: $capacityText, axis: .vertical)
                    .lineLimit(2...5)
                TextField("Fair use wording", text: $fairUseText, axis: .vertical)
                    .lineLimit(2...5)
            }
            .listRowBackground(FenixTheme.darkCard)

            Section {
                WellnessAcknowledgementContent(acknowledgementOverride: draftAcknowledgement)
                    .padding(.vertical, 8)
            } header: {
                Text("Draft Member Preview")
            }
            .listRowBackground(FenixTheme.darkCard)

            if let accountMessage = appModel.accountMessage(for: .acknowledgement) {
                Section {
                    Text(accountMessage)
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                }
                .listRowBackground(FenixTheme.darkCard)
            }
        }
        .adminListStyle(title: "Acknowledgement")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Publish") {
                    Task {
                        await appModel.publishAcknowledgement(
                            title: title,
                            body: acknowledgementBody,
                            capacityText: capacityText,
                            fairUseText: fairUseText,
                            medicalText: medicalText
                        )
                    }
                }
                .disabled(!canSave)
            }
        }
        .onAppear(perform: loadCurrentAcknowledgement)
        .onChange(of: appModel.activeAcknowledgement) { _, _ in
            loadCurrentAcknowledgement()
        }
    }

    private func loadCurrentAcknowledgement() {
        let acknowledgement = appModel.activeAcknowledgement
        title = acknowledgement.title
        acknowledgementBody = acknowledgement.body
        capacityText = acknowledgement.capacityText
        fairUseText = acknowledgement.fairUseText
        medicalText = acknowledgement.medicalText
    }

    private var draftAcknowledgement: WellnessAcknowledgement {
        WellnessAcknowledgement(
            id: appModel.activeAcknowledgement.id,
            version: appModel.activeAcknowledgement.version,
            title: title.isEmpty ? "Wellbeing Facility Acknowledgement" : title,
            body: acknowledgementBody,
            capacityText: capacityText,
            fairUseText: fairUseText,
            medicalText: medicalText,
            isActive: true,
            publishedAt: appModel.activeAcknowledgement.publishedAt,
            createdAt: appModel.activeAcknowledgement.createdAt,
            updatedAt: appModel.activeAcknowledgement.updatedAt
        )
    }
}

private struct AdminBlackoutPeriodsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var blackoutDate = Date()
    @State private var blackoutStart = Date()
    @State private var blackoutEnd = Date()
    @State private var blackoutReason = ""

    private var blackoutStartsAt: Date {
        date(from: blackoutDate, time: blackoutStart)
    }

    private var blackoutEndsAt: Date {
        date(from: blackoutDate, time: blackoutEnd)
    }

    private var blackoutIsValid: Bool {
        blackoutStartsAt < blackoutEndsAt && !blackoutReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var affectedBookingsCount: Int {
        appModel.adminBookings.filter { booking in
            booking.cancelledAt == nil && booking.startTime < blackoutEndsAt && booking.endTime > blackoutStartsAt
        }.count
    }

    var body: some View {
        List {
            Section {
                DatePicker("Date", selection: $blackoutDate, displayedComponents: .date)
                    .tint(FenixTheme.orange)
                DatePicker("Starts", selection: $blackoutStart, displayedComponents: .hourAndMinute)
                    .tint(FenixTheme.orange)
                DatePicker("Ends", selection: $blackoutEnd, displayedComponents: .hourAndMinute)
                    .tint(FenixTheme.orange)
                TextField("Reason", text: $blackoutReason)
                Button {
                    Task {
                        await appModel.createBlackoutPeriod(
                            startsAt: blackoutStartsAt,
                            endsAt: blackoutEndsAt,
                            reason: blackoutReason
                        )
                        if appModel.loadState == .idle {
                            blackoutReason = ""
                        }
                    }
                } label: {
                    Label("Add blackout period", systemImage: "plus.circle")
                }
                .disabled(!blackoutIsValid || appModel.loadState == .loading)
            } header: {
                Text("Add Blackout")
            } footer: {
                Text("Blackout periods block member booking availability for maintenance, closures, or special events.")
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Upcoming Blackouts") {
                if appModel.blackoutPeriods.isEmpty {
                    Text("No upcoming blackout periods.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                } else {
                    ForEach(appModel.blackoutPeriods) { blackout in
                        BlackoutPeriodRow(blackout: blackout)
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await appModel.deleteBlackoutPeriod(blackout) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            if blackoutIsValid && affectedBookingsCount > 0 {
                Section {
                    Label("\(affectedBookingsCount) existing booking\(affectedBookingsCount == 1 ? "" : "s") overlap this blackout. Existing bookings remain visible for admin review.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(FenixTheme.amber)
                }
                .listRowBackground(FenixTheme.darkCard)
            }

            if let accountMessage = appModel.accountMessage(for: .blackouts) {
                Section {
                    Text(accountMessage)
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                }
                .listRowBackground(FenixTheme.darkCard)
            }
        }
        .adminListStyle(title: "Blackouts")
        .refreshable { await appModel.refreshBlackoutPeriods() }
        .onAppear {
            let now = Date()
            blackoutDate = now
            blackoutStart = now
            blackoutEnd = FacilityTime.calendar.date(byAdding: .hour, value: 1, to: now) ?? now
            Task {
                await appModel.refreshBlackoutPeriods()
                await appModel.refreshBookings()
            }
        }
    }

    private func date(from date: Date, time: Date) -> Date {
        let dateComponents = FacilityTime.calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = FacilityTime.calendar.dateComponents([.hour, .minute], from: time)
        var combined = DateComponents()
        combined.timeZone = FacilityTime.timeZone
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        return FacilityTime.calendar.date(from: combined) ?? date
    }
}

private struct BlackoutPeriodRow: View {
    let blackout: BlackoutPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(blackout.reason)
                .font(.headline)
                .foregroundStyle(.white)
            Text(blackout.intervalText)
                .font(.footnote)
                .foregroundStyle(FenixTheme.darkSecondaryText)
        }
        .padding(.vertical, 4)
    }
}

private struct OpeningHoursEditorRow: View {
    @Binding var hours: OpeningHours

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { !hours.isClosed },
                set: { hours.isClosed = !$0 }
            )) {
                Text(hours.dayName)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .tint(FenixTheme.orange)

            if !hours.isClosed {
                DatePicker(
                    "Opens",
                    selection: timeBinding(\.opensAtMinutes),
                    displayedComponents: .hourAndMinute
                )
                .tint(FenixTheme.orange)

                DatePicker(
                    "Closes",
                    selection: timeBinding(\.closesAtMinutes),
                    displayedComponents: .hourAndMinute
                )
                .tint(FenixTheme.orange)
            } else {
                Text("Closed")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FenixTheme.darkSecondaryText)
            }
        }
        .padding(.vertical, 4)
    }

    private func timeBinding(_ keyPath: WritableKeyPath<OpeningHours, Int>) -> Binding<Date> {
        Binding {
            date(from: hours[keyPath: keyPath])
        } set: { date in
            let components = FacilityTime.calendar.dateComponents([.hour, .minute], from: date)
            hours[keyPath: keyPath] = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
    }

    private func date(from minutes: Int) -> Date {
        let day = FacilityTime.calendar.startOfDay(for: Date())
        return FacilityTime.calendar.date(byAdding: .minute, value: minutes, to: day) ?? day
    }
}

#Preview {
    NavigationStack {
        AdminBookingsView()
            .environment(AppModel(repository: MockGymBookingRepository()))
    }
}
