//
//  fenixTests.swift
//  fenixTests
//
//  Created by Michael Fullarton on 5/6/2026.
//

import Foundation
import Testing
@testable import fenix

struct fenixTests {

    @Test func facilityCalendarUsesPerthTime() {
        #expect(FacilityTime.calendar.timeZone.identifier == "Australia/Perth")
    }

    @MainActor
    @Test func mockRepositoryRejectsSecondActiveBookingForSameDay() async throws {
        let repository = MockGymBookingRepository()
        _ = try await repository.signIn(email: "member@fenix.com.au", password: "password123")

        let calendar = FacilityTime.calendar
        let targetDay = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: Date())) ?? Date()
        let firstStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: targetDay) ?? targetDay
        let secondStart = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: targetDay) ?? targetDay

        _ = try await repository.createBooking(startTime: firstStart, durationMinutes: 30)

        await #expect(throws: BookingError.maxDailyBookings) {
            _ = try await repository.createBooking(startTime: secondStart, durationMinutes: 30)
        }
    }

    @MainActor
    @Test func availabilityUsesWellnessCentreHours() async throws {
        let repository = MockGymBookingRepository()
        let calendar = FacilityTime.calendar
        let targetDay = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: Date())) ?? Date()

        let slots = try await repository.fetchAvailability(for: targetDay, durationMinutes: 60)

        #expect(FacilityTime.timeText(slots.first?.startTime ?? Date()) == "7:00 AM")
        #expect(FacilityTime.timeText(slots.last?.startTime ?? Date()) == "6:00 PM")
        #expect(slots.allSatisfy { slot in
            let hour = calendar.component(.hour, from: slot.startTime)
            let minute = calendar.component(.minute, from: slot.startTime)
            return hour > 7 || (hour == 7 && minute >= 0)
        })
    }

    @MainActor
    @Test func mockRepositoryRejectsBookingsOutsideWellnessCentreHours() async throws {
        let repository = MockGymBookingRepository()
        _ = try await repository.signIn(email: "member@fenix.com.au", password: "password123")

        let calendar = FacilityTime.calendar
        let targetDay = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: Date())) ?? Date()
        let beforeOpen = calendar.date(bySettingHour: 6, minute: 45, second: 0, of: targetDay) ?? targetDay
        let tooLate = calendar.date(bySettingHour: 18, minute: 15, second: 0, of: targetDay) ?? targetDay
        let lastValid = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: targetDay) ?? targetDay

        await #expect(throws: BookingError.outsideOpeningHours) {
            _ = try await repository.createBooking(startTime: beforeOpen, durationMinutes: 15)
        }
        await #expect(throws: BookingError.outsideOpeningHours) {
            _ = try await repository.createBooking(startTime: tooLate, durationMinutes: 60)
        }

        _ = try await repository.createBooking(startTime: lastValid, durationMinutes: 60)
    }

}
