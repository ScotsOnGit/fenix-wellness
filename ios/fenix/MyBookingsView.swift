//
//  MyBookingsView.swift
//  fenix
//
//  Created by Codex on 5/6/2026.
//

import SwiftUI

struct MyBookingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var bookingToCancel: GymBooking?

    private var upcoming: [GymBooking] {
        appModel.bookings.filter { $0.status == .active }.sorted { $0.startTime < $1.startTime }
    }

    private var history: [GymBooking] {
        appModel.bookings.filter { $0.status != .active }.sorted { $0.startTime > $1.startTime }
    }

    var body: some View {
        List {
            Section {
                if let nextBooking = upcoming.first {
                    BookingRow(
                        booking: nextBooking,
                        canCancel: canCancel(nextBooking)
                    ) {
                        bookingToCancel = nextBooking
                    }
                        .listRowBackground(FenixTheme.darkCard)
                        .swipeActions {
                            Button(role: .destructive) {
                                bookingToCancel = nextBooking
                            } label: {
                                Label("Cancel", systemImage: "xmark.circle")
                            }
                        }
                } else {
                    ContentUnavailableView("No upcoming bookings", systemImage: "calendar")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                        .listRowBackground(FenixTheme.darkCard)
                }
            } header: {
                Text("Next Session")
            } footer: {
                if !upcoming.isEmpty {
                    Text("Tap Cancel booking or swipe left to cancel before the cutoff.")
                }
            }

            if upcoming.count > 1 {
                Section {
                    ForEach(upcoming.dropFirst()) { booking in
                        BookingRow(
                            booking: booking,
                            canCancel: canCancel(booking)
                        ) {
                            bookingToCancel = booking
                        }
                            .listRowBackground(FenixTheme.darkCard)
                            .swipeActions {
                                Button(role: .destructive) {
                                    bookingToCancel = booking
                                } label: {
                                    Label("Cancel", systemImage: "xmark.circle")
                                }
                            }
                }
            } header: {
                Text("Upcoming")
            } footer: {
                Text("Tap Cancel booking or swipe left to cancel before the cutoff.")
            }
            }

            Section {
                if history.isEmpty {
                    Text("Cancelled and completed bookings will appear here.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                        .listRowBackground(FenixTheme.darkCard)
                } else {
                    ForEach(history) { booking in
                        BookingRow(booking: booking)
                            .listRowBackground(FenixTheme.darkCard)
                    }
                }
            } header: {
                Text("History")
            } footer: {
                Text("Showing the 30 most recent cancelled or completed bookings.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(FenixTheme.loginBlue.ignoresSafeArea())
        .navigationTitle("My Bookings")
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
            Text("\(FacilityTime.dateText(booking.startTime))\n\(FacilityTime.intervalText(start: booking.startTime, end: booking.endTime))")
        }
    }

    private func canCancel(_ booking: GymBooking) -> Bool {
        let cutoff = appModel.rules?.cancellationCutoffMinutes ?? FacilityRules.fenixDefault.cancellationCutoffMinutes
        return booking.startTime.timeIntervalSince(Date()) > TimeInterval(cutoff * 60)
    }
}

struct BookingRow: View {
    let booking: GymBooking
    var canCancel = false
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(FacilityTime.dateText(booking.startTime))
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(booking.status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(booking.status.tint)
            }

            Text(FacilityTime.intervalText(start: booking.startTime, end: booking.endTime))
                .foregroundStyle(FenixTheme.darkSecondaryText)

            Text("\(booking.durationMinutes) minutes")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(FenixTheme.glowGold.opacity(0.20), in: Capsule())

            if booking.status == .active {
                if canCancel, let onCancel {
                    Button(role: .destructive, action: onCancel) {
                        Label("Cancel booking", systemImage: "xmark.circle")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
                    .accessibilityHint("Cancels this wellness centre booking after confirmation.")
                } else {
                    Label("Cancellation cutoff has passed.", systemImage: "lock")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        MyBookingsView()
            .environment(AppModel(repository: MockGymBookingRepository()))
    }
}
