//
//  SupabaseGymBookingRepository.swift
//  fenix
//
//  Created by Codex on 5/6/2026.
//

import Foundation
import Security

@MainActor
final class SupabaseGymBookingRepository: GymBookingRepository {
    private struct AuthSession: Codable {
        var accessToken: String
        var refreshToken: String?
        var userID: UUID
    }

    private struct AuthResponse: Decodable {
        struct User: Decodable {
            let id: UUID
        }

        let accessToken: String?
        let refreshToken: String?
        let user: User?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case user
        }
    }

    private struct ProfileRow: Decodable {
        let id: UUID
        let fullName: String?
        let email: String?
        let phone: String?
        let role: String?
        let accessStatus: String?
        let inductionCompletedAt: Date?
        let inductionCompletedBy: UUID?
        let lastSeenAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case fullName = "full_name"
            case email
            case phone
            case role
            case accessStatus = "access_status"
            case inductionCompletedAt = "induction_completed_at"
            case inductionCompletedBy = "induction_completed_by"
            case lastSeenAt = "last_seen_at"
        }
    }

    private struct FacilityRulesRow: Decodable {
        let capacity: Int
        let allowedDurationsMinutes: [Int]?
        let cancellationCutoffMinutes: Int
        let maxFutureBookings: Int
        let maxActiveBookingsPerDay: Int
        let bookingHorizonDays: Int
        let timezoneIdentifier: String
        let checkInGraceMinutes: Int?
        let checkInWindowBeforeMinutes: Int?

        enum CodingKeys: String, CodingKey {
            case capacity
            case allowedDurationsMinutes = "allowed_durations_minutes"
            case cancellationCutoffMinutes = "cancellation_cutoff_minutes"
            case maxFutureBookings = "max_future_bookings"
            case maxActiveBookingsPerDay = "max_active_bookings_per_day"
            case bookingHorizonDays = "booking_horizon_days"
            case timezoneIdentifier = "timezone_identifier"
            case checkInGraceMinutes = "check_in_grace_minutes"
            case checkInWindowBeforeMinutes = "check_in_window_before_minutes"
        }
    }

    private struct OpeningHoursRow: Codable {
        let weekday: Int
        let opensAt: String
        let closesAt: String
        let isClosed: Bool

        enum CodingKeys: String, CodingKey {
            case weekday
            case opensAt = "opens_at"
            case closesAt = "closes_at"
            case isClosed = "is_closed"
        }
    }

    private struct FacilityContactRow: Codable {
        let displayName: String
        let address: String?
        let phone: String?
        let email: String?
        let notes: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case address
            case phone
            case email
            case notes
        }
    }

    private struct AcknowledgementRow: Decodable {
        let id: UUID
        let version: String
        let title: String
        let body: String
        let capacityText: String?
        let fairUseText: String?
        let medicalText: String?
        let isActive: Bool
        let publishedAt: Date?
        let createdAt: Date
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case version
            case title
            case body
            case capacityText = "capacity_text"
            case fairUseText = "fair_use_text"
            case medicalText = "medical_text"
            case isActive = "is_active"
            case publishedAt = "published_at"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    private struct AcknowledgementAcceptanceRow: Decodable {
        let acknowledgementID: UUID
        let version: String
        let acceptedAt: Date

        enum CodingKeys: String, CodingKey {
            case acknowledgementID = "acknowledgement_id"
            case version
            case acceptedAt = "accepted_at"
        }
    }

    private struct BlackoutPeriodRow: Codable {
        let id: UUID
        let startsAt: Date
        let endsAt: Date
        let reason: String
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case reason
            case createdAt = "created_at"
        }
    }

    private struct AvailabilityRow: Decodable {
        let startTime: Date
        let occupiedCount: Int
        let remainingCapacity: Int

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case occupiedCount = "occupied_count"
            case remainingCapacity = "remaining_capacity"
        }
    }

    private struct BookingRow: Decodable {
        let id: UUID
        let userID: UUID
        let startTime: Date
        let endTime: Date
        let cancelledAt: Date?
        let createdAt: Date
        let checkedInAt: Date?
        let checkedOutAt: Date?
        let noShowMarkedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case startTime = "start_time"
            case endTime = "end_time"
            case cancelledAt = "cancelled_at"
            case createdAt = "created_at"
            case checkedInAt = "checked_in_at"
            case checkedOutAt = "checked_out_at"
            case noShowMarkedAt = "no_show_marked_at"
        }
    }

    private struct ResourceRow: Decodable {
        let id: UUID
        let title: String
        let description: String?
        let category: String
        let resourceType: String
        let url: String?
        let storagePath: String?
        let isPublished: Bool
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case description
            case category
            case resourceType = "resource_type"
            case url
            case storagePath = "storage_path"
            case isPublished = "is_published"
            case createdAt = "created_at"
        }
    }

    private struct ProgramRow: Decodable {
        let id: UUID
        let userID: UUID
        let title: String
        let description: String?
        let resourceType: String
        let url: String?
        let storagePath: String?
        let assignedAt: Date
        let archivedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case title
            case description
            case resourceType = "resource_type"
            case url
            case storagePath = "storage_path"
            case assignedAt = "assigned_at"
            case archivedAt = "archived_at"
        }
    }

    private struct ReportSummaryRow: Decodable {
        let totalBookings: Int
        let activeMembers: Int
        let attendedCount: Int
        let noShowCount: Int
        let cancelledCount: Int
        let peakHour: Int

        enum CodingKeys: String, CodingKey {
            case totalBookings = "total_bookings"
            case activeMembers = "active_members"
            case attendedCount = "attended_count"
            case noShowCount = "no_show_count"
            case cancelledCount = "cancelled_count"
            case peakHour = "peak_hour"
        }
    }

    private struct BookingExportRowDTO: Decodable {
        let bookingID: UUID
        let memberName: String?
        let email: String?
        let startTime: Date
        let endTime: Date
        let cancelledAt: Date?
        let checkedInAt: Date?
        let checkedOutAt: Date?
        let noShowMarkedAt: Date?

        enum CodingKeys: String, CodingKey {
            case bookingID = "booking_id"
            case memberName = "member_name"
            case email
            case startTime = "start_time"
            case endTime = "end_time"
            case cancelledAt = "cancelled_at"
            case checkedInAt = "checked_in_at"
            case checkedOutAt = "checked_out_at"
            case noShowMarkedAt = "no_show_marked_at"
        }
    }

    private struct AuditRow: Decodable {
        let id: Int
        let actorID: UUID?
        let action: String
        let targetType: String
        let targetID: String?
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case actorID = "actor_id"
            case action
            case targetType = "target_type"
            case targetID = "target_id"
            case createdAt = "created_at"
        }
    }

    private struct ChallengeRow: Decodable {
        let id: UUID
        let title: String
        let description: String?
        let challengeType: String
        let metricName: String
        let metricUnit: String?
        let targetValue: Double?
        let startsOn: String
        let endsOn: String
        let rules: String?
        let leaderboardVisible: Bool
        let isPublished: Bool
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case description
            case challengeType = "challenge_type"
            case metricName = "metric_name"
            case metricUnit = "metric_unit"
            case targetValue = "target_value"
            case startsOn = "starts_on"
            case endsOn = "ends_on"
            case rules
            case leaderboardVisible = "leaderboard_visible"
            case isPublished = "is_published"
            case createdAt = "created_at"
        }
    }

    private struct ChallengeParticipantRow: Decodable {
        let id: UUID
        let challengeID: UUID
        let userID: UUID
        let joinedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case challengeID = "challenge_id"
            case userID = "user_id"
            case joinedAt = "joined_at"
        }
    }

    private struct ChallengeEntryRow: Decodable {
        let id: UUID
        let challengeID: UUID
        let userID: UUID
        let value: Double
        let note: String?
        let entryDate: String
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case challengeID = "challenge_id"
            case userID = "user_id"
            case value
            case note
            case entryDate = "entry_date"
            case createdAt = "created_at"
        }
    }

    private struct ChallengeLeaderboardRow: Decodable {
        let userID: UUID
        let memberName: String
        let totalValue: Double
        let entryCount: Int
        let rank: Int

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case memberName = "member_name"
            case totalValue = "total_value"
            case entryCount = "entry_count"
            case rank
        }
    }

    private struct SignedURLResponse: Decodable {
        let signedURL: String

        enum CodingKeys: String, CodingKey {
            case signedURL = "signedURL"
        }
    }

    private struct SupabaseError: Decodable {
        let message: String?
        let msg: String?
        let errorDescription: String?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case message
            case msg
            case errorDescription = "error_description"
            case error
        }

        var bestMessage: String {
            message ?? errorDescription ?? msg ?? error ?? "Supabase request failed."
        }
    }

    private struct EmptyResponse: Decodable {}

    private let baseURL: URL
    private let apiKey: String
    private let keychainService = "com.fullarton.fenix.supabase-session"
    private let sessionStorageKey = "fenix.supabase.session"
    private let historyBookingLimit = 30
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    private var authSession: AuthSession?
    private var profile: UserProfile?

    init(
        baseURL: URL = SupabaseConfig.projectURL,
        apiKey: String = SupabaseConfig.publishableKey,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.urlSession = urlSession

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Date.supabaseISOFormatter.date(from: value) {
                return date
            }
            if let date = Date.supabaseISOFormatterNoFraction.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Supabase date: \(value)")
        }
        self.decoder = decoder

        restoreStoredSession()
    }

    func restoreSession() async throws -> UserProfile? {
        guard authSession != nil else { return nil }
        do {
            profile = try await fetchCurrentProfile()
            return profile
        } catch {
            clearStoredSession()
            throw error
        }
    }

    func signIn(email: String, password: String) async throws -> UserProfile {
        let body = ["email": email, "password": password]
        let response: AuthResponse = try await request(
            path: "/auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "password")],
            method: "POST",
            body: body,
            requiresAuth: false
        )
        try store(response)
        profile = try await fetchCurrentProfile()
        return profile!
    }

    func register(fullName: String, email: String, password: String, phone: String) async throws -> UserProfile {
        let body: [String: SendableValue] = [
            "email": .string(email),
            "password": .string(password),
            "data": .object([
                "full_name": .string(fullName),
                "phone": .string(phone)
            ])
        ]
        let response: AuthResponse = try await request(path: "/auth/v1/signup", method: "POST", body: body, requiresAuth: false)
        try store(response)
        profile = try await fetchCurrentProfile()
        return profile!
    }

    func resetPassword(email: String) async throws {
        try await requestWithoutResponse(
            path: "/auth/v1/recover",
            queryItems: [
                URLQueryItem(name: "redirect_to", value: FenixBrand.passwordResetRedirectURL.absoluteString)
            ],
            method: "POST",
            body: [
                "email": email
            ],
            requiresAuth: false
        )
    }

    func handlePasswordRecovery(url: URL) async throws -> UserProfile {
        let parameters = recoveryParameters(from: url)
        guard parameters["type"] == nil || parameters["type"] == "recovery" else {
            throw BookingError.remote("This link is not a password reset link.")
        }

        guard let accessToken = parameters["access_token"], !accessToken.isEmpty else {
            if parameters["code"] != nil {
                throw BookingError.remote("This reset link opened with a one-time code instead of a mobile session. Add \(FenixBrand.passwordResetRedirectURL.absoluteString) to the Supabase Auth redirect URLs, then send a new reset email.")
            }
            throw BookingError.remote("This reset link is missing its recovery session. Please request a new password reset email.")
        }

        guard let userID = userID(fromJWT: accessToken) else {
            throw BookingError.remote("This reset link could not be verified. Please request a new password reset email.")
        }

        let session = AuthSession(
            accessToken: accessToken,
            refreshToken: parameters["refresh_token"],
            userID: userID
        )
        authSession = session
        try writeStoredSession(session)
        profile = try await fetchCurrentProfile()
        return profile!
    }

    func updateProfile(fullName: String, phone: String) async throws -> UserProfile {
        guard let userID = authSession?.userID else { throw BookingError.unauthenticated }
        let cleanPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        try await requestWithoutResponse(
            path: "/rest/v1/profiles",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(userID.uuidString)")],
            method: "PATCH",
            body: [
                "full_name": SendableValue.string(fullName),
                "phone": cleanPhone.isEmpty ? .null : .string(cleanPhone)
            ]
        )
        profile = try await fetchCurrentProfile()
        return profile!
    }

    func updatePassword(currentPassword: String, newPassword: String) async throws {
        var body: [String: String] = ["password": newPassword]
        if !currentPassword.isEmpty {
            body["current_password"] = currentPassword
        }
        try await requestWithoutResponse(
            path: "/auth/v1/user",
            method: "PUT",
            body: body
        )
    }

    func fetchOpeningHours() async throws -> [OpeningHours] {
        let rows: [OpeningHoursRow] = try await request(
            path: "/rest/v1/opening_hours",
            queryItems: [
                URLQueryItem(name: "select", value: "weekday,opens_at,closes_at,is_closed"),
                URLQueryItem(name: "order", value: "weekday.asc")
            ],
            method: "GET"
        )
        return rows.map(openingHours(from:))
    }

    func updateOpeningHours(_ openingHours: [OpeningHours]) async throws -> [OpeningHours] {
        for hours in openingHours {
            try await requestWithoutResponse(
                path: "/rest/v1/opening_hours",
                queryItems: [URLQueryItem(name: "weekday", value: "eq.\(hours.weekday)")],
                method: "PATCH",
                body: [
                    "opens_at": SendableValue.string(timeDatabaseText(minutes: hours.opensAtMinutes)),
                    "closes_at": SendableValue.string(timeDatabaseText(minutes: hours.closesAtMinutes)),
                    "is_closed": SendableValue.bool(hours.isClosed)
                ]
            )
        }
        return try await fetchOpeningHours()
    }

    func fetchFacilityContact() async throws -> FacilityContact {
        let rows: [FacilityContactRow] = try await request(
            path: "/rest/v1/facility_contact",
            queryItems: [
                URLQueryItem(name: "select", value: "display_name,address,phone,email,notes"),
                URLQueryItem(name: "limit", value: "1")
            ],
            method: "GET"
        )
        return rows.first.map(contact(from:)) ?? .fenixDefault
    }

    func updateFacilityContact(_ contact: FacilityContact) async throws -> FacilityContact {
        try await requestWithoutResponse(
            path: "/rest/v1/facility_contact",
            queryItems: [URLQueryItem(name: "id", value: "eq.true")],
            method: "PATCH",
            body: [
                "display_name": SendableValue.string(contact.displayName.trimmingCharacters(in: .whitespacesAndNewlines)),
                "address": nullableString(contact.address),
                "phone": nullableString(contact.phone),
                "email": nullableString(contact.email),
                "notes": nullableString(contact.notes)
            ]
        )
        return try await fetchFacilityContact()
    }

    func fetchActiveAcknowledgement() async throws -> WellnessAcknowledgement {
        let rows: [AcknowledgementRow] = try await request(
            path: "/rest/v1/wellness_acknowledgements",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "is_active", value: "eq.true"),
                URLQueryItem(name: "limit", value: "1")
            ],
            method: "GET",
            requiresAuth: false
        )
        return rows.first.map(acknowledgement(from:)) ?? .fallback
    }

    func fetchMyAcknowledgementAcceptance() async throws -> WellnessAcknowledgementAcceptance? {
        guard let userID = authSession?.userID else { return nil }
        let rows: [AcknowledgementAcceptanceRow] = try await request(
            path: "/rest/v1/profile_acknowledgements",
            queryItems: [
                URLQueryItem(name: "select", value: "acknowledgement_id,version,accepted_at"),
                URLQueryItem(name: "profile_id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "order", value: "accepted_at.desc"),
                URLQueryItem(name: "limit", value: "10")
            ],
            method: "GET"
        )
        return rows.first.map(acknowledgementAcceptance(from:))
    }

    func acceptAcknowledgement(_ acknowledgement: WellnessAcknowledgement) async throws -> WellnessAcknowledgementAcceptance {
        guard let userID = authSession?.userID else { throw BookingError.unauthenticated }
        let existingRows: [AcknowledgementAcceptanceRow] = try await request(
            path: "/rest/v1/profile_acknowledgements",
            queryItems: [
                URLQueryItem(name: "select", value: "acknowledgement_id,version,accepted_at"),
                URLQueryItem(name: "profile_id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "acknowledgement_id", value: "eq.\(acknowledgement.id.uuidString)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            method: "GET"
        )
        if let existing = existingRows.first {
            return acknowledgementAcceptance(from: existing)
        }

        try await requestWithoutResponse(
            path: "/rest/v1/profile_acknowledgements",
            method: "POST",
            body: [
                "profile_id": SendableValue.string(userID.uuidString),
                "acknowledgement_id": SendableValue.string(acknowledgement.id.uuidString),
                "version": SendableValue.string(acknowledgement.version)
            ]
        )
        let acceptedAt = Date()
        return WellnessAcknowledgementAcceptance(
            acknowledgementID: acknowledgement.id,
            version: acknowledgement.version,
            acceptedAt: acceptedAt
        )
    }

    func publishAcknowledgement(title: String, body: String, capacityText: String, fairUseText: String, medicalText: String) async throws -> WellnessAcknowledgement {
        let row: AcknowledgementRow = try await request(
            path: "/rest/v1/rpc/publish_wellness_acknowledgement",
            method: "POST",
            body: [
                "p_title": SendableValue.string(title),
                "p_body": SendableValue.string(body),
                "p_capacity_text": nullableString(capacityText),
                "p_fair_use_text": SendableValue.string(fairUseText),
                "p_medical_text": SendableValue.string(medicalText)
            ]
        )
        return acknowledgement(from: row)
    }

    func fetchBlackoutPeriods() async throws -> [BlackoutPeriod] {
        let rows: [BlackoutPeriodRow] = try await request(
            path: "/rest/v1/blackout_periods",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "ends_at", value: "gte.\(Date.supabaseISOFormatter.string(from: Date()))"),
                URLQueryItem(name: "order", value: "starts_at.asc")
            ],
            method: "GET"
        )
        return rows.map(blackout(from:))
    }

    func createBlackoutPeriod(startsAt: Date, endsAt: Date, reason: String) async throws -> BlackoutPeriod {
        let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        try await requestWithoutResponse(
            path: "/rest/v1/blackout_periods",
            method: "POST",
            body: [
                "starts_at": SendableValue.string(Date.supabaseISOFormatter.string(from: startsAt)),
                "ends_at": SendableValue.string(Date.supabaseISOFormatter.string(from: endsAt)),
                "reason": SendableValue.string(cleanReason)
            ]
        )

        let created = try await fetchBlackoutPeriods()
            .first {
                abs($0.startsAt.timeIntervalSince(startsAt)) < 1 &&
                    abs($0.endsAt.timeIntervalSince(endsAt)) < 1 &&
                    $0.reason == cleanReason
            }
        guard let created else { throw BookingError.remote("Blackout period was added, but could not be reloaded.") }
        return created
    }

    func deleteBlackoutPeriod(_ blackout: BlackoutPeriod) async throws {
        try await requestWithoutResponse(
            path: "/rest/v1/blackout_periods",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(blackout.id.uuidString)")],
            method: "DELETE"
        )
    }

    func fetchAdminProfiles() async throws -> [UserProfile] {
        let rows: [ProfileRow] = try await request(
            path: "/rest/v1/profiles",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "role", value: "eq.admin"),
                URLQueryItem(name: "order", value: "email.asc")
            ],
            method: "GET"
        )
        return rows.map(profile(from:))
    }

    func promoteAdmin(email: String) async throws -> UserProfile {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanEmail.isEmpty else {
            throw BookingError.remote("Enter the staff member's email address.")
        }

        let existingRows: [ProfileRow] = try await request(
            path: "/rest/v1/profiles",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "email", value: "eq.\(cleanEmail)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            method: "GET"
        )
        guard let existingRow = existingRows.first else {
            throw BookingError.remote("No registered staff account found for \(cleanEmail). Ask them to create their account first, then try again.")
        }
        if existingRow.role == UserProfile.Role.admin.rawValue {
            return profile(from: existingRow)
        }

        try await requestWithoutResponse(
            path: "/rest/v1/profiles",
            queryItems: [
                URLQueryItem(name: "email", value: "eq.\(cleanEmail)")
            ],
            method: "PATCH",
            body: ["role": SendableValue.string(UserProfile.Role.admin.rawValue)]
        )

        let updatedRows: [ProfileRow] = try await request(
            path: "/rest/v1/profiles",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "email", value: "eq.\(cleanEmail)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            method: "GET"
        )
        guard let updatedRow = updatedRows.first, updatedRow.role == UserProfile.Role.admin.rawValue else {
            throw BookingError.remote("Could not add admin access for \(cleanEmail). Check your admin permissions and try again.")
        }
        return profile(from: updatedRow)
    }

    func demoteAdmin(_ admin: UserProfile) async throws {
        guard admin.id != authSession?.userID else {
            throw BookingError.remote("You cannot remove your own admin access.")
        }

        try await requestWithoutResponse(
            path: "/rest/v1/profiles",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(admin.id.uuidString)")],
            method: "PATCH",
            body: ["role": SendableValue.string(UserProfile.Role.member.rawValue)]
        )
    }

    func searchMembers(query: String) async throws -> [UserProfile] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "role", value: "eq.member"),
            URLQueryItem(name: "order", value: "full_name.asc"),
            URLQueryItem(name: "limit", value: "50")
        ]
        if !cleanQuery.isEmpty {
            let escaped = cleanQuery.replacingOccurrences(of: ",", with: " ")
            queryItems.append(URLQueryItem(name: "or", value: "(full_name.ilike.*\(escaped)*,email.ilike.*\(escaped)*,phone.ilike.*\(escaped)*)"))
        }

        let rows: [ProfileRow] = try await request(
            path: "/rest/v1/profiles",
            queryItems: queryItems,
            method: "GET"
        )
        return rows.map(profile(from:))
    }

    func updateMemberAccess(_ member: UserProfile, accessStatus: UserProfile.AccessStatus, inductionComplete: Bool) async throws -> UserProfile {
        let row: ProfileRow = try await request(
            path: "/rest/v1/rpc/update_member_access",
            method: "POST",
            body: [
                "p_user_id": SendableValue.string(member.id.uuidString),
                "p_access_status": SendableValue.string(accessStatus.rawValue),
                "p_induction_complete": SendableValue.bool(inductionComplete)
            ]
        )
        return profile(from: row)
    }

    func deleteRemovedMemberLogin(_ member: UserProfile) async throws {
        let _: EmptyResponse = try await request(
            path: "/functions/v1/delete-removed-member",
            method: "POST",
            body: [
                "user_id": SendableValue.string(member.id.uuidString)
            ]
        )
    }

    func signOut() async throws {
        if authSession != nil {
            try? await requestWithoutResponse(path: "/auth/v1/logout", method: "POST", requiresAuth: true)
        }
        clearStoredSession()
        profile = nil
    }

    func fetchRules() async throws -> FacilityRules {
        let rows: [FacilityRulesRow] = try await request(
            path: "/rest/v1/facility_rules",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "limit", value: "1")
            ],
            method: "GET"
        )
        guard let row = rows.first else { throw BookingError.rulesUnavailable }
        return FacilityRules(
            capacity: row.capacity,
            bookingHorizonDays: row.bookingHorizonDays,
            maxFutureBookings: row.maxFutureBookings,
            maxActiveBookingsPerDay: row.maxActiveBookingsPerDay,
            cancellationCutoffMinutes: row.cancellationCutoffMinutes,
            facilityTimeZoneIdentifier: row.timezoneIdentifier,
            allowedDurationsMinutes: row.allowedDurationsMinutes ?? FacilityRules.fenixDefault.allowedDurationsMinutes,
            checkInGraceMinutes: row.checkInGraceMinutes ?? FacilityRules.fenixDefault.checkInGraceMinutes,
            checkInWindowBeforeMinutes: row.checkInWindowBeforeMinutes ?? FacilityRules.fenixDefault.checkInWindowBeforeMinutes
        )
    }

    func updateRules(_ rules: FacilityRules) async throws -> FacilityRules {
        try await requestWithoutResponse(
            path: "/rest/v1/facility_rules",
            queryItems: [URLQueryItem(name: "id", value: "eq.true")],
            method: "PATCH",
            body: [
                "capacity": SendableValue.int(rules.capacity),
                "cancellation_cutoff_minutes": SendableValue.int(rules.cancellationCutoffMinutes),
                "max_future_bookings": SendableValue.int(rules.maxFutureBookings),
                "max_active_bookings_per_day": SendableValue.int(rules.maxActiveBookingsPerDay),
                "booking_horizon_days": SendableValue.int(rules.bookingHorizonDays),
                "timezone_identifier": SendableValue.string(rules.facilityTimeZoneIdentifier),
                "allowed_durations_minutes": SendableValue.intArray(rules.allowedDurationsMinutes),
                "check_in_grace_minutes": SendableValue.int(rules.checkInGraceMinutes),
                "check_in_window_before_minutes": SendableValue.int(rules.checkInWindowBeforeMinutes)
            ]
        )
        return try await fetchRules()
    }

    func fetchAvailability(for date: Date, durationMinutes: Int) async throws -> [AvailabilitySlot] {
        let rows: [AvailabilityRow] = try await request(
            path: "/rest/v1/rpc/get_availability_for_date",
            method: "POST",
            body: [
                "p_date": SendableValue.string(FacilityTime.isoDateText(date)),
                "p_duration_minutes": SendableValue.int(durationMinutes)
            ]
        )
        return rows.map {
            AvailabilitySlot(
                startTime: $0.startTime,
                occupiedCount: max(0, $0.occupiedCount),
                capacity: $0.occupiedCount + $0.remainingCapacity
            )
        }
    }

    func createBooking(startTime: Date, durationMinutes: Int) async throws -> GymBooking {
        let row: BookingRow = try await request(
            path: "/rest/v1/rpc/create_booking",
            method: "POST",
            body: [
                "p_start_time": SendableValue.string(Date.supabaseISOFormatter.string(from: startTime)),
                "p_duration_minutes": SendableValue.int(durationMinutes)
            ]
        )
        return booking(from: row, memberName: profile?.fullName)
    }

    func fetchBookings() async throws -> [GymBooking] {
        let futureRows: [BookingRow] = try await request(
            path: "/rest/v1/bookings",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "cancelled_at", value: "is.null"),
                URLQueryItem(name: "end_time", value: "gte.\(Date.supabaseISOFormatter.string(from: Date()))"),
                URLQueryItem(name: "order", value: "start_time.asc")
            ],
            method: "GET"
        )
        let completedRows: [BookingRow] = try await request(
            path: "/rest/v1/bookings",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "cancelled_at", value: "is.null"),
                URLQueryItem(name: "end_time", value: "lt.\(Date.supabaseISOFormatter.string(from: Date()))"),
                URLQueryItem(name: "order", value: "start_time.desc"),
                URLQueryItem(name: "limit", value: "\(historyBookingLimit)")
            ],
            method: "GET"
        )
        let cancelledRows: [BookingRow] = try await request(
            path: "/rest/v1/bookings",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "cancelled_at", value: "not.is.null"),
                URLQueryItem(name: "order", value: "start_time.desc"),
                URLQueryItem(name: "limit", value: "\(historyBookingLimit)")
            ],
            method: "GET"
        )
        let historyRows = (completedRows + cancelledRows)
            .sorted { $0.startTime > $1.startTime }
            .prefix(historyBookingLimit)
        let rows = futureRows + historyRows
        return rows.map { booking(from: $0, memberName: profile?.fullName) }
    }

    func cancelBooking(_ booking: GymBooking) async throws -> GymBooking {
        let row: BookingRow = try await request(
            path: "/rest/v1/rpc/cancel_booking",
            method: "POST",
            body: ["p_booking_id": booking.id.uuidString]
        )
        return self.booking(from: row, memberName: profile?.fullName)
    }

    func fetchAdminBookings(for date: Date) async throws -> [GymBooking] {
        let calendar = FacilityTime.calendar
        let day = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let rows: [BookingRow] = try await request(
            path: "/rest/v1/bookings",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "start_time", value: "gte.\(Date.supabaseISOFormatter.string(from: day))"),
                URLQueryItem(name: "start_time", value: "lt.\(Date.supabaseISOFormatter.string(from: nextDay))"),
                URLQueryItem(name: "order", value: "start_time.asc")
            ],
            method: "GET"
        )
        let names = try await fetchProfileNames(for: rows.map(\.userID))
        return rows.map { booking(from: $0, memberName: names[$0.userID]) }
    }

    func fetchMemberBookings(userID: UUID, limit: Int) async throws -> [GymBooking] {
        let rows: [BookingRow] = try await request(
            path: "/rest/v1/bookings",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "order", value: "start_time.desc"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ],
            method: "GET"
        )
        let names = try await fetchProfileNames(for: rows.map(\.userID))
        return rows.map { booking(from: $0, memberName: names[$0.userID]) }
    }

    func checkIn(code: String) async throws -> GymBooking {
        let row: BookingRow = try await request(
            path: "/rest/v1/rpc/check_in_booking",
            method: "POST",
            body: ["p_code": SendableValue.string(code.trimmingCharacters(in: .whitespacesAndNewlines))]
        )
        return booking(from: row, memberName: profile?.fullName)
    }

    func checkOut(booking: GymBooking) async throws -> GymBooking {
        let row: BookingRow = try await request(
            path: "/rest/v1/rpc/check_out_booking",
            method: "POST",
            body: ["p_booking_id": SendableValue.string(booking.id.uuidString)]
        )
        return self.booking(from: row, memberName: profile?.fullName)
    }

    func markDueNoShows() async throws -> Int {
        let count: Int = try await request(
            path: "/rest/v1/rpc/mark_due_no_shows",
            method: "POST",
            body: EmptyRequestBody()
        )
        return count
    }

    func uploadWellnessPDF(data: Data, fileName: String) async throws -> String {
        let cleanName = fileName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let path = "uploads/\(UUID().uuidString)-\(cleanName)"
        var request = try makeRequest(
            path: "/storage/v1/object/wellness-resources/\(path)",
            queryItems: [],
            method: "POST",
            requiresAuth: true
        )
        request.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        try await sendEmptyWithRefresh(request, requiresAuth: true)
        return path
    }

    func signedURL(forStoragePath storagePath: String) async throws -> URL {
        let response: SignedURLResponse = try await request(
            path: "/storage/v1/object/sign/wellness-resources/\(storagePath)",
            method: "POST",
            body: ["expiresIn": SendableValue.int(600)]
        )
        let signed = response.signedURL.hasPrefix("http")
            ? response.signedURL
            : "\(baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))\(response.signedURL)"
        guard let url = URL(string: signed) else {
            throw BookingError.remote("Could not open this PDF.")
        }
        return url
    }

    func fetchResources() async throws -> [WellnessResource] {
        let rows: [ResourceRow] = try await request(
            path: "/rest/v1/wellness_resources",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "category.asc,title.asc")
            ],
            method: "GET"
        )
        return rows.map(resource(from:))
    }

    func createResource(title: String, description: String, category: String, type: ResourceKind, url: String, storagePath: String, isPublished: Bool) async throws -> WellnessResource {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "General" : category.trimmingCharacters(in: .whitespacesAndNewlines)
        try await requestWithoutResponse(
            path: "/rest/v1/wellness_resources",
            method: "POST",
            body: [
                "title": SendableValue.string(cleanTitle),
                "description": nullableString(description),
                "category": SendableValue.string(cleanCategory),
                "resource_type": SendableValue.string(type.rawValue),
                "url": nullableString(url),
                "storage_path": nullableString(storagePath),
                "is_published": SendableValue.bool(isPublished)
            ]
        )
        guard let resource = try await fetchResources().first(where: { $0.title == cleanTitle && $0.category == cleanCategory }) else {
            throw BookingError.remote("Resource was saved, but could not be reloaded.")
        }
        return resource
    }

    func updateResource(_ resource: WellnessResource) async throws -> WellnessResource {
        try await requestWithoutResponse(
            path: "/rest/v1/wellness_resources",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(resource.id.uuidString)")],
            method: "PATCH",
            body: [
                "title": SendableValue.string(resource.title),
                "description": nullableString(resource.description),
                "category": SendableValue.string(resource.category),
                "resource_type": SendableValue.string(resource.resourceType.rawValue),
                "url": nullableString(resource.url),
                "storage_path": nullableString(resource.storagePath),
                "is_published": SendableValue.bool(resource.isPublished)
            ]
        )
        guard let updated = try await fetchResources().first(where: { $0.id == resource.id }) else {
            throw BookingError.remote("Resource was updated, but could not be reloaded.")
        }
        return updated
    }

    func deleteResource(_ resource: WellnessResource) async throws {
        try await requestWithoutResponse(
            path: "/rest/v1/wellness_resources",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(resource.id.uuidString)")],
            method: "DELETE"
        )
    }

    func fetchPrograms(for userID: UUID?) async throws -> [ProgramAssignment] {
        var queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "archived_at", value: "is.null"),
            URLQueryItem(name: "order", value: "assigned_at.desc")
        ]
        if let userID {
            queryItems.append(URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"))
        }
        let rows: [ProgramRow] = try await request(path: "/rest/v1/program_assignments", queryItems: queryItems, method: "GET")
        let names = try await fetchProfileNames(for: rows.map(\.userID))
        return rows.map { program(from: $0, memberName: names[$0.userID]) }
    }

    func createProgram(userID: UUID, title: String, description: String, type: ResourceKind, url: String, storagePath: String) async throws -> ProgramAssignment {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try await requestWithoutResponse(
            path: "/rest/v1/program_assignments",
            method: "POST",
            body: [
                "user_id": SendableValue.string(userID.uuidString),
                "title": SendableValue.string(cleanTitle),
                "description": nullableString(description),
                "resource_type": SendableValue.string(type.rawValue),
                "url": nullableString(url),
                "storage_path": nullableString(storagePath)
            ]
        )
        guard let program = try await fetchPrograms(for: userID).first(where: { $0.title == cleanTitle }) else {
            throw BookingError.remote("Program was assigned, but could not be reloaded.")
        }
        return program
    }

    func archiveProgram(_ program: ProgramAssignment) async throws {
        try await requestWithoutResponse(
            path: "/rest/v1/program_assignments",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(program.id.uuidString)")],
            method: "PATCH",
            body: ["archived_at": SendableValue.string(Date.supabaseISOFormatter.string(from: Date()))]
        )
    }

    func fetchChallenges(includeDrafts: Bool) async throws -> [WellbeingChallenge] {
        var queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "starts_on.desc")
        ]
        if !includeDrafts {
            queryItems.append(URLQueryItem(name: "is_published", value: "eq.true"))
        }
        let rows: [ChallengeRow] = try await request(path: "/rest/v1/wellbeing_challenges", queryItems: queryItems, method: "GET")
        return rows.map(challenge(from:))
    }

    func createChallenge(_ challenge: WellbeingChallenge) async throws -> WellbeingChallenge {
        let cleanTitle = challenge.title.trimmingCharacters(in: .whitespacesAndNewlines)
        try await requestWithoutResponse(
            path: "/rest/v1/wellbeing_challenges",
            method: "POST",
            body: challengeBody(challenge, title: cleanTitle)
        )
        guard let saved = try await fetchChallenges(includeDrafts: true).first(where: { $0.title == cleanTitle }) else {
            throw BookingError.remote("Challenge was saved, but could not be reloaded.")
        }
        return saved
    }

    func updateChallenge(_ challenge: WellbeingChallenge) async throws -> WellbeingChallenge {
        try await requestWithoutResponse(
            path: "/rest/v1/wellbeing_challenges",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(challenge.id.uuidString)")],
            method: "PATCH",
            body: challengeBody(challenge)
        )
        guard let updated = try await fetchChallenges(includeDrafts: true).first(where: { $0.id == challenge.id }) else {
            throw BookingError.remote("Challenge was updated, but could not be reloaded.")
        }
        return updated
    }

    func deleteChallenge(_ challenge: WellbeingChallenge) async throws {
        try await requestWithoutResponse(
            path: "/rest/v1/wellbeing_challenges",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(challenge.id.uuidString)")],
            method: "DELETE"
        )
    }

    func joinChallenge(_ challenge: WellbeingChallenge) async throws -> ChallengeParticipant {
        let row: ChallengeParticipantRow = try await request(
            path: "/rest/v1/rpc/join_wellbeing_challenge",
            method: "POST",
            body: ["p_challenge_id": SendableValue.string(challenge.id.uuidString)]
        )
        return try await participant(from: row)
    }

    func fetchChallengeEntries(challengeID: UUID, userID: UUID?) async throws -> [ChallengeEntry] {
        var queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "challenge_id", value: "eq.\(challengeID.uuidString)"),
            URLQueryItem(name: "order", value: "entry_date.desc")
        ]
        if let userID {
            queryItems.append(URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"))
        }
        let rows: [ChallengeEntryRow] = try await request(path: "/rest/v1/wellbeing_challenge_entries", queryItems: queryItems, method: "GET")
        let names = try await fetchProfileNames(for: rows.map(\.userID))
        return rows.map { challengeEntry(from: $0, memberName: names[$0.userID]) }
    }

    func addChallengeEntry(challengeID: UUID, value: Double, note: String, entryDate: Date) async throws -> ChallengeEntry {
        let row: ChallengeEntryRow = try await request(
            path: "/rest/v1/rpc/add_wellbeing_challenge_entry",
            method: "POST",
            body: [
                "p_challenge_id": SendableValue.string(challengeID.uuidString),
                "p_value": SendableValue.double(value),
                "p_note": nullableString(note),
                "p_entry_date": SendableValue.string(FacilityTime.isoDateText(entryDate))
            ]
        )
        return challengeEntry(from: row, memberName: profile?.fullName)
    }

    func fetchChallengeLeaderboard(challengeID: UUID) async throws -> [ChallengeLeaderboardEntry] {
        let rows: [ChallengeLeaderboardRow] = try await request(
            path: "/rest/v1/rpc/wellbeing_challenge_leaderboard",
            method: "POST",
            body: ["p_challenge_id": SendableValue.string(challengeID.uuidString)]
        )
        return rows.map {
            ChallengeLeaderboardEntry(
                userID: $0.userID,
                memberName: $0.memberName,
                totalValue: $0.totalValue,
                entryCount: $0.entryCount,
                rank: $0.rank
            )
        }
    }

    func fetchReportSummary(startDate: Date, endDate: Date) async throws -> AdminReportSummary {
        let rows: [ReportSummaryRow] = try await request(
            path: "/rest/v1/rpc/admin_report_summary",
            method: "POST",
            body: [
                "p_start_date": SendableValue.string(FacilityTime.isoDateText(startDate)),
                "p_end_date": SendableValue.string(FacilityTime.isoDateText(endDate))
            ]
        )
        guard let row = rows.first else { return .empty }
        return AdminReportSummary(
            totalBookings: row.totalBookings,
            activeMembers: row.activeMembers,
            attendedCount: row.attendedCount,
            noShowCount: row.noShowCount,
            cancelledCount: row.cancelledCount,
            peakHour: row.peakHour
        )
    }

    func fetchBookingExport(startDate: Date, endDate: Date) async throws -> [BookingExportRow] {
        let rows: [BookingExportRowDTO] = try await request(
            path: "/rest/v1/rpc/admin_bookings_export",
            method: "POST",
            body: [
                "p_start_date": SendableValue.string(FacilityTime.isoDateText(startDate)),
                "p_end_date": SendableValue.string(FacilityTime.isoDateText(endDate))
            ]
        )
        return rows.map {
            BookingExportRow(
                bookingID: $0.bookingID,
                memberName: $0.memberName ?? "Member",
                email: $0.email ?? "",
                startTime: $0.startTime,
                endTime: $0.endTime,
                cancelledAt: $0.cancelledAt,
                checkedInAt: $0.checkedInAt,
                checkedOutAt: $0.checkedOutAt,
                noShowMarkedAt: $0.noShowMarkedAt
            )
        }
    }

    func fetchAuditLog(limit: Int) async throws -> [AuditLogEntry] {
        let rows: [AuditRow] = try await request(
            path: "/rest/v1/audit_log",
            queryItems: [
                URLQueryItem(name: "select", value: "id,actor_id,action,target_type,target_id,created_at"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ],
            method: "GET"
        )
        return rows.map {
            AuditLogEntry(
                id: $0.id,
                actorID: $0.actorID,
                action: $0.action,
                targetType: $0.targetType,
                targetID: $0.targetID ?? "",
                createdAt: $0.createdAt
            )
        }
    }

    private func fetchCurrentProfile() async throws -> UserProfile {
        guard let userID = authSession?.userID else { throw BookingError.unauthenticated }
        let rows: [ProfileRow] = try await request(
            path: "/rest/v1/profiles",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            method: "GET"
        )
        guard let row = rows.first else { throw BookingError.unauthenticated }
        return profile(from: row)
    }

    private func fetchProfileNames(for userIDs: [UUID]) async throws -> [UUID: String] {
        let uniqueIDs = Array(Set(userIDs))
        guard !uniqueIDs.isEmpty else { return [:] }
        let idList = uniqueIDs.map(\.uuidString).joined(separator: ",")
        let rows: [ProfileRow] = try await request(
            path: "/rest/v1/profiles",
            queryItems: [
                URLQueryItem(name: "select", value: "id,full_name,email"),
                URLQueryItem(name: "id", value: "in.(\(idList))")
            ],
            method: "GET"
        )
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.fullName ?? $0.email ?? "Member") })
    }

    private func profile(from row: ProfileRow) -> UserProfile {
        UserProfile(
            id: row.id,
            fullName: row.fullName?.isEmpty == false ? row.fullName! : "Fenix Staff",
            email: row.email ?? "",
            phone: row.phone ?? "",
            role: UserProfile.Role(rawValue: row.role ?? "") ?? .member,
            accessStatus: UserProfile.AccessStatus(rawValue: row.accessStatus ?? "") ?? .pending,
            inductionCompletedAt: row.inductionCompletedAt,
            inductionCompletedBy: row.inductionCompletedBy,
            lastSeenAt: row.lastSeenAt
        )
    }

    private func openingHours(from row: OpeningHoursRow) -> OpeningHours {
        OpeningHours(
            weekday: row.weekday,
            opensAtMinutes: minutes(fromDatabaseTime: row.opensAt),
            closesAtMinutes: minutes(fromDatabaseTime: row.closesAt),
            isClosed: row.isClosed
        )
    }

    private func contact(from row: FacilityContactRow) -> FacilityContact {
        FacilityContact(
            displayName: row.displayName,
            address: row.address ?? "",
            phone: row.phone ?? "",
            email: row.email ?? "",
            notes: row.notes ?? ""
        )
    }

    private func acknowledgement(from row: AcknowledgementRow) -> WellnessAcknowledgement {
        WellnessAcknowledgement(
            id: row.id,
            version: row.version,
            title: row.title,
            body: row.body,
            capacityText: row.capacityText ?? "",
            fairUseText: row.fairUseText ?? "",
            medicalText: row.medicalText ?? "",
            isActive: row.isActive,
            publishedAt: row.publishedAt,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt
        )
    }

    private func acknowledgementAcceptance(from row: AcknowledgementAcceptanceRow) -> WellnessAcknowledgementAcceptance {
        WellnessAcknowledgementAcceptance(
            acknowledgementID: row.acknowledgementID,
            version: row.version,
            acceptedAt: row.acceptedAt
        )
    }

    private func blackout(from row: BlackoutPeriodRow) -> BlackoutPeriod {
        BlackoutPeriod(
            id: row.id,
            startsAt: row.startsAt,
            endsAt: row.endsAt,
            reason: row.reason,
            createdAt: row.createdAt
        )
    }

    private func resource(from row: ResourceRow) -> WellnessResource {
        WellnessResource(
            id: row.id,
            title: row.title,
            description: row.description ?? "",
            category: row.category,
            resourceType: ResourceKind(rawValue: row.resourceType) ?? .link,
            url: row.url ?? "",
            storagePath: row.storagePath ?? "",
            isPublished: row.isPublished,
            createdAt: row.createdAt
        )
    }

    private func program(from row: ProgramRow, memberName: String?) -> ProgramAssignment {
        ProgramAssignment(
            id: row.id,
            userID: row.userID,
            memberName: memberName ?? "Member",
            title: row.title,
            description: row.description ?? "",
            resourceType: ResourceKind(rawValue: row.resourceType) ?? .link,
            url: row.url ?? "",
            storagePath: row.storagePath ?? "",
            assignedAt: row.assignedAt,
            archivedAt: row.archivedAt
        )
    }

    private func challenge(from row: ChallengeRow) -> WellbeingChallenge {
        WellbeingChallenge(
            id: row.id,
            title: row.title,
            description: row.description ?? "",
            challengeType: row.challengeType,
            metricName: row.metricName,
            metricUnit: row.metricUnit ?? "",
            targetValue: row.targetValue,
            startsOn: dateOnly(from: row.startsOn),
            endsOn: dateOnly(from: row.endsOn),
            rules: row.rules ?? "",
            leaderboardVisible: row.leaderboardVisible,
            isPublished: row.isPublished,
            createdAt: row.createdAt
        )
    }

    private func participant(from row: ChallengeParticipantRow) async throws -> ChallengeParticipant {
        let names = try await fetchProfileNames(for: [row.userID])
        return ChallengeParticipant(
            id: row.id,
            challengeID: row.challengeID,
            userID: row.userID,
            memberName: names[row.userID] ?? "Member",
            joinedAt: row.joinedAt
        )
    }

    private func challengeEntry(from row: ChallengeEntryRow, memberName: String?) -> ChallengeEntry {
        ChallengeEntry(
            id: row.id,
            challengeID: row.challengeID,
            userID: row.userID,
            memberName: memberName ?? "Member",
            value: row.value,
            note: row.note ?? "",
            entryDate: dateOnly(from: row.entryDate),
            createdAt: row.createdAt
        )
    }

    private func challengeBody(_ challenge: WellbeingChallenge, title overrideTitle: String? = nil) -> [String: SendableValue] {
        [
            "title": .string(overrideTitle ?? challenge.title.trimmingCharacters(in: .whitespacesAndNewlines)),
            "description": nullableString(challenge.description),
            "challenge_type": .string(challenge.challengeType.trimmingCharacters(in: .whitespacesAndNewlines)),
            "metric_name": .string(challenge.metricName.trimmingCharacters(in: .whitespacesAndNewlines)),
            "metric_unit": nullableString(challenge.metricUnit),
            "target_value": challenge.targetValue.map(SendableValue.double) ?? .null,
            "starts_on": .string(FacilityTime.isoDateText(challenge.startsOn)),
            "ends_on": .string(FacilityTime.isoDateText(challenge.endsOn)),
            "rules": nullableString(challenge.rules),
            "leaderboard_visible": .bool(challenge.leaderboardVisible),
            "is_published": .bool(challenge.isPublished)
        ]
    }

    private func nullableString(_ value: String) -> SendableValue {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? .null : .string(clean)
    }

    private func dateOnly(from value: String) -> Date {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        return FacilityTime.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? Date()
    }

    private func minutes(fromDatabaseTime value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return 0 }
        return min(max(parts[0] * 60 + parts[1], 0), 24 * 60)
    }

    private func timeDatabaseText(minutes: Int) -> String {
        let clamped = min(max(minutes, 0), 24 * 60)
        return String(format: "%02d:%02d:00", clamped / 60, clamped % 60)
    }

    private func booking(from row: BookingRow, memberName: String?) -> GymBooking {
        GymBooking(
            id: row.id,
            userID: row.userID,
            memberName: memberName ?? "Member",
            startTime: row.startTime,
            endTime: row.endTime,
            cancelledAt: row.cancelledAt,
            createdAt: row.createdAt,
            checkedInAt: row.checkedInAt,
            checkedOutAt: row.checkedOutAt,
            noShowMarkedAt: row.noShowMarkedAt
        )
    }

    private func store(_ response: AuthResponse) throws {
        guard let accessToken = response.accessToken, let userID = response.user?.id else {
            throw BookingError.unauthenticated
        }
        let session = AuthSession(accessToken: accessToken, refreshToken: response.refreshToken, userID: userID)
        authSession = session
        try writeStoredSession(session)
    }

    private func restoreStoredSession() {
        if let data = readStoredSessionData() {
            authSession = try? JSONDecoder().decode(AuthSession.self, from: data)
            return
        }
        guard
            let legacyData = UserDefaults.standard.data(forKey: sessionStorageKey),
            let legacySession = try? JSONDecoder().decode(AuthSession.self, from: legacyData)
        else { return }
        authSession = legacySession
        try? writeStoredSession(legacySession)
        UserDefaults.standard.removeObject(forKey: sessionStorageKey)
    }

    private func clearStoredSession() {
        authSession = nil
        try? deleteStoredSession()
        UserDefaults.standard.removeObject(forKey: sessionStorageKey)
    }

    private func recoveryParameters(from url: URL) -> [String: String] {
        var output: [String: String] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems?.forEach { item in
                output[item.name] = item.value
            }
        }
        if let fragment = url.fragment,
           let fragmentComponents = URLComponents(string: "fenix://fragment?\(fragment)") {
            fragmentComponents.queryItems?.forEach { item in
                output[item.name] = item.value
            }
        }
        return output
    }

    private func userID(fromJWT token: String) -> UUID? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }
        guard
            let data = Data(base64Encoded: payload),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sub = json["sub"] as? String
        else {
            return nil
        }
        return UUID(uuidString: sub)
    }

    private func readStoredSessionData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: sessionStorageKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    private func writeStoredSession(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: sessionStorageKey
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else {
                throw BookingError.remote("Could not store session securely.")
            }
        } else if status != errSecSuccess {
            throw BookingError.remote("Could not update stored session.")
        }
    }

    private func deleteStoredSession() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: sessionStorageKey
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw BookingError.remote("Could not clear stored session.")
        }
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: Body,
        requiresAuth: Bool = true
    ) async throws -> Response {
        var request = try makeRequest(path: path, queryItems: queryItems, method: method, requiresAuth: requiresAuth)
        request.httpBody = try encoder.encode(body)
        return try await sendWithRefresh(request, requiresAuth: requiresAuth)
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        requiresAuth: Bool = true
    ) async throws -> Response {
        let request = try makeRequest(path: path, queryItems: queryItems, method: method, requiresAuth: requiresAuth)
        return try await sendWithRefresh(request, requiresAuth: requiresAuth)
    }

    private func requestWithoutResponse<Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: Body,
        requiresAuth: Bool = true
    ) async throws {
        var request = try makeRequest(path: path, queryItems: queryItems, method: method, requiresAuth: requiresAuth)
        request.httpBody = try encoder.encode(body)
        try await sendEmptyWithRefresh(request, requiresAuth: requiresAuth)
    }

    private func requestWithoutResponse(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        requiresAuth: Bool = true
    ) async throws {
        let request = try makeRequest(path: path, queryItems: queryItems, method: method, requiresAuth: requiresAuth)
        try await sendEmptyWithRefresh(request, requiresAuth: requiresAuth)
    }

    private func makeRequest(
        path: String,
        queryItems: [URLQueryItem],
        method: String,
        requiresAuth: Bool
    ) throws -> URLRequest {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(url: baseURL.appendingPathComponent(cleanPath), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw BookingError.rulesUnavailable }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if requiresAuth {
            guard let accessToken = authSession?.accessToken else { throw BookingError.unauthenticated }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BookingError.rulesUnavailable
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let error = try? decoder.decode(SupabaseError.self, from: data) {
                throw BookingError.remote(error.bestMessage)
            }
            throw BookingError.remote("Supabase request failed with status \(httpResponse.statusCode).")
        }

        return try decoder.decode(Response.self, from: data)
    }

    private func sendWithRefresh<Response: Decodable>(_ request: URLRequest, requiresAuth: Bool) async throws -> Response {
        do {
            return try await send(request)
        } catch let error as BookingError where requiresAuth && error.needsSessionRefresh {
            try await refreshSession()
            var retry = request
            if let accessToken = authSession?.accessToken {
                retry.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            return try await send(retry)
        }
    }

    private func sendEmptyWithRefresh(_ request: URLRequest, requiresAuth: Bool) async throws {
        do {
            try await sendEmpty(request)
        } catch let error as BookingError where requiresAuth && error.needsSessionRefresh {
            try await refreshSession()
            var retry = request
            if let accessToken = authSession?.accessToken {
                retry.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            try await sendEmpty(retry)
        }
    }

    private func sendEmpty(_ request: URLRequest) async throws {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BookingError.rulesUnavailable
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let error = try? decoder.decode(SupabaseError.self, from: data) {
                throw BookingError.remote(error.bestMessage)
            }
            throw BookingError.remote("Supabase request failed with status \(httpResponse.statusCode).")
        }
    }

    private func refreshSession() async throws {
        guard let refreshToken = authSession?.refreshToken else {
            clearStoredSession()
            throw BookingError.unauthenticated
        }
        var request = try makeRequest(
            path: "/auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            method: "POST",
            requiresAuth: false
        )
        request.httpBody = try encoder.encode(["refresh_token": refreshToken])
        let response: AuthResponse = try await send(request)
        try store(response)
    }
}

private extension BookingError {
    var needsSessionRefresh: Bool {
        switch self {
        case .unauthenticated:
            return true
        case let .remote(message):
            let lowercased = message.lowercased()
            return lowercased.contains("jwt expired") ||
                lowercased.contains("invalid jwt") ||
                lowercased.contains("invalid token")
        default:
            return false
        }
    }
}

private enum SendableValue: Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case intArray([Int])
    case bool(Bool)
    case null
    case object([String: SendableValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .intArray(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case let .object(value):
            try container.encode(value)
        }
    }
}

private struct EmptyRequestBody: Encodable {}

private extension Date {
    static let supabaseISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let supabaseISOFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension FacilityTime {
    static func isoDateText(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
