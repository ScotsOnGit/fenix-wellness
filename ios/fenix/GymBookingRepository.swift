//
//  GymBookingRepository.swift
//  fenix
//
//  Created by Codex on 5/6/2026.
//

import Foundation

protocol GymBookingRepository {
    func restoreSession() async throws -> UserProfile?
    func signIn(email: String, password: String) async throws -> UserProfile
    func register(fullName: String, email: String, password: String, phone: String) async throws -> UserProfile
    func resetPassword(email: String) async throws
    func handlePasswordRecovery(url: URL) async throws -> UserProfile
    func updateProfile(fullName: String, phone: String) async throws -> UserProfile
    func updatePassword(currentPassword: String, newPassword: String) async throws
    func signOut() async throws
    func fetchRules() async throws -> FacilityRules
    func updateRules(_ rules: FacilityRules) async throws -> FacilityRules
    func fetchOpeningHours() async throws -> [OpeningHours]
    func updateOpeningHours(_ openingHours: [OpeningHours]) async throws -> [OpeningHours]
    func fetchFacilityContact() async throws -> FacilityContact
    func updateFacilityContact(_ contact: FacilityContact) async throws -> FacilityContact
    func fetchActiveAcknowledgement() async throws -> WellnessAcknowledgement
    func fetchMyAcknowledgementAcceptance() async throws -> WellnessAcknowledgementAcceptance?
    func acceptAcknowledgement(_ acknowledgement: WellnessAcknowledgement) async throws -> WellnessAcknowledgementAcceptance
    func publishAcknowledgement(title: String, body: String, capacityText: String, fairUseText: String, medicalText: String) async throws -> WellnessAcknowledgement
    func fetchBlackoutPeriods() async throws -> [BlackoutPeriod]
    func createBlackoutPeriod(startsAt: Date, endsAt: Date, reason: String) async throws -> BlackoutPeriod
    func deleteBlackoutPeriod(_ blackout: BlackoutPeriod) async throws
    func fetchAdminProfiles() async throws -> [UserProfile]
    func promoteAdmin(email: String) async throws -> UserProfile
    func demoteAdmin(_ admin: UserProfile) async throws
    func searchMembers(query: String) async throws -> [UserProfile]
    func updateMemberAccess(_ member: UserProfile, accessStatus: UserProfile.AccessStatus, inductionComplete: Bool) async throws -> UserProfile
    func deleteRemovedMemberLogin(_ member: UserProfile) async throws
    func fetchAvailability(for date: Date, durationMinutes: Int) async throws -> [AvailabilitySlot]
    func createBooking(startTime: Date, durationMinutes: Int) async throws -> GymBooking
    func fetchBookings() async throws -> [GymBooking]
    func cancelBooking(_ booking: GymBooking) async throws -> GymBooking
    func fetchAdminBookings(for date: Date) async throws -> [GymBooking]
    func fetchMemberBookings(userID: UUID, limit: Int) async throws -> [GymBooking]
    func checkIn(code: String) async throws -> GymBooking
    func checkOut(booking: GymBooking) async throws -> GymBooking
    func markDueNoShows() async throws -> Int
    func fetchResources() async throws -> [WellnessResource]
    func uploadWellnessPDF(data: Data, fileName: String) async throws -> String
    func signedURL(forStoragePath storagePath: String) async throws -> URL
    func createResource(title: String, description: String, category: String, type: ResourceKind, url: String, storagePath: String, isPublished: Bool) async throws -> WellnessResource
    func updateResource(_ resource: WellnessResource) async throws -> WellnessResource
    func deleteResource(_ resource: WellnessResource) async throws
    func fetchPrograms(for userID: UUID?) async throws -> [ProgramAssignment]
    func createProgram(userID: UUID, title: String, description: String, type: ResourceKind, url: String, storagePath: String) async throws -> ProgramAssignment
    func archiveProgram(_ program: ProgramAssignment) async throws
    func fetchChallenges(includeDrafts: Bool) async throws -> [WellbeingChallenge]
    func createChallenge(_ challenge: WellbeingChallenge) async throws -> WellbeingChallenge
    func updateChallenge(_ challenge: WellbeingChallenge) async throws -> WellbeingChallenge
    func deleteChallenge(_ challenge: WellbeingChallenge) async throws
    func joinChallenge(_ challenge: WellbeingChallenge) async throws -> ChallengeParticipant
    func fetchChallengeEntries(challengeID: UUID, userID: UUID?) async throws -> [ChallengeEntry]
    func addChallengeEntry(challengeID: UUID, value: Double, note: String, entryDate: Date) async throws -> ChallengeEntry
    func fetchChallengeLeaderboard(challengeID: UUID) async throws -> [ChallengeLeaderboardEntry]
    func fetchReportSummary(startDate: Date, endDate: Date) async throws -> AdminReportSummary
    func fetchBookingExport(startDate: Date, endDate: Date) async throws -> [BookingExportRow]
    func fetchAuditLog(limit: Int) async throws -> [AuditLogEntry]
}

@MainActor
final class MockGymBookingRepository: GymBookingRepository {
    private let userID = UUID(uuidString: "FEE00000-0000-4000-8000-000000000001")!
    private let adminID = UUID(uuidString: "FEE00000-0000-4000-8000-000000000002")!
    private var signedInProfile: UserProfile?
    private var bookings: [GymBooking]
    private var rules = FacilityRules.fenixDefault
    private var openingHours = OpeningHours.fenixDefaultWeek
    private var facilityContact = FacilityContact.fenixDefault
    private var activeAcknowledgement = WellnessAcknowledgement.fallback
    private var acknowledgementAcceptances: [UUID: WellnessAcknowledgementAcceptance] = [:]
    private var blackoutPeriods: [BlackoutPeriod] = []
    private var profiles: [UserProfile] = []
    private var resources: [WellnessResource] = []
    private var programs: [ProgramAssignment] = []
    private var challenges: [WellbeingChallenge] = []
    private var challengeParticipants: [ChallengeParticipant] = []
    private var challengeEntries: [ChallengeEntry] = []
    private var auditLog: [AuditLogEntry] = []
    private let historyBookingLimit = 30

    init() {
        let calendar = FacilityTime.calendar
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? Date()
        let start = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: tomorrow) ?? tomorrow
        let end = calendar.date(byAdding: .minute, value: 45, to: start) ?? start

        profiles = [
            UserProfile(
                id: userID,
                fullName: "Michael Fullarton",
                email: "michael@example.com",
                phone: "0400 000 000",
                role: .member,
                accessStatus: .active,
                inductionCompletedAt: Date()
            ),
            UserProfile(
                id: adminID,
                fullName: "Fenix Admin",
                email: "admin@fenix.com.au",
                phone: "",
                role: .admin,
                accessStatus: .active,
                inductionCompletedAt: Date()
            )
        ]

        bookings = [
            GymBooking(
                id: UUID(),
                userID: userID,
                memberName: "Michael Fullarton",
                startTime: start,
                endTime: end,
                cancelledAt: nil,
                createdAt: Date(),
                checkedInAt: nil,
                checkedOutAt: nil,
                noShowMarkedAt: nil
            )
        ]

        challenges = [
            WellbeingChallenge(
                id: UUID(),
                title: "June Step Challenge",
                description: "Log your steps and keep each other moving.",
                challengeType: "Steps",
                metricName: "Steps",
                metricUnit: "steps",
                targetValue: 100_000,
                startsOn: today,
                endsOn: calendar.date(byAdding: .day, value: 14, to: today) ?? today,
                rules: "Enter progress manually. Totals appear on the leaderboard while it is visible.",
                leaderboardVisible: true,
                isPublished: true,
                createdAt: Date()
            )
        ]
    }

    func restoreSession() async throws -> UserProfile? {
        try await shortDelay()
        return signedInProfile
    }

    func signIn(email: String, password: String) async throws -> UserProfile {
        try await shortDelay()
        let role: UserProfile.Role = email.lowercased().contains("admin") ? .admin : .member
        var profile = profiles.first { $0.role == role } ?? profiles[0]
        profile.email = email
        signedInProfile = profile
        return profile
    }

    func register(fullName: String, email: String, password: String, phone: String) async throws -> UserProfile {
        try await shortDelay()
        let profile = UserProfile(
            id: userID,
            fullName: fullName,
            email: email,
            phone: phone,
            role: .member,
            accessStatus: .pending,
            inductionCompletedAt: nil
        )
        profiles.append(profile)
        signedInProfile = profile
        return profile
    }

    func resetPassword(email: String) async throws {
        try await shortDelay()
    }

    func handlePasswordRecovery(url: URL) async throws -> UserProfile {
        try await shortDelay()
        let profile = profiles.first { $0.role == .member } ?? profiles[0]
        signedInProfile = profile
        return profile
    }

    func updateProfile(fullName: String, phone: String) async throws -> UserProfile {
        try await shortDelay()
        guard var profile = signedInProfile else { throw BookingError.unauthenticated }
        profile.fullName = fullName
        profile.phone = phone
        signedInProfile = profile
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        }
        return profile
    }

    func updatePassword(currentPassword: String, newPassword: String) async throws {
        try await shortDelay()
    }

    func signOut() async throws {
        try await shortDelay()
        signedInProfile = nil
    }

    func fetchRules() async throws -> FacilityRules {
        try await shortDelay()
        return rules
    }

    func updateRules(_ rules: FacilityRules) async throws -> FacilityRules {
        try await shortDelay()
        self.rules = rules
        return rules
    }

    func fetchOpeningHours() async throws -> [OpeningHours] {
        try await shortDelay()
        return openingHours.sorted { $0.weekday < $1.weekday }
    }

    func updateOpeningHours(_ openingHours: [OpeningHours]) async throws -> [OpeningHours] {
        try await shortDelay()
        self.openingHours = openingHours.sorted { $0.weekday < $1.weekday }
        return self.openingHours
    }

    func fetchFacilityContact() async throws -> FacilityContact {
        try await shortDelay()
        return facilityContact
    }

    func updateFacilityContact(_ contact: FacilityContact) async throws -> FacilityContact {
        try await shortDelay()
        facilityContact = contact
        return contact
    }

    func fetchActiveAcknowledgement() async throws -> WellnessAcknowledgement {
        try await shortDelay()
        return activeAcknowledgement
    }

    func fetchMyAcknowledgementAcceptance() async throws -> WellnessAcknowledgementAcceptance? {
        try await shortDelay()
        guard let userID = signedInProfile?.id else { return nil }
        return acknowledgementAcceptances[userID]
    }

    func acceptAcknowledgement(_ acknowledgement: WellnessAcknowledgement) async throws -> WellnessAcknowledgementAcceptance {
        try await shortDelay()
        guard let userID = signedInProfile?.id else { throw BookingError.unauthenticated }
        let acceptance = WellnessAcknowledgementAcceptance(
            acknowledgementID: acknowledgement.id,
            version: acknowledgement.version,
            acceptedAt: Date()
        )
        acknowledgementAcceptances[userID] = acceptance
        return acceptance
    }

    func publishAcknowledgement(title: String, body: String, capacityText: String, fairUseText: String, medicalText: String) async throws -> WellnessAcknowledgement {
        try await shortDelay()
        activeAcknowledgement = WellnessAcknowledgement(
            id: UUID(),
            version: "v\(Int(Date().timeIntervalSince1970))",
            title: title,
            body: body,
            capacityText: capacityText,
            fairUseText: fairUseText,
            medicalText: medicalText,
            isActive: true,
            publishedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )
        return activeAcknowledgement
    }

    func fetchBlackoutPeriods() async throws -> [BlackoutPeriod] {
        try await shortDelay()
        return blackoutPeriods.sorted { $0.startsAt < $1.startsAt }
    }

    func createBlackoutPeriod(startsAt: Date, endsAt: Date, reason: String) async throws -> BlackoutPeriod {
        try await shortDelay()
        let blackout = BlackoutPeriod(
            id: UUID(),
            startsAt: startsAt,
            endsAt: endsAt,
            reason: reason,
            createdAt: Date()
        )
        blackoutPeriods.append(blackout)
        return blackout
    }

    func deleteBlackoutPeriod(_ blackout: BlackoutPeriod) async throws {
        try await shortDelay()
        blackoutPeriods.removeAll { $0.id == blackout.id }
    }

    func fetchAdminProfiles() async throws -> [UserProfile] {
        try await shortDelay()
        return [
            profiles.first { $0.id == adminID } ?? UserProfile(id: adminID, fullName: "Fenix Admin", email: "admin@fenix.com.au", phone: "", role: .admin)
        ]
    }

    func promoteAdmin(email: String) async throws -> UserProfile {
        try await shortDelay()
        guard let index = profiles.firstIndex(where: { $0.email.caseInsensitiveCompare(email) == .orderedSame }) else {
            throw BookingError.remote("No registered staff account found for \(email).")
        }
        profiles[index].role = .admin
        audit(action: "admin_added", targetType: "profile", targetID: profiles[index].id.uuidString)
        return profiles[index]
    }

    func demoteAdmin(_ admin: UserProfile) async throws {
        try await shortDelay()
        guard let index = profiles.firstIndex(where: { $0.id == admin.id }) else { return }
        profiles[index].role = .member
        audit(action: "admin_removed", targetType: "profile", targetID: admin.id.uuidString)
    }

    func searchMembers(query: String) async throws -> [UserProfile] {
        try await shortDelay()
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let members = profiles.filter { $0.role == .member }
        guard !cleanQuery.isEmpty else {
            return members.sorted { $0.fullName < $1.fullName }
        }
        return members
            .filter { profile in
                profile.fullName.lowercased().contains(cleanQuery) ||
                    profile.email.lowercased().contains(cleanQuery) ||
                    profile.phone.lowercased().contains(cleanQuery)
            }
            .sorted { $0.fullName < $1.fullName }
    }

    func updateMemberAccess(_ member: UserProfile, accessStatus: UserProfile.AccessStatus, inductionComplete: Bool) async throws -> UserProfile {
        try await shortDelay()
        guard let index = profiles.firstIndex(where: { $0.id == member.id }) else {
            throw BookingError.remote("Member profile not found.")
        }
        profiles[index].accessStatus = accessStatus
        profiles[index].inductionCompletedAt = inductionComplete ? (profiles[index].inductionCompletedAt ?? Date()) : nil
        if accessStatus == .removed {
            profiles[index].inductionCompletedAt = nil
            let now = Date()
            for bookingIndex in bookings.indices where bookings[bookingIndex].userID == member.id && bookings[bookingIndex].cancelledAt == nil && bookings[bookingIndex].startTime > now {
                bookings[bookingIndex].cancelledAt = now
            }
            for programIndex in programs.indices where programs[programIndex].userID == member.id && programs[programIndex].archivedAt == nil {
                programs[programIndex].archivedAt = now
            }
        }
        if signedInProfile?.id == member.id {
            signedInProfile = profiles[index]
        }
        audit(action: accessStatus == .removed ? "member_access_removed" : "profile_access_changed", targetType: "profile", targetID: member.id.uuidString)
        return profiles[index]
    }

    func deleteRemovedMemberLogin(_ member: UserProfile) async throws {
        try await shortDelay()
        guard member.accessStatus == .removed else {
            throw BookingError.remote("Remove this member's access before deleting their login account.")
        }
        guard member.role == .member else {
            throw BookingError.remote("Admin accounts cannot be deleted from this screen.")
        }
        profiles.removeAll { $0.id == member.id }
        let now = Date()
        for bookingIndex in bookings.indices where bookings[bookingIndex].userID == member.id && bookings[bookingIndex].cancelledAt == nil && bookings[bookingIndex].startTime > now {
            bookings[bookingIndex].cancelledAt = now
        }
        for programIndex in programs.indices where programs[programIndex].userID == member.id && programs[programIndex].archivedAt == nil {
            programs[programIndex].archivedAt = now
        }
        audit(action: "member_auth_deleted", targetType: "profile", targetID: member.id.uuidString)
    }

    func fetchAvailability(for date: Date, durationMinutes: Int) async throws -> [AvailabilitySlot] {
        try await shortDelay()

        let calendar = FacilityTime.calendar
        let now = Date()
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        guard day >= today else { return [] }

        guard let hours = openingHours.first(where: { $0.weekday == calendar.component(.weekday, from: day) - 1 }), !hours.isClosed else {
            return []
        }
        let opening = calendar.date(byAdding: .minute, value: hours.opensAtMinutes, to: day) ?? day
        let closing = calendar.date(byAdding: .minute, value: hours.closesAtMinutes, to: day) ?? day
        var current = opening
        var slots: [AvailabilitySlot] = []

        while let end = calendar.date(byAdding: .minute, value: durationMinutes, to: current), end <= closing {
            if current >= now {
                let occupied = occupancy(for: current, durationMinutes: durationMinutes)
                slots.append(AvailabilitySlot(startTime: current, occupiedCount: occupied, capacity: rules.capacity))
            }
            current = calendar.date(byAdding: .minute, value: 15, to: current) ?? closing
        }

        return slots
    }

    func createBooking(startTime: Date, durationMinutes: Int) async throws -> GymBooking {
        try await shortDelay()
        guard let profile = signedInProfile else { throw BookingError.unauthenticated }
        guard profile.canBookWellnessSessions else { throw BookingError.accessPending }
        guard rules.allowedDurationsMinutes.contains(durationMinutes) else {
            throw BookingError.remote("Choose a 15, 30, or 45 minute session.")
        }
        guard occupancy(for: startTime, durationMinutes: durationMinutes) < rules.capacity else {
            throw BookingError.slotFull
        }
        guard let endTime = FacilityTime.calendar.date(byAdding: .minute, value: durationMinutes, to: startTime) else {
            throw BookingError.outsideOpeningHours
        }
        guard isInsideOpeningHours(startTime: startTime, endTime: endTime) else {
            throw BookingError.outsideOpeningHours
        }
        guard dailyActiveBooking(on: startTime, userID: profile.id) == nil else {
            throw BookingError.maxDailyBookings
        }
        guard futureActiveBookings(userID: profile.id).count < rules.maxFutureBookings else {
            throw BookingError.maxFutureBookings
        }

        let booking = GymBooking(
            id: UUID(),
            userID: profile.id,
            memberName: profile.fullName,
            startTime: startTime,
            endTime: endTime,
            cancelledAt: nil,
            createdAt: Date(),
            checkedInAt: nil,
            checkedOutAt: nil,
            noShowMarkedAt: nil
        )
        bookings.append(booking)
        return booking
    }

    func fetchBookings() async throws -> [GymBooking] {
        try await shortDelay()
        guard let profile = signedInProfile else { throw BookingError.unauthenticated }
        let userBookings = bookings
            .filter { $0.userID == profile.id }
        let upcoming = userBookings
            .filter { $0.status == .active }
            .sorted { $0.startTime < $1.startTime }
        let history = userBookings
            .filter { $0.status != .active }
            .sorted { $0.startTime > $1.startTime }
            .prefix(historyBookingLimit)
        return upcoming + history
    }

    func cancelBooking(_ booking: GymBooking) async throws -> GymBooking {
        try await shortDelay()
        guard booking.startTime.timeIntervalSince(Date()) > TimeInterval(rules.cancellationCutoffMinutes * 60) else {
            throw BookingError.cancellationCutoff
        }
        guard let index = bookings.firstIndex(where: { $0.id == booking.id }) else { return booking }
        bookings[index].cancelledAt = Date()
        return bookings[index]
    }

    func fetchAdminBookings(for date: Date) async throws -> [GymBooking] {
        try await shortDelay()
        let calendar = FacilityTime.calendar
        return bookings
            .filter { calendar.isDate($0.startTime, inSameDayAs: date) }
            .sorted { $0.startTime < $1.startTime }
    }

    func fetchMemberBookings(userID: UUID, limit: Int) async throws -> [GymBooking] {
        try await shortDelay()
        return bookings
            .filter { $0.userID == userID }
            .sorted { $0.startTime > $1.startTime }
            .prefix(limit)
            .map { $0 }
    }

    func checkIn(code: String) async throws -> GymBooking {
        try await shortDelay()
        guard let profile = signedInProfile else { throw BookingError.unauthenticated }
        guard code.trimmingCharacters(in: .whitespacesAndNewlines) == "FENIX-WELLNESS-CENTRE" else {
            throw BookingError.remote("This QR code is not valid for the wellness centre.")
        }
        guard let index = bookings.firstIndex(where: {
            $0.userID == profile.id &&
                $0.status == .active &&
                $0.cancelledAt == nil &&
                $0.startTime <= Date().addingTimeInterval(TimeInterval(rules.checkInWindowBeforeMinutes * 60)) &&
                $0.endTime >= Date()
        }) else {
            throw BookingError.remote("No active booking is available for check-in right now.")
        }
        bookings[index].checkedInAt = bookings[index].checkedInAt ?? Date()
        bookings[index].noShowMarkedAt = nil
        audit(action: "booking_checked_in", targetType: "booking", targetID: bookings[index].id.uuidString)
        return bookings[index]
    }

    func checkOut(booking: GymBooking) async throws -> GymBooking {
        try await shortDelay()
        guard let index = bookings.firstIndex(where: { $0.id == booking.id }) else {
            throw BookingError.remote("Booking not found.")
        }
        bookings[index].checkedOutAt = bookings[index].checkedOutAt ?? Date()
        audit(action: "booking_checked_out", targetType: "booking", targetID: booking.id.uuidString)
        return bookings[index]
    }

    func markDueNoShows() async throws -> Int {
        try await shortDelay()
        var count = 0
        for index in bookings.indices where bookings[index].cancelledAt == nil &&
            bookings[index].checkedInAt == nil &&
            bookings[index].noShowMarkedAt == nil &&
            bookings[index].startTime < Date().addingTimeInterval(TimeInterval(-rules.checkInGraceMinutes * 60)) {
            bookings[index].noShowMarkedAt = Date()
            count += 1
        }
        if count > 0 {
            audit(action: "no_shows_marked", targetType: "booking", targetID: "")
        }
        return count
    }

    func fetchResources() async throws -> [WellnessResource] {
        try await shortDelay()
        return resources.filter { $0.isPublished || signedInProfile?.role == .admin }
    }

    func uploadWellnessPDF(data: Data, fileName: String) async throws -> String {
        try await shortDelay()
        return "mock/\(UUID().uuidString)-\(fileName)"
    }

    func signedURL(forStoragePath storagePath: String) async throws -> URL {
        try await shortDelay()
        return URL(string: "https://example.com/\(storagePath)")!
    }

    func createResource(title: String, description: String, category: String, type: ResourceKind, url: String, storagePath: String, isPublished: Bool) async throws -> WellnessResource {
        try await shortDelay()
        let resource = WellnessResource(id: UUID(), title: title, description: description, category: category, resourceType: type, url: url, storagePath: storagePath, isPublished: isPublished, createdAt: Date())
        resources.append(resource)
        audit(action: "resource_changed", targetType: "wellness_resource", targetID: resource.id.uuidString)
        return resource
    }

    func updateResource(_ resource: WellnessResource) async throws -> WellnessResource {
        try await shortDelay()
        if let index = resources.firstIndex(where: { $0.id == resource.id }) {
            resources[index] = resource
        }
        audit(action: "resource_changed", targetType: "wellness_resource", targetID: resource.id.uuidString)
        return resource
    }

    func deleteResource(_ resource: WellnessResource) async throws {
        try await shortDelay()
        resources.removeAll { $0.id == resource.id }
        audit(action: "resource_changed", targetType: "wellness_resource", targetID: resource.id.uuidString)
    }

    func fetchPrograms(for userID: UUID?) async throws -> [ProgramAssignment] {
        try await shortDelay()
        let targetID = userID ?? signedInProfile?.id
        return programs.filter { $0.archivedAt == nil && (signedInProfile?.role == .admin ? (targetID == nil || $0.userID == targetID) : $0.userID == targetID) }
    }

    func createProgram(userID: UUID, title: String, description: String, type: ResourceKind, url: String, storagePath: String) async throws -> ProgramAssignment {
        try await shortDelay()
        let memberName = profiles.first(where: { $0.id == userID })?.fullName ?? "Member"
        let program = ProgramAssignment(id: UUID(), userID: userID, memberName: memberName, title: title, description: description, resourceType: type, url: url, storagePath: storagePath, assignedAt: Date(), archivedAt: nil)
        programs.append(program)
        audit(action: "program_changed", targetType: "program_assignment", targetID: program.id.uuidString)
        return program
    }

    func archiveProgram(_ program: ProgramAssignment) async throws {
        try await shortDelay()
        if let index = programs.firstIndex(where: { $0.id == program.id }) {
            programs[index].archivedAt = Date()
        }
        audit(action: "program_changed", targetType: "program_assignment", targetID: program.id.uuidString)
    }

    func fetchChallenges(includeDrafts: Bool) async throws -> [WellbeingChallenge] {
        try await shortDelay()
        return challenges
            .filter { includeDrafts || $0.isPublished }
            .sorted { $0.startsOn > $1.startsOn }
    }

    func createChallenge(_ challenge: WellbeingChallenge) async throws -> WellbeingChallenge {
        try await shortDelay()
        let saved = WellbeingChallenge(
            id: UUID(),
            title: challenge.title,
            description: challenge.description,
            challengeType: challenge.challengeType,
            metricName: challenge.metricName,
            metricUnit: challenge.metricUnit,
            targetValue: challenge.targetValue,
            startsOn: challenge.startsOn,
            endsOn: challenge.endsOn,
            rules: challenge.rules,
            leaderboardVisible: challenge.leaderboardVisible,
            isPublished: challenge.isPublished,
            createdAt: Date()
        )
        challenges.append(saved)
        audit(action: "challenge_created", targetType: "wellbeing_challenge", targetID: saved.id.uuidString)
        return saved
    }

    func updateChallenge(_ challenge: WellbeingChallenge) async throws -> WellbeingChallenge {
        try await shortDelay()
        if let index = challenges.firstIndex(where: { $0.id == challenge.id }) {
            challenges[index] = challenge
        }
        audit(action: "challenge_updated", targetType: "wellbeing_challenge", targetID: challenge.id.uuidString)
        return challenge
    }

    func deleteChallenge(_ challenge: WellbeingChallenge) async throws {
        try await shortDelay()
        challenges.removeAll { $0.id == challenge.id }
        challengeParticipants.removeAll { $0.challengeID == challenge.id }
        challengeEntries.removeAll { $0.challengeID == challenge.id }
        audit(action: "challenge_deleted", targetType: "wellbeing_challenge", targetID: challenge.id.uuidString)
    }

    func joinChallenge(_ challenge: WellbeingChallenge) async throws -> ChallengeParticipant {
        try await shortDelay()
        guard let profile = signedInProfile else { throw BookingError.unauthenticated }
        if let existing = challengeParticipants.first(where: { $0.challengeID == challenge.id && $0.userID == profile.id }) {
            return existing
        }
        let participant = ChallengeParticipant(
            id: UUID(),
            challengeID: challenge.id,
            userID: profile.id,
            memberName: profile.fullName,
            joinedAt: Date()
        )
        challengeParticipants.append(participant)
        return participant
    }

    func fetchChallengeEntries(challengeID: UUID, userID: UUID?) async throws -> [ChallengeEntry] {
        try await shortDelay()
        return challengeEntries
            .filter { $0.challengeID == challengeID && (userID == nil || $0.userID == userID) }
            .sorted { $0.entryDate > $1.entryDate }
    }

    func addChallengeEntry(challengeID: UUID, value: Double, note: String, entryDate: Date) async throws -> ChallengeEntry {
        try await shortDelay()
        guard let profile = signedInProfile else { throw BookingError.unauthenticated }
        guard let challenge = challenges.first(where: { $0.id == challengeID }) else {
            throw BookingError.remote("Challenge not found.")
        }
        _ = try await joinChallenge(challenge)
        let entry = ChallengeEntry(
            id: UUID(),
            challengeID: challengeID,
            userID: profile.id,
            memberName: profile.fullName,
            value: value,
            note: note,
            entryDate: entryDate,
            createdAt: Date()
        )
        challengeEntries.append(entry)
        return entry
    }

    func fetchChallengeLeaderboard(challengeID: UUID) async throws -> [ChallengeLeaderboardEntry] {
        try await shortDelay()
        let grouped = Dictionary(grouping: challengeEntries.filter { $0.challengeID == challengeID }, by: \.userID)
        return grouped
            .map { userID, entries in
                ChallengeLeaderboardEntry(
                    userID: userID,
                    memberName: entries.first?.memberName ?? "Member",
                    totalValue: entries.reduce(0) { $0 + $1.value },
                    entryCount: entries.count,
                    rank: 0
                )
            }
            .sorted { $0.totalValue > $1.totalValue }
            .enumerated()
            .map { offset, entry in
                ChallengeLeaderboardEntry(
                    userID: entry.userID,
                    memberName: entry.memberName,
                    totalValue: entry.totalValue,
                    entryCount: entry.entryCount,
                    rank: offset + 1
                )
            }
    }

    func fetchReportSummary(startDate: Date, endDate: Date) async throws -> AdminReportSummary {
        try await shortDelay()
        let filtered = bookings.filter { $0.startTime >= startDate && $0.startTime <= endDate }
        let hours = Dictionary(grouping: filtered) { FacilityTime.calendar.component(.hour, from: $0.startTime) }
        let peak = hours.max { $0.value.count < $1.value.count }?.key ?? 0
        return AdminReportSummary(
            totalBookings: filtered.count,
            activeMembers: profiles.filter { $0.accessStatus == .active }.count,
            attendedCount: filtered.filter { $0.checkedInAt != nil }.count,
            noShowCount: filtered.filter { $0.noShowMarkedAt != nil }.count,
            cancelledCount: filtered.filter { $0.cancelledAt != nil }.count,
            peakHour: peak
        )
    }

    func fetchBookingExport(startDate: Date, endDate: Date) async throws -> [BookingExportRow] {
        try await shortDelay()
        return bookings
            .filter { $0.startTime >= startDate && $0.startTime <= endDate }
            .map { booking in
                let member = profiles.first { $0.id == booking.userID }
                return BookingExportRow(
                    bookingID: booking.id,
                    memberName: booking.memberName,
                    email: member?.email ?? "",
                    startTime: booking.startTime,
                    endTime: booking.endTime,
                    cancelledAt: booking.cancelledAt,
                    checkedInAt: booking.checkedInAt,
                    checkedOutAt: booking.checkedOutAt,
                    noShowMarkedAt: booking.noShowMarkedAt
                )
            }
    }

    func fetchAuditLog(limit: Int) async throws -> [AuditLogEntry] {
        try await shortDelay()
        return Array(auditLog.suffix(limit).reversed())
    }

    private func occupancy(for startTime: Date, durationMinutes: Int) -> Int {
        let activeBookings = bookings.filter { $0.cancelledAt == nil }
        let coveringBookings = activeBookings.filter { booking in
            booking.startTime <= startTime && booking.endTime > startTime
        }

        return coveringBookings.count
    }

    private func isInsideOpeningHours(startTime: Date, endTime: Date) -> Bool {
        let calendar = FacilityTime.calendar
        let day = calendar.startOfDay(for: startTime)
        guard
            calendar.isDate(startTime, inSameDayAs: endTime),
            let hours = openingHours.first(where: { $0.weekday == calendar.component(.weekday, from: day) - 1 }),
            !hours.isClosed,
            let opening = calendar.date(byAdding: .minute, value: hours.opensAtMinutes, to: day),
            let closing = calendar.date(byAdding: .minute, value: hours.closesAtMinutes, to: day)
        else {
            return false
        }
        return startTime >= opening && endTime <= closing
    }

    private func dailyActiveBooking(on date: Date, userID: UUID) -> GymBooking? {
        bookings.first { booking in
            booking.userID == userID &&
            booking.cancelledAt == nil &&
            FacilityTime.calendar.isDate(booking.startTime, inSameDayAs: date)
        }
    }

    private func futureActiveBookings(userID: UUID) -> [GymBooking] {
        bookings.filter { booking in
            booking.userID == userID &&
            booking.cancelledAt == nil &&
            booking.startTime > Date()
        }
    }

    private func shortDelay() async throws {
        try await Task.sleep(for: .milliseconds(180))
    }

    private func audit(action: String, targetType: String, targetID: String) {
        auditLog.append(AuditLogEntry(id: auditLog.count + 1, actorID: signedInProfile?.id, action: action, targetType: targetType, targetID: targetID, createdAt: Date()))
    }
}
