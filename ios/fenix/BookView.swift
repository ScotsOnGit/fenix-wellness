//
//  BookView.swift
//  fenix
//
//  Created by Codex on 5/6/2026.
//

import SwiftUI

struct BookView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showsConfirmation = false

    private var durations: [Int] {
        appModel.rules?.allowedDurationsMinutes.sorted() ?? FacilityRules.fenixDefault.allowedDurationsMinutes
    }
    private let columns = [
        GridItem(.adaptive(minimum: 96), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    dailyBookingNotice
                    availabilityGrid
                    messageView
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
        }
        .background(FenixTheme.loginBlue.ignoresSafeArea())
        .navigationTitle("Book")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(FenixTheme.loginBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            Button {
                Task { await appModel.refreshAll() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .safeAreaInset(edge: .bottom) {
            confirmBar
        }
        .sheet(isPresented: $showsConfirmation) {
            BookingConfirmationView()
                .presentationDetents([.medium])
                .preferredColorScheme(.dark)
        }
        .task {
            await appModel.refreshBookings()
            await appModel.refreshAvailability()
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            DatePicker(
                "Date",
                selection: Binding(
                    get: { appModel.selectedDate },
                    set: { appModel.selectDate($0) }
                ),
                in: appModel.dateRange,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .foregroundStyle(.white)
            .tint(FenixTheme.orange)

            Picker(
                "Duration",
                selection: Binding(
                    get: { appModel.selectedDuration },
                    set: { appModel.selectDuration($0) }
                )
            ) {
                ForEach(durations, id: \.self) { minutes in
                    Text("\(minutes)m").tag(minutes)
                }
            }
            .pickerStyle(.segmented)
            .tint(FenixTheme.orange)

            Text("Availability updates based on the session length selected.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FenixTheme.darkSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let profile = appModel.profile, !profile.canBookWellnessSessions {
                Label("Booking unlocks after admin induction approval.", systemImage: "lock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FenixTheme.amber)
            }
        }
        .padding()
        .background(FenixTheme.darkCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(FenixTheme.darkBorder, lineWidth: 1)
        }
    }

    private var availabilityGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Start times")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
            }

            statusLegend

            if appModel.loadState == .loading && appModel.availability.isEmpty {
                InlineAvailabilityLoadingView()
            } else if case let .failed(message) = appModel.loadState, appModel.availability.isEmpty {
                AvailabilityUnavailableView(message: message) {
                    Task { await appModel.refreshAll() }
                }
            } else if appModel.availability.isEmpty, let emptyState = appModel.selectedDateAvailabilityMessage {
                AvailabilityEmptyView(
                    title: emptyState.title,
                    message: emptyState.message,
                    systemImage: emptyState.systemImage
                )
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(appModel.availability) { slot in
                        let userBooking = bookingCovering(slot)
                        SlotButton(
                            slot: slot,
                            selectedDuration: appModel.selectedDuration,
                            isSelected: appModel.selectedSlot?.id == slot.id,
                            userBooking: userBooking,
                            isBlockedForDay: appModel.usedBookingForSelectedDate != nil
                        ) {
                            guard slot.status != .full, userBooking == nil, appModel.usedBookingForSelectedDate == nil, appModel.profile?.canBookWellnessSessions == true else { return }
                            appModel.selectedSlot = slot
                        }
                    }
                }
            }
        }
        .padding()
        .background(FenixTheme.darkCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(FenixTheme.darkBorder, lineWidth: 1)
        }
    }

    private func bookingCovering(_ slot: AvailabilitySlot) -> GymBooking? {
        appModel.bookings.first { booking in
            booking.status == .active &&
            booking.cancelledAt == nil &&
            booking.startTime <= slot.startTime &&
            booking.endTime > slot.startTime
        }
    }

    private var statusLegend: some View {
        HStack(spacing: 10) {
            LegendItem(label: "Available", color: .green)
            LegendItem(label: "Nearly full", color: .orange)
            LegendItem(label: "Full", color: .red)
            LegendItem(label: "Your booking", color: FenixTheme.glowGold)
        }
        .accessibilityLabel("Availability status legend")
    }

    private var messageView: some View {
        Group {
            if let bookingMessage = appModel.bookingMessage {
                Label(bookingMessage, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FenixTheme.orange.opacity(0.20), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var dailyBookingNotice: some View {
        Group {
            if let booking = appModel.usedBookingForSelectedDate {
                Label {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(booking.status == .completed ? "Session already completed" : "Booking already made")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Text(appModel.bookingUnavailableReason ?? "")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(FenixTheme.darkSecondaryText)
                    }
                } icon: {
                    Image(systemName: booking.status == .completed ? "checkmark.seal.fill" : "calendar.badge.checkmark")
                        .foregroundStyle(FenixTheme.glowGold)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(FenixTheme.glowGold.opacity(0.42), lineWidth: 1)
                }
            }
        }
    }

    private var confirmBar: some View {
        VStack(spacing: 10) {
            if let reason = appModel.bookingUnavailableReason, appModel.usedBookingForSelectedDate != nil {
                Text(reason)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            Button {
                showsConfirmation = true
            } label: {
                Label(appModel.usedBookingForSelectedDate == nil ? "Review booking" : "Booking unavailable", systemImage: appModel.usedBookingForSelectedDate == nil ? "checkmark.circle" : "lock.circle")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(FenixTheme.orange)
            .disabled(!appModel.canReviewSelectedBooking)
        }
        .padding()
        .background(FenixTheme.loginBlue.opacity(0.96))
    }
}

private struct InlineAvailabilityLoadingView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(FenixTheme.glowGold)
            Text("Checking start times")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FenixTheme.darkSecondaryText)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AvailabilityUnavailableView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Cannot confirm availability", systemImage: "wifi.exclamationmark")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(.footnote)
                .foregroundStyle(FenixTheme.darkSecondaryText)

            Button(action: retry) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(FenixTheme.orange)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(FenixTheme.darkBorder, lineWidth: 1)
        }
    }
}

private struct LegendItem: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(FenixTheme.darkSecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

struct SlotButton: View {
    let slot: AvailabilitySlot
    let selectedDuration: Int
    let isSelected: Bool
    let userBooking: GymBooking?
    let isBlockedForDay: Bool
    let action: () -> Void

    private var isBookedByUser: Bool {
        userBooking != nil
    }

    private var isBookingStart: Bool {
        guard let userBooking else { return false }
        return userBooking.startTime == slot.startTime
    }

    private var isInsideBooking: Bool {
        guard let userBooking else { return false }
        return userBooking.startTime < slot.startTime && userBooking.endTime > slot.startTime
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(FacilityTime.timeText(slot.startTime))
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(isBookedByUser ? .white : isSelected ? .white.opacity(0.9) : FenixTheme.darkSecondaryText)
                Capsule()
                    .fill(isBookedByUser ? FenixTheme.glowGold : slot.status.tint)
                    .frame(width: 44, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderStyle, lineWidth: isBookedByUser || isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(slot.status == .full || isBookedByUser || isBlockedForDay)
        .opacity((slot.status == .full && !isBookedByUser) || (isBlockedForDay && !isBookedByUser) ? 0.56 : 1)
        .accessibilityLabel(accessibilityText)
    }

    private var detailText: String {
        guard let userBooking else {
            return "\(slot.remaining) for \(selectedDuration)m"
        }

        if isBookingStart {
            return "\(userBooking.durationMinutes)m booked"
        }
        if isInsideBooking {
            return "Booked"
        }
        return "\(slot.remaining) for \(selectedDuration)m"
    }

    private var backgroundStyle: Color {
        if isBookedByUser {
            return FenixTheme.glowGold.opacity(0.22)
        }
        if isSelected {
            return FenixTheme.darkCardPressed
        }
        return Color.white.opacity(0.055)
    }

    private var borderStyle: Color {
        if isBookedByUser {
            return FenixTheme.glowGold.opacity(0.95)
        }
        if slot.status == .full {
            return FenixTheme.alertRed.opacity(0.55)
        }
        if isSelected {
            return FenixTheme.orange.opacity(0.85)
        }
        return FenixTheme.darkBorder
    }

    private var accessibilityText: String {
        if let userBooking {
            if isBookingStart {
                return "\(FacilityTime.timeText(slot.startTime)), your \(userBooking.durationMinutes) minute booking starts here"
            }
            if isInsideBooking {
                return "\(FacilityTime.timeText(slot.startTime)), covered by your \(userBooking.durationMinutes) minute booking"
            }
        }
        return "\(FacilityTime.timeText(slot.startTime)), \(slot.status.label), \(slot.remaining) places available for a \(selectedDuration) minute session"
    }
}

struct BookingConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    private var cancellationCutoffMinutes: Int {
        appModel.rules?.cancellationCutoffMinutes ?? FacilityRules.fenixDefault.cancellationCutoffMinutes
    }

    private var reminderMinutes: Int {
        60
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if let slot = appModel.selectedSlot,
                   let end = FacilityTime.calendar.date(byAdding: .minute, value: appModel.selectedDuration, to: slot.startTime) {
                    LabeledContent("Date", value: FacilityTime.dateText(slot.startTime))
                    LabeledContent("Time", value: FacilityTime.intervalText(start: slot.startTime, end: end))
                    LabeledContent("Duration", value: "\(appModel.selectedDuration) minutes")
                    LabeledContent("Remaining", value: "\(slot.remaining) places available for this session")
                }

                VStack(alignment: .leading, spacing: 10) {
                    ConfirmationRuleRow(
                        systemImage: "person.crop.circle.badge.checkmark",
                        text: "One session per staff member, per day."
                    )
                    ConfirmationRuleRow(
                        systemImage: "clock.badge.checkmark",
                        text: "Bookings can be cancelled until \(cancellationCutoffMinutes) minutes before the session starts."
                    )
                    ConfirmationRuleRow(
                        systemImage: "bell",
                        text: "A reminder will be scheduled \(reminderMinutes) minutes before your session if notifications are allowed."
                    )
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))

                Spacer()
            }
            .padding()
            .background(FenixTheme.loginBlue)
            .foregroundStyle(.white)
            .navigationTitle("Confirm")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(FenixTheme.loginBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Book") {
                        Task {
                            guard appModel.canReviewSelectedBooking else { return }
                            dismiss()
                            await appModel.createSelectedBooking()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!appModel.canReviewSelectedBooking)
                }
            }
        }
    }
}

private struct ConfirmationRuleRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FenixTheme.darkSecondaryText)
                .frame(width: 22)

            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FenixTheme.darkSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AvailabilityEmptyView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(.footnote)
                .foregroundStyle(FenixTheme.darkSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(FenixTheme.darkBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        BookView()
            .environment(AppModel(repository: MockGymBookingRepository()))
    }
}
