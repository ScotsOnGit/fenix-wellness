//
//  RootView.swift
//  fenix
//
//  Created by Codex on 5/6/2026.
//

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if appModel.isRestoringSession {
                FenixLoadingView(message: "Opening", fillsScreen: true)
            } else if appModel.passwordRecoveryActive {
                PasswordRecoveryView()
            } else if appModel.isSignedIn {
                if appModel.shouldShowLocalUnlock {
                    LocalUnlockView()
                } else if appModel.hasAcceptedWellnessAcknowledgement || appModel.canShowAdmin {
                    MainTabView()
                } else {
                    WellnessAcknowledgementView()
                }
            } else {
                AuthView()
            }
        }
        .task {
            await appModel.restoreSession()
        }
        .onOpenURL { url in
            Task { await appModel.handlePasswordRecovery(url: url) }
        }
        .dismissableKeyboard()
        .preferredColorScheme(.dark)
    }
}

struct PasswordRecoveryView: View {
    @Environment(AppModel.self) private var appModel

    @State private var newPassword = ""
    @State private var confirmPassword = ""

    private var validationMessage: String? {
        if newPassword.count < 8 {
            return "Use at least 8 characters."
        }
        if newPassword != confirmPassword {
            return "Passwords do not match."
        }
        return nil
    }

    private var canSave: Bool {
        validationMessage == nil && appModel.loadState != .loading
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            FenixBrandMark(
                size: 82,
                padding: 16,
                background: FenixTheme.loginBlue,
                showsBorder: false
            )

            VStack(spacing: 8) {
                Text("Reset Password")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text("Enter a new password for your wellness centre account.")
                    .font(.body)
                    .foregroundStyle(FenixTheme.darkSecondaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                RevealSecureField(
                    title: "New password",
                    text: $newPassword,
                    textContentType: .newPassword
                )
                RevealSecureField(
                    title: "Confirm new password",
                    text: $confirmPassword,
                    textContentType: .newPassword
                )
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FenixTheme.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = appModel.passwordRecoveryMessage {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FenixTheme.darkSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await appModel.completePasswordRecovery(newPassword: newPassword) }
            } label: {
                HStack {
                    if appModel.loadState == .loading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Update Password")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canSave ? FenixTheme.orange : FenixTheme.orange.opacity(0.30), in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)

            Button("Cancel") {
                Task { await appModel.signOut() }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(FenixTheme.darkSecondaryText)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FenixTheme.loginBlue.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

struct LocalUnlockView: View {
    @Environment(AppModel.self) private var appModel
    @State private var pin = ""

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            FenixBrandMark(
                size: 82,
                padding: 16,
                background: FenixTheme.loginBlue,
                showsBorder: false
            )

            VStack(spacing: 8) {
                Text("Unlock")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text("Use \(appModel.biometryLabel) or your app PIN to continue.")
                    .font(.body)
                    .foregroundStyle(FenixTheme.darkSecondaryText)
                    .multilineTextAlignment(.center)
            }

            if appModel.localSecuritySettings.faceIDEnabled {
                Button {
                    Task { await appModel.unlockWithBiometrics() }
                } label: {
                    Label("Unlock with \(appModel.biometryLabel)", systemImage: "faceid")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(FenixTheme.orange, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            if appModel.localSecuritySettings.pinEnabled {
                RevealSecureField(
                    title: "PIN",
                    text: $pin,
                    keyboardType: .numberPad,
                    textContentType: .oneTimeCode
                )

                Button {
                    Task { await appModel.unlockWithPIN(pin) }
                } label: {
                    Text("Unlock with PIN")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(pin.count >= 4 ? FenixTheme.orange : FenixTheme.orange.opacity(0.30), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(pin.count < 4)
            }

            if let message = appModel.accountMessage(for: .localUnlock) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(FenixTheme.amber)
                    .multilineTextAlignment(.center)
            }

            Button(role: .destructive) {
                Task { await appModel.signOut() }
            } label: {
                Text("Use email and password")
                    .font(.footnote.weight(.semibold))
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FenixTheme.loginBlue.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            if appModel.localSecuritySettings.faceIDEnabled {
                await appModel.unlockWithBiometrics()
            }
        }
    }
}

struct WellnessAcknowledgementView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            FenixBrandMark(
                size: 82,
                padding: 16,
                background: FenixTheme.loginBlue,
                showsBorder: false
            )

            WellnessAcknowledgementContent()

            Button {
                appModel.acceptWellnessAcknowledgement()
            } label: {
                Text("I acknowledge")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(FenixTheme.orange, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                Task { await appModel.signOut() }
            } label: {
                Text("Log out")
                    .font(.footnote.weight(.semibold))
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FenixTheme.loginBlue.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

struct WellnessAcknowledgementContent: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let rules = appModel.rules ?? .fenixDefault
        VStack(spacing: 14) {
            Text("Wellness Centre Acknowledgement")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text("Please read and acknowledge this before using the wellness centre. Use of the facility is voluntary and at your own risk. If you have a medical condition, injury, or any concern about exercise, seek medical advice before using the facility.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(FenixTheme.darkSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                AcknowledgementPoint(
                    icon: "person.3.fill",
                    title: "Capacity",
                    text: "The wellness centre is limited to \(rules.capacity) people at a time."
                )
                AcknowledgementPoint(
                    icon: "calendar.badge.clock",
                    title: "Fair use",
                    text: "To keep access fair, each staff member can book one session per day, up to \(rules.bookingHorizonDays) days in advance."
                )
                AcknowledgementPoint(
                    icon: "clock",
                    title: "Facility time",
                    text: "All session times are shown in \(rules.facilityTimeZoneIdentifier) time."
                )
                AcknowledgementPoint(
                    icon: "bell",
                    title: "Reminders",
                    text: "If notifications are allowed, the app can remind you 60 minutes before a confirmed session."
                )
            }
            .padding()
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))

            Text("Acknowledgement version \(AppModel.wellnessAcknowledgementVersion)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(FenixTheme.darkSecondaryText)
        }
    }
}

private struct AcknowledgementPoint: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(FenixTheme.glowGold)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(FenixTheme.darkSecondaryText)
            }
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        TabView {
            if appModel.canShowAdmin {
                NavigationStack {
                    AdminBookingsView()
                }
                .tabItem {
                    Label("Admin", systemImage: "lock.shield")
                }

                NavigationStack {
                    AdminOperationsView()
                }
                .tabItem {
                    Label("Operations", systemImage: "slider.horizontal.3")
                }

                NavigationStack {
                    AdminMembersView()
                }
                .tabItem {
                    Label("Members", systemImage: "person.2")
                }

                NavigationStack {
                    AdminAccessView()
                }
                .tabItem {
                    Label("Access", systemImage: "person.badge.key")
                }

                NavigationStack {
                    AdminReportsView()
                }
                .tabItem {
                    Label("Reports", systemImage: "chart.bar.doc.horizontal")
                }

                NavigationStack {
                    ProfileView()
                }
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
            } else {
                NavigationStack {
                    BookView()
                }
                .tabItem {
                    Label("Book", systemImage: "calendar.badge.plus")
                }

                NavigationStack {
                    MyBookingsView()
                }
                .tabItem {
                    Label("Bookings", systemImage: "list.bullet.rectangle")
                }

                NavigationStack {
                    CheckInView()
                }
                .tabItem {
                    Label("Check In", systemImage: "qrcode.viewfinder")
                }

                NavigationStack {
                    ChallengesView()
                }
                .tabItem {
                    Label("Challenges", systemImage: "figure.run")
                }

                NavigationStack {
                    ResourcesView()
                }
                .tabItem {
                    Label("Resources", systemImage: "doc.text")
                }

                NavigationStack {
                    ProfileView()
                }
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
            }
        }
        .tint(FenixTheme.orange)
        .toolbarColorScheme(.dark, for: .tabBar)
        .toolbarBackground(FenixTheme.loginBlue, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

#Preview {
    RootView()
        .environment(AppModel(repository: MockGymBookingRepository()))
}
