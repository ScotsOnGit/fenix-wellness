//
//  AppModel.swift
//  fenix
//
//  Created by Codex on 5/6/2026.
//

import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class AppModel {
    enum AuthMode {
        case signIn
        case register
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case failed(String)
    }

    enum AccountMessageScope: Equatable {
        case localUnlock
        case profile
        case bookingRules
        case openingHours
        case contact
        case blackouts
        case access
        case members
        case resources
        case challenges
        case reports
        case checkIn
        case acknowledgement
    }

    private let repository: GymBookingRepository
    private let localSecurity = LocalSecurityManager.shared
    private let reminders = SessionReminderManager.shared

    // Kept for migrating the first locally-stored acknowledgement into the newer
    // database-backed acknowledgement versioning system.
    static let wellnessAcknowledgementVersion = "2026-06-06-v1"

    var profile: UserProfile?
    var authMode: AuthMode = .signIn
    var rules: FacilityRules?
    var openingHours: [OpeningHours] = OpeningHours.fenixDefaultWeek
    var facilityContact = FacilityContact.fenixDefault
    var selectedDate = Date()
    var selectedDuration = 30
    var availability: [AvailabilitySlot] = []
    var selectedSlot: AvailabilitySlot?
    var bookings: [GymBooking] = []
    var adminBookings: [GymBooking] = []
    var adminProfiles: [UserProfile] = []
    var memberSearchResults: [UserProfile] = []
    var selectedMemberBookings: [GymBooking] = []
    var blackoutPeriods: [BlackoutPeriod] = []
    var resources: [WellnessResource] = []
    var myPrograms: [ProgramAssignment] = []
    var selectedMemberPrograms: [ProgramAssignment] = []
    var challenges: [WellbeingChallenge] = []
    var selectedChallengeEntries: [ChallengeEntry] = []
    var selectedChallengeLeaderboard: [ChallengeLeaderboardEntry] = []
    var reportSummary = AdminReportSummary.empty
    var bookingExportRows: [BookingExportRow] = []
    var auditLog: [AuditLogEntry] = []
    var loadState: LoadState = .idle
    var isRestoringSession = true
    var bookingMessage: String?
    var confirmationBooking: GymBooking?
    var activeAcknowledgement = WellnessAcknowledgement.fallback
    var acknowledgementAcceptance: WellnessAcknowledgementAcceptance?
    var hasAcceptedWellnessAcknowledgement = false
    var wellnessAcknowledgementAcceptedAt: Date?
    var authNotice: String?
    var passwordRecoveryActive = false
    var passwordRecoveryMessage: String?
    var localSecuritySettings = LocalSecuritySettings(faceIDEnabled: false, pinEnabled: false)
    var isLocallyUnlocked = true
    var accountMessage: String?
    var accountMessageScope: AccountMessageScope?

    var isSignedIn: Bool {
        profile != nil
    }

    var canShowAdmin: Bool {
        profile?.role == .admin
    }

    var shouldShowLocalUnlock: Bool {
        isSignedIn && localSecuritySettings.isEnabled && !isLocallyUnlocked
    }

    var localSecurityStatus: String {
        if localSecuritySettings.faceIDEnabled && localSecuritySettings.pinEnabled {
            return "\(localSecurity.biometryLabel) and PIN enabled"
        }
        if localSecuritySettings.faceIDEnabled {
            return "\(localSecurity.biometryLabel) enabled"
        }
        if localSecuritySettings.pinEnabled {
            return "PIN enabled"
        }
        return "Not enabled"
    }

    var biometryLabel: String {
        localSecurity.biometryLabel
    }

    var activeBookings: [GymBooking] {
        bookings.filter { $0.status == .active && $0.cancelledAt == nil }
    }

    var activeBookingForSelectedDate: GymBooking? {
        activeBookings.first { FacilityTime.calendar.isDate($0.startTime, inSameDayAs: selectedDate) }
    }

    var usedBookingForSelectedDate: GymBooking? {
        // The one-session-per-day rule applies after attendance too, so completed
        // sessions still block another same-day booking while cancelled sessions do not.
        bookings
            .filter { $0.cancelledAt == nil && FacilityTime.calendar.isDate($0.startTime, inSameDayAs: selectedDate) }
            .sorted { $0.startTime < $1.startTime }
            .first
    }

    var canReviewSelectedBooking: Bool {
        selectedSlot != nil && usedBookingForSelectedDate == nil && profile?.canBookWellnessSessions == true
    }

    var bookingUnavailableReason: String? {
        if let profile, !profile.canBookWellnessSessions {
            return "Your wellbeing facility access is pending admin induction approval."
        }
        if let booking = usedBookingForSelectedDate {
            switch booking.status {
            case .active:
                return "You already have a booking on this day: \(FacilityTime.intervalText(start: booking.startTime, end: booking.endTime)). Cancel it before booking another session."
            case .completed:
                return "You have already completed a session on this day."
            case .cancelled:
                break
            }
        }
        if selectedSlot == nil {
            return "Choose a start time to review your booking."
        }
        return nil
    }

    var selectedDateAvailabilityMessage: (title: String, message: String, systemImage: String)? {
        let calendar = FacilityTime.calendar
        let selectedDay = calendar.startOfDay(for: selectedDate)
        let today = calendar.startOfDay(for: Date())
        let horizon = calendar.startOfDay(for: dateRange.upperBound)

        if selectedDay > horizon {
            return (
                "Outside booking window",
                "Bookings can only be made up to \(rules?.bookingHorizonDays ?? FacilityRules.fenixDefault.bookingHorizonDays) days in advance.",
                "calendar.badge.exclamationmark"
            )
        }

        if let hours = selectedDateOpeningHours, hours.isClosed {
            return (
                "Facility closed",
                "The wellbeing facility is closed on this day. Choose another date.",
                "door.left.hand.closed"
            )
        }

        if selectedDay == today {
            return (
                "No sessions left today",
                "There are no remaining start times for the selected session length today.",
                "clock.badge.xmark"
            )
        }

        return (
            "No start times available",
            "No start times fit the selected date and session length. Try a shorter session or another day.",
            "calendar"
        )
    }

    var dateRange: ClosedRange<Date> {
        let calendar = FacilityTime.calendar
        let today = calendar.startOfDay(for: Date())
        let days = rules?.bookingHorizonDays ?? FacilityRules.fenixDefault.bookingHorizonDays
        let horizon = calendar.date(byAdding: .day, value: days, to: today) ?? today
        return today ... horizon
    }

    var selectedDateOpeningHours: OpeningHours? {
        let weekday = FacilityTime.calendar.component(.weekday, from: selectedDate) - 1
        return openingHours.first { $0.weekday == weekday }
    }

    init(repository: GymBookingRepository) {
        self.repository = repository
    }

    func restoreSession() async {
        isRestoringSession = true
        defer { isRestoringSession = false }

        do {
            profile = try await repository.restoreSession()
            if profile != nil {
                updateLocalSecurityState()
                if localSecuritySettings.isEnabled {
                    isLocallyUnlocked = false
                } else {
                    isLocallyUnlocked = true
                    await refreshAll()
                }
            }
        } catch {
            profile = nil
            loadState = .idle
            isLocallyUnlocked = true
        }
    }

    func signIn(email: String, password: String) async {
        await performLoading {
            profile = try await repository.signIn(email: email, password: password)
            authNotice = nil
            updateLocalSecurityState()
            isLocallyUnlocked = true
            try await refreshAfterAuth()
        }
    }

    func register(fullName: String, email: String, password: String, phone: String) async {
        await performLoading {
            profile = try await repository.register(fullName: fullName, email: email, password: password, phone: phone)
            authNotice = nil
            updateLocalSecurityState()
            isLocallyUnlocked = true
            try await refreshAfterAuth()
            _ = try await acceptActiveAcknowledgement()
        }
    }

    func resetPassword(email: String) async {
        await performLoading {
            try await repository.resetPassword(email: email)
            authNotice = "Password reset email sent. Check your inbox."
        }
    }

    func handlePasswordRecovery(url: URL) async {
        guard url.scheme == "fenixwellness" else { return }
        loadState = .loading
        do {
            profile = try await repository.handlePasswordRecovery(url: url)
            authNotice = nil
            passwordRecoveryActive = true
            passwordRecoveryMessage = nil
            updateLocalSecurityState()
            isLocallyUnlocked = true
            try await refreshAfterAuth()
            loadState = .idle
        } catch {
            passwordRecoveryActive = false
            passwordRecoveryMessage = error.localizedDescription
            loadState = .failed(error.localizedDescription)
        }
    }

    func completePasswordRecovery(newPassword: String) async {
        await performLoading {
            try await repository.updatePassword(currentPassword: "", newPassword: newPassword)
            passwordRecoveryActive = false
            passwordRecoveryMessage = "Password updated. You are signed in."
            setAccountMessage("Password updated.", scope: .profile)
        }
    }

    func signOut() async {
        let signedOutUserID = profile?.id
        await performLoading {
            try await repository.signOut()
            if let signedOutUserID {
                // Local unlock settings belong to the signed-in person, not the device
                // globally. Clearing them on sign-out avoids another user inheriting access.
                try? localSecurity.disableAll(for: signedOutUserID)
                reminders.cancelAll(for: signedOutUserID)
            }
            profile = nil
            availability = []
            bookings = []
            adminBookings = []
            adminProfiles = []
            blackoutPeriods = []
            memberSearchResults = []
            selectedMemberBookings = []
            resources = []
            myPrograms = []
            selectedMemberPrograms = []
            challenges = []
            selectedChallengeEntries = []
            selectedChallengeLeaderboard = []
            reportSummary = .empty
            bookingExportRows = []
            auditLog = []
            openingHours = OpeningHours.fenixDefaultWeek
            facilityContact = .fenixDefault
            selectedSlot = nil
            confirmationBooking = nil
            passwordRecoveryActive = false
            passwordRecoveryMessage = nil
            activeAcknowledgement = .fallback
            acknowledgementAcceptance = nil
            hasAcceptedWellnessAcknowledgement = false
            wellnessAcknowledgementAcceptedAt = nil
            localSecuritySettings = LocalSecuritySettings(faceIDEnabled: false, pinEnabled: false)
            isLocallyUnlocked = true
            clearAccountMessage()
        }
    }

    func unlockWithBiometrics() async {
        do {
            try await localSecurity.authenticateWithBiometrics(reason: "Unlock Fenix Wellbeing Facility")
            isLocallyUnlocked = true
            clearAccountMessage()
            await refreshAll()
        } catch {
            setAccountMessage(error.localizedDescription, scope: .localUnlock)
        }
    }

    func unlockWithPIN(_ pin: String) async {
        guard let userID = profile?.id else { return }
        do {
            if try localSecurity.verifyPIN(pin, for: userID) {
                isLocallyUnlocked = true
                clearAccountMessage()
                await refreshAll()
            } else {
                setAccountMessage(LocalSecurityError.invalidPIN.localizedDescription, scope: .localUnlock)
            }
        } catch {
            setAccountMessage(error.localizedDescription, scope: .localUnlock)
        }
    }

    func setFaceIDEnabled(_ isEnabled: Bool) {
        guard let userID = profile?.id else { return }
        do {
            localSecuritySettings = try localSecurity.setFaceIDEnabled(isEnabled, for: userID)
            setAccountMessage(isEnabled ? "\(biometryLabel) unlock enabled." : "\(biometryLabel) unlock disabled.", scope: .profile)
        } catch {
            setAccountMessage(error.localizedDescription, scope: .profile)
        }
    }

    func setPIN(_ pin: String) {
        guard let userID = profile?.id else { return }
        do {
            localSecuritySettings = try localSecurity.setPIN(pin, for: userID)
            setAccountMessage("PIN unlock enabled.", scope: .profile)
        } catch {
            setAccountMessage(error.localizedDescription, scope: .profile)
        }
    }

    func setPINEnabled(_ isEnabled: Bool) {
        guard let userID = profile?.id else { return }
        do {
            localSecuritySettings = try localSecurity.setPINEnabled(isEnabled, for: userID)
            setAccountMessage(isEnabled ? "PIN unlock enabled." : "PIN unlock disabled.", scope: .profile)
        } catch {
            setAccountMessage(error.localizedDescription, scope: .profile)
        }
    }

    func disableLocalSecurity() {
        guard let userID = profile?.id else { return }
        do {
            try localSecurity.disableAll(for: userID)
            updateLocalSecurityState()
            isLocallyUnlocked = true
            setAccountMessage("Face ID and PIN unlock disabled.", scope: .profile)
        } catch {
            setAccountMessage(error.localizedDescription, scope: .profile)
        }
    }

    func updateProfile(fullName: String, phone: String) async {
        await performLoading {
            profile = try await repository.updateProfile(fullName: fullName, phone: phone)
            setAccountMessage("Profile updated.", scope: .profile)
        }
    }

    func updatePassword(currentPassword: String, newPassword: String) async {
        await performLoading {
            try await repository.updatePassword(currentPassword: currentPassword, newPassword: newPassword)
            setAccountMessage("Password updated.", scope: .profile)
        }
    }

    func updateOpeningHours(_ hours: [OpeningHours]) async {
        await performLoading {
            openingHours = try await repository.updateOpeningHours(hours)
            availability = try await repository.fetchAvailability(for: selectedDate, durationMinutes: selectedDuration)
            setAccountMessage("Opening hours updated.", scope: .openingHours)
        }
    }

    func updateRules(_ rules: FacilityRules) async {
        await performLoading {
            self.rules = try await repository.updateRules(rules)
            availability = try await repository.fetchAvailability(for: selectedDate, durationMinutes: selectedDuration)
            setAccountMessage("Booking rules updated.", scope: .bookingRules)
        }
    }

    func updateFacilityContact(_ contact: FacilityContact) async {
        await performLoading {
            facilityContact = try await repository.updateFacilityContact(contact)
            setAccountMessage("Wellbeing facility contact details updated.", scope: .contact)
        }
    }

    func refreshBlackoutPeriods() async {
        do {
            blackoutPeriods = try await repository.fetchBlackoutPeriods()
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func createBlackoutPeriod(startsAt: Date, endsAt: Date, reason: String) async {
        await performLoading {
            guard startsAt < endsAt else {
                throw BookingError.remote("Blackout end time must be after the start time.")
            }
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BookingError.remote("Add a reason for this blackout period.")
            }
            _ = try await repository.createBlackoutPeriod(startsAt: startsAt, endsAt: endsAt, reason: reason)
            blackoutPeriods = try await repository.fetchBlackoutPeriods()
            availability = try await repository.fetchAvailability(for: selectedDate, durationMinutes: selectedDuration)
            setAccountMessage("Blackout period added.", scope: .blackouts)
        }
    }

    func deleteBlackoutPeriod(_ blackout: BlackoutPeriod) async {
        await performLoading {
            try await repository.deleteBlackoutPeriod(blackout)
            blackoutPeriods = try await repository.fetchBlackoutPeriods()
            availability = try await repository.fetchAvailability(for: selectedDate, durationMinutes: selectedDuration)
            setAccountMessage("Blackout period removed.", scope: .blackouts)
        }
    }

    func refreshAdminProfiles() async {
        guard canShowAdmin else { return }
        do {
            adminProfiles = try await repository.fetchAdminProfiles()
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func promoteAdmin(email: String) async -> Bool {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanEmail.contains("@") && cleanEmail.contains(".") else {
            setAccountMessage("Enter a valid email address.", scope: .access)
            return false
        }

        loadState = .loading
        do {
            let admin = try await repository.promoteAdmin(email: cleanEmail)
            adminProfiles = try await repository.fetchAdminProfiles()
            setAccountMessage("\(admin.email) now has admin access.", scope: .access)
            loadState = .idle
            return true
        } catch {
            loadState = .idle
            setAccountMessage(error.localizedDescription, scope: .access)
            return false
        }
    }

    func demoteAdmin(_ admin: UserProfile) async {
        await performLoading {
            try await repository.demoteAdmin(admin)
            adminProfiles = try await repository.fetchAdminProfiles()
            setAccountMessage("\(admin.email) is now a member.", scope: .access)
        }
    }

    func searchMembers(query: String) async {
        guard canShowAdmin else { return }
        do {
            memberSearchResults = try await repository.searchMembers(query: query)
        } catch {
            setAccountMessage(error.localizedDescription, scope: .members)
        }
    }

    @discardableResult
    func updateMemberAccess(_ member: UserProfile, accessStatus: UserProfile.AccessStatus, inductionComplete: Bool) async -> UserProfile? {
        loadState = .loading
        do {
            let updated = try await repository.updateMemberAccess(member, accessStatus: accessStatus, inductionComplete: inductionComplete)
            if let index = memberSearchResults.firstIndex(where: { $0.id == updated.id }) {
                memberSearchResults[index] = updated
            }
            if accessStatus == .removed {
                // The database function performs the destructive part of removal:
                // cancelling future bookings and archiving personal program assignments.
                // The extra fetches keep this screen honest after the server-side cleanup.
                selectedMemberBookings = try await repository.fetchMemberBookings(userID: updated.id, limit: 100)
                selectedMemberPrograms = try await repository.fetchPrograms(for: updated.id)
                setAccountMessage("\(updated.fullName) access removed. Future bookings were cancelled and personal programs were archived.", scope: .members)
            } else {
                setAccountMessage("\(updated.fullName) access updated.", scope: .members)
            }
            loadState = .idle
            return updated
        } catch {
            loadState = .failed(error.localizedDescription)
            setAccountMessage(error.localizedDescription, scope: .members)
            return nil
        }
    }

    func deleteRemovedMemberLogin(_ member: UserProfile) async -> Bool {
        loadState = .loading
        do {
            try await repository.deleteRemovedMemberLogin(member)
            memberSearchResults.removeAll { $0.id == member.id }
            selectedMemberBookings = []
            selectedMemberPrograms = []
            setAccountMessage("\(member.fullName)'s login account was deleted. If they return later, they will need to register again and be approved.", scope: .members)
            loadState = .idle
            return true
        } catch {
            loadState = .failed(error.localizedDescription)
            setAccountMessage(error.localizedDescription, scope: .members)
            return false
        }
    }

    func refreshMemberDetail(_ member: UserProfile) async {
        guard canShowAdmin else { return }
        do {
            selectedMemberBookings = try await repository.fetchMemberBookings(userID: member.id, limit: 100)
            selectedMemberPrograms = try await repository.fetchPrograms(for: member.id)
        } catch {
            setAccountMessage(error.localizedDescription, scope: .members)
        }
    }

    func accountMessage(for scope: AccountMessageScope) -> String? {
        accountMessageScope == scope ? accountMessage : nil
    }

    func clearAccountMessage() {
        accountMessage = nil
        accountMessageScope = nil
    }

    private func setAccountMessage(_ message: String, scope: AccountMessageScope) {
        accountMessage = message
        accountMessageScope = scope
        Task {
            // Messages are scoped so a success toast from one admin screen does not
            // follow the user around the rest of the app.
            try? await Task.sleep(for: .seconds(4))
            if accountMessage == message && accountMessageScope == scope {
                clearAccountMessage()
            }
        }
    }

    func refreshAll() async {
        await performLoading {
            try await refreshAfterAuth()
        }
    }

    func refreshAvailability() async {
        do {
            availability = try await repository.fetchAvailability(for: selectedDate, durationMinutes: selectedDuration)
            if let selectedSlot, !availability.contains(where: { $0.id == selectedSlot.id && $0.status != .full }) {
                self.selectedSlot = nil
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func refreshBookings() async {
        do {
            bookings = try await repository.fetchBookings()
            if canShowAdmin {
                adminBookings = try await repository.fetchAdminBookings(for: selectedDate)
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func checkIn(code: String) async {
        await performLoading {
            _ = try await repository.checkIn(code: code)
            bookings = try await repository.fetchBookings()
            setAccountMessage("Checked in.", scope: .checkIn)
        }
    }

    func checkOut(_ booking: GymBooking) async {
        await performLoading {
            _ = try await repository.checkOut(booking: booking)
            bookings = try await repository.fetchBookings()
            setAccountMessage("Checked out.", scope: .checkIn)
        }
    }

    func markDueNoShows() async {
        guard canShowAdmin else { return }
        await performLoading {
            let count = try await repository.markDueNoShows()
            adminBookings = try await repository.fetchAdminBookings(for: selectedDate)
            setAccountMessage(count == 1 ? "Marked 1 no-show." : "Marked \(count) no-shows.", scope: .reports)
        }
    }

    func refreshResourcesAndPrograms() async {
        do {
            resources = try await repository.fetchResources()
            myPrograms = try await repository.fetchPrograms(for: nil)
        } catch {
            setAccountMessage(error.localizedDescription, scope: .resources)
        }
    }

    func refreshActiveAcknowledgement() async {
        do {
            activeAcknowledgement = try await repository.fetchActiveAcknowledgement()
            updateAcknowledgementState()
        } catch {
            activeAcknowledgement = .fallback
        }
    }

    func saveResource(title: String, description: String, category: String, type: ResourceKind, url: String, pdfData: Data?, fileName: String?, isPublished: Bool) async {
        await performLoading {
            let storagePath: String
            if type == .pdf, let pdfData, let fileName {
                storagePath = try await repository.uploadWellnessPDF(data: pdfData, fileName: fileName)
            } else {
                storagePath = ""
            }
            _ = try await repository.createResource(
                title: title,
                description: description,
                category: category,
                type: type,
                url: url,
                storagePath: storagePath,
                isPublished: isPublished
            )
            resources = try await repository.fetchResources()
            setAccountMessage("Resource saved.", scope: .resources)
        }
    }

    func signedURL(forStoragePath storagePath: String) async -> URL? {
        do {
            return try await repository.signedURL(forStoragePath: storagePath)
        } catch {
            setAccountMessage(error.localizedDescription, scope: .resources)
            return nil
        }
    }

    func deleteResource(_ resource: WellnessResource) async {
        await performLoading {
            try await repository.deleteResource(resource)
            resources = try await repository.fetchResources()
            setAccountMessage("Resource removed.", scope: .resources)
        }
    }

    func assignProgram(to member: UserProfile, title: String, description: String, type: ResourceKind, url: String, pdfData: Data?, fileName: String?) async {
        await performLoading {
            let storagePath: String
            if type == .pdf, let pdfData, let fileName {
                storagePath = try await repository.uploadWellnessPDF(data: pdfData, fileName: fileName)
            } else {
                storagePath = ""
            }
            _ = try await repository.createProgram(
                userID: member.id,
                title: title,
                description: description,
                type: type,
                url: url,
                storagePath: storagePath
            )
            selectedMemberPrograms = try await repository.fetchPrograms(for: member.id)
            setAccountMessage("Program assigned.", scope: .members)
        }
    }

    func archiveProgram(_ program: ProgramAssignment, member: UserProfile?) async {
        await performLoading {
            try await repository.archiveProgram(program)
            if let member {
                selectedMemberPrograms = try await repository.fetchPrograms(for: member.id)
            } else {
                myPrograms = try await repository.fetchPrograms(for: nil)
            }
            setAccountMessage("Program archived.", scope: .members)
        }
    }

    func refreshChallenges() async {
        do {
            challenges = try await repository.fetchChallenges(includeDrafts: canShowAdmin)
        } catch {
            setAccountMessage(error.localizedDescription, scope: .challenges)
        }
    }

    func saveChallenge(_ challenge: WellbeingChallenge) async {
        await performLoading {
            guard !challenge.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BookingError.remote("Add a challenge title.")
            }
            guard !challenge.challengeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BookingError.remote("Add a challenge type.")
            }
            guard !challenge.metricName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BookingError.remote("Add a metric name.")
            }
            guard challenge.startsOn <= challenge.endsOn else {
                throw BookingError.remote("Challenge end date must be after the start date.")
            }
            if challenges.contains(where: { $0.id == challenge.id }) {
                _ = try await repository.updateChallenge(challenge)
                setAccountMessage("Challenge updated.", scope: .challenges)
            } else {
                _ = try await repository.createChallenge(challenge)
                setAccountMessage("Challenge created.", scope: .challenges)
            }
            challenges = try await repository.fetchChallenges(includeDrafts: canShowAdmin)
        }
    }

    func deleteChallenge(_ challenge: WellbeingChallenge) async {
        await performLoading {
            try await repository.deleteChallenge(challenge)
            challenges = try await repository.fetchChallenges(includeDrafts: canShowAdmin)
            setAccountMessage("Challenge removed.", scope: .challenges)
        }
    }

    func joinChallenge(_ challenge: WellbeingChallenge) async {
        await performLoading {
            _ = try await repository.joinChallenge(challenge)
            selectedChallengeLeaderboard = try await repository.fetchChallengeLeaderboard(challengeID: challenge.id)
            setAccountMessage("Challenge joined.", scope: .challenges)
        }
    }

    func refreshChallengeDetail(_ challenge: WellbeingChallenge) async {
        do {
            selectedChallengeEntries = try await repository.fetchChallengeEntries(challengeID: challenge.id, userID: profile?.id)
            selectedChallengeLeaderboard = challenge.leaderboardVisible || canShowAdmin
                ? try await repository.fetchChallengeLeaderboard(challengeID: challenge.id)
                : []
        } catch {
            setAccountMessage(error.localizedDescription, scope: .challenges)
        }
    }

    func addChallengeEntry(challenge: WellbeingChallenge, value: Double, note: String, entryDate: Date) async {
        await performLoading {
            guard value > 0 else {
                throw BookingError.remote("Enter a progress value greater than zero.")
            }
            _ = try await repository.addChallengeEntry(challengeID: challenge.id, value: value, note: note, entryDate: entryDate)
            selectedChallengeEntries = try await repository.fetchChallengeEntries(challengeID: challenge.id, userID: profile?.id)
            selectedChallengeLeaderboard = challenge.leaderboardVisible || canShowAdmin
                ? try await repository.fetchChallengeLeaderboard(challengeID: challenge.id)
                : []
            setAccountMessage("Progress added.", scope: .challenges)
        }
    }

    func refreshReports(startDate: Date, endDate: Date) async {
        guard canShowAdmin else { return }
        do {
            reportSummary = try await repository.fetchReportSummary(startDate: startDate, endDate: endDate)
            bookingExportRows = try await repository.fetchBookingExport(startDate: startDate, endDate: endDate)
            auditLog = try await repository.fetchAuditLog(limit: 50)
        } catch {
            setAccountMessage(error.localizedDescription, scope: .reports)
        }
    }

    func exportCSVText() -> String {
        var lines = ["booking_id,member_name,email,start_time,end_time,cancelled_at,checked_in_at,checked_out_at,no_show_marked_at"]
        lines += bookingExportRows.map { row in
            [
                row.bookingID.uuidString,
                csvEscape(row.memberName),
                csvEscape(row.email),
                Date.supabaseExportFormatter.string(from: row.startTime),
                Date.supabaseExportFormatter.string(from: row.endTime),
                row.cancelledAt.map(Date.supabaseExportFormatter.string(from:)) ?? "",
                row.checkedInAt.map(Date.supabaseExportFormatter.string(from:)) ?? "",
                row.checkedOutAt.map(Date.supabaseExportFormatter.string(from:)) ?? "",
                row.noShowMarkedAt.map(Date.supabaseExportFormatter.string(from:)) ?? ""
            ].joined(separator: ",")
        }
        return lines.joined(separator: "\n")
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        selectedSlot = nil
        Task { await refreshAvailability(); await refreshBookings() }
    }

    func selectDuration(_ duration: Int) {
        let previousStartTime = selectedSlot?.startTime
        selectedDuration = duration
        Task {
            await refreshAvailability()
            if let previousStartTime {
                // Preserve the selected start time when changing duration, but only if
                // the refreshed server availability says that start is still bookable.
                selectedSlot = availability.first {
                    $0.startTime == previousStartTime &&
                    $0.status != .full
                }
            }
        }
    }

    func createSelectedBooking() async {
        // Client-side checks are for clear feedback only. The create_booking RPC is the
        // final authority for induction, capacity, blackout, hours, and one-per-day rules.
        guard profile?.canBookWellnessSessions == true else {
            bookingMessage = BookingError.accessPending.localizedDescription
            return
        }
        guard let startTime = selectedSlot?.startTime else {
            bookingMessage = BookingError.noStartTimeSelected.localizedDescription
            return
        }
        if let existing = usedBookingForSelectedDate {
            bookingMessage = existing.status == .completed
                ? "You have already completed a session on this day."
                : "You already have a booking on this day: \(FacilityTime.intervalText(start: existing.startTime, end: existing.endTime)). Cancel it before booking another session."
            selectedSlot = nil
            return
        }

        confirmationBooking = GymBooking(
            id: UUID(),
            userID: profile?.id ?? UUID(),
            memberName: profile?.fullName ?? "Pending",
            startTime: startTime,
            endTime: FacilityTime.calendar.date(byAdding: .minute, value: selectedDuration, to: startTime) ?? startTime,
            cancelledAt: nil,
            createdAt: Date()
            ,
            checkedInAt: nil,
            checkedOutAt: nil,
            noShowMarkedAt: nil
        )
        bookingMessage = "Confirming booking..."

        do {
            let booking = try await repository.createBooking(startTime: startTime, durationMinutes: selectedDuration)
            confirmationBooking = booking
            bookingMessage = "Booking confirmed."
            selectedSlot = nil
            scheduleReminder(for: booking)
            try await refreshAfterAuth()
        } catch {
            confirmationBooking = nil
            bookingMessage = error.localizedDescription
            await refreshAvailability()
        }
    }

    func acceptWellnessAcknowledgement() async {
        loadState = .loading
        do {
            _ = try await acceptActiveAcknowledgement()
            loadState = .idle
        } catch {
            loadState = .failed(error.localizedDescription)
            setAccountMessage(error.localizedDescription, scope: .acknowledgement)
        }
    }

    func publishAcknowledgement(title: String, body: String, capacityText: String, fairUseText: String, medicalText: String) async {
        await performLoading {
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanCapacity = capacityText.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanFairUse = fairUseText.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanMedical = medicalText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cleanTitle.isEmpty else { throw BookingError.remote("Add an acknowledgement title.") }
            guard !cleanBody.isEmpty else { throw BookingError.remote("Add acknowledgement wording.") }
            guard !cleanMedical.isEmpty else { throw BookingError.remote("Add the medical advice wording.") }
            guard !cleanFairUse.isEmpty else { throw BookingError.remote("Add the fair use wording.") }

            activeAcknowledgement = try await repository.publishAcknowledgement(
                title: cleanTitle,
                body: cleanBody,
                capacityText: cleanCapacity,
                fairUseText: cleanFairUse,
                medicalText: cleanMedical
            )
            try await refreshAcknowledgementState()
            setAccountMessage("Acknowledgement published. Members will accept the new version next time they open the app.", scope: .acknowledgement)
        }
    }

    @discardableResult
    private func acceptActiveAcknowledgement() async throws -> WellnessAcknowledgementAcceptance {
        let acceptance = try await repository.acceptAcknowledgement(activeAcknowledgement)
        acknowledgementAcceptance = acceptance
        persistAcknowledgementFallback(acceptance)
        updateAcknowledgementState()
        return acceptance
    }

    private func refreshAcknowledgementState() async throws {
        activeAcknowledgement = try await repository.fetchActiveAcknowledgement()
        acknowledgementAcceptance = try await repository.fetchMyAcknowledgementAcceptance()
        if acknowledgementAcceptance == nil, hasLocalAcknowledgementForActiveVersion() {
            // Older builds stored acknowledgement acceptance only on-device. If the
            // local version matches the active database wording, silently backfill it.
            acknowledgementAcceptance = try? await repository.acceptAcknowledgement(activeAcknowledgement)
        }
        updateAcknowledgementState()
    }

    private func persistAcknowledgementFallback(_ acceptance: WellnessAcknowledgementAcceptance) {
        guard let userID = profile?.id else { return }
        let defaults = UserDefaults.standard
        defaults.set(acceptance.version, forKey: acknowledgementVersionKey(for: userID))
        defaults.set(acceptance.acceptedAt, forKey: acknowledgementAcceptedAtKey(for: userID))
        defaults.removeObject(forKey: acknowledgementKey(for: userID))
    }

    private func updateAcknowledgementState() {
        guard let userID = profile?.id else {
            hasAcceptedWellnessAcknowledgement = false
            wellnessAcknowledgementAcceptedAt = nil
            return
        }
        let defaults = UserDefaults.standard
        let acceptedVersion = defaults.string(forKey: acknowledgementVersionKey(for: userID))
        if acceptedVersion == nil, defaults.bool(forKey: acknowledgementKey(for: userID)) {
            let migratedAt = Date()
            defaults.set(Self.wellnessAcknowledgementVersion, forKey: acknowledgementVersionKey(for: userID))
            defaults.set(migratedAt, forKey: acknowledgementAcceptedAtKey(for: userID))
        }
        let dbAcceptanceMatches = acknowledgementAcceptance?.acknowledgementID == activeAcknowledgement.id
        let localAcceptanceMatches = defaults.string(forKey: acknowledgementVersionKey(for: userID)) == activeAcknowledgement.version
        hasAcceptedWellnessAcknowledgement = dbAcceptanceMatches || localAcceptanceMatches
        wellnessAcknowledgementAcceptedAt = acknowledgementAcceptance?.acceptedAt ?? defaults.object(forKey: acknowledgementAcceptedAtKey(for: userID)) as? Date
    }

    private func hasLocalAcknowledgementForActiveVersion() -> Bool {
        guard let userID = profile?.id else { return false }
        let defaults = UserDefaults.standard
        return defaults.string(forKey: acknowledgementVersionKey(for: userID)) == activeAcknowledgement.version
    }

    private func acknowledgementKey(for userID: UUID) -> String {
        "fenix.wellnessAcknowledgement.\(userID.uuidString)"
    }

    private func acknowledgementVersionKey(for userID: UUID) -> String {
        "fenix.wellnessAcknowledgement.version.\(userID.uuidString)"
    }

    private func acknowledgementAcceptedAtKey(for userID: UUID) -> String {
        "fenix.wellnessAcknowledgement.acceptedAt.\(userID.uuidString)"
    }

    private func updateLocalSecurityState() {
        guard let userID = profile?.id else {
            localSecuritySettings = LocalSecuritySettings(faceIDEnabled: false, pinEnabled: false)
            return
        }
        localSecuritySettings = localSecurity.settings(for: userID)
    }

    func cancel(_ booking: GymBooking) async {
        do {
            _ = try await repository.cancelBooking(booking)
            bookingMessage = "Booking cancelled."
            reminders.cancelReminder(for: booking)
            try await refreshAfterAuth()
        } catch {
            bookingMessage = error.localizedDescription
        }
    }

    private func scheduleReminder(for booking: GymBooking) {
        reminders.scheduleReminder(for: booking, minutesBefore: 60)
    }

    private func refreshAfterAuth() async throws {
        // This is the single "signed-in bootstrap" refresh. Keeping the sequence in one
        // place prevents different tabs from drifting into different app state.
        rules = try await repository.fetchRules()
        openingHours = try await repository.fetchOpeningHours()
        facilityContact = try await repository.fetchFacilityContact()
        try await refreshAcknowledgementState()
        availability = try await repository.fetchAvailability(for: selectedDate, durationMinutes: selectedDuration)
        bookings = try await repository.fetchBookings()
        resources = try await repository.fetchResources()
        myPrograms = try await repository.fetchPrograms(for: nil)
        challenges = try await repository.fetchChallenges(includeDrafts: canShowAdmin)
        if canShowAdmin {
            adminBookings = try await repository.fetchAdminBookings(for: selectedDate)
            adminProfiles = try await repository.fetchAdminProfiles()
            blackoutPeriods = try await repository.fetchBlackoutPeriods()
            memberSearchResults = try await repository.searchMembers(query: "")
            auditLog = try await repository.fetchAuditLog(limit: 50)
        }
    }

    private func performLoading(_ operation: () async throws -> Void) async {
        // Most user actions use a shared loading/error state so the UI can show one
        // consistent busy state while still surfacing the server's exact error message.
        loadState = .loading
        do {
            try await operation()
            loadState = .idle
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}

private func csvEscape(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escaped)\""
}

private extension Date {
    static let supabaseExportFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

@MainActor
final class SessionReminderManager {
    static let shared = SessionReminderManager()

    private let center = UNUserNotificationCenter.current()

    func scheduleReminder(for booking: GymBooking, minutesBefore: Int) {
        let reminderDate = booking.startTime.addingTimeInterval(TimeInterval(-minutesBefore * 60))
        guard reminderDate > Date() else { return }

        Task {
            do {
                // Local notifications are device-side reminders only. They still fire if
                // the app is force-closed, as long as iOS has accepted the request.
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                guard granted else { return }

                let content = UNMutableNotificationContent()
                content.title = FenixBrand.appName
                content.body = "Your session starts at \(FacilityTime.timeText(booking.startTime))."
                content.sound = .default

                let triggerDate = FacilityTime.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
                let request = UNNotificationRequest(
                    identifier: reminderIdentifier(for: booking),
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
                )

                try await center.add(request)
            } catch {
                // Reminders are helpful, but booking confirmation should never fail because notifications are unavailable.
            }
        }
    }

    func cancelReminder(for booking: GymBooking) {
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier(for: booking)])
    }

    func cancelAll(for userID: UUID) {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("fenix-session-\(userID.uuidString)-") }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    private func reminderIdentifier(for booking: GymBooking) -> String {
        "fenix-session-\(booking.userID.uuidString)-\(booking.id.uuidString)"
    }
}
