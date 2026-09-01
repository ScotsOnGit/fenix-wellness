//
//  AppModels.swift
//  fenix
//
//  Created by Codex on 5/6/2026.
//

import Foundation
import SwiftUI

enum FenixTheme {
    static let primaryBlue = Color(red: 0 / 255, green: 50 / 255, blue: 97 / 255)
    static let loginBlue = Color(red: 0 / 255, green: 66 / 255, blue: 123 / 255)
    static let actionBlue = Color(red: 0 / 255, green: 131 / 255, blue: 255 / 255)
    static let darkCard = Color.white.opacity(0.07)
    static let darkCardPressed = Color.white.opacity(0.14)
    static let darkBorder = Color.white.opacity(0.10)
    static let darkSecondaryText = Color.white.opacity(0.62)
    static let slateGrey = Color(red: 152 / 255, green: 165 / 255, blue: 176 / 255)
    static let charcoal = Color(red: 54 / 255, green: 54 / 255, blue: 56 / 255)
    static let mutedText = Color(red: 74 / 255, green: 85 / 255, blue: 104 / 255)
    static let borderGrey = Color(red: 217 / 255, green: 223 / 255, blue: 225 / 255)
    static let lightGrey = Color(red: 237 / 255, green: 242 / 255, blue: 247 / 255)
    static let surface = Color(red: 247 / 255, green: 250 / 255, blue: 252 / 255)
    static let orange = Color(red: 247 / 255, green: 99 / 255, blue: 12 / 255)
    static let glowGold = Color(red: 255 / 255, green: 139 / 255, blue: 32 / 255)
    static let alertRed = Color(red: 184 / 255, green: 33 / 255, blue: 5 / 255)
    static let amber = Color(red: 245 / 255, green: 165 / 255, blue: 36 / 255)

    static let navy = primaryBlue
    static let gold = orange
}

enum FenixBrand {
    static let appName = "Fenix Wellbeing Facility"
    static let passwordResetRedirectURL = URL(string: "fenixwellness://password-reset")!
}

enum FenixURLValidator {
    static func webURL(from text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

struct FenixBrandMark: View {
    var size: CGFloat = 66
    var padding: CGFloat = 13
    var background: Color = .white
    var showsBorder = true

    var body: some View {
        Image("FenixXMark")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .padding(padding)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if showsBorder {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(FenixTheme.borderGrey, lineWidth: 1)
                }
            }
            .shadow(color: FenixTheme.primaryBlue.opacity(0.10), radius: 10, x: 0, y: 5)
            .accessibilityLabel("Fenix")
    }
}

struct FenixLoadingView: View {
    var message = "Loading"
    var fillsScreen = false

    var body: some View {
        VStack(spacing: 18) {
            FenixBrandMark(
                size: fillsScreen ? 88 : 64,
                padding: fillsScreen ? 17 : 12,
                background: FenixTheme.loginBlue,
                showsBorder: !fillsScreen
            )

            VStack(spacing: 8) {
                Text(FenixBrand.appName)
                    .font((fillsScreen ? Font.title : Font.headline).weight(.bold))
                    .foregroundStyle(.white)

                ProgressView(message)
                    .tint(FenixTheme.orange)
                    .foregroundStyle(FenixTheme.darkSecondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: fillsScreen ? 0 : 160)
        .frame(maxHeight: fillsScreen ? .infinity : 160)
        .background(fillsScreen ? FenixTheme.loginBlue : Color.clear)
    }
}

enum FacilityTime {
    // The facility operates on Perth time regardless of the device's current region.
    // Keep booking/date calculations on this calendar to avoid FIFO travel edge cases.
    static let timeZone = TimeZone(identifier: "Australia/Perth")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static func dateText(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func timeText(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func intervalText(start: Date, end: Date) -> String {
        "\(timeText(start)) - \(timeText(end))"
    }

    static func timeOfDayText(minutesAfterMidnight: Int) -> String {
        let day = calendar.startOfDay(for: Date())
        let date = calendar.date(byAdding: .minute, value: minutesAfterMidnight, to: day) ?? day
        return timeFormatter.string(from: date)
    }
}

struct FacilityRules: Sendable {
    var capacity: Int
    var bookingHorizonDays: Int
    var maxFutureBookings: Int
    var maxActiveBookingsPerDay: Int
    var cancellationCutoffMinutes: Int
    var facilityTimeZoneIdentifier: String
    var allowedDurationsMinutes: [Int]
    var checkInGraceMinutes: Int
    var checkInWindowBeforeMinutes: Int

    static let fenixDefault = FacilityRules(
        capacity: 20,
        bookingHorizonDays: 7,
        maxFutureBookings: 5,
        maxActiveBookingsPerDay: 1,
        cancellationCutoffMinutes: 60,
        facilityTimeZoneIdentifier: "Australia/Perth",
        allowedDurationsMinutes: [15, 30, 45],
        checkInGraceMinutes: 15,
        checkInWindowBeforeMinutes: 10
    )
}

struct BlackoutPeriod: Identifiable, Equatable, Sendable {
    var id: UUID
    var startsAt: Date
    var endsAt: Date
    var reason: String
    var createdAt: Date

    var intervalText: String {
        "\(FacilityTime.dateText(startsAt)) \(FacilityTime.timeText(startsAt)) - \(FacilityTime.timeText(endsAt))"
    }
}

struct OpeningHours: Identifiable, Equatable, Sendable {
    var weekday: Int
    var opensAtMinutes: Int
    var closesAtMinutes: Int
    var isClosed: Bool

    var id: Int { weekday }

    var dayName: String {
        let symbols = FacilityTime.calendar.weekdaySymbols
        let index = weekday == 0 ? 0 : weekday
        return symbols.indices.contains(index) ? symbols[index] : "Day \(weekday)"
    }

    var summary: String {
        if isClosed {
            return "Closed"
        }
        return "\(FacilityTime.timeOfDayText(minutesAfterMidnight: opensAtMinutes)) - \(FacilityTime.timeOfDayText(minutesAfterMidnight: closesAtMinutes))"
    }

    static let fenixDefaultWeek: [OpeningHours] = (0...6).map {
        OpeningHours(weekday: $0, opensAtMinutes: 7 * 60, closesAtMinutes: 19 * 60, isClosed: false)
    }
}

struct FacilityContact: Equatable, Sendable {
    var displayName: String
    var address: String
    var phone: String
    var email: String
    var notes: String

    static let fenixDefault = FacilityContact(
        displayName: "Fenix Wellbeing Facility",
        address: "",
        phone: "",
        email: "",
        notes: "Contact your Fenix admin or HR team for wellbeing facility support."
    )
}

struct WellnessAcknowledgement: Identifiable, Equatable, Sendable {
    var id: UUID
    var version: String
    var title: String
    var body: String
    var capacityText: String
    var fairUseText: String
    var medicalText: String
    var isActive: Bool
    var publishedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    static let fallback = WellnessAcknowledgement(
        id: UUID(uuidString: "FEE00000-0000-4000-8000-000000000100")!,
        version: "2026-06-06-v1",
        title: "Wellbeing Facility Acknowledgement",
        body: "Please read and acknowledge this before using the wellbeing facility. Use of the facility is voluntary and at your own risk.",
        capacityText: "The wellbeing facility is limited to 20 people at a time.",
        fairUseText: "To keep access fair, each staff member can book one session per day, up to 7 days in advance.",
        medicalText: "If you have a medical condition, injury, or any concern about exercise, seek medical advice before using the facility.",
        isActive: true,
        publishedAt: nil,
        createdAt: Date(timeIntervalSince1970: 1_717_676_800),
        updatedAt: Date(timeIntervalSince1970: 1_717_676_800)
    )
}

struct WellnessAcknowledgementAcceptance: Equatable, Sendable {
    var acknowledgementID: UUID
    var version: String
    var acceptedAt: Date
}

struct UserProfile: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable {
        case member
        case admin
    }

    enum AccessStatus: String, Sendable, CaseIterable {
        case pending
        case active
        case paused
        case suspended
        case removed

        var label: String {
            switch self {
            case .pending: "Pending"
            case .active: "Active"
            case .paused: "Paused"
            case .suspended: "Suspended"
            case .removed: "Removed"
            }
        }

        var canBook: Bool {
            self == .active
        }
    }

    var id: UUID
    var fullName: String
    var email: String
    var phone: String
    var role: Role
    var accessStatus: AccessStatus = .active
    var inductionCompletedAt: Date?
    var inductionCompletedBy: UUID?
    var lastSeenAt: Date?

    var initials: String {
        fullName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    var canBookWellnessSessions: Bool {
        // Admins can test/manage booking flows; members must be both active and inducted.
        role == .admin || (accessStatus.canBook && inductionCompletedAt != nil)
    }
}

enum BookingStatus: String, Sendable {
    case active
    case cancelled
    case completed

    var label: String {
        switch self {
        case .active: "Active"
        case .cancelled: "Cancelled"
        case .completed: "Completed"
        }
    }

    var tint: Color {
        switch self {
        case .active: .green
        case .cancelled: .red
        case .completed: .secondary
        }
    }
}

enum AttendanceStatus: String, Sendable {
    case notCheckedIn
    case checkedIn
    case completed
    case noShow

    var label: String {
        switch self {
        case .notCheckedIn: "Not checked in"
        case .checkedIn: "Checked in"
        case .completed: "Completed"
        case .noShow: "No-show"
        }
    }

    var tint: Color {
        switch self {
        case .notCheckedIn: FenixTheme.darkSecondaryText
        case .checkedIn: .green
        case .completed: FenixTheme.actionBlue
        case .noShow: FenixTheme.amber
        }
    }
}

struct GymBooking: Identifiable, Equatable, Sendable {
    var id: UUID
    var userID: UUID
    var memberName: String
    var startTime: Date
    var endTime: Date
    var cancelledAt: Date?
    var createdAt: Date
    var checkedInAt: Date?
    var checkedOutAt: Date?
    var noShowMarkedAt: Date?

    var status: BookingStatus {
        if cancelledAt != nil {
            return .cancelled
        }
        return endTime < Date() ? .completed : .active
    }

    var durationMinutes: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }

    var attendanceStatus: AttendanceStatus {
        // Cancellation is represented by BookingStatus; this value only describes
        // attendance for bookings that were allowed to proceed.
        if noShowMarkedAt != nil {
            return .noShow
        }
        if checkedOutAt != nil {
            return .completed
        }
        if checkedInAt != nil {
            return .checkedIn
        }
        return .notCheckedIn
    }
}

struct AvailabilitySlot: Identifiable, Equatable, Sendable {
    enum Status: Sendable {
        case available
        case nearlyFull
        case full

        var label: String {
            switch self {
            case .available: "Available"
            case .nearlyFull: "Nearly full"
            case .full: "Full"
            }
        }

        var tint: Color {
            switch self {
            case .available: .green
            case .nearlyFull: .orange
            case .full: .red
            }
        }
    }

    var startTime: Date
    var occupiedCount: Int
    var capacity: Int

    var id: Date { startTime }
    var remaining: Int { max(capacity - occupiedCount, 0) }
    var status: Status {
        if occupiedCount >= capacity {
            return .full
        }
        // Nearly-full is a visual cue only. Capacity and write safety are enforced by
        // the database RPCs when a booking is created.
        if occupiedCount >= 15 {
            return .nearlyFull
        }
        return .available
    }
}

struct BookingDraft: Equatable {
    var date: Date
    var slot: AvailabilitySlot?
    var durationMinutes: Int = 30

    var startTime: Date? { slot?.startTime }

    var endTime: Date? {
        guard let startTime else { return nil }
        return FacilityTime.calendar.date(byAdding: .minute, value: durationMinutes, to: startTime)
    }
}

enum BookingError: LocalizedError, Equatable {
    case rulesUnavailable
    case noStartTimeSelected
    case slotFull
    case outsideOpeningHours
    case maxDailyBookings
    case maxFutureBookings
    case cancellationCutoff
    case accessPending
    case unauthenticated
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .rulesUnavailable:
            "Cannot confirm current availability. Please refresh rules and try again."
        case .noStartTimeSelected:
            "Choose a start time before confirming."
        case .slotFull:
            "This start time is now full. Refresh availability and choose another time."
        case .outsideOpeningHours:
            "This session extends outside wellbeing facility hours."
        case .maxDailyBookings:
            "You already have a booking on this day."
        case .maxFutureBookings:
            "You already have five upcoming bookings."
        case .cancellationCutoff:
            "Bookings can only be cancelled when more than 60 minutes remain."
        case .accessPending:
            "Your wellbeing facility access is pending admin induction approval."
        case .unauthenticated:
            "Please sign in again to continue."
        case let .remote(message):
            message
        }
    }
}

enum ResourceKind: String, Sendable, CaseIterable {
    case link
    case pdf

    var label: String {
        switch self {
        case .link: "Link"
        case .pdf: "PDF"
        }
    }
}

struct WellnessResource: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var description: String
    var category: String
    var resourceType: ResourceKind
    var url: String
    var storagePath: String
    var isPublished: Bool
    var createdAt: Date

    var displayURL: URL? {
        FenixURLValidator.webURL(from: url)
    }
}

struct ProgramAssignment: Identifiable, Equatable, Sendable {
    var id: UUID
    var userID: UUID
    var memberName: String
    var title: String
    var description: String
    var resourceType: ResourceKind
    var url: String
    var storagePath: String
    var assignedAt: Date
    var archivedAt: Date?

    var displayURL: URL? {
        FenixURLValidator.webURL(from: url)
    }
}

enum ChallengeStatus: String, Sendable {
    case draft
    case upcoming
    case active
    case ended

    var label: String {
        switch self {
        case .draft: "Draft"
        case .upcoming: "Upcoming"
        case .active: "Active"
        case .ended: "Ended"
        }
    }

    var tint: Color {
        switch self {
        case .draft: FenixTheme.darkSecondaryText
        case .upcoming: FenixTheme.amber
        case .active: .green
        case .ended: FenixTheme.slateGrey
        }
    }
}

struct WellbeingChallenge: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var description: String
    var challengeType: String
    var metricName: String
    var metricUnit: String
    var targetValue: Double?
    var startsOn: Date
    var endsOn: Date
    var rules: String
    var leaderboardVisible: Bool
    var isPublished: Bool
    var createdAt: Date

    var status: ChallengeStatus {
        // Draft challenges remain admin-only even if their dates would otherwise make
        // them upcoming or active.
        if !isPublished {
            return .draft
        }
        let today = FacilityTime.calendar.startOfDay(for: Date())
        if today < startsOn {
            return .upcoming
        }
        if today > endsOn {
            return .ended
        }
        return .active
    }

    var dateRangeText: String {
        "\(FacilityTime.dateText(startsOn)) - \(FacilityTime.dateText(endsOn))"
    }

    var metricLabel: String {
        metricUnit.isEmpty ? metricName : "\(metricName) (\(metricUnit))"
    }

    var targetText: String {
        guard let targetValue else { return "No target set" }
        return "\(targetValue.cleanText) \(metricUnit)".trimmingCharacters(in: .whitespaces)
    }
}

struct ChallengeParticipant: Identifiable, Equatable, Sendable {
    var id: UUID
    var challengeID: UUID
    var userID: UUID
    var memberName: String
    var joinedAt: Date
}

struct ChallengeEntry: Identifiable, Equatable, Sendable {
    var id: UUID
    var challengeID: UUID
    var userID: UUID
    var memberName: String
    var value: Double
    var note: String
    var entryDate: Date
    var createdAt: Date

    var valueText: String {
        value.cleanText
    }
}

struct ChallengeLeaderboardEntry: Identifiable, Equatable, Sendable {
    var id: UUID { userID }
    var userID: UUID
    var memberName: String
    var totalValue: Double
    var entryCount: Int
    var rank: Int

    var totalText: String {
        totalValue.cleanText
    }
}

struct AdminReportSummary: Equatable, Sendable {
    var totalBookings: Int
    var activeMembers: Int
    var attendedCount: Int
    var noShowCount: Int
    var cancelledCount: Int
    var peakHour: Int

    static let empty = AdminReportSummary(
        totalBookings: 0,
        activeMembers: 0,
        attendedCount: 0,
        noShowCount: 0,
        cancelledCount: 0,
        peakHour: 0
    )

    var attendanceRateText: String {
        guard totalBookings > 0 else { return "0%" }
        return "\(Int((Double(attendedCount) / Double(totalBookings) * 100).rounded()))%"
    }

    var peakHourText: String {
        String(format: "%02d:00", peakHour)
    }
}

private extension Double {
    var cleanText: String {
        if rounded() == self {
            return String(Int(self))
        }
        return String(format: "%.2f", self)
    }
}

struct BookingExportRow: Identifiable, Equatable, Sendable {
    var id: UUID { bookingID }
    var bookingID: UUID
    var memberName: String
    var email: String
    var startTime: Date
    var endTime: Date
    var cancelledAt: Date?
    var checkedInAt: Date?
    var checkedOutAt: Date?
    var noShowMarkedAt: Date?
}

struct AuditLogEntry: Identifiable, Equatable, Sendable {
    var id: Int
    var actorID: UUID?
    var action: String
    var targetType: String
    var targetID: String
    var createdAt: Date

    var title: String {
        action.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

extension View {
    func dismissableKeyboard() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.dismissKeyboard()
                    }
                }
            }
    }

    func adminListStyle(title: String) -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(FenixTheme.loginBlue.ignoresSafeArea())
            .foregroundStyle(.white)
            .navigationTitle(title)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(FenixTheme.loginBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

private extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
