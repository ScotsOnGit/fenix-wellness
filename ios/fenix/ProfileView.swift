//
//  ProfileView.swift
//  fenix
//
//  Created by Codex on 5/6/2026.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        List {
            if let profile = appModel.profile {
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(FenixTheme.darkCardPressed)
                                .frame(width: 58, height: 58)
                            Text(profile.initials)
                                .font(.headline)
                                .foregroundStyle(FenixTheme.glowGold)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.fullName)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(profile.email)
                                .font(.subheadline)
                                .foregroundStyle(FenixTheme.darkSecondaryText)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(FenixTheme.darkCard)
                }

                Section("Details") {
                    LabeledContent("Email", value: profile.email)
                    LabeledContent("Phone", value: profile.phone.isEmpty ? "Not supplied" : profile.phone)
                    LabeledContent("Access", value: profile.accessStatus.label)
                    LabeledContent("Induction", value: profile.inductionCompletedAt == nil ? "Pending" : "Complete")
                    NavigationLink {
                        EditProfileView(profile: profile)
                    } label: {
                        Label("Update phone", systemImage: "phone")
                    }
                }
                .listRowBackground(FenixTheme.darkCard)

                Section("Wellness Centre") {
                    LabeledContent("Hours", value: appModel.selectedDateOpeningHours?.summary ?? "Available in Book")
                    LabeledContent("Bookings", value: (appModel.rules?.allowedDurationsMinutes ?? FacilityRules.fenixDefault.allowedDurationsMinutes).sorted().map { "\($0)m" }.joined(separator: ", "))
                    LabeledContent("Reminders", value: "60 minutes before")
                    if !appModel.facilityContact.address.isEmpty {
                        LabeledContent("Address", value: appModel.facilityContact.address)
                    }
                    if !appModel.facilityContact.phone.isEmpty {
                        LabeledContent("Phone", value: appModel.facilityContact.phone)
                    }
                    if !appModel.facilityContact.email.isEmpty {
                        LabeledContent("Email", value: appModel.facilityContact.email)
                    }
                    if !appModel.facilityContact.notes.isEmpty {
                        Text(appModel.facilityContact.notes)
                            .foregroundStyle(FenixTheme.darkSecondaryText)
                    }
                    if let acceptedAt = appModel.wellnessAcknowledgementAcceptedAt {
                        LabeledContent("Acknowledged", value: FacilityTime.dateText(acceptedAt))
                    }
                    LabeledContent("Version", value: appModel.activeAcknowledgement.version)
                    NavigationLink {
                        WellnessAcknowledgementDetailView()
                    } label: {
                        Label("View acknowledgement", systemImage: "doc.text.magnifyingglass")
                    }
                }
                .listRowBackground(FenixTheme.darkCard)

                Section("Security") {
                    LabeledContent("Sign-in", value: "Remembered on this device")
                    LabeledContent("Face ID / PIN", value: appModel.localSecurityStatus)
                    NavigationLink {
                        SecuritySettingsView()
                    } label: {
                        Label("Face ID and PIN", systemImage: "lock.shield")
                    }
                    NavigationLink {
                        ChangePasswordView()
                    } label: {
                        Label("Change password", systemImage: "key")
                    }
                }
                .listRowBackground(FenixTheme.darkCard)

                if let accountMessage = appModel.accountMessage(for: .profile) {
                    Section {
                        Text(accountMessage)
                            .foregroundStyle(FenixTheme.darkSecondaryText)
                    }
                    .listRowBackground(FenixTheme.darkCard)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await appModel.signOut() }
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .listRowBackground(FenixTheme.darkCard)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(FenixTheme.loginBlue.ignoresSafeArea())
        .navigationTitle("Profile")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(FenixTheme.loginBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct WellnessAcknowledgementDetailView: View {
    var body: some View {
        ScrollView {
            WellnessAcknowledgementContent()
                .padding(24)
        }
        .background(FenixTheme.loginBlue.ignoresSafeArea())
        .navigationTitle("Acknowledgement")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(FenixTheme.loginBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    private let profile: UserProfile
    @State private var phone: String

    init(profile: UserProfile) {
        self.profile = profile
        _phone = State(initialValue: profile.phone)
    }

    private var canSave: Bool {
        appModel.loadState != .loading
    }

    var body: some View {
        List {
            Section("Staff Details") {
                LabeledContent("Name", value: profile.fullName)
                LabeledContent("Email", value: profile.email)
            }
            .listRowBackground(FenixTheme.darkCard)

            Section {
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            } header: {
                Text("Contact")
            } footer: {
                Text("Your name and email are managed by Fenix. Phone is optional and can be cleared at any time.")
            }
            .listRowBackground(FenixTheme.darkCard)

            if case let .failed(message) = appModel.loadState {
                Section {
                    Text(message)
                        .foregroundStyle(FenixTheme.alertRed)
                }
                .listRowBackground(FenixTheme.darkCard)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(FenixTheme.loginBlue.ignoresSafeArea())
        .foregroundStyle(.white)
        .navigationTitle("Update Phone")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(FenixTheme.loginBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await appModel.updateProfile(
                            fullName: profile.fullName,
                            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        if appModel.loadState == .idle {
                            dismiss()
                        }
                    }
                }
                .disabled(!canSave)
            }
        }
    }
}

struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""

    private var validationMessage: String? {
        if newPassword.count < 8 {
            return "Use at least 8 characters."
        }
        if newPassword != confirmPassword {
            return "New passwords do not match."
        }
        return nil
    }

    private var canSave: Bool {
        validationMessage == nil && appModel.loadState != .loading
    }

    var body: some View {
        List {
            Section("Password") {
                RevealSecureField(
                    title: "Current password",
                    text: $currentPassword,
                    textContentType: .password
                )
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
            .listRowBackground(FenixTheme.darkCard)

            Section {
                Text(validationMessage ?? "Your password will be updated for future email/password sign-ins.")
                    .foregroundStyle(validationMessage == nil ? FenixTheme.darkSecondaryText : FenixTheme.amber)
            }
            .listRowBackground(FenixTheme.darkCard)

            if case let .failed(message) = appModel.loadState {
                Section {
                    Text(message)
                        .foregroundStyle(FenixTheme.alertRed)
                }
                .listRowBackground(FenixTheme.darkCard)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(FenixTheme.loginBlue.ignoresSafeArea())
        .foregroundStyle(.white)
        .navigationTitle("Change Password")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(FenixTheme.loginBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await appModel.updatePassword(
                            currentPassword: currentPassword,
                            newPassword: newPassword
                        )
                        if appModel.loadState == .idle {
                            dismiss()
                        }
                    }
                }
                .disabled(!canSave)
            }
        }
    }
}

struct SecuritySettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var pin = ""
    @State private var confirmPIN = ""

    private var pinIsValid: Bool {
        pin.count >= 4 && pin == confirmPIN && pin.allSatisfy(\.isNumber)
    }

    var body: some View {
        List {
            Section("Unlock") {
                Toggle(isOn: Binding(
                    get: { appModel.localSecuritySettings.faceIDEnabled },
                    set: { appModel.setFaceIDEnabled($0) }
                )) {
                    Label("Use \(appModel.biometryLabel)", systemImage: "faceid")
                }

                if appModel.localSecuritySettings.pinHash != nil {
                    Toggle(isOn: Binding(
                        get: { appModel.localSecuritySettings.pinEnabled },
                        set: { appModel.setPINEnabled($0) }
                    )) {
                        Label("Use app PIN", systemImage: "number.square")
                    }
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Set PIN") {
                RevealSecureField(
                    title: "PIN",
                    text: $pin,
                    keyboardType: .numberPad,
                    textContentType: .oneTimeCode
                )
                RevealSecureField(
                    title: "Confirm PIN",
                    text: $confirmPIN,
                    keyboardType: .numberPad,
                    textContentType: .oneTimeCode
                )

                Button {
                    appModel.setPIN(pin)
                    pin = ""
                    confirmPIN = ""
                } label: {
                    Label(appModel.localSecuritySettings.pinHash == nil ? "Enable PIN" : "Change PIN", systemImage: "checkmark.circle")
                }
                .disabled(!pinIsValid)
            }
            .listRowBackground(FenixTheme.darkCard)

            Section {
                Button(role: .destructive) {
                    appModel.disableLocalSecurity()
                } label: {
                    Label("Disable Face ID and PIN", systemImage: "lock.open")
                }
                .disabled(!appModel.localSecuritySettings.isEnabled)
            } footer: {
                Text("Face ID and PIN only unlock this app on this device. Email and password are still required after logout or when your Supabase session expires.")
            }
            .listRowBackground(FenixTheme.darkCard)

            if let accountMessage = appModel.accountMessage(for: .profile) {
                Section {
                    Text(accountMessage)
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                }
                .listRowBackground(FenixTheme.darkCard)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(FenixTheme.loginBlue.ignoresSafeArea())
        .foregroundStyle(.white)
        .navigationTitle("App Lock")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(FenixTheme.loginBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct RevealSecureField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isVisible {
                    TextField(title, text: $text)
                        .textContentType(textContentType)
                } else {
                    SecureField(title, text: $text)
                        .textContentType(textContentType)
                }
            }
            .keyboardType(keyboardType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .foregroundStyle(FenixTheme.darkSecondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isVisible ? "Hide \(title)" : "Show \(title)")
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environment(AppModel(repository: MockGymBookingRepository()))
    }
}
